// probes/widgets/scrollbar/mutation.cjs -- proves tools/probe.cjs CAN go red on the
// scrollbar probe.
//
// The bars are CHROME: no rect, key or callback changes when they are missing or
// wrong, so every structural assertion in the library stays green while the screen
// lies. These four mutations are the four ways the bars can be wrong:
//
//   M1 the bars are never drawn (the state this widget shipped in: "no scrollbars"),
//   M2 the drag maps the pointer through the DRAWN thumb length instead of the full
//      one, so the content races ahead of the pointer by 2*BAR_INSET of free travel,
//   M3 a horizontal offset is published but never written into the scrollRect -- the
//      old widget's exact bug: offsetX existed, the pixels never moved,
//   M4 the wheel does not fall back to the horizontal axis, so a film strip ignores
//      the wheel it cannot scroll vertically.
//
// Every file is restored in `finally` and its sha256 compared byte-for-byte with the
// pre-mutation hash: a mutation run can never leave the kit subtly altered.
//
// USAGE (from asaotui/):   node probes/widgets/scrollbar/mutation.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const DIR = __dirname;
const UI = path.resolve(DIR, '..', '..', '..');   // probes/widgets/scrollbar -> asaotui
const PROBE = 'probes/widgets/scrollbar';
const RESULTS = path.join(DIR, 'scrollbar-mutation.txt');
const WIDGET = 'kit/asaot/ui/kind/ScrollViewWidget.as';

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const MUTATIONS = [
  {
    id: 'M1',
    file: WIDGET,
    why: 'THE BARS ARE NEVER DRAWN (the shipped state): the "nothing to show" early return fires '
      + 'unconditionally, so both tracks and both thumbs are missing from the bitmap',
    find: '            if (!wantY && !wantX)\n'
      + '            {\n'
      + '                var g0:Object = n.shapeB.graphics;',
    replace: '            if (true)\n'
      + '            {\n'
      + '                var g0:Object = n.shapeB.graphics;',
    expect: 'pixel (215,30)',
  },
  {
    id: 'M2',
    file: WIDGET,
    why: 'THE DRAG USES THE DRAWN THUMB LENGTH: the span becomes track minus the 4px-shortened rect, '
      + 'so a 15px pointer move yields 15*160/57.333 = 41.87 instead of 45 and the content leads '
      + 'the pointer',
    find: '            var span:Number = track - thumb - BAR_INSET * 2;',
    replace: '            var span:Number = track - thumb;',
    expect: 'dragging the thumb 15px left offsetY at',
  },
  {
    id: 'M3',
    file: WIDGET,
    why: 'A HORIZONTAL OFFSET NEVER REACHES THE SCROLLRECT (the old widget\'s bug): offsetX is '
      + 'clamped and published, and the rectangle left edge is pinned to 0, so the content does not '
      + 'slide sideways',
    find: '                n.backing.scrollRect = new Rectangle(ox, oy, w, h);',
    replace: '                n.backing.scrollRect = new Rectangle(0, oy, w, h);',
    expect: 'a horizontal offset did not slide the content',
  },
  {
    id: 'M4',
    file: WIDGET,
    why: 'NO HORIZONTAL WHEEL FALLBACK: a viewport with no vertical range ignores the wheel, so a '
      + 'film strip is unreachable by the mouse',
    find: '            var maxX:Number = Number(n.extra[MAX_X]);\n'
      + '            if (maxX > 0 && this.scrollX(n, -d * step)) e.stopPropagation();',
    replace: '            var maxX:Number = Number(n.extra[MAX_X]);\n'
      + '            if (false && maxX > 0 && this.scrollX(n, -d * step)) e.stopPropagation();',
    expect: 'the wheel over a horizontal-only viewport left offsetX at',
  },
];

function runProbe() {
  return spawnSync(process.execPath, ['tools/probe.cjs', PROBE], { cwd: UI, encoding: 'utf8' });
}

const log = [];
const line = (s) => { console.log(s); log.push(s); };
let caught = 0;
let broken = 0;

const base = runProbe();
const baseOut = (base.stdout || '') + (base.stderr || '');
const baseVerdict = /RESULT: (PASS|FAIL)/.exec(baseOut);
line('baseline (unmutated): ' + (baseVerdict ? baseVerdict[0] : 'NO VERDICT -- build failure?'));

if (!baseVerdict || baseVerdict[1] !== 'PASS') {
  line('the baseline is not green; a mutation run would be meaningless. Aborting.');
  line('--- baseline output (tail) ---');
  for (const l of baseOut.split(/\r?\n/).slice(-25)) line('  ' + l);
  fs.writeFileSync(RESULTS, log.join('\n') + '\n');
  process.exit(1);
}
line('');

for (const m of MUTATIONS) {
  const file = path.join(UI, m.file);
  const before = fs.readFileSync(file, 'utf8');
  const beforeHash = sha(file);
  if (before.indexOf(m.find) < 0) {
    line(m.id + '  SKIPPED -- anchor text not found in ' + m.file
      + ' (the file drifted; fix the mutation, do not ignore it)');
    broken++;
    continue;
  }
  try {
    fs.writeFileSync(file, before.split(m.find).join(m.replace));
    const r = runProbe();
    const out = (r.stdout || '') + (r.stderr || '');
    const verdict = /RESULT: (PASS|FAIL)/.exec(out);
    const saidIt = out.indexOf(m.expect) >= 0;
    const buildFailed = /BUILD FAILED/.test(out);
    const ok = verdict != null && verdict[1] === 'FAIL' && saidIt && !buildFailed;
    if (ok) caught++; else broken++;
    line(m.id + '  ' + (ok ? 'CAUGHT' : 'MISSED (THIS IS BAD)') + '  ' + m.why);
    line('     verdict: ' + (verdict ? verdict[0] : 'none')
      + (buildFailed ? '  BUILD FAILED -- a mutation that does not compile proves nothing' : '')
      + (saidIt ? '' : '  MISSING the expected failure line "' + m.expect + '"'));
    const fails = out.split(/\r?\n/).filter((l) => /  FAIL  /.test(l));
    for (const f of fails.slice(0, 4)) line('     ' + f.trim());
    if (fails.length > 4) line('     ... and ' + (fails.length - 4) + ' more');
  } finally {
    fs.writeFileSync(file, before);
  }
  const afterHash = sha(file);
  line('     restore: ' + (afterHash === beforeHash
    ? 'byte-identical (' + afterHash.slice(0, 16) + ')'
    : 'MISMATCH ' + beforeHash.slice(0, 16) + ' -> ' + afterHash.slice(0, 16) + '  THIS IS BAD'));
  if (afterHash !== beforeHash) broken++;
}

line('');
line('MUTATION scrollbar: ' + caught + '/' + MUTATIONS.length + ' caught, ' + broken + ' problem(s)');
line(broken === 0 && caught === MUTATIONS.length ? 'RESULT: PASS' : 'RESULT: FAIL');
fs.writeFileSync(RESULTS, log.join('\n') + '\n');
process.exit(broken === 0 && caught === MUTATIONS.length ? 0 : 1);

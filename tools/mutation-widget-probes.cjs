// tools/mutation-widget-probes.cjs -- proves the feedback and media probes CAN go red.
//
// A probe that cannot fail is decoration. These two groups had no mutation script of
// their own (unlike widgets/data and probes/g16-ternary-null), so `gates.cjs` had
// nothing to cite for their teeth. This is that citation.
//
// Every mutation is a deliberate one-token change to the thing the probe measures:
// a palette constant, the fit factor, the scroll clamp, and -- M5/M6 -- the two halves
// of the paint-scheduling contract a spinner depends on. After each one the probe
// MUST fail AND must fail with the specific line named in `expect`, so that "it went
// red" is never confused with "it failed to build". Every file is restored in
// `finally` and its sha256 compared byte-for-byte with the pre-mutation hash.
//
// USAGE (from asaotui/):   node tools/mutation-widget-probes.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const UI = path.resolve(__dirname, '..');
const RESULTS = path.join(UI, 'reviews', 'mutation-widget-probes.txt');

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const MUTATIONS = [
  {
    id: 'M1',
    probe: 'probes/widgets/feedback',
    why: 'the skeleton plate colour moves 1/255 blue-ward -> the hand-written pixel must name the wrong colour',
    file: 'kit/asaot/ui/SkeletonNode.as',
    find: 'this.tone = 0xE5E7EB;',
    replace: 'this.tone = 0xE5E7EC;',
    expect: 'pixel (80,24)',
  },
  {
    id: 'M2',
    probe: 'probes/widgets/feedback',
    why: 'the spinner arc colour (tone "info") moves 1/255 -> the hand-written pixel on the arc must fail',
    file: 'kit/asaot/ui/kind/SpinnerWidget.as',
    find: '        return 0x2563EB;',
    replace: '        return 0x2563EC;',
    expect: 'pixel (57,40)',
  },
  {
    id: 'M3',
    probe: 'probes/widgets/media',
    why: 'the "fit" factor becomes max instead of min -> the DEFAULT scale mode grows the 8x8 source to 80x80 '
      + 'instead of 40x40, so the letterbox pixel that proves containment turns solid',
    file: 'kit/asaot/ui/kind/ImageWidget.as',
    find: 'var k:Number = Math.min(w / sw, h / sh);',
    replace: 'var k:Number = Math.max(w / sw, h / sh);',
    expect: 'pixel (30,210)',
  },
  {
    id: 'M4',
    probe: 'probes/widgets/media',
    why: 'the scroll clamp forgets the viewport height (maxY = ch) -> the overscroll no longer stops at 60',
    file: 'kit/asaot/ui/kind/ScrollViewWidget.as',
    find: 'var maxY:Number = ch - h;',
    replace: 'var maxY:Number = ch;',
    expect: 'clamped offset is',
  },
  {
    id: 'M5',
    probe: 'probes/widgets/feedback',
    why: 'paintDirty clears M_PAINT AFTER painting -> a paint that raises its own next frame has '
      + 'that request erased, so the spinning spinner repaints once and freezes',
    file: 'kit/asaot/ui/UiApp.as',
    find: '                n.dirty = n.dirty & ~Dirty.M_PAINT;\n                n.paintSelf();',
    replace: '                n.paintSelf();\n                n.dirty = n.dirty & ~Dirty.M_PAINT;',
    expect: 'spinning repainted only',
  },
  {
    id: 'M6',
    probe: 'probes/widgets/feedback',
    why: 'the spinner self-perpetuating frame asks for a LAYOUT bit instead of paint -> the whole '
      + 'tree re-measures every frame (it still spins, but no longer paint-only)',
    file: 'kit/asaot/ui/kind/SpinnerWidget.as',
    find: '            if (spinning) n.app.markPaint(n);',
    replace: '            if (spinning) { n.dirty |= Dirty.M_MEASURE; n.markLayoutDirty(); n.app.markPaint(n); }',
    expect: 'spinning re-solved layout',
  },
];

function runProbe(dir) {
  return spawnSync(process.execPath, ['tools/probe.cjs', dir], { cwd: UI, encoding: 'utf8', maxBuffer: 1 << 28 });
}

const log = [];
const line = (s) => { console.log(s); log.push(s); };
let caught = 0;
let broken = 0;

// Baseline: both probes must be green unmutated, else "it went red" proves nothing.
for (const dir of ['probes/widgets/feedback', 'probes/widgets/media']) {
  const r = runProbe(dir);
  const out = (r.stdout || '') + (r.stderr || '');
  const v = /RESULT: (PASS|FAIL)/.exec(out);
  const m = /PROBE \S+: (\d+) checks, (\d+) failures/.exec(out);
  line('baseline ' + dir + ': ' + (v ? v[0] : 'NO VERDICT -- build failure?') + (m ? '  (' + m[1] + ' checks)' : ''));
  if (!v || v[1] !== 'PASS') {
    broken++;
    line('  the baseline is not green; a mutation run would be meaningless. Aborting.');
    fs.writeFileSync(RESULTS, log.join('\n') + '\n');
    process.exit(1);
  }
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
    const r = runProbe(m.probe);
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
    for (const f of fails.slice(0, 3)) line('     ' + f.trim());
    if (fails.length > 3) line('     ... and ' + (fails.length - 3) + ' more');
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
line('MUTATION feedback+media: ' + caught + '/' + MUTATIONS.length + ' caught, ' + broken + ' problem(s)');
line(broken === 0 && caught === MUTATIONS.length ? 'RESULT: PASS' : 'RESULT: FAIL');
fs.writeFileSync(RESULTS, log.join('\n') + '\n');
process.exit(broken === 0 && caught === MUTATIONS.length ? 0 : 1);

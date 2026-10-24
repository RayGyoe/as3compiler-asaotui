// probes/widgets/vlist/mutation.cjs -- proves the virtualisation probe CAN go red.
//
// The probe asserts four separable things (the window is small, the rows are the
// RIGHT rows, the viewport CLIPS, and the wheel/keys move the window through the
// documented callback). Each mutation below breaks exactly one of them and must fail
// with the SPECIFIC message named in `expect`, so "it went red" is never confused
// with "it failed to build".
//
// Every file is restored in `finally` and its sha256 compared with the pre-mutation
// hash: a mutation run can never leave the kit altered.
//
// USAGE (from asaotui/):   node probes/widgets/vlist/mutation.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const DIR = __dirname;
const UI = path.resolve(DIR, '..', '..', '..');   // probes/widgets/vlist -> asaotui
const PROBE = 'probes/widgets/vlist';
const RESULTS = path.join(DIR, 'vlist-mutation.txt');

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const MUTATIONS = [
  {
    id: 'M1',
    why: 'the viewport stops clipping -> the mounted-but-invisible 9th row paints BELOW the viewport '
      + '(the pixel at y=175 turns into row 8 instead of the page background)',
    file: 'kit/asaot/ui/kind/VirtualListWidget.as',
    find: '                n.backing.scrollRect = new Rectangle(0, 0, w, h);',
    replace: '                applied[0] = w; applied[1] = h;',
    expect: 'the clip is missing',
  },
  {
    id: 'M2',
    why: 'the factory stops mounting the partial row (+1) -> a viewport whose height is not a multiple of '
      + 'rowHeight shows a white sliver at the bottom',
    file: 'kit/asaot/ui/virtualList.as',
    find: '        var window:int = fit + 1 + n.overscan * 2;',
    replace: '        var window:int = fit + n.overscan * 2;',
    expect: 'rows for 1000 items, not 9',
  },
  {
    id: 'M3',
    why: 'the rows lose their min-height -> the window is one row taller than the viewport, so flexbox '
      + 'correctly shrinks all nine rows to 16.67px and no row sits on a rowHeight boundary any more',
    file: 'kit/asaot/ui/virtualList.as',
    find: '        var patch:StyleRefinement = StyleRefinement.from({ height: rh, minSize: [null, rh] });',
    replace: '        var patch:StyleRefinement = StyleRefinement.from({ height: rh });',
    expect: 'a row must not be flexed into the viewport',
  },
  {
    id: 'M4',
    why: 'the wheel sign flips -> a notch toward the end scrolls BACK toward the start (the probe reads '
      + 'the offset the callback reports, not the direction it "feels")',
    file: 'kit/asaot/ui/kind/VirtualListWidget.as',
    find: '            this.step(n, d > 0 ? -step : step);',
    replace: '            this.step(n, d > 0 ? step : -step);',
    expect: 'onScroll reported -1',
  },
  {
    id: 'M5',
    why: 'the widget stops clamping a request to the last full page -> End hands the author an offset of '
      + '1<<28 rows, which no author-side model can survive',
    file: 'kit/asaot/ui/kind/VirtualListWidget.as',
    find: '            if (f > maxFirst) f = maxFirst;',
    replace: '            if (f < 0) f = 0;',
    expect: "End's onScroll reported",
  },
  {
    id: 'M6',
    why: 'the widget stops reporting a scroll -> the author never learns the window moved, so nothing '
      + 're-renders even though the offset was written back',
    file: 'kit/asaot/ui/kind/VirtualListWidget.as',
    find: '            if (v.onScroll != null) v.onScroll(y);',
    replace: '            if (v.onScroll != null) v.offsetY = y;',
    expect: 'onScroll reported -1',
  },
];

function runProbe() {
  return spawnSync(process.execPath, ['tools/probe.cjs', PROBE], { cwd: UI, encoding: 'utf8' });
}

const log = [];
const line = (s) => { console.log(s); log.push(s); };
let caught = 0;
let broken = 0;

// Baseline: the unmutated probe must PASS, otherwise a mutation "failing" proves
// nothing (it was already red).
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
    for (const f of fails.slice(0, 4)) line('     ' + f.trim().slice(0, 300));
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
line('MUTATION vlist: ' + caught + '/' + MUTATIONS.length + ' caught, ' + broken + ' problem(s)');
line(broken === 0 && caught === MUTATIONS.length ? 'RESULT: PASS' : 'RESULT: FAIL');
fs.writeFileSync(RESULTS, log.join('\n') + '\n');
process.exit(broken === 0 && caught === MUTATIONS.length ? 0 : 1);
// tools/mutation-widget-theme-metrics.cjs -- proves probes/widgets/theme-metrics CAN go red.
//
// A metrics bundle has FIVE ways to reach a pixel, and every one of them can be broken
// while the screen still looks "themed":
//
//   1. the BUILDER consumes the bundle   (a kind that keeps a literal 9 cannot be skinned)
//   2. the BASELINE is built from it     (buildBaselines(pal, m) -- not from a cached table)
//   3. the EPOCH is bumped               (a metrics swap must RE-SOLVE; a repaint is not it)
//   4. every SCOPE is rebuilt            (a scoped subtree takes the app's density)
//   5. the NO-OP stays a no-op           (same numbers must not cost a full layout pass)
//
// Each mutation below removes exactly one and the run must fail with THAT assertion
// named in `expect` -- "it went red" is never enough (a build failure is red too), and
// every mutation is also required to still COMPILE. Every file is restored in
// `finally` and compared byte for byte by sha256.
//
// USAGE (from asaotui/):   node tools/mutation-widget-theme-metrics.cjs
//   (honours ASC_COMPILER, i.e. the same pinned compiler tree as tools/probe.cjs)
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const UI = path.resolve(__dirname, '..');
const RESULTS = path.join(UI, 'reviews', 'mutation-widget-theme-metrics.txt');
const PROBE = 'probes/widgets/theme-metrics';

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const MUTATIONS = [
  {
    id: 'M1',
    why: 'the BUTTON baseline keeps the literal padding -> the slot is stored and never read, so a denser skin leaves that one kind at 9/14 while every other kind moves',
    file: 'kit/asaot/ui/Theme.as',
    find: 's.padding = Edges.of(m.buttonPadY, m.buttonPadX, m.buttonPadY, m.buttonPadX);',
    replace: 's.padding = Edges.of(9, 14, 9, 14);   // MUTATED: literal padding',
    expect: "the button's padding is",
  },
  {
    id: 'M2',
    why: 'buildBaselines ignores the bundle and rebuilds the SHIPPED metrics -> the whole table is frozen at base and no kind follows a swap (the input is the cheapest witness: its left-aligned text origin moves with the padding)',
    file: 'kit/asaot/ui/Theme.as',
    find: 'if (m == null) m = _metrics != null ? _metrics : ThemeMetrics.base();',
    replace: 'm = ThemeMetrics.base();   // MUTATED: the bundle is ignored',
    expect: "the input's text starts at x",
  },
  {
    id: 'M3',
    why: 'setMetrics swaps the numbers but does NOT bump the epoch -> UiApp never re-solves: the resolved styles still say bad numbers would be fine, but the TREE keeps the old boxes, so nothing shrinks and no sibling slides',
    file: 'kit/asaot/ui/Theme.as',
    find: '_metricsEpoch = _metricsEpoch + 1;',
    replace: '_metricsEpoch = _metricsEpoch;   // MUTATED: no epoch bump',
    expect: 'compact: the auto-height button did not get shorter',
  },
  {
    id: 'M4',
    why: 'cached SCOPES are not rebuilt -> a scoped subtree keeps its own palette (correct) and the PREVIOUS density (wrong): the failure is invisible unless a scope is on screen next to the global tree',
    file: 'kit/asaot/ui/Theme.as',
    find: 'for (var i:int = 0; i < _scopes.length; i++) ScopedTheme(_scopes[i]).rebuild();',
    replace: '// MUTATED: scopes not rebuilt',
    expect: "the SCOPED button's padding/radius is",
  },
  {
    id: 'M5',
    why: 'the no-op guard is gone -> setMetrics(current()) bumps the epoch and re-solves the entire tree to arrive at the same numbers (a per-frame layout pass waiting to be written by accident)',
    file: 'kit/asaot/ui/Theme.as',
    find: 'if (_metrics.same(m)) return;',
    replace: 'if (false) return;   // MUTATED: the no-op is not detected',
    expect: 'a no-op setMetrics bumped the epoch',
  },
];

function runProbe() {
  return spawnSync(process.execPath, ['tools/probe.cjs', PROBE], { cwd: UI, encoding: 'utf8', maxBuffer: 1 << 28 });
}

const log = [];
const line = (s) => { console.log(s); log.push(s); };
let caught = 0;
let broken = 0;

// Baseline: the probe must be green unmutated, or "it went red" proves nothing.
{
  const r = runProbe();
  const out = (r.stdout || '') + (r.stderr || '');
  const v = /RESULT: (PASS|FAIL)/.exec(out);
  const m = /PROBE \S+: (\d+) checks, (\d+) failures/.exec(out);
  line('baseline ' + PROBE + ': ' + (v ? v[0] : 'NO VERDICT -- build failure?') + (m ? '  (' + m[1] + ' checks)' : ''));
  if (!v || v[1] !== 'PASS') {
    line('  the baseline is not green; a mutation run would be meaningless. Aborting.');
    fs.writeFileSync(RESULTS, log.join('\n') + '\n');
    process.exit(1);
  }
  line('');
}

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
    for (const f of fails.slice(0, 2)) line('     ' + f.trim().slice(0, 300));
    if (fails.length > 2) line('     ... and ' + (fails.length - 2) + ' more');
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
line('MUTATION theme-metrics: ' + caught + '/' + MUTATIONS.length + ' caught, ' + broken + ' problem(s)');
line(broken === 0 && caught === MUTATIONS.length ? 'RESULT: PASS' : 'RESULT: FAIL');
fs.writeFileSync(RESULTS, log.join('\n') + '\n');
process.exit(broken === 0 && caught === MUTATIONS.length ? 0 : 1);
// tools/mutation-widget-theme-scope.cjs -- proves probes/widgets/theme-scope CAN go red.
//
// A scoped palette has FIVE ways to reach a widget, and four of them can be broken
// while the picture still looks "plausibly themed":
//
//   1. the kind BASELINE      (Theme.resolve picks the scope's controlDefault)
//   2. INHERITANCE            (a child with no palette of its own takes the parent's)
//   3. the DESCRIBE stack     (factories inside the builder bake the scoped palette)
//   4. PAINT-TIME reads       (widgets call n.pal(), not Theme.tokens())
//   5. the SCOPE CACHE        (the same palette value is the same scope object)
//
// Each mutation below removes exactly one and the run must fail with THAT assertion
// named in `expect` -- "it went red" is never enough (a build failure is red too), and
// every mutation is also required to still COMPILE. Every file is restored in
// `finally` and compared byte for byte by sha256.
//
// USAGE (from asaotui/):   node tools/mutation-widget-theme-scope.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const UI = path.resolve(__dirname, '..');
const RESULTS = path.join(UI, 'reviews', 'mutation-widget-theme-scope.txt');
const PROBE = 'probes/widgets/theme-scope';

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const MUTATIONS = [
  {
    id: 'M1',
    why: 'the baseline ignores the scope -> the scoped button gets the GLOBAL control defaults (fill, border, label ink) while the branch still believes it is themed',
    file: 'kit/asaot/ui/Theme.as',
    find: 'var base:Style = scope != null ? scope.controlDefault(kind) : controlDefault(kind);',
    replace: 'var base:Style = controlDefault(kind);   // MUTATED: ignore the scope',
    expect: "the scoped button's surface is",
  },
  {
    id: 'M2',
    why: 'a child with no palette of its own does NOT inherit the parent scope -> only the boundary node itself is scoped, its whole subtree falls back to the global palette',
    file: 'kit/asaot/ui/UiNode.as',
    find: '            if (want == null) want = this.parent != null ? this.parent.scope : null;',
    replace: '            if (want == null) want = null;   // MUTATED: no inheritance',
    expect: "the scoped button's surface is",
  },
  {
    id: 'M3',
    why: 'the builder runs WITHOUT the palette on the describe stack -> factory-baked refinements (the table header fill, the header ink) silently keep the global palette',
    file: 'kit/asaot/ui/themeScope.as',
    find: '        Theme.pushDescribe(scope.tokens());',
    replace: '        // MUTATED: Theme.pushDescribe(scope.tokens());',
    expect: 'light: sepia table header at (436,116)',
  },
  {
    id: 'M4',
    why: 'paint-time reads go to the global palette -> widgets that read a colour while painting (the progress accent) repaint with the wrong one, while resolve still looks right',
    file: 'kit/asaot/ui/UiNode.as',
    find: 'return this.scope != null ? this.scope.tokens() : Theme.tokens();',
    replace: 'return Theme.tokens();   // MUTATED: pal() ignores the scope',
    expect: 'light: sepia progress fill at (346,88)',
  },
  {
    id: 'M5',
    why: 'the scope cache is not keyed by palette VALUE -> every describe mints a new scope, so the scope pointer churns every frame and the subtree is re-staled forever',
    file: 'kit/asaot/ui/Theme.as',
    find: '                if (s.samePalette(pal)) return s;',
    replace: '                if (s == null) return s;   // MUTATED: never reuse',
    expect: 'did not cache by palette value',
  },
];

function runProbe() {
  return spawnSync(process.execPath, ['tools/probe.cjs', PROBE], { windowsHide: true, cwd: UI, encoding: 'utf8', maxBuffer: 1 << 28 });
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
line('MUTATION theme-scope: ' + caught + '/' + MUTATIONS.length + ' caught, ' + broken + ' problem(s)');
line(broken === 0 && caught === MUTATIONS.length ? 'RESULT: PASS' : 'RESULT: FAIL');
fs.writeFileSync(RESULTS, log.join('\n') + '\n');
process.exit(broken === 0 && caught === MUTATIONS.length ? 0 : 1);
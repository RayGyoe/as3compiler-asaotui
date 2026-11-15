// tools/mutation-widget-reduced-motion.cjs -- proves probes/widgets/reduced-motion CAN go red.
//
// The reduced-motion path has four independent seams, and each can be broken while the
// app still "looks fine" to someone who never toggles the switch:
//
//   1. Anim.retarget honours the switch  (a fresh change must SNAP, not arm a tween)
//   2. Anim.advance honours the switch   (a live tween must LAND when toggled on)
//   3. OverlayMotion.start honours it    (no entrance travel; appear at the final pose)
//   4. OverlayMotion.startExit honours it(hide immediately; final state = gone)
//
// Each mutation removes exactly one and the run must fail with THAT assertion named in
// `expect`, and must still COMPILE. Every file is restored in `finally` and compared
// byte for byte by sha256.
//
// USAGE (from asaotui/):   node tools/mutation-widget-reduced-motion.cjs
//   (honours ASC_COMPILER, i.e. the same pinned compiler tree as tools/probe.cjs)
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const UI = path.resolve(__dirname, '..');
const RESULTS = path.join(UI, 'reviews', 'mutation-widget-reduced-motion.txt');
const PROBE = 'probes/widgets/reduced-motion';

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const MUTATIONS = [
  {
    id: 'M1',
    why: 'Anim.retarget drops the reduced-motion snap -> a fresh style change under the switch arms a 200ms tween, so the "reduced" user still sees travel',
    file: 'kit/asaot/ui/anim/Anim.as',
    find: 'if (Motion.reducedMotion || isNaN(ms) || ms <= 0)',
    replace: 'if (isNaN(ms) || ms <= 0)   // MUTATED: reduced-motion ignored on retarget',
    expect: 'reduced: a fresh retarget armed a tween',
  },
  {
    id: 'M2',
    why: 'Anim.advance drops the reduced-motion land -> toggling the switch mid-flight leaves the tween interpolating instead of snapping to its target',
    file: 'kit/asaot/ui/anim/Anim.as',
    find: 'var t:Number = Motion.reducedMotion ? 1 : (nowMs - tw.startMs) / tw.durMs;',
    replace: 'var t:Number = (nowMs - tw.startMs) / tw.durMs;   // MUTATED: no mid-flight land',
    expect: 'reduced: a live tween survived advance',
  },
  {
    id: 'M3',
    why: 'OverlayMotion.start ignores the switch -> an opening surface still fades/slides in for a reduced-motion user',
    file: 'kit/asaot/ui/OverlayMotion.as',
    find: 'if (Motion.reducedMotion) return;',
    replace: '// MUTATED: entrance ignores reduced-motion',
    expect: 'reduced: overlay entrance armed',
  },
  {
    id: 'M4',
    why: 'OverlayMotion.startExit ignores the switch -> a closing surface holds the screen for the exit tween instead of hiding immediately',
    file: 'kit/asaot/ui/OverlayMotion.as',
    find: 'if (Motion.reducedMotion) return false;',
    replace: '// MUTATED: exit ignores reduced-motion',
    expect: 'reduced: startExit should return false',
  },
];

function runProbe() {
  return spawnSync(process.execPath, ['tools/probe.cjs', PROBE], { windowsHide: true, cwd: UI, encoding: 'utf8', maxBuffer: 1 << 28 });
}

const log = [];
const line = (s) => { console.log(s); log.push(s); };
let caught = 0;
let broken = 0;

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
line('MUTATION reduced-motion: ' + caught + '/' + MUTATIONS.length + ' caught, ' + broken + ' problem(s)');
line(broken === 0 && caught === MUTATIONS.length ? 'RESULT: PASS' : 'RESULT: FAIL');
fs.writeFileSync(RESULTS, log.join('\n') + '\n');
process.exit(broken === 0 && caught === MUTATIONS.length ? 0 : 1);
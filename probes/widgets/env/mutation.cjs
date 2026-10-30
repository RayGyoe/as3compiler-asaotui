// probes/widgets/env/mutation.cjs -- proves probes/widgets/env CAN go red on the
// round that added `Env` (MOBILE.md E1) and the safe-area padding fold (E2).
//
// Every mutation is one CONTRACT, not one bug: each removes exactly the mechanism
// whose absence the probe is supposed to see, so a green run after a mutation would
// mean the probe is measuring nothing.
//
//   M1 the fold never adds the inset            -> the notch is not reserved at all
//   M2 every node claims all four edges         -> an inset leaks into nodes that
//                                                  never asked (the `safeArea:` opt
//                                                  stops being a choice)
//   M3 the inset lands on the wrong side        -> a phone reserves one edge twice and
//                                                  the other never
//   M4 hasHover is not taken from the Env        -> 103 hover branches keep running on
//                                                  a finger-only device
//   M5 a rebind keeps the old subscription       -> a dead platform keeps driving the app
//   M6 an env change never wakes a frame         -> the change is latched forever
//   M7 the desktop answers a fake safe area      -> the floor every app gets is a lie
//                                                  on a machine with no notch
//
// Each mutated file is restored in `finally` and its sha256 compared byte-for-byte
// with the pre-mutation hash: a mutation run can never leave the kit subtly altered.
//
// USAGE (from asaotui/):   node probes/widgets/env/mutation.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const DIR = __dirname;
const UI = path.resolve(DIR, '..', '..', '..');
const PROBE = 'probes/widgets/env';
const RESULTS = path.join(DIR, 'env-mutation.txt');

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const MUTATIONS = [
  {
    id: 'M1',
    file: 'kit/asaot/ui/UiNode.as',
    why: 'THE FOLD NEVER ADDS THE INSET: `safeArea: true` becomes decoration and the '
      + 'content starts under the notch',
    find: '            return (isNaN(v) ? 0 : v) + inset;',
    replace: '            return (isNaN(v) ? 0 : v);',
    expect: 'rect pchild[y] want 169',
  },
  {
    id: 'M2',
    file: 'kit/asaot/ui/SafeArea.as',
    why: 'EVERY NODE CLAIMS ALL FOUR EDGES: the `safeArea:` opt stops being a choice, so '
      + 'the inset lands on nodes that never asked -- exactly the "scatter it everywhere" '
      + 'E2 forbids',
    find: '            if (v == null || v == false) return NONE;',
    replace: '            if (v == null || v == false) return ALL;',
    expect: 'rect inner[y] want 85',
  },
  {
    id: 'M3',
    file: 'kit/asaot/ui/UiNode.as',
    why: 'THE INSET LANDS ON THE WRONG SIDE: every edge claims the TOP number, so a phone '
      + 'with a status bar and a home indicator reserves one of them twice and the other '
      + 'never',
    find: 'safeSide(p != null ? p.bottom : NaN, this.safeAreaMask, SafeArea.BOTTOM, this.safeBottom)',
    replace: 'safeSide(p != null ? p.bottom : NaN, this.safeAreaMask, SafeArea.BOTTOM, this.safeTop)',
    expect: 'root padding bottom is 51',
  },
  {
    id: 'M4',
    file: 'kit/asaot/ui/UiApp.as',
    why: 'HAS HOVER IS NOT TAKEN FROM THE ENV: the 103 hover branches keep running on a '
      + 'window with no hover-capable pointer',
    find: '            this.setHasHover(this.env.hasHover);',
    replace: '            // (mutation) the hover verdict is not taken from the env',
    expect: 'Env.hasHover(false) did not reach UiApp',
  },
  {
    id: 'M5',
    file: 'kit/asaot/ui/UiApp.as',
    why: 'A REBIND KEEPS THE OLD SUBSCRIPTION: a platform nobody is listening to keeps '
      + 'driving the app, invisibly, for the rest of the session',
    find: '                this._envSub.cancel();',
    replace: '                // (mutation) the old subscription is kept',
    expect: 'the OLD env still notifies the app',
  },
  {
    id: 'M6',
    file: 'kit/asaot/ui/UiApp.as',
    why: 'AN ENV CHANGE NEVER WAKES A FRAME: the change is latched and the reflow that '
      + 'would consume it never runs, so the app is stuck on the old geometry',
    find: '            if (this.root != null) this._needsPaint = true;',
    replace: '            // (mutation) no frame is requested',
    expect: 'with no safe area the first row is at y 51',
  },
  {
    id: 'M7',
    file: 'kit/asaot/ui/DesktopEnv.as',
    why: 'THE DESKTOP FLOOR ANSWERS A FAKE SAFE AREA: every app in this repo would start '
      + 'with a notch it does not have, and nothing would be able to tell',
    find: '            this._pixelRatio = pixelRatio;',
    replace: '            this._pixelRatio = pixelRatio;\n            this._safeArea.top = 20;',
    expect: 'the desktop safe area is not all zero',
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
    const timedOut = /TIMEOUT/.test(out);
    const ok = verdict != null && verdict[1] === 'FAIL' && saidIt && !buildFailed;
    if (ok) caught++; else broken++;
    line(m.id + '  ' + (ok ? 'CAUGHT' : 'MISSED (THIS IS BAD)') + '  ' + m.why);
    line('     verdict: ' + (verdict ? verdict[0] : 'none')
      + (buildFailed ? '  BUILD FAILED -- a mutation that does not compile proves nothing' : '')
      + (timedOut ? '  TIMEOUT -- the program never reached its verdict' : '')
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
line('MUTATION env: ' + caught + '/' + MUTATIONS.length + ' caught, ' + broken + ' problem(s)');
line(broken === 0 && caught === MUTATIONS.length ? 'RESULT: PASS' : 'RESULT: FAIL');
fs.writeFileSync(RESULTS, log.join('\n') + '\n');
process.exit(broken === 0 && caught === MUTATIONS.length ? 0 : 1);

// probes/widgets/fps/mutation.cjs -- proves probes/widgets/fps CAN go red.
//
// Each mutation removes exactly the MECHANISM the probe is supposed to see, not a
// random bug, so a green run afterwards would mean the assertion measures nothing:
//
//   M1 the HUD is never re-raised       -> an author overlay (a dialog) is drawn
//     above it                              AFTER it, so the panel is covered and
//                                           its pixels lose to the scrim
//   M2 the HUD hit-tests its children   -> `mouseEnabled = false` alone is not
//     (mouseChildren back on)               enough: as_pick_hit walks the subtree,
//                                           so the click never reaches the button
//   M3 the HUD hit-tests itself         -> the panel's own box eats the click
//   M4 the fps is a CONSTANT 60         -> every assertion about the band and the
//                                           arithmetic still passes at 60Hz; the
//                                           30Hz phase is the tooth, because a HUD
//                                           that echoes the request cannot halve
//
// Each mutated file is restored in `finally` and its sha256 compared with the
// pre-mutation hash: a mutation run can never leave the kit subtly altered.
//
// USAGE (from asaotui/):   node probes/widgets/fps/mutation.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const DIR = __dirname;
const UI = path.resolve(DIR, '..', '..', '..');
const PROBE = 'probes/widgets/fps';
const RESULTS = path.join(DIR, 'fps-mutation.txt');

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const MUTATIONS = [
  {
    id: 'M1',
    file: 'kit/asaot/ui/UiApp.as',
    why: 'THE HUD IS NEVER RE-RAISED: with a dialog open the overlay is added after '
      + 'the HUD, so the last child is the dialog and the panel is painted under it',
    find: '            this.raiseFps();\n\n            // SAFE AREA FOLD',
    replace: '            // (mutation) raiseFps removed\n\n            // SAFE AREA FOLD',
    expect: 'the HUD is at display index',
  },
  {
    id: 'M2',
    file: 'kit/asaot/ui/UiApp.as',
    why: 'THE HUD STILL HIT-TESTS ITS CHILDREN: mouseEnabled is not enough, because '
      + 'the hit test walks the subtree and the panel has a painted background',
    find: 'this.fpsRoot.backing.mouseChildren = false;',
    replace: 'this.fpsRoot.backing.mouseChildren = true; // (mutation)',
    expect: 'still hit-tests its children',
  },
  {
    id: 'M3',
    file: 'kit/asaot/ui/UiApp.as',
    why: 'THE HUD HIT-TESTS ITSELF: the panel box answers the click, so the button '
      + 'underneath never sees it',
    find: 'this.fpsRoot.backing.mouseEnabled = false;',
    replace: 'this.fpsRoot.backing.mouseEnabled = true; // (mutation)',
    expect: 'a click inside the HUD reported 0 picks',
  },
  {
    id: 'M4',
    file: 'kit/asaot/ui/FpsPanel.as',
    why: 'THE RATE IS A CONSTANT: the band (45..75 at 60Hz) and the arithmetic '
      + '(1000/fps == avgMs) both still hold, so only the 30Hz phase can tell a '
      + 'measurement from an echo of the request',
    find: '            this.fps = int(Math.round(f * 1000 / span));',
    replace: '            this.fps = 60; // (mutation) a constant, not a measurement',
    expect: 'at stage.frameRate = 30 the HUD reads',
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
    const buildFailed = /BUILD FAILED|Codegen error/.test(out);
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
line('MUTATION fps: ' + caught + '/' + MUTATIONS.length + ' caught, ' + broken + ' problem(s)');
line(broken === 0 && caught === MUTATIONS.length ? 'RESULT: PASS' : 'RESULT: FAIL');
fs.writeFileSync(RESULTS, log.join('\n') + '\n');
process.exit(broken === 0 && caught === MUTATIONS.length ? 0 : 1);
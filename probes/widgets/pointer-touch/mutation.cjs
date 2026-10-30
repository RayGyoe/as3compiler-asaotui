// probes/widgets/pointer-touch/mutation.cjs -- proves probes/widgets/pointer-touch CAN
// go red on the round that added touch routing (MOBILE.md M0).
//
// Every mutation is one CONTRACT, not one bug: each removes exactly the mechanism whose
// absence the probe is supposed to see, so a green run after a mutation would mean the
// probe is measuring nothing.
//
//   M1 the synthetic mouse event is aimed at the stage -> the press/click vocabulary
//                                                        never reaches a node, so a tap
//                                                        is silent
//   M2 EVERY press is delayed                          -> a button waits out the scroller
//                                                        delay, i.e. the 130ms reacts dead
//   M3 NO press is delayed                             -> a list row flashes pressed on
//                                                        every scroll gesture
//   M4 slop no longer suppresses the click             -> dragging a control also clicks
//                                                        it, which is the "tap fires after
//                                                        a drag" bug in every mobile app
//   M5 the synthetic guard in onStageMouseMove goes     -> the hover is re-derived from the
//                                                        node the router itself picked, so
//                                                        "our hover is the engine's hover"
//                                                        becomes true by construction
//   M7 a cancelled touch leaves the press slot set      -> the next tap is silently
//                                                        ignored ("the window froze")
//   M6 pickAt stops asking the engine for geometry     -> the pick returns the deepest node
//                                                        regardless of where the finger is
//                                                        (a second rule for "under the
//                                                        finger", the exact thing the
//                                                        agreement check exists to catch)
//
// Each mutated file is restored in `finally` and its sha256 compared byte-for-byte with
// the pre-mutation hash: a mutation run can never leave the kit subtly altered.
//
// USAGE (from asaotui/):   node probes/widgets/pointer-touch/mutation.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const DIR = __dirname;
const UI = path.resolve(DIR, '..', '..', '..');
const PROBE = 'probes/widgets/pointer-touch';
const RESULTS = path.join(DIR, 'pointer-touch-mutation.txt');

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const MUTATIONS = [
  {
    id: 'M1',
    file: 'kit/asaot/ui/UiApp.as',
    why: 'THE SYNTHETIC EVENT IS AIMED AT THE STAGE: it bubbles from the root, so no node on the path '
      + 'ever sees the press or the click -- a tap is silent and nothing paints pressed',
    find: '            n.backing.dispatchEvent(ev);',
    replace: '            this.stage.dispatchEvent(ev);',
    expect: 'the tap did not click the button',
  },
  {
    id: 'M2',
    file: 'kit/asaot/ui/PointerRouter.as',
    why: 'EVERY PRESS IS DELAYED: the scroller wait is applied to every container, so a plain button only '
      + 'paints pressed 130ms after the finger went down -- the delay exists to protect scrolling, not to tax buttons',
    find: '            if (this.scrollerOf(node) != null)\n            {',
    replace: '            if (true)\n            {',
    expect: 'is not pressed on touch-down',
  },
  {
    id: 'M3',
    file: 'kit/asaot/ui/PointerRouter.as',
    why: 'NO PRESS IS DELAYED: a row inside a scroller flashes pressed on every scroll, because the drag '
      + 'and the tap are decided by the same immediate press',
    find: '            if (this.scrollerOf(node) != null)\n            {',
    replace: '            if (false)\n            {',
    expect: 'a press inside a scroller landed immediately',
  },
  {
    id: 'M4',
    file: 'kit/asaot/ui/PointerRouter.as',
    why: 'SLOP NO LONGER SUPPRESSES THE CLICK: dragging a control also clicks it, which is the "tap fires '
      + 'after a drag" bug every mobile app has shipped at least once',
    find: '                this.noTap = true;\n                if (this.startDrag(p)) return;',
    replace: '                if (this.startDrag(p)) return;',
    expect: 'a dragged touch still clicked the button',
  },
  {
    id: 'M5',
    file: 'kit/asaot/ui/UiApp.as',
    why: 'THE SYNTHETIC GUARD GOES: the hover is re-derived from the node the router itself picked, so the '
      + 'agreement between "our hover" and "the engine hover" becomes true by construction',
    find: '            if (this._synthetic) return;',
    replace: '            if (false) return;',
    expect: "a synthetic touch move replaced the engine's hover",
  },
  {
    id: 'M7',
    file: 'kit/asaot/ui/PointerRouter.as',
    why: 'A CANCELLED TOUCH LEAVES THE PRESS SLOT SET: the button still learns the press is over, but the '
      + 'router never takes the slot back -- so every later touch is dropped and the window looks frozen',
    find: '            if (p.node != null) this.app.dispatchPointerMouse(MouseEvent.MOUSE_UP, p.node, p.x, p.y);\n            this.press = null;',
    replace: '            this.app.dispatchPointerMouse(MouseEvent.MOUSE_UP, p.node, p.x, p.y);\n            // (mutation) the press slot stays taken',
    expect: 'a tap after the cancel did not press the button',
  },
  {
    id: 'M6',
    file: 'kit/asaot/ui/UiApp.as',
    why: 'pickAt STOPS ASKING THE ENGINE: the walk returns the deepest node regardless of where the finger '
      + 'is, which is a second definition of "under the finger" -- precisely what the agreement check catches',
    find: '            if (n.backing.hitTestPoint(x, y, true)) return n;',
    replace: '            return n;',
    expect: 'but the engine hovers',
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
line('MUTATION pointer-touch: ' + caught + '/' + MUTATIONS.length + ' caught, ' + broken + ' problem(s)');
line(broken === 0 && caught === MUTATIONS.length ? 'RESULT: PASS' : 'RESULT: FAIL');
fs.writeFileSync(RESULTS, log.join('\n') + '\n');
process.exit(broken === 0 && caught === MUTATIONS.length ? 0 : 1);

// tools/mutation-air-sweep.cjs -- proves tools/air-sweep.cjs CAN go red.
//
// A gate that only ever says PASS is decoration, and this one is expensive enough
// (a real adl run over 41 pages) that "it passed" has to mean something. The five
// mutations are the five ways this gate is supposed to have teeth:
//
//   M1  THE FIRST DEFECT, re-introduced: `fixDisplayOrder` addresses a display slot
//       by `<internalCount> + <description index>` again. A lifted popup holds a
//       description slot but no display slot, so the index overshoots by one and AIR
//       throws RangeError #2006 on the select / combobox / datePicker pages -- the
//       user-visible bug (a frozen page, an error a frame) that our own runtime CLAMPS
//       away and therefore hides.
//   M2  the sweep stops OPENING the popups. Every page is still visited, nothing
//       throws, the picture is fine -- and the gate must still fail, because a sweep
//       that never opens a popup never exercises the lifted state it exists for. This
//       is the mutation that keeps the gate from quietly going blind: `OPENED <n>` is
//       counted from the MODEL after the flip, not from the argument list.
//   M3  the sweep stops one page early. A window that dies mid-catalog must not look
//       like a pass, so the "every catalog page, in order" criterion has to fire.
//   M4  THE SECOND DEFECT, re-introduced: `destroySubtree` stops releasing the listeners
//       it wired on its own backing. This is `TypeError #1009` out of `UiNode.setHover`
//       -- the report that started the drill -- because AIR delivers `mouseOut` to a
//       display object whose node was torn down one frame earlier. The gate must fail
//       on the thousands of roll-outs the drill makes, and it does: 145 errors before
//       the window died at page 15.
//   M5  the drill stops DELIVERING (the hover capture stays). The sweep is clean, the
//       log looks normal, and the gate must still fail, because a drill that hovered
//       3107 nodes and delivered nothing is exactly the blind test M4 exists to rule
//       out. This one grades `ROLL` lines, not the code's good intentions.
//
// Every file is restored in `finally` and compared by sha256 -- a mutation run can
// never leave the kit or the demo subtly altered.
//
// USAGE (from asaotui/):   node tools/mutation-air-sweep.cjs
//   Needs the AIR SDK (AIRSDK_HOME or --sdk, same as the gate). ~6 adl runs, ~3 min.
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const UI = path.resolve(__dirname, '..');
const RESULTS = path.join(UI, 'reviews', 'mutation-air-sweep.txt');

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const MUTATIONS = [
  {
    id: 'M1',
    why: 'THE REPORTED BUG, re-introduced: the display slot is computed from the description '
      + 'index, so a lifted popup makes it overshoot -> RangeError #2006 on AIR',
    file: 'kit/asaot/ui/Reconciler.as',
    find: '                    n.backing.setChildIndex(c.backing, slot);\n'
      + '                    slot = slot + 1;',
    replace: '                    n.backing.setChildIndex(c.backing, n.internalCount + i);',
    expect: '#2006'
  },
  {
    id: 'M2',
    why: 'the sweep never opens a popup -- 41 pages visited, zero errors, and the lifted '
      + 'state it exists for is never reached (the gate must notice: OPENED)',
    file: 'ui-demo/demo/DocsAir.as',
    find: '                this.flipOpen(true);\n                this.sweepStep = 3;',
    replace: '                this.sweepStep = 3;',
    expect: 'OPENED'
  },
  {
    id: 'M3',
    why: 'the sweep stops one page early -- a window that dies mid-catalog must not pass',
    file: 'ui-demo/demo/DocsAir.as',
    find: 'if (this.sweepIndex >= this.pages.length)',
    replace: 'if (this.sweepIndex >= this.pages.length - 1)',
    expect: 'visited'
  },
  {
    id: 'M4',
    why: 'THE REPORTED CRASH, re-introduced: a torn-down node keeps the listeners it wired '
      + 'on its own backing, so the roll-out AIR delivers one beat later hits a null field '
      + '-> TypeError #1009 out of UiNode.setHover',
    file: 'kit/asaot/ui/UiNode.as',
    find: 'this.releaseListeners();',
    replace: '',
    expect: '#1009'
  },
  {
    id: 'M5',
    why: 'the drill hovers thousands of nodes and delivers nothing -- a clean sweep of a '
      + 'blind test, which is the one outcome this gate must never accept',
    file: 'ui-demo/demo/DocsAir.as',
    find: '                this.dispatchRoll();\n',
    replace: '',
    expect: 'pointer drill'
  }
];

function runGate() {
  return spawnSync(process.execPath, ['tools/air-sweep.cjs'], {
    cwd: UI, encoding: 'utf8', maxBuffer: 1 << 28,
    env: process.env,
  });
}

const log = [];
const line = (s) => { console.log(s); log.push(s); };
let caught = 0;
let broken = 0;

const base = runGate();
const baseOut = (base.stdout || '') + (base.stderr || '');
line('baseline (unmutated): exit ' + base.status);
if (base.status !== 0) {
  line('the baseline is not green; a mutation run would be meaningless. Aborting.');
  for (const l of baseOut.split(/\r?\n/).slice(-20)) line('  ' + l);
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
    const r = runGate();
    const out = (r.stdout || '') + (r.stderr || '');
    const saidIt = out.indexOf(m.expect) >= 0;
    const ok = r.status === 1 && saidIt;
    if (ok) caught++; else broken++;
    line(m.id + '  ' + (ok ? 'CAUGHT' : 'MISSED (THIS IS BAD)') + '  ' + m.why);
    line('     exit ' + r.status + (saidIt ? '' : '  MISSING the expected text "' + m.expect + '"'));
    for (const l of out.split(/\r?\n/).filter((l) => /^  - |^  \[|^\[air-sweep\] \d+\//.test(l)).slice(0, 4)) {
      line('     ' + l.trim().slice(0, 200));
    }
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
line('MUTATION air-sweep: ' + caught + '/' + MUTATIONS.length + ' caught, ' + broken + ' problem(s)');
line(broken === 0 && caught === MUTATIONS.length ? 'RESULT: PASS' : 'RESULT: FAIL');
fs.mkdirSync(path.dirname(RESULTS), { recursive: true });
fs.writeFileSync(RESULTS, log.join('\n') + '\n');
process.exit(broken === 0 && caught === MUTATIONS.length ? 0 : 1);
// probes/widgets/popup/mutation.cjs -- proves tools/probe.cjs CAN go red on the
// open-popup stacking probe.
//
// The defect this probe guards is a RASTERIZATION fact: nothing about the widget's
// rects, keys or callbacks changes when a dropdown is buried under the next card, so
// every structural assertion in the library passes while the screen is wrong. These
// four mutations are the four ways the lift can be missing or wrong:
//
//   M1 the lift never happens (the defect itself: the popup stays a child),
//   M2 the lifted node is positioned with the PARENT-RELATIVE offset (double offset),
//   M3 closing never puts the node back (it stays on the stage container forever),
//   M4 unmounting a LIFTED node leaks its sprite (the old guarded removal path).
//
// Every file is restored in `finally` and its sha256 compared byte-for-byte with the
// pre-mutation hash: a mutation run can never leave the kit subtly altered.
//
// USAGE (from asaotui/):   node probes/widgets/popup/mutation.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const DIR = __dirname;
const UI = path.resolve(DIR, '..', '..', '..');   // probes/widgets/popup -> asaotui
const PROBE = 'probes/widgets/popup';
const RESULTS = path.join(DIR, 'popup-mutation.txt');

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const MUTATIONS = [
  {
    id: 'M1',
    file: 'kit/asaot/ui/kind/SelectWidget.as',
    why: 'THE LIFT NEVER HAPPENS (the reported defect): the open dropdown stays a child of its owner, '
      + 'so the card below paints over rows 1..3 and the selected row is invisible',
    find: '            n.lifted = open;',
    replace: '            n.lifted = false;',
    expect: 'sel.lifted is false not true',
  },
  {
    id: 'M2',
    file: 'kit/asaot/ui/UiNode.as',
    why: 'THE LIFTED NODE KEEPS ITS PARENT-RELATIVE X (the classic double offset): on the stage '
      + 'container the absolute value is the LOCAL value, so the whole popup shifts 20px left and '
      + 'the row no longer reaches the point that was inside it',
    find: '            this.backing.x = this.absX;\n            this.backing.y = this.absY;',
    replace: '            this.backing.x = this.absX - this.parent.absX;\n            this.backing.y = this.absY;',
    expect: '(250,95) the selected row (Normal) over the card is #1e3a8a not #dbeafe',
  },
  {
    id: 'M3',
    file: 'kit/asaot/ui/UiNode.as',
    why: 'CLOSING NEVER PUTS THE NODE BACK: the un-lift branch is short-circuited, so the owner keeps '
      + 'living on the stage container after the list closes (layout still solves, nothing re-attaches)',
    find: '                if (this.parent != null && this.parent.backing != null\n'
      + '                    && this.backing.parent != this.parent.backing)',
    replace: '                if (false)',
    expect: 'sel did not go back into its owner\'s backing',
  },
  {
    id: 'M4',
    file: 'kit/asaot/ui/UiNode.as',
    why: 'UNMOUNTING A LIFTED NODE LEAKS ITS SPRITE: the pre-fix removal path only detached when the '
      + 'display parent was `parent.backing`, which is false for a lifted node -- the popup stays on '
      + 'screen, over the re-flowed page, forever',
    find: '                DisplayObjectContainer(this.backing.parent).removeChild(this.backing);',
    replace: '                if (this.parent != null && this.backing.parent == this.parent.backing)\n'
      + '                    this.parent.backing.removeChild(this.backing);',
    expect: 'unmounting a lifted node left 1 extra display object(s)',
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
line('MUTATION popup: ' + caught + '/' + MUTATIONS.length + ' caught, ' + broken + ' problem(s)');
line(broken === 0 && caught === MUTATIONS.length ? 'RESULT: PASS' : 'RESULT: FAIL');
fs.writeFileSync(RESULTS, log.join('\n') + '\n');
process.exit(broken === 0 && caught === MUTATIONS.length ? 0 : 1);
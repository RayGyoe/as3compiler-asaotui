// probes/widgets/select-scroll/mutation.cjs -- proves tools/probe.cjs CAN go red on the
// select-in-a-scrolled-viewport probe.
//
// The defect this probe pins is ONE root cause with three consequences, so the
// mutations are aimed at each link of the chain rather than at the pixels:
//
//   M1 the visual origin stops subtracting the ancestors' slide -- the reported bug
//      verbatim (the popup lands at the rect the viewport was sliding);
//   M2 the viewport renders the scroll but never PUBLISHES the slide, so every reader
//      of visualX/Y stays at zero;
//   M3 the lift is correct but never RE-SEATED: scrolling the pane repaints the pane,
//      not the popup, so the position is right when it opens at offset 0 and stale
//      after the wheel turns (the reason UiApp keeps a lifted list);
//   M4 the popup is positioned right but PICKED in tree order: a later sibling that
//      sits behind it wins the point, so a tap on a row lands on the spacer;
//   M5 the pick is right but the synthetic pointer reports layout-relative localX/Y:
//      inside a scrolled pane the row under the finger is not `stageY - absY`.
//
// Every file is restored in `finally` and its sha256 compared byte-for-byte with the
// pre-mutation hash: a mutation run can never leave the kit subtly altered.
//
// USAGE (from asaotui/):   node probes/widgets/select-scroll/mutation.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const DIR = __dirname;
const UI = path.resolve(DIR, '..', '..', '..');   // probes/widgets/select-scroll -> asaotui
const PROBE = 'probes/widgets/select-scroll';
const RESULTS = path.join(DIR, 'select-scroll-mutation.txt');
const NODE = 'kit/asaot/ui/UiNode.as';
const APP = 'kit/asaot/ui/UiApp.as';
const WIDGET = 'kit/asaot/ui/kind/ScrollViewWidget.as';

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const MUTATIONS = [
  {
    id: 'M1',
    file: NODE,
    why: 'THE VISUAL ORIGIN IGNORES THE SLIDE: visualY stops subtracting the ancestors\' '
      + 'shift, so the lift places the popup at the LAYOUT rect the pane was sliding -- '
      + 'the reported bug, at the one definition the lift and the synthetic pointer both '
      + 'read',
    find: '                y = y - p.scrollShiftY;',
    replace: '                if (false) y = y - p.scrollShiftY;',
    expect: 'the lifted select is at y 50',
  },
  {
    id: 'M2',
    file: WIDGET,
    why: 'THE VIEWPORT NEVER PUBLISHES ITS SLIDE: the pixels scroll (the scrollRect is '
      + 'assigned) and every consumer of visualX/Y stays at zero',
    find: '            n.scrollShiftY = vy;',
    replace: '            if (false) n.scrollShiftY = vy;',
    expect: 'the lifted select is at y 50',
  },
  {
    id: 'M3',
    file: NODE,
    why: 'THE LIFT IS NEVER RE-SEATED: correct when it opens, stale after the pane '
      + 'scrolls (nothing marks the popup dirty)',
    find: '            this.app.registerLifted(this);',
    replace: '            if (false) this.app.registerLifted(this);',
    expect: 'the lifted select is at y 50',
  },
  {
    id: 'M4',
    file: APP,
    why: 'THE POPUP IS PICKED IN TREE ORDER: a later sibling behind the open dropdown '
      + 'wins the point, so the row tap hits the spacer',
    find: '            if (hit == null) hit = this.pickLifted(x, y);',
    replace: '            if (false) hit = this.pickLifted(x, y);',
    expect: 'the tap did not select a row',
  },
  {
    id: 'M5',
    file: APP,
    why: 'THE SYNTHETIC POINTER REPORTS LAYOUT-RELATIVE LOCAL X/Y: inside a scrolled '
      + 'pane the coordinates name a point 40px away from the finger',
    find: '            var lx:Number = sx - n.visualX();\n'
      + '            var ly:Number = sy - n.visualY();',
    replace: '            var lx:Number = sx - n.absX;\n'
      + '            var ly:Number = sy - n.absY;',
    expect: 'the tap did not select a row',
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
line('MUTATION select-scroll: ' + caught + '/' + MUTATIONS.length + ' caught, ' + broken + ' problem(s)');
line(broken === 0 && caught === MUTATIONS.length ? 'RESULT: PASS' : 'RESULT: FAIL');
fs.writeFileSync(RESULTS, log.join('\n') + '\n');
process.exit(broken === 0 && caught === MUTATIONS.length ? 0 : 1);
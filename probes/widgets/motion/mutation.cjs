// probes/widgets/motion/mutation.cjs -- proves the motion probe CAN go red.
//
// The probe asserts three separable claims (a LAYOUT field animates by re-solving,
// a TEXT colour animates without re-solving, and a floating surface runs an EXIT
// before it disappears). Each mutation below breaks exactly one of them, and the
// probe must fail with the SPECIFIC message named in `expect` -- so "it went red" is
// never confused with "it failed to build".
//
// Every file is restored in `finally` and its sha256 compared with the pre-mutation
// hash: a mutation run can never leave the kit altered.
//
// USAGE (from asaotui/):   node probes/widgets/motion/mutation.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const DIR = __dirname;
const UI = path.resolve(DIR, '..', '..', '..');   // probes/widgets/motion -> asaotui
const PROBE = 'probes/widgets/motion';
const RESULTS = path.join(DIR, 'motion-mutation.txt');

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const MUTATIONS = [
  {
    id: 'M1',
    why: 'a layout tween writes the engine but forgets the dirty bit -> reflow never re-solves, so the '
      + 'sizer stays at its old width for the whole 600ms (the one semantic difference between a layout '
      + 'field and a paint field)',
    file: 'kit/asaot/ui/anim/Anim.as',
    find: '            node.applyEngineStyle();\n            node.markLayoutDirty();',
    replace: '            node.applyEngineStyle();',
    expect: 'not strictly between 100 and 240',
  },
  {
    id: 'M2',
    why: 'paddingLeft stops being a layout field -> the left padding tween becomes a no-op, so the child '
      + 'never moves even though the style says it should',
    file: 'kit/asaot/ui/anim/Anim.as',
    find: '                || field == FIELD_PAD_B || field == FIELD_PAD_L',
    replace: '                || field == FIELD_PAD_B',
    expect: 'the padding did not animate',
  },
  {
    id: 'M3',
    why: 'the text colour is no longer retargeted (it just adopts the new value) -> it SNAPS white on the '
      + 'toggle frame instead of ramping, so the mid sample has no dark pixels left',
    file: 'kit/asaot/ui/UiNode.as',
    find: '                Anim.retarget(this, Anim.FIELD_TEXT, curTc, toTc, ms, ease);',
    replace: '                curTc = toTc;',
    expect: 'mid label has',
  },
  {
    id: 'M4',
    why: 'the exit does not HOLD the node on screen -> the next re-render (description says `visible: false`) '
      + 'hides the surface in the middle of its own exit, which is the one-frame vanish the motion exists to remove',
    file: 'kit/asaot/ui/kind/PanelShellWidget.as',
    find: '                n.extra[EXITING_KEY] = 1;\n                n.visibleHold = 1;',
    replace: '                n.extra[EXITING_KEY] = 1;\n                n.visibleHold = 0;',
    expect: 'disappeared mid-exit',
  },
  {
    id: 'M5',
    why: 'the close path no longer re-shows the node it just hid via the description\'s `visible: false` -> the '
      + 'surface is hidden on the SAME frame it closed and the whole motion is invisible',
    file: 'kit/asaot/ui/kind/PanelShellWidget.as',
    find: '                n.visibleHold = 1;\n                n.visible = true;',
    replace: '                n.visibleHold = 1;',
    expect: 'the closing dialog is already invisible',
  },
  {
    id: 'M6',
    why: 'the exit never lands -> the surface stays visible (and keeps painting) forever',
    file: 'kit/asaot/ui/OverlayMotion.as',
    find: 'public static const EXIT_MS:int = 120;',
    replace: 'public static const EXIT_MS:int = 3000;',
    expect: 'the exit motion never finished',
  },
  {
    id: 'M7',
    why: 'the landing frame forgets to hide the surface -> the motion completes but the dialog is left on '
      + 'screen (an "invisible" node that still paints)',
    file: 'kit/asaot/ui/kind/PanelShellWidget.as',
    find: '                    n.extra[EXITING_KEY] = 0;\n                    n.visibleHold = 0;\n                    n.visible = false;',
    replace: '                    n.extra[EXITING_KEY] = 0;\n                    n.visibleHold = 0;\n                    n.visible = true;',
    expect: 'the dialog is still visible after the exit landed',
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
line('MUTATION motion: ' + caught + '/' + MUTATIONS.length + ' caught, ' + broken + ' problem(s)');
line(broken === 0 && caught === MUTATIONS.length ? 'RESULT: PASS' : 'RESULT: FAIL');
fs.writeFileSync(RESULTS, log.join('\n') + '\n');
process.exit(broken === 0 && caught === MUTATIONS.length ? 0 : 1);
// probes/widgets/callback/mutation.cjs -- proves tools/probe.cjs CAN go red on this
// probe, and that the probe measures the CONTRACT rather than the pixels it happens
// to look at.
//
// The first four mutations are the defect this probe exists for, re-introduced one
// kind at a time: a value callback called with NO argument throws #1063 on a handler
// that declares one, so the handler never runs and the counter stays at zero. The
// rest pin the slider's drag: that the value change reaches the SCREEN at all (M5 is
// the `invalidate`-only defect), that the release really detaches the stage listener
// (M6), that motion follows the pointer (M7), and that one gesture is one report (M8).
//
// Every file is restored in `finally` and its sha256 compared byte-for-byte with the
// pre-mutation hash: a mutation run can never leave the kit subtly altered.
//
// USAGE (from asaotui/):   node probes/widgets/callback/mutation.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const DIR = __dirname;
const UI = path.resolve(DIR, '..', '..', '..');   // probes/widgets/callback -> asaotui
const PROBE = 'probes/widgets/callback';
const RESULTS = path.join(DIR, 'callback-mutation.txt');

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const MUTATIONS = [
  {
    id: 'M1',
    why: 'the slider reports with no argument (THE REPORTED BUG): the handler declares (v:Number), so it '
      + 'never runs and every later counter reads 0',
    file: 'kit/asaot/ui/kind/SliderWidget.as',
    find: 'if (n.onChange != null) n.onChange(v);',
    replace: 'if (n.onChange != null) n.onChange();',
    expect: 'slider onChange'
  },
  {
    id: 'M2',
    why: 'the checkbox reports with no argument',
    file: 'kit/asaot/ui/kind/CheckboxWidget.as',
    find: 'else if (n.onChange != null) n.onChange(next);',
    replace: 'else if (n.onChange != null) n.onChange();',
    expect: 'checkbox onChange'
  },
  {
    id: 'M3',
    why: 'the switch reports with no argument',
    file: 'kit/asaot/ui/kind/SwitchWidget.as',
    find: 'else if (n.onChange != null) n.onChange(next);',
    replace: 'else if (n.onChange != null) n.onChange();',
    expect: 'toggle onChange'
  },
  {
    id: 'M4',
    why: 'the radio drops the constant `true` it still has to pass',
    file: 'kit/asaot/ui/kind/RadioWidget.as',
    find: 'else if (n.onChange != null) n.onChange(true);',
    replace: 'else if (n.onChange != null) n.onChange();',
    expect: 'radio onChange'
  },
  {
    id: 'M5',
    why: 'the widget stops raising its OWN paint request (invalidate alone): the value changes, the model '
      + 'agrees, and nothing ever repaints. Sampled MID-drag, because the release flips the pressed state '
      + 'and that repaint would hide this one',
    file: 'kit/asaot/ui/kind/SliderWidget.as',
    find: '            n.app.markPaint(n);\n            n.app.invalidate(Dirty.VALUE);',
    replace: '            n.app.invalidate(Dirty.VALUE);',
    expect: 'the knob must follow the drag'
  },
  {
    // ONE conceptual change, both halves: `endDrag` also clears the DRAG flag, so
    // deleting only the removeEventListener calls is behaviourally invisible (the
    // flag makes a surviving listener a no-op -- it just leaks a closure per
    // destroyed slider). The contract the assertion names is "the release ends the
    // drag", so the mutation makes the release do nothing at all.
    id: 'M6',
    why: 'the release ENDS NOTHING: the stage listener stays attached and the drag flag stays set, so a '
      + 'later pointer move keeps dragging the value',
    file: 'kit/asaot/ui/kind/SliderWidget.as',
    find: 'private function endDrag(n:UiNode):void\n        {',
    replace: 'private function endDrag(n:UiNode):void\n        {\n            if (n != null) return;   // mutation: the release ends nothing',
    expect: 'the stage listener survived the release'
  },
  {
    id: 'M7',
    why: 'motion is ignored, so only the press sets the value (a slider that looks draggable and is not)',
    file: 'kit/asaot/ui/kind/SliderWidget.as',
    find: 'if (int(n.extra[DRAG]) == 0) return;',
    replace: 'return;',
    expect: 'the drag did not follow to 0.75'
  },
  {
    id: 'M8',
    why: 'the "only report a CHANGE" gate is removed, so the press and the click the window glue sends '
      + 'afterwards both report -- one gesture, two model writes',
    file: 'kit/asaot/ui/kind/SliderWidget.as',
    find: 'if (!isNaN(prev) && prev == v) return;',
    replace: '// (mutation: an unchanged value is reported again)',
    expect: 'pressing where the value already is reported a change'
  }
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
    const ok = verdict != null && verdict[1] === 'FAIL' && saidIt && !buildFailed && !timedOut;
    if (ok) caught++; else broken++;
    line(m.id + '  ' + (ok ? 'CAUGHT' : 'MISSED (THIS IS BAD)') + '  ' + m.why);
    line('     verdict: ' + (verdict ? verdict[0] : 'none')
      + (buildFailed ? '  BUILD FAILED -- a mutation that does not compile proves nothing' : '')
      + (timedOut ? '  TIMEOUT -- an opaque failure is not a named one' : '')
      + (saidIt ? '' : '  MISSING the expected failure line "' + m.expect + '"'));
    const fails = out.split(/\r?\n/).filter((l) => /  FAIL  /.test(l));
    for (const f of fails.slice(0, 3)) line('     ' + f.trim().slice(0, 220));
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
line('MUTATION callback: ' + caught + '/' + MUTATIONS.length + ' caught, ' + broken + ' problem(s)');
line(broken === 0 && caught === MUTATIONS.length ? 'RESULT: PASS' : 'RESULT: FAIL');
fs.writeFileSync(RESULTS, log.join('\n') + '\n');
process.exit(broken === 0 && caught === MUTATIONS.length ? 0 : 1);
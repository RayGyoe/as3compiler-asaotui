// probes/widgets/typing/mutation.cjs -- proves tools/probe.cjs CAN go red on the
// single-line field probe.
//
// Both defects that started this probe were VISIBLE, not structural: the model, the
// callbacks and the rects were all correct while the screen lied. So each mutation
// puts back one specific lie, one per behaviour the widget owes its author:
//
//   M1 the ghost never goes away          -> "the placeholder stays while I type"
//                                            (the first reported defect, verbatim),
//   M2 the ghost ignores the focus gate   -> ghost over the caret of an empty field,
//   M3 paint calls setTextFormat again    -> the runtime APPENDS one run per call and
//                                            paints the string once per run, so every
//                                            repaint doubles the text (defect b),
//   M4 blur never reports the commit      -> onCommit is lost.
//
// Every file is restored in `finally` and its sha256 compared byte-for-byte with the
// pre-mutation hash: a mutation run can never leave the kit subtly altered.
//
// USAGE (from asaotui/):   node probes/widgets/typing/mutation.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const DIR = __dirname;
const UI = path.resolve(DIR, '..', '..', '..');   // probes/widgets/typing -> asaotui
const PROBE = 'probes/widgets/typing';
const FILE = 'kit/asaot/ui/kind/InputWidget.as';
const RESULTS = path.join(DIR, 'typing-mutation.txt');

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const MUTATIONS = [
  {
    id: 'M1',
    why: 'THE GHOST NEVER GOES AWAY (reported defect a, verbatim): visible is forced on instead of being '
      + 'derived from "the model is empty", so "Placeholder text goes right here" sits on top of the '
      + 'typing for as long as the field is on screen',
    find: '            ph.visible = usePh;',
    replace: '            ph.visible = true;',
    expect: 'while it should be hidden',
  },
  {
    id: 'M2',
    why: 'THE GHOST IGNORES THE FOCUS GATE: the caret of a focused empty field sits exactly where the '
      + 'ghost text is, so the ghost must be hidden before the first character lands',
    find: '            var usePh:Boolean = shown.length == 0 && n.state.focused == 0',
    replace: '            var usePh:Boolean = shown.length == 0',
    expect: 'focused: the ghost is visible, expected hidden',
  },
  {
    id: 'M3',
    why: 'setTextFormat IS CALLED FROM paint AGAIN (reported defect b): the runtime APPENDS one run per '
      + 'call instead of replacing the range, and its run-to-paragraph builder emits the string once per '
      + 'run -- so every repaint makes the same text wider and the screen shows it twice',
    find: '            n.tf.textColor = uint(color);',
    replace: '            n.tf.textColor = uint(color);\n            n.tf.setTextFormat(f);',
    expect: '(runs accumulated)',
  },
  {
    id: 'M4',
    why: 'BLUR NEVER REPORTS THE COMMIT: onFieldBlur still reads the field into the model but the author\'s '
      + 'onCommit is never called, so "finished with this field" is silently lost',
    find: '            if (n.onCommit != null) n.onCommit(n.value);',
    replace: '            if (false) n.onCommit(n.value);',
    expect: "onCommit got '' not '1111'",
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
  const file = path.join(UI, FILE);
  const before = fs.readFileSync(file, 'utf8');
  const beforeHash = sha(file);
  if (before.indexOf(m.find) < 0) {
    line(m.id + '  SKIPPED -- anchor text not found in ' + FILE
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
line('MUTATION typing: ' + caught + '/' + MUTATIONS.length + ' caught, ' + broken + ' problem(s)');
line(broken === 0 && caught === MUTATIONS.length ? 'RESULT: PASS' : 'RESULT: FAIL');
fs.writeFileSync(RESULTS, log.join('\n') + '\n');
process.exit(broken === 0 && caught === MUTATIONS.length ? 0 : 1);
// probes/widgets/text-align/mutation.cjs -- proves the text-align probe CAN go red.
//
// The probe asserts that a run lines up inside its BOX: left at the left edge, centre
// at the box's centre, right at the box's right edge. Each mutation breaks exactly one
// branch of that and must fail with the SPECIFIC message named in `expect`, so "it went
// red" is never confused with "it failed to build".
//
// Every file is restored in `finally` and its sha256 compared with the pre-mutation
// hash: a mutation run can never leave the kit altered.
//
// USAGE (from asaotui/):   node probes/widgets/text-align/mutation.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const DIR = __dirname;
const UI = path.resolve(DIR, '..', '..', '..');   // probes/widgets/text-align -> asaotui
const PROBE = 'probes/widgets/text-align';
const RESULTS = path.join(DIR, 'text-align-mutation.txt');

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const MUTATIONS = [
  {
    id: 'M1',
    why: 'the alignment offset is dropped -- the pre-fix behaviour: the field is autoSize "left", so the '
      + 'run sits at the box\'s left edge whatever textAlign says (this is the reported tab-bar symptom)',
    file: 'kit/asaot/ui/kind/TextWidget.as',
    find: '            if (s.text.whiteSpace != "normal" && (al == "center" || al == "right"))',
    replace: '            if (false)',
    expect: "the centred run's ink centre",
  },
  {
    id: 'M2',
    why: 'RIGHT is treated as CENTRE -- the offset uses slack/2 for both, so a right-aligned run lands in '
      + 'the middle of its box (and a numeric column stops hugging its right edge)',
    file: 'kit/asaot/ui/kind/TextWidget.as',
    find: '                if (slack > 0.5) n.tf.x = n.tf.x + (al == "center" ? slack / 2 : slack);',
    replace: '                if (slack > 0.5) n.tf.x = n.tf.x + slack / 2;',
    expect: 'the right-aligned run ends at',
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
    for (const f of fails.slice(0, 4)) line('     ' + f.trim().slice(0, 300));
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
line('MUTATION text-align: ' + caught + '/' + MUTATIONS.length + ' caught, ' + broken + ' problem(s)');
line(broken === 0 && caught === MUTATIONS.length ? 'RESULT: PASS' : 'RESULT: FAIL');
fs.writeFileSync(RESULTS, log.join('\n') + '\n');
process.exit(broken === 0 && caught === MUTATIONS.length ? 0 : 1);
// probes/widgets/gutter/mutation.cjs -- proves tools/probe.cjs CAN go red on the
// gutter probe.
//
// The subtlety this file exists for: the bar is OPAQUE, so a bitmap cannot tell a
// reserved lane from a covered one. Only the solved rect can, which is why the
// mutations below are aimed at the lane's arithmetic rather than at pixels -- and
// why one of them (M3) is aimed at the pixels, to prove "reserve the lane" did not
// quietly become "move the bar off its edge".
//
//   M1 the widget never asks for the lane (setScrollGutter(0, 0)): the description
//      says "stable" and the layout does not move,
//   M2 the node folds nothing (UiNode.foldInsets drops the right gutter): the request
//      reaches the node and dies there,
//   M3 the bar is painted one thickness further in, so the lane is reserved AND the
//      bar leaves half of it: the content is clear, the thumb is in the wrong place.
//
// Every file is restored in `finally` and its sha256 compared byte-for-byte with the
// pre-mutation hash: a mutation run can never leave the kit subtly altered.
//
// USAGE (from asaotui/):   node probes/widgets/gutter/mutation.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const DIR = __dirname;
const UI = path.resolve(DIR, '..', '..', '..');   // probes/widgets/gutter -> asaotui
const PROBE = 'probes/widgets/gutter';
const RESULTS = path.join(DIR, 'gutter-mutation.txt');
const WIDGET = 'kit/asaot/ui/kind/ScrollViewWidget.as';
const NODE = 'kit/asaot/ui/UiNode.as';

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const MUTATIONS = [
  {
    id: 'M1',
    file: WIDGET,
    why: 'THE WIDGET NEVER ASKS FOR THE LANE: a description that says "stable" lays its '
      + 'content out in the whole box, i.e. the mode is a no-op',
    find: '            n.setScrollGutter(stable && sv.scrollbarY != "never" ? lane : 0,\n'
      + '                              stable && sv.scrollbarX != "never" ? lane : 0);',
    replace: '            n.setScrollGutter(0, 0);',
    expect: 'rect stablec[w]',
  },
  {
    id: 'M2',
    file: NODE,
    why: 'THE NODE FOLDS NOTHING: the request arrives and the right gutter is dropped from '
      + 'the padding fold, so the content keeps the full width',
    find: '            if (this.gutterRight != 0) r = (isNaN(r) ? 0 : r) + this.gutterRight;',
    replace: '            if (false) r = (isNaN(r) ? 0 : r) + this.gutterRight;',
    expect: 'rect stablec[w]',
  },
  {
    id: 'M3',
    file: WIDGET,
    why: 'THE BAR IS PAINTED ONE LANE FURTHER IN: the content is clear of the lane and the '
      + 'thumb sits over the content instead of in its lane',
    find: '            if (wantY) { bars[2] = w - t; bars[3] = 0; bars[4] = t; bars[5] = vTrackH; }',
    replace: '            if (wantY) { bars[2] = w - t * 2; bars[3] = 0; bars[4] = t; bars[5] = vTrackH; }',
    // The bar lands on the band's last 10px, so the pixel that proves "content
    // stops before the lane" is the one that goes red.
    expect: 'pixel (205,80)', 
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
line('MUTATION gutter: ' + caught + '/' + MUTATIONS.length + ' caught, ' + broken + ' problem(s)');
line(broken === 0 && caught === MUTATIONS.length ? 'RESULT: PASS' : 'RESULT: FAIL');
fs.writeFileSync(RESULTS, log.join('\n') + '\n');
process.exit(broken === 0 && caught === MUTATIONS.length ? 0 : 1);
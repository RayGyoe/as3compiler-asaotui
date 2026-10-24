// probes/widgets/stick/mutation.cjs -- proves probes/widgets/stick CAN go red on
// ScrollView's `stickToBottom`.
//
// Every mutation is one CONTRACT, not one bug: each removes exactly the mechanism whose
// absence the probe is supposed to see, so a green run after a mutation would mean the
// probe is measuring nothing.
//
//   S1 sticky is never applied            -> the flag is parsed and then ignored: the view
//                                            opens at the TOP of a log and never follows
//   S2 position is not consulted          -> a reader who scrolled up is yanked back to the
//                                            end on every append
//   S3 "at the end" measured AFTER growth -> every offset is short of the new end, so the
//                                            view never follows at all; this is the bug the
//                                            PREV_MAX_Y bookkeeping exists to prevent
//   S4 a fresh view is not "at the end"   -> a log opens on its OLDEST line, and the first
//                                            growth leaves it at the top forever
//   S5 the slack becomes a tolerance      -> "near the end" counts as at-the-end, so a
//                                            reader 24px up still gets dragged down
//
// Each mutated file is restored in `finally` and its sha256 compared byte-for-byte with
// the pre-mutation hash: a mutation run can never leave the kit subtly altered.
//
// USAGE (from asaotui/):   node probes/widgets/stick/mutation.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const DIR = __dirname;
const UI = path.resolve(DIR, '..', '..', '..');   // probes/widgets/stick -> asaotui
const PROBE = 'probes/widgets/stick';
const RESULTS = path.join(DIR, 'stick-mutation.txt');

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const MUTATIONS = [
  {
    id: 'S1',
    file: 'kit/asaot/ui/kind/ScrollViewWidget.as',
    why: 'STICKY IS NEVER APPLIED: the option is parsed, carried on the node and then ignored, so a log opens '
      + 'at its oldest line and content growth scrolls nothing',
    find: 'if (sv.stickToBottom && atBottom(n, maxY))',
    replace: 'if (false && sv.stickToBottom && atBottom(n, maxY))',
    expect: 'a fresh sticky view sits at',
  },
  {
    id: 'S2',
    file: 'kit/asaot/ui/kind/ScrollViewWidget.as',
    why: 'THE POSITION IS NOT CONSULTED: every append drags the reader back to the end, so scrolling up in a '
      + 'live log is impossible',
    find: 'if (sv.stickToBottom && atBottom(n, maxY))',
    replace: 'if (sv.stickToBottom)',
    expect: 'content growth yanked the view',
  },
  {
    id: 'S3',
    file: 'kit/asaot/ui/kind/ScrollViewWidget.as',
    why: '"AT THE END" IS MEASURED AFTER THE GROWTH: once maxY has moved, every offset is short of it, so the '
      + 'view never follows -- the exact bug the previous-frame bookkeeping exists to prevent',
    find: '            var sv:ScrollViewNode = ScrollViewNode(n.desc);\n'
      + '            var ox:Number = clamp(Number(n.extra[LIVE_X]), maxX);',
    replace: '            var sv:ScrollViewNode = ScrollViewNode(n.desc);\n'
      + '            n.extra[MAX_Y] = maxY;\n'
      + '            n.extra[PREV_MAX_Y] = maxY;\n'
      + '            var ox:Number = clamp(Number(n.extra[LIVE_X]), maxX);',
    expect: 'the sticky view is at',
  },
  {
    id: 'S4',
    file: 'kit/asaot/ui/kind/ScrollViewWidget.as',
    why: 'A FRESH VIEW IS NOT "AT THE END": a log opens on its oldest line, and with nothing scrolled there is '
      + 'no growth that can re-attach it',
    find: '            if (prev == null) return true;',
    replace: '            if (prev == null) return false;',
    expect: 'a fresh sticky view sits at',
  },
  {
    id: 'S5',
    file: 'kit/asaot/ui/kind/ScrollViewWidget.as',
    why: 'THE SLACK BECOMES A TOLERANCE: 0.5px of rounding allowance widened to 100px, so a reader who scrolled '
      + 'up a notch still counts as "at the end" and is dragged back down',
    find: '            return live >= Number(prev) - 0.5;',
    replace: '            return live >= Number(prev) - 100.0;',
    expect: 'content growth yanked the view',
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
line('MUTATION stick: ' + caught + '/' + MUTATIONS.length + ' caught, ' + broken + ' problem(s)');
line(broken === 0 && caught === MUTATIONS.length ? 'RESULT: PASS' : 'RESULT: FAIL');
fs.writeFileSync(RESULTS, log.join('\n') + '\n');
process.exit(broken === 0 && caught === MUTATIONS.length ? 0 : 1);
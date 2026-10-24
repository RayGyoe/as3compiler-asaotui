// probes/g16-ternary-null/mutation.cjs -- proves run.cjs CAN go red.
//
// A probe that cannot fail is decoration. Each mutation is a deliberate one-token
// change to the thing the probe measures; after it, run.cjs MUST change verdict.
// Every file is restored in `finally` and its sha256 is compared byte-for-byte with
// the pre-mutation hash, so a mutation run can never leave the probe subtly altered.
//
// HISTORY (read this before "simplifying" the list): while G16 was OPEN, two of the
// four mutations measured the defect itself -- "patch case 1 into the if/return
// workaround, the failure must disappear" and "rewrite the working case 6 into the
// broken shape, it must join the failure set". Both went VACUOUS the moment the
// compiler was fixed (stage 266, v0.4.230), because a broken shape now works and a
// patched one changes nothing. They are NOT deleted and NOT left in place: they are
// re-pointed at the harness properties that still have to hold when there is no
// deviation to observe -- the AIR arm is rebuilt from the source rather than read
// from a stale file, the rule is checked against it, a dying arm is reported as such,
// and a build failure is never mistaken for agreement. Deleting them would leave the
// probe's teeth unverified; keeping them as-is would have made the whole script pass
// by measuring nothing.
//
// USAGE (from asaotui/):   node probes/g16-ternary-null/mutation.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const DIR = __dirname;
const UI = path.resolve(DIR, '..', '..');
const RUN = path.join(DIR, 'run.cjs');
const RESULTS = path.join(DIR, 'g16-ternary-null-mutation.txt');

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const MUTATIONS = [
  {
    id: 'M1',
    why: 'the RULE is checked, not assumed: expect.json claims case 1 is NULL while the source says '
      + 'otherwise -> the runner must report that the REFERENCE disagrees with the hand-derived rule',
    file: 'probes/g16-ternary-null/expect.json',
    find: '    "1": "ok",',
    replace: '    "1": "NULL",',
    expectSubstring: 'the REFERENCE disagrees',
  },
  {
    id: 'M2',
    why: 'the AIR arm is REBUILT from the source, not read off a stale file: case 17 answers 8 instead '
      + 'of 7 -> AIR must now disagree with the rule (and the AOT arm must follow the source too)',
    file: 'probes/g16-ternary-null/NullCases.as',
    find: '        private static function t17(x:Object):int { return x == null ? null : 7; }',
    replace: '        private static function t17(x:Object):int { return x == null ? null : 8; }',
    expectSubstring: 'the REFERENCE disagrees',
  },
  {
    id: 'M3',
    why: 'an arm that DIES is reported, not silently compared against missing lines: case 3 returns a '
      + 'bare null from both branches -> the AIR arm stops after id 2 and the runner must say so',
    file: 'probes/g16-ternary-null/NullCases.as',
    find: 'private static function t3(x:Object):Bitmap { return 1 == 0 ? null : Bitmap(x); }',
    replace: 'private static function t3(x:Object):Bitmap { return 1 == 0 ? null : null; }',
    expectSubstring: 'AIR arm wrote only',
  },
  {
    id: 'M4',
    why: 'a BUILD failure is never mistaken for agreement: a parse error in the case table must make the '
      + 'runner stop with "AOT BUILD FAILED" (exit 2) instead of comparing against nothing',
    file: 'probes/g16-ternary-null/NullCases.as',
    find: '        public static const COUNT:int = 20;',
    replace: '        public static const COUNT:int = ;',
    expectSubstring: 'AOT BUILD FAILED',
    expectExit: 2,
  },
];

const log = [];
const line = (s) => { console.log(s); log.push(s); };
let caught = 0;
let broken = 0;

for (const m of MUTATIONS) {
  const file = path.join(UI, m.file);
  const before = fs.readFileSync(file, 'utf8');
  const beforeHash = sha(file);
  if (before.indexOf(m.find) < 0) {
    line(m.id + '  SKIPPED -- anchor text not found in ' + m.file
      + ' (the probe file drifted; fix the mutation, do not ignore it)');
    broken++;
    continue;
  }
  try {
    fs.writeFileSync(file, before.split(m.find).join(m.replace));
    const r = spawnSync(process.execPath, [RUN], { cwd: UI, encoding: 'utf8' });
    const out = (r.stdout || '') + (r.stderr || '');

    let ok = out.indexOf(m.expectSubstring) >= 0;
    let detail = ok ? '' : ' expected the runner to say "' + m.expectSubstring + '"';
    if (m.expectExit != null && r.status !== m.expectExit) {
      ok = false;
      detail += ' (exit ' + r.status + ', wanted ' + m.expectExit + ')';
    }
    if (ok) caught++; else broken++;
    line(m.id + '  ' + (ok ? 'CAUGHT' : 'MISSED (THIS IS BAD)') + '  ' + m.why + detail);
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
line('MUTATION ' + path.basename(DIR) + ': ' + caught + '/' + MUTATIONS.length + ' caught, ' + broken + ' problem(s)');
line(broken === 0 ? 'RESULT: PASS' : 'RESULT: FAIL');
fs.writeFileSync(RESULTS, log.join('\n') + '\n');
process.exit(broken === 0 && caught === MUTATIONS.length ? 0 : 1);
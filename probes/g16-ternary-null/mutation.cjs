// probes/g16-ternary-null/mutation.cjs -- proves run.cjs CAN go red.
//
// A probe that cannot fail is decoration. Each mutation is a deliberate one-token
// change to the thing the probe measures; after it, run.cjs MUST change verdict.
// Every file is restored in `finally` and its sha256 is compared byte-for-byte with
// the pre-mutation hash, so a mutation run can never leave the probe subtly altered.
//
// Kept only until G16 is fixed by the compiler: once the AOT arm passes all 14 cases
// the first mutation below ("patch the shape the probe is measuring") stops being
// meaningful in its current form and turns into "re-introduce the shape", which is
// the mirror image. The note is here so that whoever closes G16 rewrites M1 rather
// than deleting it -- deleting it would leave the probe's teeth unverified.
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
    why: 'case 1 patched to the if/return workaround -> the AOT arm must STOP reporting id 1 as NULL '
      + '(this is the "the probe reads the real value" direction)',
    file: 'probes/g16-ternary-null/NullCases.as',
    find: '        private static function t1(x:Object):Bitmap { return x == null ? null : Bitmap(x); }',
    replace: '        private static function t1(x:Object):Bitmap\n'
      + '        {\n'
      + '            if (x == null) return null;\n'
      + '            return Bitmap(x);\n'
      + '        }',
    // with the shape patched, the count of FAIL lines must drop by exactly one
    expectFewerFails: true,
    wantFailedIdsNot: ['1'],
  },
  {
    id: 'M2',
    why: 'the rule itself: expect.json claims case 1 is NULL -> the runner must report that the '
      + 'REFERENCE disagrees with the hand-derived rule',
    file: 'probes/g16-ternary-null/expect.json',
    find: '    "1": "ok",',
    replace: '    "1": "NULL",',
    expectSubstring: 'the REFERENCE disagrees',
  },
  {
    id: 'M3',
    why: 'case 6 -- the WORKING shape -- rewritten into the broken one: id 6 must join the failing set '
      + '(the probe follows the source, not a snapshot)',
    file: 'probes/g16-ternary-null/NullCases.as',
    find: '        private static function t6(x:Object):Bitmap { return x != null ? Bitmap(x) : null; }',
    replace: '        private static function t6(x:Object):Bitmap { return x == null ? null : Bitmap(x); }',
    expectFailedIds: ['6'],
  },
  {
    id: 'M4',
    why: 'case 3 returns a bare null from both branches -> measured: the AIR arm DIES after id 2, and the '
      + 'runner must say so instead of comparing against missing lines',
    file: 'probes/g16-ternary-null/NullCases.as',
    find: 'private static function t3(x:Object):Bitmap { return 1 == 0 ? null : Bitmap(x); }',
    replace: 'private static function t3(x:Object):Bitmap { return 1 == 0 ? null : null; }',
    expectSubstring: 'AIR arm wrote only',
  },
];

const log = [];
const line = (s) => { console.log(s); log.push(s); };
let caught = 0;
let broken = 0;

// Baseline (unmutated) failure set, computed once so each mutation is compared
// against a measured reference rather than a guess.
const base = spawnSync(process.execPath, [RUN], { cwd: UI, encoding: 'utf8' });
const baseOut = (base.stdout || '') + (base.stderr || '');
const baselineFailIds = [...new Set([...baseOut.matchAll(/FAIL  id (\d+)/g)].map((x) => x[1]))];
line('baseline (unmutated): ' + baselineFailIds.length + ' failing case(s): ' + baselineFailIds.join(', '));
line('');

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
    const failedIds = [...new Set([...out.matchAll(/FAIL  id (\d+)/g)].map((x) => x[1]))];

    let ok = false;
    let detail = '';
    if (m.expectSubstring) {
      ok = out.indexOf(m.expectSubstring) >= 0;
      detail = ok ? '' : ' expected the runner to say "' + m.expectSubstring + '"';
    } else if (m.expectFewerFails) {
      ok = failedIds.length === baselineFailIds.length - 1
        && !failedIds.includes(m.wantFailedIdsNot[0]);
      detail = ok ? '' : ' baseline failed ids [' + baselineFailIds.join(',') + '], mutated [' + failedIds.join(',') + ']';
    } else if (m.expectFailedIds) {
      ok = m.expectFailedIds.every((id) => failedIds.includes(id));
      detail = ok ? '' : ' mutated failed ids [' + failedIds.join(',') + ']';
    }
    if (ok) caught++; else broken++;
    line(m.id + '  ' + (ok ? 'CAUGHT' : 'MISSED (THIS IS BAD)') + '  ' + m.why + detail);
    if (failedIds.length) line('     failed cases with the mutation: ' + failedIds.join(', '));
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

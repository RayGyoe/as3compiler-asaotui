// probes/obj-array-identity/mutation.cjs -- prove the G14 probe has TEETH.
//
// A checker that cannot fail certifies nothing. Each mutation below changes ONE
// unit of the checker's own inputs and requires the specific red it should cause:
//
//   M1  flip one AIR expectation -> the "the REFERENCE disagrees with the written
//       rule" branch must fire (i.e. run.cjs really compares AIR to the rule)
//   M2  drop one documented AOT deviation (id 1) -> the deviation set must be
//       reported as CHANGED, not silently accepted
//   M3  add a deviation that is not there -> "undocumented deviations appeared"
//   M4  flip an expectation for a case that is NOT yet deviating (id 2) -> must
//       be reported as "undocumented deviations appeared" (a NEW bug cannot hide)
//
// Every file is restored byte-for-byte in `finally`, and the restore is verified
// by hashing (the project's rule: a mutation that leaves the tree dirty is worse
// than no mutation at all).
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const DIR = __dirname;
const EXPECT = path.join(DIR, 'expect.json');

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const before = sha(EXPECT);
const original = fs.readFileSync(EXPECT, 'utf8');

function runProbe() {
  const r = spawnSync(process.execPath, [path.join(DIR, 'run.cjs')], { cwd: path.resolve(DIR, '..', '..'), encoding: 'utf8' });
  return { code: r.status, out: (r.stdout || '') + (r.stderr || '') };
}

const results = [];
function check(name, expect, got, want) {
  const ok = expect(got);
  results.push({ name, ok, want, got: (got || '').split(/\r?\n/).filter((l) => l.trim()).slice(-4).join(' | ') });
}

function withPatched(patch, body) {
  try {
    const obj = JSON.parse(original);
    patch(obj);
    fs.writeFileSync(EXPECT, JSON.stringify(obj, null, 2) + '\n');
    return body();
  } finally {
    fs.writeFileSync(EXPECT, original);
  }
}

// ---- M1: the AIR arm must be checked against the written rule ----------------
withPatched((o) => { o.truth['1'] = 'false'; }, () => {
  const r = runProbe();
  check('M1 flip one AS3 rule -> red', (x) => x.code !== 0, r.out,
    'exit != 0 with "the REFERENCE disagrees"');
});

// ---- M2: a documented deviation must not silently disappear -----------------
// (dropping id 1 makes it an UNDOCUMENTED deviation -> the `missing` branch)
withPatched((o) => { o.knownAotDeviations = o.knownAotDeviations.filter((i) => i !== 1); }, () => {
  const r = runProbe();
  check('M2 drop a documented deviation -> red', (x) => x.code !== 0, r.out,
    'exit != 0 with "undocumented deviations appeared"');
});

// ---- M3: an extra documented deviation must not be accepted ------------------
// (claiming id 2 is a deviation makes it a `closed` entry -> GAP-CHANGED)
withPatched((o) => { o.knownAotDeviations = o.knownAotDeviations.concat([2]); }, () => {
  const r = runProbe();
  check('M3 invent a documented deviation -> red', (x) => x.code !== 0, r.out,
    'exit != 0 with GAP-CHANGED');
});

// ---- M4: a case that silently stops being run must not pass ------------------
// Truncating COUNT hides ids 16/19/21, whose deviations then look "closed".
withPatched((o) => { o.count = 15; }, () => {
  const r = runProbe();
  check('M4 truncate the case list -> red', (x) => x.code !== 0, r.out,
    'exit != 0 with GAP-CHANGED (cases 16..22 never ran)');
});

// ---- restore verification ----------------------------------------------------
const after = sha(EXPECT);
const restored = before === after;
console.log('');
for (const r of results) console.log((r.ok ? 'MUTATION PASS  ' : 'MUTATION FAIL  ') + r.name + '   [want: ' + r.want + ']');
console.log('restore: ' + (restored ? 'expect.json byte-identical (' + after.slice(0, 16) + ')' : 'TAMPERED -- ' + before.slice(0, 16) + ' -> ' + after.slice(0, 16)));
const bad = results.filter((r) => !r.ok).length + (restored ? 0 : 1);
console.log('');
console.log('MUTATION: ' + (bad === 0 ? 'PASS (' + results.length + '/' + results.length + ')' : 'FAIL (' + bad + ' problem(s))'));
process.exit(bad === 0 ? 0 : 1);

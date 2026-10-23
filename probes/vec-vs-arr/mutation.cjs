// probes/vec-vs-arr/mutation.cjs -- prove the Vector benchmark has TEETH.
//
// A benchmark that cannot fail proves nothing. Two independent mutations:
//
//   M1  lower the claim to an impossible target (RATIO_CLAIM = 0.001) -> the claim
//       branch must fire, i.e. the ratio really is asserted and not just printed.
//   M2  make the "Vector.<int>" benchmark actually RUN ON AN ARRAY (one line of
//       BenchCore.as: `new Vector.<int>()` -> `[]`) -> the measured ratio must
//       collapse towards 1 and the gate must go red. This is the strong one: it
//       proves the number comes from a measurement of the real lowering, so if the
//       monomorphized element storage ever disappears the gate notices.
//
// Both restore their file byte-for-byte in `finally`, verified by hash.
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const DIR = __dirname;
const UI = path.resolve(DIR, '..', '..');
const RUN = path.join(DIR, 'run.cjs');
const CORE = path.join(DIR, 'BenchCore.as');

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const hashBefore = { run: sha(RUN), core: sha(CORE) };

function runProbe() {
  const r = spawnSync(process.execPath, [RUN], { cwd: UI, encoding: 'utf8' });
  return { code: r.status, out: (r.stdout || '') + (r.stderr || '') };
}

const results = [];
const record = (name, ok, detail) => results.push({ name, ok, detail });

// ---- M1 -----------------------------------------------------------------------
{
  const orig = fs.readFileSync(RUN, 'utf8');
  try {
    fs.writeFileSync(RUN, orig.replace('const RATIO_CLAIM = 0.5;', 'const RATIO_CLAIM = 0.001;'));
    const r = runProbe();
    record('M1 impossible claim threshold -> red', r.code !== 0 && /claim: <= 0.001x/.test(r.out),
      'wanted exit!=0 + the claim FAIL line; got exit ' + r.code);
  } finally { fs.writeFileSync(RUN, orig); }
}

// ---- M2 -----------------------------------------------------------------------
{
  const orig = fs.readFileSync(CORE, 'utf8');
  const needle = 'var v:Vector.<int> = new Vector.<int>();';
  if (!orig.includes(needle)) {
    record('M2 vector lowered to an array -> red', false, 'needle not found in BenchCore.as: ' + needle);
  } else {
    try {
      fs.writeFileSync(CORE, orig.replace(needle, 'var v:Array = [];'));
      const r = runProbe();
      record('M2 vector lowered to an array -> red', r.code !== 0 && /only \d+\.\d+x Array on the AOT arm/.test(r.out),
        'wanted exit!=0 + the ratio FAIL line; got exit ' + r.code);
    } finally { fs.writeFileSync(CORE, orig); }
  }
}

// ---- restore verification -----------------------------------------------------
const restored = hashBefore.run === sha(RUN) && hashBefore.core === sha(CORE);
console.log('');
for (const r of results) console.log((r.ok ? 'MUTATION PASS  ' : 'MUTATION FAIL  ') + r.name + '   [' + r.detail + ']');
console.log('restore: ' + (restored ? 'run.cjs + BenchCore.as byte-identical' : 'TAMPERED'));
const bad = results.filter((r) => !r.ok).length + (restored ? 0 : 1);
console.log('');
console.log('MUTATION: ' + (bad === 0 ? 'PASS (' + results.length + '/' + results.length + ')' : 'FAIL (' + bad + ' problem(s))'));
process.exit(bad === 0 ? 0 : 1);

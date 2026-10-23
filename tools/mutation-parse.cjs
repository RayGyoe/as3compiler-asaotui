// mutation-parse.cjs -- proves tools/fingerprint-parse-check.cjs has teeth.
//
// The check pins the porcelain parser against the exact bug it was written for, so
// the mutation is that bug: trim each record before slicing it at fixed offsets.
// That is not a synthetic edit -- it is, verbatim, what the tool used to do to the
// whole buffer, and it silently shifted every path left by one for the common
// " M x" (worktree-modified) first line.
//
// Restored in a `finally` and verified by hash: a mutation harness that leaves a
// mutant behind poisons every later run.
//
// Usage:  node tools/mutation-parse.cjs

'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const TARGET = path.join(__dirname, 'compiler-fingerprint.cjs');
const original = fs.readFileSync(TARGET, 'utf8');
const hash = (s) => crypto.createHash('sha256').update(s).digest('hex').slice(0, 16);

const FROM = "    entries.push({ code: rec.slice(0, 2), f: rec.slice(3) });";
const TO = "    const r = rec.trim(); entries.push({ code: r.slice(0, 2), f: r.slice(3) });";

let code = 1;
try {
  if (original.indexOf(FROM) < 0) throw new Error('mutation anchor not found -- parser reshaped?');
  const mutant = original.replace(FROM, TO);
  if (mutant === original) throw new Error('mutation did not change the file');
  fs.writeFileSync(TARGET, mutant);
  console.log('mutator: fingerprint parser -- per-record trim() before slicing (the original bug)');
  console.log('mutator: compiler-fingerprint.cjs  ' + hash(original) + ' -> ' + hash(mutant));
  console.log('');

  const r = spawnSync(process.execPath, [path.join(__dirname, 'fingerprint-parse-check.cjs')], {
    cwd: path.resolve(__dirname, '..'), encoding: 'utf8', maxBuffer: 1 << 24,
  });
  const out = (r.stdout || '') + (r.stderr || '');
  console.log(out);
  const red = r.status !== 0;
  if (red) console.log('mutator: parse check went RED (as required)');
  else console.log('mutator: *** parse check stayed GREEN -- it does not pin the bug ***');
  code = red ? 0 : 1;
} catch (e) {
  console.error('mutator error: ' + e.message);
  code = 1;
} finally {
  fs.writeFileSync(TARGET, original);
  const back = fs.readFileSync(TARGET, 'utf8');
  console.log('mutator: compiler-fingerprint.cjs restored  ' + hash(back) + (back === original ? '  (identical)' : '  *** MISMATCH ***'));
  if (back !== original) code = 1;
}
console.log('');
console.log(code === 0
  ? '==== MUTATION: PASS -- the bug the parser was fixed for makes the check go red ===='
  : '==== MUTATION: FAIL ====');
process.exit(code);

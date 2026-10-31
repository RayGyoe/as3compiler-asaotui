// mutation-air-sdk.cjs -- proves tools/air-sdk-check.cjs has teeth.
//
// The resolver is the instrument that decided nine gates were SKIP for three rounds,
// so "it says no SDK" has to be a measurement, not an opinion. Each mutation below is
// one of the ways that answer can be WRONG, and the check must go red for each:
//
//   M1  structural check removed  -- `usable` is true for any directory, so a
//       half-extracted `AIRSDK_99.0` (newest name, empty bin/) wins.
//   M2  version ranking reversed  -- the OLD install wins; "newest" is the whole point
//       of ranking, and a stale SDK silently becomes the reference runtime.
//   M3  --sdk falls through to the scan -- an explicit root that does not verify is
//       replaced by whatever the search found, so the caller's answer is not theirs.
//   M4  ASC_NO_AIR_SCAN ignored   -- the escape hatch stops working, so a caller that
//       turned the search off is still given a root from a directory it excluded.
//   M5  complete = mxmlc only     -- a half install is reported as complete, and the
//       adl gates then run without adl instead of skipping honestly.
//
// Each mutation is applied to a COPY of the resolver? No -- the real file, restored in
// a `finally` and verified by hash: a harness that leaves a mutant behind poisons
// every later run (and the workspace's own gates would then be measuring the mutant).
//
// Usage:  node tools/mutation-air-sdk.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const UI = path.resolve(__dirname, '..');
const TARGET = path.join(__dirname, 'air-sdk.cjs');
const CHECK = path.join(__dirname, 'air-sdk-check.cjs');
const original = fs.readFileSync(TARGET, 'utf8');
const hash = (s) => crypto.createHash('sha256').update(s).digest('hex').slice(0, 16);

const MUTATIONS = [
  {
    id: 'M1',
    what: 'the structural check is removed (any directory is "usable")',
    from: 'return { root, bin, mxmlc, adl, usable: mxmlc !== null, complete: mxmlc !== null && adl !== null };',
    to: 'return { root, bin, mxmlc, adl, usable: true, complete: true };',
  },
  {
    id: 'M2',
    what: 'version ranking reversed (an OLDER install wins)',
    from: '    candidates.sort((a, b) => (b.complete - a.complete) || newer(b.root, a.root));',
    to: '    candidates.sort((a, b) => (b.complete - a.complete) || newer(a.root, b.root));',
  },
  {
    id: 'M3',
    what: '--sdk that does not verify falls through to the scan',
    from: "    if (!c.usable) {\n      return { root: null, mxmlc: null, adl: null, source: '--sdk',",
    to: "    if (false) {\n      return { root: null, mxmlc: null, adl: null, source: '--sdk',",
  },
  {
    id: 'M4',
    what: 'ASC_NO_AIR_SCAN is ignored (the search always runs)',
    from: "  if (process.env.ASC_NO_AIR_SCAN === '1') {",
    to: "  if (false && process.env.ASC_NO_AIR_SCAN === '1') {",
  },
  {
    id: 'M5',
    what: 'complete is computed from mxmlc alone (adl ignored)',
    from: 'usable: mxmlc !== null, complete: mxmlc !== null && adl !== null',
    to: 'usable: mxmlc !== null, complete: mxmlc !== null',
  },
];

function runCheck() {
  const r = spawnSync(process.execPath, [CHECK], { cwd: UI, encoding: 'utf8', maxBuffer: 1 << 24 });
  return { red: r.status !== 0, out: (r.stdout || '') + (r.stderr || '') };
}

let code = 0;
const rows = [];
try {
  // The baseline: a mutation harness is worthless if the unmutated check is red.
  const base = runCheck();
  rows.push(['--', 'baseline (no mutation)', 'GREEN']);
  if (base.red) {
    console.log(base.out);
    throw new Error('the check is red WITHOUT a mutation -- fix that before believing any row below');
  }

  for (const m of MUTATIONS) {
    if (original.indexOf(m.from) < 0) throw new Error(m.id + ': anchor not found -- resolver reshaped?');
    const mutant = original.replace(m.from, m.to);
    if (mutant === original) throw new Error(m.id + ': mutation did not change the file');
    fs.writeFileSync(TARGET, mutant);
    const r = runCheck();
    const firstFail = (/FAIL ([^\n]+)/.exec(r.out) || [])[1] || '';
    rows.push([m.id, m.what, r.red ? 'RED (required)' + (firstFail ? '  -- ' + firstFail.trim() : '') : '*** STAYED GREEN ***']);
    if (!r.red) code = 1;
    fs.writeFileSync(TARGET, original);
  }
} catch (e) {
  console.error('mutator error: ' + e.message);
  code = 1;
} finally {
  fs.writeFileSync(TARGET, original);
  const back = fs.readFileSync(TARGET, 'utf8');
  if (back !== original) {
    console.error('mutator: *** air-sdk.cjs was NOT restored ***');
    code = 1;
  }
}

for (const [id, what, verdict] of rows) {
  console.log(id + '  ' + verdict.padEnd(22) + '  ' + what);
}
console.log('');
console.log('mutator: air-sdk.cjs restored  ' + hash(original) + ' -> ' + hash(fs.readFileSync(TARGET, 'utf8')));
console.log('');
console.log(code === 0
  ? '==== MUTATION: PASS -- ' + MUTATIONS.length + '/' + MUTATIONS.length
    + ' resolver defects make the check go red ===='
  : '==== MUTATION: FAIL ====');
process.exit(code);
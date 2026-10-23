// mutation.cjs -- prove the G11 closing measurement has teeth.
//
// A checker that never fails certifies nothing. This machine changes ONE thing at a
// time and requires the corresponding assertion in run.cjs to go red:
//
//   M1  input, naming:  take artifact-3 (the consistent one, 0 errors) and rename
//                       ONLY the struct field `_time` -> `time__`, leaving the props
//                       table and the body literal alone. This is G11's exact shape,
//                       produced from the healthy file in one token. clang must now
//                       report `no member named '_time'`.
//   M2  input, props:   leave the struct alone and point the props entry at a field
//                       that does not exist (`offsetof(Date, nope)`). clang must name
//                       `nope`. Together with M1 this shows the checker reads the FILE
//                       (struct side and props side), not a cached verdict.
//   M3  hash arm:       build a source that differs by one string literal and require
//                       the generated C's hash to CHANGE. Without this, "5 identical
//                       hashes" could be a constant, i.e. a vacuous equality.
//   M4  expectation:    flip run.cjs's own expectation for artifact-3 (0 -> 1 error)
//                       and require the gate to exit non-zero naming that artifact.
//                       This is the only mutation that touches the checker itself; it
//                       is restored by hash.
//
// The three artifacts and run.cjs are restored byte-for-byte (sha256 checked) in
// `finally`; the mutants are deleted. Nothing here touches the compiler repo: the
// whole point of G11 is that the compiler tree must stay clean.
//
// Usage:  node probes/g11-nondeterminism/mutation.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const HERE = __dirname;
const UI = path.resolve(HERE, '..', '..');
const REPO = path.resolve(UI, '..', 'as3compiler');
const RUN = path.join(HERE, 'run.cjs');
const CONSISTENT = path.join(HERE, 'artifact-3-consistent.c');
const { cErrors, logKinds } = require(RUN);

const sha = (f) => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const results = [];
const check = (name, ok, detail) => {
  results.push({ name, ok, detail });
  console.log((ok ? '[PASS] ' : '[FAIL] ') + name);
  if (detail) console.log('        ' + detail);
};

// Watch everything this run may touch, so "restored" is a hash comparison and not a
// claim. The independent hashes catch a mutation that leaked into another file.
const WATCH = [CONSISTENT, path.join(HERE, 'artifact-1-struct-time__.c'), path.join(HERE, 'artifact-2-struct-socket-1-error.c'), RUN];
const before = new Map(WATCH.map((f) => [f, sha(f)]));
const mutants = [path.join(HERE, 'mutant-1-struct-time__.c'), path.join(HERE, 'mutant-2-bad-props.c'), path.join(HERE, 'mutation-src.as')];

function buildHash(asFile, cFile) {
  if (fs.existsSync(cFile)) fs.unlinkSync(cFile);
  const { ALL } = require(path.join(UI, 'ui-demo', 'kit-list.cjs'));
  const args = [
    'src/index.ts', asFile, ...ALL,
    '--manifest', 'examples/window.build.example.json',
    '--cc', process.env.ASC_CC || 'clang',
    '-I', './vendor/curl/include', '-L', './vendor/curl/lib/windows-x64', '-l', 'zlib'
  ];
  const r = spawnSync(process.execPath, args, { cwd: REPO, encoding: 'utf8', maxBuffer: 1 << 28 });
  if (r.status !== 0 || !fs.existsSync(cFile)) return null;
  return crypto.createHash('sha256').update(fs.readFileSync(cFile)).digest('hex').slice(0, 16);
}

try {
  // ---- M1: struct field renamed, props and body untouched -------------------
  {
    const text = fs.readFileSync(CONSISTENT, 'utf8');
    const needle = 'struct Date {\n  Date_vtable* vtable;\n  double _time;\n};';
    if (!text.includes(needle)) throw new Error('M1 anchor not found: struct Date block shape changed');
    const mutated = text.replace(needle, needle.replace('double _time;', 'double time__;'));
    fs.writeFileSync(mutants[0], mutated);
    const c = cErrors(mutants[0]);
    // clang says `in 'Date'` here (the other spelling, `in 'struct Date'`, shows up
    // for a variable receiver), so the predicate must not pin the wording.
    const hit = c.errors.some((e) => /no member named '(_time|time__)'/.test(e.msg));
    check('M1 struct field -> time__ is detected', hit,
      'clang errors ' + c.errors.length + ', kinds [' + c.kinds.join(', ') + ']'
      + (c.errors.length ? '; first: ' + c.errors[0].msg : ''));
  }

  // ---- M2: props entry pointing at a field that does not exist ---------------
  {
    const text = fs.readFileSync(CONSISTENT, 'utf8');
    const needle = 'offsetof(Date, _time)';
    if (!text.includes(needle)) throw new Error('M2 anchor not found: props entry shape changed');
    fs.writeFileSync(mutants[1], text.replace(needle, 'offsetof(Date, nope)'));
    const c = cErrors(mutants[1]);
    const hit = c.errors.some((e) => /no member named 'nope'/.test(e.msg));
    check('M2 props entry -> nope is detected', hit,
      'clang errors ' + c.errors.length + (c.errors.length ? '; first: ' + c.errors[0].msg : ''));
  }

  // ---- M3: the hash arm is not a constant -----------------------------------
  {
    const probeAs = path.join(UI, 'probes', 'array-scope', 'Main.as');
    const baseline = buildHash(probeAs, path.join(UI, 'probes', 'array-scope', 'Main.c'));
    check('M3 baseline build produced C', baseline !== null, 'baseline sha256/16 ' + baseline);
    const text = fs.readFileSync(probeAs, 'utf8');
    const anchor = 'DONE';
    if (!text.includes(anchor)) throw new Error('M3 anchor not found: Main.as no longer says DONE');
    // A one-token source change: the string the program prints.
    fs.writeFileSync(mutants[2], text.replace(anchor, 'DONE!'));
    const after = buildHash(mutants[2], path.join(HERE, 'mutation-src.c'));
    check('M3 a one-literal source change changes the generated C',
      after !== null && baseline !== null && after !== baseline,
      'baseline ' + baseline + ' vs mutant ' + after);
  }

  // ---- M4: the gate's own expectation is compared ---------------------------
  {
    const original = fs.readFileSync(RUN);
    const text = original.toString('utf8');
    const needle = "file: 'artifact-3-consistent.c', mtime: '2026-10-23 04:01:34 +0800', truncated: false, exact: 0,";
    if (!text.includes(needle)) throw new Error('M4 anchor not found: the artifact-3 expectation moved');
    fs.writeFileSync(RUN, text.replace(needle, needle.replace('exact: 0', 'exact: 1')));
    const r = spawnSync(process.execPath, [RUN], {
      cwd: UI, encoding: 'utf8', maxBuffer: 1 << 26,
      env: { ...process.env, ASC_G11_RUNS: '1', ASC_G11_EVIDENCE: 'off' }
    });
    const out = (r.stdout || '') + (r.stderr || '');
    const named = /FAIL: artifact-3-consistent\.c/.test(out);
    // `named` is the discriminating part: that FAIL line can only appear when the
    // artifact's measured error count stops matching the expectation. The exit code
    // alone is NOT enough -- run.cjs also exits non-zero on a dirty compiler tree.
    check('M4 flipping artifact-3\'s expectation makes the gate red',
      named,
      'exit ' + r.status + ', FAIL line naming artifact-3: ' + (named ? 'present' : 'ABSENT'));
    fs.writeFileSync(RUN, original);
  }
  {
    // ---- M5: the SKIP branch is reachable, and it is not a green ----------------
    // "All gates PASS" is only honest if the one non-PASS verdict a gate can emit is
    // itself tested. ASC_G11_FORCE_SKIP makes run.cjs see the generator as having moved
    // mid-run; the only acceptable outcome is exit 3 with that reason printed. If it
    // ever came out 0, the hook could launder an unmeasured run into a green.
    const r = spawnSync(process.execPath, [RUN], {
      cwd: UI, encoding: 'utf8', maxBuffer: 1 << 26,
      env: { ...process.env, ASC_G11_RUNS: '1', ASC_G11_EVIDENCE: 'off', ASC_G11_FORCE_SKIP: '1' }
    });
    const out = (r.stdout || '') + (r.stderr || '');
    const says = /INCONCLUSIVE: every measurement above is green/.test(out)
      && /blocked by: the compiler source changed mid-run/.test(out)
      && !/^PASS:/m.test(out);
    check('M5 a mid-run generator move is INCONCLUSIVE (exit 3), never a green',
      r.status === 3 && says,
      'exit ' + r.status + ' (want 3), INCONCLUSIVE text: ' + (says ? 'present' : 'ABSENT'));
  }
} finally {
  // ---- restore, and prove it by hash ---------------------------------------
  let restored = true;
  for (const f of WATCH) {
    const now = sha(f);
    if (now !== before.get(f)) {
      restored = false;
      console.log('[FAIL] NOT RESTORED: ' + path.basename(f) + ' ' + before.get(f).slice(0, 16) + ' -> ' + now.slice(0, 16));
    }
  }
  for (const m of [...mutants, path.join(HERE, 'mutation-src.c')]) if (fs.existsSync(m)) fs.unlinkSync(m);
  check('every watched file restored byte-for-byte', restored,
    WATCH.map((f) => path.basename(f) + ' ' + before.get(f).slice(0, 16)).join(', '));
  check('no mutant left on disk', mutants.every((m) => !fs.existsSync(m)));
}

const failed = results.filter((r) => !r.ok);
console.log('---- verdict ----');
console.log(failed.length === 0
  ? 'MUTATION: PASS (' + results.length + '/' + results.length + ') -- each assertion fires when its condition is violated'
  : 'MUTATION: FAIL (' + failed.length + ' of ' + results.length + ' did not fire)');
const ev = path.join(HERE, 'mutation-' + new Date().toISOString().slice(0, 10) + '.txt');
fs.appendFileSync(ev, '\n== ' + new Date().toISOString() + ' ==\n' + results.map((r) => (r.ok ? 'PASS ' : 'FAIL ') + r.name + (r.detail ? '\n     ' + r.detail : '')).join('\n') + '\n');
console.log('---- evidence appended to ' + path.relative(UI, ev) + ' ----');
process.exit(failed.length === 0 ? 0 : 1);
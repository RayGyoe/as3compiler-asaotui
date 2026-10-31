// probes/g22-closure-statics/run.cjs -- ONE command, BOTH arms, plus a source audit.
//
// QUESTION: does a static field read that happens inside an anonymous closure run
// the declaring class's `_cinit()`? AS3 says yes (a class initializer runs before
// the first static read, and a closure is just a value). Our AOT used to emit the
// read as a bare `Owner_FIELD` there -- no guard -- because the "which classes own
// a `_cinit`" set was only filled AFTER the closure bodies had already been
// emitted. The class initializer therefore never ran and the C slot was NULL.
//
// The probe measures three things at once:
//   1. the VALUES (both arms, 10 cases);
//   2. the generated C: every read of a runtime-initialized static from a body
//      must sit next to `(Owner_cinit(), ...)`;
//   3. the generated C: the `_cinit` forward declaration must precede its first
//      call (the fix has to add BOTH, otherwise C rejects the call outright).
//
// USAGE (from asaotui/):   node probes/g22-closure-statics/run.cjs
//   ASC_CC=clang            override the C compiler
//   AIRSDK_HOME=<sdk root>  AIR SDK root (default: the known local 51.4.1)
//   ASC_SKIP_AIR=1          AOT arm + source audit only
//
// EXIT CODES
//   0  both arms agree with the derived answers, and the generated C is guarded
//   1  a semantic disagreement, or an unguarded read / late declaration
//   2  a build or run step failed
'use strict';

const fs = require('fs');
const path = require('path');
const { mxmlcRun } = require('../../tools/mxmlc-run.cjs');
const { spawnSync, execFileSync } = require('child_process');

const DIR = __dirname;
const UI = path.resolve(DIR, '..', '..');
const COMPILER = path.resolve(UI, '..', 'as3compiler');
const clang = process.env.ASC_CC || 'clang';
// The SDK is resolved by the workspace's ONE resolver (tools/air-sdk.cjs): env
// first, then PATH, then the install locations -- and a hit only counts if this
// HOST can run the launcher. The old fallback here was a hard-coded Windows path
// ('D:/Adobe/Flex_Sdk/...'), which on macOS is a guaranteed miss: the runner
// reported "AIR SDK not found" with the SDK sitting two directories away.
const { resolveAirSdk, describe } = require('../../tools/air-sdk.cjs');
const SDK_INFO = resolveAirSdk();
const SDK = SDK_INFO.root;
const skipAir = process.env.ASC_SKIP_AIR === '1';

const AOT_TXT = path.join(DIR, 'g22-closure-statics-aot.txt');
const AIR_TXT = path.join(DIR, 'g22-closure-statics-air.txt');
const AOT_EXE = path.join(DIR, 'AotMain.exe');
const AOT_C = path.join(DIR, 'AotMain.exe.c');
const AIR_SWF = path.join(DIR, 'AirMain.swf');
const RESULTS = path.join(DIR, 'g22-closure-statics-results.txt');

const expect = JSON.parse(fs.readFileSync(path.join(DIR, 'expect.json'), 'utf8'));
const clean = (p) => { if (fs.existsSync(p)) fs.unlinkSync(p); };

function parse(file) {
  const out = {};
  if (!fs.existsSync(file)) return out;
  for (const line of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
    const m = line.match(/^id=(\d+)\s(.*)$/);
    if (m) out[Number(m[1])] = m[2].trim();
  }
  return out;
}

// --------------------------------------------------------- source audit ------
// Runtime-initialized statics of the probe. `TITLE` is absent on purpose: it is a
// compile-time literal, so its class needs no `_cinit` and a bare read is correct.
const GUARDED = {
  ClosureCases: ['NAMES', 'NUMBER', 'CFG', 'PAIR'],
  Bag: ['NAMES'],
  Sealed: ['VALUE'],
};

function auditC(cPath) {
  const problems = [];
  if (!fs.existsSync(cPath)) return ['the generated C is missing: ' + path.basename(cPath)];
  const lines = fs.readFileSync(cPath, 'utf8').split(/\r?\n/);

  const isNoise = (l, sym) =>
    new RegExp('^\\s*static\\s+[^;=]*\\b' + sym + '\\s*;').test(l) ||        // forward decl
    new RegExp('^\\s*static\\s+[^;=]*\\b' + sym + '\\s*=').test(l) ||        // definition
    new RegExp('^\\s*gc_mark_ptr\\(\\(void\\*\\)' + sym + '\\)').test(l) ||  // GC root
    new RegExp('^\\s*' + sym + '\\s*=').test(l) ||                           // initializer write
    new RegExp('^\\s*' + sym + '\\s*=\\s*as_array_make').test(l);

  for (const [owner, fields] of Object.entries(GUARDED)) {
    for (const f of fields) {
      const sym = owner + '_' + f;
      const re = new RegExp('\\b' + sym + '\\b');
      let reads = 0;
      lines.forEach((l, i) => {
        if (!re.test(l)) return;
        if (isNoise(l, sym)) return;
        reads++;
        if (!l.includes(owner + '_cinit()')) {
          problems.push('line ' + (i + 1) + ': read of ' + sym + ' has no ' + owner + '_cinit() guard: '
            + l.trim().slice(0, 120));
        }
      });
      if (reads === 0) problems.push(sym + ': no read point found in the generated C (audit is stale)');
    }
    // Declaration order: a call may not precede the forward declaration.
    const declAt = lines.findIndex((l) => new RegExp('^\\s*static void ' + owner + '_cinit\\(void\\);').test(l));
    const callAt = lines.findIndex((l) => new RegExp('\\b' + owner + '_cinit\\(\\)').test(l) && !/static void /.test(l));
    if (declAt < 0) problems.push(owner + '_cinit: no forward declaration in the generated C');
    else if (callAt >= 0 && callAt < declAt) {
      problems.push(owner + '_cinit: first call at line ' + (callAt + 1)
        + ' precedes its declaration at line ' + (declAt + 1) + ' (C would reject it)');
    }
  }
  return problems;
}

// --------------------------------------------------------------- AOT arm -----
console.log('[g22] building the AOT arm');
clean(AOT_EXE); clean(AOT_C); clean(AOT_TXT);
const build = spawnSync(process.execPath, [
  'src/index.ts',
  path.join(DIR, 'AotMain.as'),
  path.join(DIR, 'ClosureCases.as'),
  path.join(DIR, 'Bag.as'),
  path.join(DIR, 'Sealed.as'),
  '-o', AOT_EXE,
  '--cc', clang,
  '-w',
    // Host include/link flags come from the manifest -- the single place that
  // knows what each platform needs. Spelling the Windows curl import library
  // and `-l zlib` here by hand made this runner Windows-only (clang on macOS
  // reads that as a file named libzlib.a and the link dies).
  '--manifest', 'examples/window.build.example.json',
], { cwd: COMPILER, encoding: 'utf8' });
if (build.status !== 0) {
  console.error('[g22] AOT BUILD FAILED (exit ' + build.status + ')');
  console.error(((build.stdout || '') + (build.stderr || '')).split(/\r?\n/).slice(-30).join('\n'));
  process.exit(2);
}
console.log('[g22] running the AOT arm');
const aotRun = spawnSync(AOT_EXE, [], { cwd: DIR, encoding: 'utf8' });
const aot = parse(AOT_TXT);
const aotExit = aotRun.status === null ? 'signal ' + aotRun.signal : aotRun.status;

// --------------------------------------------------------------- AIR arm -----
let air = null;
if (!skipAir) {
  const mxmlc = SDK_INFO.mxmlc; const adl = SDK_INFO.adl;
  if (!SDK_INFO.complete) {
    console.error(describe(SDK_INFO));  // names every location tried, not just one guess
    console.error('  (set AIRSDK_HOME, or ASC_SKIP_AIR=1 to skip the AIR arm)');
    process.exit(2);
  }
  console.log('[g22] building the AIR arm with mxmlc');
  clean(AIR_SWF); clean(AIR_TXT);
  const m = mxmlcRun(mxmlc, ['-output=' + AIR_SWF,
    '-source-path=' + DIR,
    path.join(DIR, 'AirMain.as')], { cwd: DIR, encoding: 'utf8' });
  if (m.status !== 0 || !fs.existsSync(AIR_SWF)) {
    console.error('[g22] mxmlc FAILED (exit ' + m.status + ')');
    console.error(((m.stdout || '') + (m.stderr || '')).split(/\r?\n/).slice(-30).join('\n'));
    process.exit(2);
  }
  console.log('[g22] running the AIR arm');
  let adlErr = '';
  try { execFileSync(adl, [path.join(DIR, 'app.xml')], { cwd: DIR, timeout: 60000, encoding: 'utf8', stdio: 'pipe' }); }
  catch (e) { adlErr = String((e && e.stderr) || ''); /* adl exit codes are noisy; the evidence is the file */ }
  if (!fs.existsSync(AIR_TXT)) {
    console.error('[g22] adl wrote no ' + AIR_TXT);
    if (adlErr) console.error('[g22] adl stderr:\n' + adlErr.trim());
    process.exit(2);
  }
  air = parse(AIR_TXT);
}

// -------------------------------------------------------------- compare ------
const w = (s, n) => String(s == null ? '(MISSING)' : s).padEnd(n);
const rows = [];
const fails = [];
for (let id = 1; id <= expect.count; id++) {
  const want = expect.truth[String(id)];
  const gotAot = aot[id];
  const gotAir = air ? air[id] : '(skipped)';
  rows.push({ id, want, aot: gotAot, air: gotAir });
  if (air && gotAir !== want) {
    fails.push('id ' + id + ': AIR says "' + gotAir + '" but the derived answer is "' + want
      + '" -- the REFERENCE disagrees; re-derive the rule');
  }
  const ref = air ? gotAir : want;
  if (gotAot !== ref) {
    fails.push('id ' + id + ': our AOT says "' + gotAot + '" but ' + (air ? 'AIR' : 'the rule') + ' says "' + ref + '"');
  }
}

// A crash stops a run, so a short file is evidence too.
for (const [name, table, where] of [['AOT', aot, 'g22-closure-statics-aot.txt'], ['AIR', air, 'g22-closure-statics-air.txt']]) {
  if (table == null) continue;
  const n = Object.keys(table).length;
  if (n < expect.count) {
    const last = Math.max(0, ...Object.keys(table).map(Number));
    fails.push(name + ' arm wrote only ' + n + '/' + expect.count + ' lines in ' + where
      + ' -- it STOPPED after id ' + last + ' (crash or early exit)');
  }
}

// --------------------------------------------------------- the C itself ------
const auditProblems = auditC(AOT_C);
for (const p of auditProblems) fails.push('generated C: ' + p);

const out = [];
out.push('');
out.push('id  ' + w('case', 52) + w('rule', 18) + w('AIR 51.4.1', 18) + 'our AOT');
for (const r of rows) {
  const mark = r.aot !== (air ? r.air : r.want) ? '   <-- DIFFERS' : '';
  out.push(String(r.id).padStart(2) + '  ' + w(expect.label[String(r.id)], 52) + w(r.want, 18)
    + w(r.air, 18) + w(r.aot) + mark);
}
out.push('');
out.push('AOT exit: ' + aotExit);
out.push('source audit (' + path.basename(AOT_C) + '): '
  + (auditProblems.length === 0 ? 'every static read is guarded by its _cinit()' : auditProblems.length + ' problem(s)'));
out.push(fails.length
  ? 'RESULT: FAIL (' + fails.length + ' disagreement(s))'
  : 'RESULT: PASS (' + expect.count + ' cases; both arms agree and every static read carries its _cinit() guard)');
for (const f of fails) out.push('  FAIL  ' + f);
const text = out.join('\n');
console.log(text);
fs.writeFileSync(RESULTS, text + '\n');

process.exit(fails.length === 0 ? 0 : 1);
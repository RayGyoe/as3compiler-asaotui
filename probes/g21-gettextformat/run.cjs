// probes/g21-gettextformat/run.cjs -- ONE command, BOTH arms, plus a source audit.
//
// QUESTION: does `TextField.getTextFormat(begin, end)` report the formatting that is
// actually in effect over that range, or does it just hand back defaultTextFormat?
//
// G21 was the second answer: the emitter contained a single
// `return (tf != NULL) ? tf->defaultTextFormat : NULL;`, written before the run
// table existed. A field with `setTextFormat(new TextFormat("Arial", 30, 0xFF0000))`
// therefore kept reporting size 20 / colour 0 -- the default -- no matter which
// range was asked for, and the no-arg form never saw a run either.
//
// The probe measures three things at once:
//   1. the VALUES (both arms, 30 cases, expect.json is hand-derived + AIR-measured);
//   2. the generated C: the function must consult `_runs` and compare formats
//      (a bare `return tf->defaultTextFormat` is the defect, so its absence is a
//      property worth pinning);
//   3. the generated C: the empty-format path and the #2006 path must both exist.
//
// USAGE (from asaotui/):   node probes/g21-gettextformat/run.cjs
//   ASC_CC=clang            override the C compiler
//   AIRSDK_HOME=<sdk root>  AIR SDK root (default: the known local 51.4.1)
//   ASC_SKIP_AIR=1          AOT arm + source audit only
//
// EXIT CODES
//   0  both arms agree with the derived answers, and the generated C is range-aware
//   1  a semantic disagreement, or the emitted function is still range-blind
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

const AOT_TXT = path.join(DIR, 'g21-gettextformat-aot.txt');
const AIR_TXT = path.join(DIR, 'g21-gettextformat-air.txt');
const AOT_EXE = path.join(DIR, 'AotMain.exe');
const AOT_C = path.join(DIR, 'AotMain.exe.c');
const AIR_SWF = path.join(DIR, 'AirMain.swf');
const RESULTS = path.join(DIR, 'g21-gettextformat-results.txt');

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
// The emitted function must be range-aware. These are properties of the FIX, so
// they are checked in the generated C rather than in the TypeScript source: a
// refactor that keeps the semantics keeps passing.
function auditC(cPath) {
  const problems = [];
  if (!fs.existsSync(cPath)) return ['the generated C is missing: ' + path.basename(cPath)];
  const text = fs.readFileSync(cPath, 'utf8');
  // The prototype comes first; the DEFINITION is the last occurrence.
  const start = text.lastIndexOf('TextField_getTextFormat(void* _this');
  if (start < 0) return ['TextField_getTextFormat is absent from the generated C'];
  // Take the body: from the opening brace to the matching one, by brace counting.
  const open = text.indexOf('{', start);
  let depth = 0;
  let end = -1;
  for (let i = open; i < text.length; i++) {
    if (text[i] === '{') depth++;
    else if (text[i] === '}') { depth--; if (depth === 0) { end = i; break; } }
  }
  if (open < 0 || end < 0) return ['TextField_getTextFormat has no parsable body'];
  const body = text.slice(open, end + 1);
  const need = [
    ['tf->_runs', 'the run table is never consulted'],
    ['as_tf_fmt_eq(', 'formats are never compared across segments'],
    ['as_tf_fmt_empty()', 'there is no empty-TextFormat answer for a straddling range'],
    ['as_tf_fmt_clone(', 'the answer is not a copy of the covering format'],
    ['2006', 'the out-of-bounds RangeError is gone'],
  ];
  for (const [needle, why] of need) {
    if (!body.includes(needle)) problems.push('generated getTextFormat: ' + why + ' (no `' + needle + '`)');
  }
  if (/if \(tf == NULL\) return NULL;\s*return \(tf != NULL\) \? tf->defaultTextFormat/.test(body)) {
    problems.push('generated getTextFormat still returns defaultTextFormat outright');
  }
  return problems;
}

// --------------------------------------------------------------- AOT arm -----
console.log('[g21] building the AOT arm');
clean(AOT_EXE); clean(AOT_C); clean(AOT_TXT);
const build = spawnSync(process.execPath, [
  'src/index.ts',
  path.join(DIR, 'AotMain.as'),
  path.join(DIR, 'GetFmtCases.as'),
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
  console.error('[g21] AOT BUILD FAILED (exit ' + build.status + ')');
  console.error(((build.stdout || '') + (build.stderr || '')).split(/\r?\n/).slice(-30).join('\n'));
  process.exit(2);
}
console.log('[g21] running the AOT arm');
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
  console.log('[g21] building the AIR arm with mxmlc');
  clean(AIR_SWF); clean(AIR_TXT);
  const m = mxmlcRun(mxmlc, ['-output=' + AIR_SWF,
    '-source-path=' + DIR,
    path.join(DIR, 'AirMain.as')], { cwd: DIR, encoding: 'utf8' });
  if (m.status !== 0 || !fs.existsSync(AIR_SWF)) {
    console.error('[g21] mxmlc FAILED (exit ' + m.status + ')');
    console.error(((m.stdout || '') + (m.stderr || '')).split(/\r?\n/).slice(-30).join('\n'));
    process.exit(2);
  }
  console.log('[g21] running the AIR arm');
  let adlErr = '';
  try { execFileSync(adl, [path.join(DIR, 'app.xml')], { cwd: DIR, timeout: 60000, encoding: 'utf8', stdio: 'pipe' }); }
  catch (e) { adlErr = String((e && e.stderr) || ''); /* adl exit codes are noisy; the evidence is the file */ }
  if (!fs.existsSync(AIR_TXT)) {
    console.error('[g21] adl wrote no ' + AIR_TXT);
    if (adlErr) console.error('[g21] adl stderr:\n' + adlErr.trim());
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
for (const [name, table, where] of [['AOT', aot, 'g21-gettextformat-aot.txt'], ['AIR', air, 'g21-gettextformat-air.txt']]) {
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
out.push('id  ' + w('case', 52) + w('rule', 22) + w('AIR 51.4.1', 22) + 'our AOT');
for (const r of rows) {
  const mark = r.aot !== (air ? r.air : r.want) ? '   <-- DIFFERS' : '';
  out.push(String(r.id).padStart(2) + '  ' + w(expect.label[String(r.id)], 52) + w(r.want, 22)
    + w(r.air, 22) + w(r.aot) + mark);
}
out.push('');
out.push('AOT exit: ' + aotExit);
out.push('source audit (' + path.basename(AOT_C) + '): '
  + (auditProblems.length === 0 ? 'getTextFormat consults _runs, compares formats and has both answers' : auditProblems.length + ' problem(s)'));
out.push(fails.length
  ? 'RESULT: FAIL (' + fails.length + ' disagreement(s))'
  : 'RESULT: PASS (' + expect.count + ' cases; both arms agree and the emitted getTextFormat is range-aware)');
for (const f of fails) out.push('  FAIL  ' + f);
const text = out.join('\n');
console.log(text);
fs.writeFileSync(RESULTS, text + '\n');

process.exit(fails.length === 0 ? 0 : 1);
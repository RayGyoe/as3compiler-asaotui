// probes/style-fromany/run.cjs -- ONE command, BOTH arms.
//
// Question: is `fromAny(o:Object)` TOTAL and SAFE on both runtimes -- i.e. does an
// AS3 Array put into an `Object`-typed parameter keep its identity, so that
// `Size/Edges/Corners/LengthEdges/Fill.fromAny` can dispatch the array form
// themselves?  The style layer used to split `fromAny` from `fromArray` precisely
// because it could NOT (compiler-gaps.md G14). G14 is fixed (compiler 阶段二百五十三)
// and this measures the revert instead of trusting it.
//
// USAGE (from asaotui/):   node probes/style-fromany/run.cjs
//   ASC_CC=clang                  override the C compiler
//   AIRSDK_HOME=<sdk root>        AIR SDK root (default: the known local 51.4.1)
//   ASC_SKIP_AIR=1                AOT arm only (no mxmlc/adl)
//
// Arms:
//   AOT  our compiler  -> native .exe
//   AIR  mxmlc -> adl  -> the reference runtime
//
// Expectations are HAND-DERIVED in expect.json. Both arms are checked against
// them, so the reference is validated rather than assumed.
'use strict';

const fs = require('fs');
const path = require('path');
const { spawnSync, execFileSync } = require('child_process');
const { ALL } = require('../../ui-demo/kit-list.cjs');

const DIR = __dirname;
const UI = path.resolve(DIR, '..', '..');
const COMPILER = path.resolve(UI, '..', 'as3compiler');
const clang = process.env.ASC_CC || 'clang';
const SDK = process.env.AIRSDK_HOME || 'D:/Adobe/Flex_Sdk/AIRSDK_51.4.1';
const skipAir = process.env.ASC_SKIP_AIR === '1';

const AOT_TXT = path.join(DIR, 'style-fromany-aot.txt');
const AIR_TXT = path.join(DIR, 'style-fromany-air.txt');
const AOT_EXE = path.join(DIR, 'style-fromany.exe');
const AIR_SWF = path.join(DIR, 'AirMain.swf');
const RESULTS = path.join(DIR, 'style-fromany-results.txt');

const expect = JSON.parse(fs.readFileSync(path.join(DIR, 'expect.json'), 'utf8'));
const clean = (p) => { if (fs.existsSync(p)) fs.unlinkSync(p); };

// "id=7 (6,6,6,6)" -> { 7: "(6,6,6,6)" }
function parse(file) {
  const out = {};
  if (!fs.existsSync(file)) return out;
  for (const line of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
    const m = line.match(/^id=(\d+)\s(.*)$/);
    if (m) out[Number(m[1])] = m[2].trim();
  }
  return out;
}

// --------------------------------------------------------------- AOT arm -----
console.log('[fromany] building the AOT arm');
clean(AOT_EXE); clean(AOT_TXT);
const build = spawnSync(process.execPath, [
  'src/index.ts',
  path.join(DIR, 'AotMain.as'),
  path.join(DIR, 'StyleCases.as'),
  ...ALL,
  '-o', AOT_EXE,
  '--cc', clang,
  '-w',
  '-I', './vendor/curl/include',
  '-L', './vendor/curl/lib/windows-x64',
  '-l', 'zlib',
], { cwd: COMPILER, encoding: 'utf8' });
if (build.status !== 0) {
  console.error('[fromany] AOT BUILD FAILED (exit ' + build.status + ')');
  console.error(((build.stdout || '') + (build.stderr || '')).split(/\r?\n/).slice(-30).join('\n'));
  process.exit(2);
}
console.log('[fromany] running the AOT arm');
const aotRun = spawnSync(AOT_EXE, [], { cwd: DIR, encoding: 'utf8' });
const aot = parse(AOT_TXT);
const aotExit = aotRun.status === null ? 'signal ' + aotRun.signal : aotRun.status;

// --------------------------------------------------------------- AIR arm -----
let air = null;
if (!skipAir) {
  const mxmlc = path.join(SDK, 'bin', process.platform === 'win32' ? 'mxmlc.bat' : 'mxmlc');
  const adl = path.join(SDK, 'bin', process.platform === 'win32' ? 'adl.exe' : 'adl');
  if (!fs.existsSync(mxmlc) || !fs.existsSync(adl)) {
    console.error('[fromany] AIR SDK not found under ' + SDK + ' (set AIRSDK_HOME, or ASC_SKIP_AIR=1)');
    process.exit(2);
  }
  console.log('[fromany] building the AIR arm with mxmlc');
  clean(AIR_SWF); clean(AIR_TXT);
  const m = spawnSync('cmd', ['/c', mxmlc,
    '-output=' + AIR_SWF,
    '-source-path=' + DIR,
    '-source-path=' + path.join(UI, 'kit'),
    '-source-path=' + path.join(UI, 'seam'),
    path.join(DIR, 'AirMain.as'),
  ], { cwd: DIR, encoding: 'utf8' });
  if (m.status !== 0 || !fs.existsSync(AIR_SWF)) {
    console.error('[fromany] mxmlc FAILED (exit ' + m.status + ')');
    console.error(((m.stdout || '') + (m.stderr || '')).split(/\r?\n/).slice(-30).join('\n'));
    process.exit(2);
  }
  console.log('[fromany] running the AIR arm under adl');
  let adlErr = '';
  try { execFileSync(adl, [path.join(DIR, 'app.xml')], { cwd: DIR, timeout: 60000, encoding: 'utf8', stdio: 'pipe' }); }
  catch (e) { adlErr = String((e && e.stderr) || ''); /* adl exit codes are noisy; the evidence is the file */ }
  if (!fs.existsSync(AIR_TXT)) {
    console.error('[fromany] adl wrote no ' + AIR_TXT);
    if (adlErr) console.error('[fromany] adl stderr:\n' + adlErr.trim());
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
    fails.push('id ' + id + ': AIR says "' + gotAir + '" but the hand-derived rule says "' + want + '" -- the REFERENCE disagrees; re-derive the rule');
  }
  const ref = air ? gotAir : want;
  if (gotAot !== ref) {
    fails.push('id ' + id + ': our AOT says "' + gotAot + '" but ' + (air ? 'AIR' : 'the rule') + ' says "' + ref + '"');
  }
}

// Crash detection: a case that died stops the run, so the file is short.
for (const [name, table, where] of [['AOT', aot, 'style-fromany-aot.txt'], ['AIR', air, 'style-fromany-air.txt']]) {
  if (table == null) continue;
  const n = Object.keys(table).length;
  if (n < expect.count) {
    const last = Math.max(0, ...Object.keys(table).map(Number));
    fails.push(name + ' arm wrote only ' + n + '/' + expect.count + ' lines in ' + where
      + ' -- it STOPPED after id ' + last + ' (crash or early exit)');
  }
}

const out = [];
out.push('');
out.push('id  ' + w('case (hand-derived expectation)', 62) + w('AIR 51.4.1', 24) + w('our AOT', 24) + '');
for (const r of rows) {
  const mark = r.aot !== (air ? r.air : r.want) ? '   <-- DIFFERS' : '';
  out.push(String(r.id).padStart(2) + '  ' + w(expect.label[String(r.id)], 62) + w(r.air, 24) + w(r.aot, 24) + mark);
}
out.push('');
out.push('AOT exit: ' + aotExit);
out.push(fails.length ? 'RESULT: FAIL' : 'RESULT: PASS (' + expect.count + ' cases; both arms agree with the hand-derived answers)');
for (const f of fails) out.push('  FAIL  ' + f);
const text = out.join('\n');
console.log(text);
fs.writeFileSync(RESULTS, text + '\n');

process.exit(fails.length === 0 ? 0 : 1);

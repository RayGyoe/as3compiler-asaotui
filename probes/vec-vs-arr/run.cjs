// probes/vec-vs-arr/run.cjs -- ONE command: is `Vector.<T>` actually faster than
// `Array` in OUR AOT, and does it behave the same way on real AIR?
//
// The point is that we do not have to guess from AVM2 folklore: our AOT lowers
// `Vector.<T>` to a MONOMORPHIZED C struct with typed element storage
// (`int* data` / `double* data`) while `Array` is `as_array`, an array of boxed
// `as_value` cells. This measures the consequence on the SAME benchmark body,
// compiled by BOTH toolchains.
//
// USAGE (from asaotui/):   node probes/vec-vs-arr/run.cjs
//   AIRSDK_HOME=<sdk root>   AIR SDK root (default: the known local 51.4.1)
//   ASC_SKIP_AIR=1           AOT arm only
'use strict';

const fs = require('fs');
const path = require('path');
const { mxmlcRun } = require('../../tools/mxmlc-run.cjs');
const { spawnSync, execFileSync } = require('child_process');

const DIR = __dirname;
const UI = path.resolve(DIR, '..', '..');
const COMPILER = path.resolve(UI, '..', 'as3compiler');
const clang = process.env.ASC_CC || 'clang';
const SDK = process.env.AIRSDK_HOME || 'D:/Adobe/Flex_Sdk/AIRSDK_51.4.1';
const skipAir = process.env.ASC_SKIP_AIR === '1';

const AOT_EXE = path.join(DIR, 'bench-aot.exe');
const AOT_TXT = path.join(DIR, 'vec-aot.txt');
const AIR_TXT = path.join(DIR, 'vec-air.txt');
const AIR_SWF = path.join(DIR, 'BenchAir.swf');

const libs = [  // Host include/link flags come from the manifest -- the single place that
  // knows what each platform needs. Spelling the Windows curl import library
  // and `-l zlib` here by hand made this runner Windows-only (clang on macOS
  // reads that as a file named libzlib.a and the link dies).
  '--manifest', 'examples/window.build.example.json',
];

console.log('[run] building the AOT arm');
if (fs.existsSync(AOT_EXE)) fs.unlinkSync(AOT_EXE);
const b = spawnSync(process.execPath, [
  'src/index.ts',
  path.join(DIR, 'BenchAot.as'), path.join(DIR, 'BenchCore.as'),
  '-o', AOT_EXE, '--cc', clang, '-w', ...libs,
], { cwd: COMPILER, encoding: 'utf8' });
if (b.status !== 0) {
  console.error('[run] AOT BUILD FAILED (exit ' + b.status + ')');
  console.error(((b.stdout || '') + (b.stderr || '')).split(/\r?\n/).slice(-30).join('\n'));
  process.exit(2);
}
if (fs.existsSync(AOT_TXT)) fs.unlinkSync(AOT_TXT);
spawnSync(AOT_EXE, [], { cwd: DIR, encoding: 'utf8' });
if (!fs.existsSync(AOT_TXT)) { console.error('[run] AOT arm wrote no ' + AOT_TXT); process.exit(2); }

let airText = null;
if (!skipAir) {
  const mxmlc = path.join(SDK, 'bin', process.platform === 'win32' ? 'mxmlc.bat' : 'mxmlc');
  const adl = path.join(SDK, 'bin', process.platform === 'win32' ? 'adl.exe' : 'adl');
  if (!fs.existsSync(mxmlc) || !fs.existsSync(adl)) {
    console.error('[run] AIR SDK not found under ' + SDK + ' (set AIRSDK_HOME, or ASC_SKIP_AIR=1)');
    process.exit(2);
  }
  console.log('[run] building the AIR arm with mxmlc');
  if (fs.existsSync(AIR_SWF)) fs.unlinkSync(AIR_SWF);
  if (fs.existsSync(AIR_TXT)) fs.unlinkSync(AIR_TXT);
  const m = mxmlcRun(mxmlc, ['-output=' + AIR_SWF, '-source-path=' + DIR, path.join(DIR, 'BenchAir.as')],
    { cwd: DIR, encoding: 'utf8' });
  if (m.status !== 0 || !fs.existsSync(AIR_SWF)) {
    console.error('[run] mxmlc FAILED (exit ' + m.status + ')');
    console.error(((m.stdout || '') + (m.stderr || '')).split(/\r?\n/).slice(-30).join('\n'));
    process.exit(2);
  }
  console.log('[run] running the AIR arm under adl');
  try { execFileSync(adl, [path.join(DIR, 'app.xml')], { cwd: DIR, timeout: 120000, encoding: 'utf8', stdio: 'ignore' }); }
  catch (e) { /* adl exits noisily; the file is the evidence */ }
  if (!fs.existsSync(AIR_TXT)) { console.error('[run] AIR arm wrote no ' + AIR_TXT); process.exit(2); }
  airText = fs.readFileSync(AIR_TXT, 'utf8');
}

const aotText = fs.readFileSync(AOT_TXT, 'utf8');

// ---- parse into { label -> ms } and print a side-by-side table --------------
function parse(txt) {
  const m = {};
  for (const l of txt.split(/\r?\n/)) {
    const mm = l.match(/^\s{2}(.+?)\s+(\d+)\s*$/);
    if (mm) m[mm[1].trim()] = Number(mm[2]);
  }
  return m;
}
const A = parse(aotText), R = airText ? parse(airText) : null;

const labels = Object.keys(A);
const hdr = ['benchmark', 'our AOT', airText ? 'AIR (adl)' : ''];
console.log('');
console.log('N=' + (/N=(\d+)/.exec(aotText) || [, '?'])[1] + ' elements, best of ' + (/best of (\d+)/.exec(aotText) || [, '?'])[1] + ', ms');
console.log(hdr[0].padEnd(28) + hdr[1].padStart(9) + (R ? hdr[2].padStart(11) : ''));
for (const k of labels) {
  console.log(k.padEnd(28) + String(A[k]).padStart(9) + (R ? String(R[k] == null ? '?' : R[k]).padStart(11) : ''));
}

// ---- the two ratios the question is actually about -------------------------
function ratio(map, a, b) {
  if (map[a] == null || map[b] == null) return null;
  return (map[a] / map[b]).toFixed(2);
}
console.log('');
for (const [name, map] of [['our AOT', A], ['AIR (adl)', R]]) {
  if (!map) continue;
  console.log(name + ': Vector.<int>/Array = ' + ratio(map, 'Vector.<int>    fill+sum', 'Array           fill+sum')
    + 'x   Vector.<Number>/Array = ' + ratio(map, 'Vector.<Number> fill+sum', 'Array           fill+sum')
    + 'x   (lower is better)');
}

// ---- sanity: the benchmark must not be vacuous -----------------------------
let bad = 0;
for (const k of labels) {
  if (!(A[k] >= 1)) { console.log('  FAIL  AOT ' + k + ' reported ' + A[k] + ' ms -- getTimer granularity? raise N'); bad++; }
  if (R && !(R[k] >= 1)) { console.log('  FAIL  AIR ' + k + ' reported ' + R[k] + ' ms'); bad++; }
}
if (A['Vector.<int>    fill+sum'] == null) { console.log('  FAIL  expected benchmark rows are missing'); bad++; }

// ---- the CLAIM this probe exists to defend ---------------------------------
// Our AOT lowers Vector.<T> to a monomorphized C struct (int*/double* element
// storage) while Array is an array of boxed as_value cells. If that ever stops
// being true (a Vector silently lowered to as_array, an extra copy, a bounds
// check with a call per read), this ratio collapses towards 1 and the gate fires.
const RATIO_CLAIM = 0.5;      // Vector.<int> must be at least 2x faster than Array
const intRat = A['Vector.<int>    fill+sum'] / A['Array           fill+sum'];
if (!(intRat <= RATIO_CLAIM)) {
  console.log('  FAIL  Vector.<int> is only ' + intRat.toFixed(2) + 'x Array on the AOT arm (claim: <= ' + RATIO_CLAIM + 'x)');
  bad++;
} else {
  console.log('  claim  AOT Vector.<int> / Array = ' + intRat.toFixed(2) + 'x  (<= ' + RATIO_CLAIM + 'x: monomorphized element storage holds)');
}
console.log('');
console.log(bad === 0 ? 'RESULT: PASS (rows measured on both runtimes)' : 'RESULT: FAIL');
process.exit(bad === 0 ? 0 : 1);

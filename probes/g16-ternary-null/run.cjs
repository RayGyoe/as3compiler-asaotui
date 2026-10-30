// probes/g16-ternary-null/run.cjs -- ONE command, BOTH arms.
//
// Question: does `cond ? null : objValue` evaluate to `objValue` when the condition
// is false? In AS3 it must (the conditional operator picks a branch by its
// condition, and a null literal is just a value). Our AOT returns NULL for the
// object-typed result, and this probe pins BOTH the shape that fails and the
// neighbouring shapes that do not, on both runtimes -- so the finding cannot be
// written off as "an object round trip is broken somehow".
//
// USAGE (from asaotui/):   node probes/g16-ternary-null/run.cjs
//   ASC_CC=clang                  override the C compiler
//   AIRSDK_HOME=<sdk root>        AIR SDK root (default: the known local 51.4.1)
//   ASC_SKIP_AIR=1                AOT arm only (no mxmlc/adl)
//
// EXIT CODES
//   0  both arms agree with the hand-derived rule AND with each other
//   1  they do not  (with G16 unfixed this is the expected result: the AOT arm
//      fails case 1, 4, 5, 7, 8, 9, 10 and 14 -- every shape whose THEN branch is a
//      null literal -- while AIR passes all of them)
//   2  a build/run step failed (build error, missing SDK, adl wrote nothing)
'use strict';

const fs = require('fs');
const path = require('path');
const { mxmlcRun } = require('../../tools/mxmlc-run.cjs');
const { spawnSync, execFileSync } = require('child_process');
const { ALL } = require('../../ui-demo/kit-list.cjs');

const DIR = __dirname;
const UI = path.resolve(DIR, '..', '..');
const COMPILER = path.resolve(UI, '..', 'as3compiler');
const clang = process.env.ASC_CC || 'clang';
const SDK = process.env.AIRSDK_HOME || 'D:/Adobe/Flex_Sdk/AIRSDK_51.4.1';
const skipAir = process.env.ASC_SKIP_AIR === '1';

const AOT_TXT = path.join(DIR, 'g16-ternary-null-aot.txt');
const AIR_TXT = path.join(DIR, 'g16-ternary-null-air.txt');
const AOT_EXE = path.join(DIR, 'AotMain.exe');
const AIR_SWF = path.join(DIR, 'AirMain.swf');
const RESULTS = path.join(DIR, 'g16-ternary-null-results.txt');

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

// --------------------------------------------------------------- AOT arm -----
console.log('[g16] building the AOT arm');
clean(AOT_EXE); clean(AOT_TXT);
const build = spawnSync(process.execPath, [
  'src/index.ts',
  path.join(DIR, 'AotMain.as'),
  path.join(DIR, 'NullCases.as'),
  ...ALL,
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
  console.error('[g16] AOT BUILD FAILED (exit ' + build.status + ')');
  console.error(((build.stdout || '') + (build.stderr || '')).split(/\r?\n/).slice(-30).join('\n'));
  process.exit(2);
}
console.log('[g16] running the AOT arm');
const aotRun = spawnSync(AOT_EXE, [], { cwd: DIR, encoding: 'utf8' });
const aot = parse(AOT_TXT);
const aotExit = aotRun.status === null ? 'signal ' + aotRun.signal : aotRun.status;

// --------------------------------------------------------------- AIR arm -----
let air = null;
if (!skipAir) {
  const mxmlc = path.join(SDK, 'bin', process.platform === 'win32' ? 'mxmlc.bat' : 'mxmlc');
  const adl = path.join(SDK, 'bin', process.platform === 'win32' ? 'adl.exe' : 'adl');
  if (!fs.existsSync(mxmlc) || !fs.existsSync(adl)) {
    console.error('[g16] AIR SDK not found under ' + SDK + ' (set AIRSDK_HOME, or ASC_SKIP_AIR=1)');
    process.exit(2);
  }
  console.log('[g16] building the AIR arm with mxmlc');
  clean(AIR_SWF); clean(AIR_TXT);
  const m = mxmlcRun(mxmlc, ['-output=' + AIR_SWF,
    '-source-path=' + DIR,
    path.join(DIR, 'AirMain.as')], { cwd: DIR, encoding: 'utf8' });
  if (m.status !== 0 || !fs.existsSync(AIR_SWF)) {
    console.error('[g16] mxmlc FAILED (exit ' + m.status + ')');
    console.error(((m.stdout || '') + (m.stderr || '')).split(/\r?\n/).slice(-30).join('\n'));
    process.exit(2);
  }
  console.log('[g16] running the AIR arm');
  let adlErr = '';
  try { execFileSync(adl, [path.join(DIR, 'app.xml')], { cwd: DIR, timeout: 60000, encoding: 'utf8', stdio: 'pipe' }); }
  catch (e) { adlErr = String((e && e.stderr) || ''); /* adl exit codes are noisy; the evidence is the file */ }
  if (!fs.existsSync(AIR_TXT)) {
    console.error('[g16] adl wrote no ' + AIR_TXT);
    if (adlErr) console.error('[g16] adl stderr:\n' + adlErr.trim());
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
    fails.push('id ' + id + ': AIR says "' + gotAir + '" but the hand-derived rule says "' + want
      + '" -- the REFERENCE disagrees; re-derive the rule');
  }
  const ref = air ? gotAir : want;
  if (gotAot !== ref) {
    fails.push('id ' + id + ': our AOT says "' + gotAot + '" but ' + (air ? 'AIR' : 'the rule') + ' says "' + ref + '"');
  }
}

// A crash stops a run, so a short file is evidence too.
for (const [name, table, where] of [['AOT', aot, 'g16-ternary-null-aot.txt'], ['AIR', air, 'g16-ternary-null-air.txt']]) {
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
out.push('id  ' + w('case', 46) + w('rule', 8) + w('AIR 51.4.1', 12) + w('our AOT', 12) + '');
for (const r of rows) {
  const mark = r.aot !== (air ? r.air : r.want) ? '   <-- DIFFERS' : '';
  out.push(String(r.id).padStart(2) + '  ' + w(expect.label[String(r.id)], 46) + w(r.want, 8) + w(r.air, 12) + w(r.aot, 12) + mark);
}
out.push('');
out.push('AOT exit: ' + aotExit);
out.push(fails.length
  ? 'RESULT: FAIL (' + fails.length + ' disagreement(s); the failing shape is `cond ? null : obj`)'
  : 'RESULT: PASS (' + expect.count + ' cases; both arms agree with the hand-derived answers)');
for (const f of fails) out.push('  FAIL  ' + f);
const text = out.join('\n');
console.log(text);
fs.writeFileSync(RESULTS, text + '\n');

process.exit(fails.length === 0 ? 0 : 1);

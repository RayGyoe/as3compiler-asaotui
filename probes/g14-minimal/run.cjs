// probes/g14-minimal/run.cjs -- the handoff package for compiler-gaps.md G14.
//
// ONE command, BOTH runtimes, on the smallest program that shows the bug:
//
//   node probes/g14-minimal/run.cjs
//
// Expected (real AIR 51.4.1, measured -- not assumed):
//     is Array  = true
//     is Marker = false
//     REACHED THE END (no crash)
//
// Ours today:
//     is Array  = false            <- silently wrong, compile-time folded
//     (nothing else)               <- the 2nd line kills the process, 0xC0000005
//
// Exit code: 0 when the bug is REPRODUCED (that is what this package is for),
// 1 when it is NOT (i.e. somebody fixed it -- then go update compiler-gaps.md G14,
// expect.json of probes/obj-array-identity, and the assertions in
// ui-demo/CheckUi.as section 8), 2 on a harness failure (build failed, SDK missing).
//
// Options: ASC_CC=clang (C compiler), AIRSDK_HOME=<sdk root>, ASC_SKIP_AIR=1.
'use strict';

const fs = require('fs');
const path = require('path');
const { spawnSync, execFileSync } = require('child_process');

const DIR = __dirname;
const UI = path.resolve(DIR, '..', '..');
const COMPILER = path.resolve(UI, '..', 'as3compiler');
const clang = process.env.ASC_CC || 'clang';
const SDK = process.env.AIRSDK_HOME || 'D:/Adobe/Flex_Sdk/AIRSDK_51.4.1';

const AOT_TXT = path.join(DIR, 'g14-aot.txt');
const AIR_TXT = path.join(DIR, 'g14-air.txt');
const AOT_EXE = path.join(DIR, 'g14-repro.exe');
const AIR_SWF = path.join(DIR, 'ReproAir.swf');

const clean = (p) => { if (fs.existsSync(p)) fs.unlinkSync(p); };
const readLines = (p) => (fs.existsSync(p) ? fs.readFileSync(p, 'utf8').trim().split(/\r?\n/) : []);

// ---------------------------------------------------------------- our AOT ----
console.log('[g14] building the AOT arm (our compiler)');
clean(AOT_EXE); clean(AOT_TXT);
const build = spawnSync(process.execPath, [
  'src/index.ts',
  path.join(DIR, 'ReproAot.as'),
  path.join(DIR, 'Marker.as'),
  '-o', AOT_EXE,
  '--cc', clang, '-w',
  '-I', './vendor/curl/include',
  '-L', './vendor/curl/lib/windows-x64',
  '-l', 'zlib',
], { cwd: COMPILER, encoding: 'utf8' });
if (build.status !== 0) {
  console.error('[g14] AOT BUILD FAILED (exit ' + build.status + ')');
  console.error(((build.stdout || '') + (build.stderr || '')).split(/\r?\n/).slice(-25).join('\n'));
  process.exit(2);
}

console.log('[g14] running the AOT arm');
const run = spawnSync(AOT_EXE, [], { cwd: DIR, encoding: 'utf8' });
const aotExit = run.status === null ? 'killed by signal ' + run.signal : run.status;
const aotLines = readLines(AOT_TXT);

// ------------------------------------------------------------------- AIR -----
let airLines = [];
if (process.env.ASC_SKIP_AIR !== '1') {
  const mxmlc = path.join(SDK, 'bin', process.platform === 'win32' ? 'mxmlc.bat' : 'mxmlc');
  const adl = path.join(SDK, 'bin', process.platform === 'win32' ? 'adl.exe' : 'adl');
  if (!fs.existsSync(mxmlc) || !fs.existsSync(adl)) {
    console.error('[g14] AIR SDK not found under ' + SDK + ' (set AIRSDK_HOME, or ASC_SKIP_AIR=1)');
    process.exit(2);
  }
  console.log('[g14] building + running the AIR arm (mxmlc + adl)');
  clean(AIR_SWF); clean(AIR_TXT);
  const m = spawnSync('cmd', ['/c', mxmlc, '-output=' + AIR_SWF, '-source-path=' + DIR, path.join(DIR, 'ReproAir.as')],
    { cwd: DIR, encoding: 'utf8' });
  if (m.status !== 0 || !fs.existsSync(AIR_SWF)) {
    console.error('[g14] mxmlc FAILED (exit ' + m.status + ')');
    console.error(((m.stdout || '') + (m.stderr || '')).split(/\r?\n/).slice(-25).join('\n'));
    process.exit(2);
  }
  try { execFileSync(adl, [path.join(DIR, 'app.xml')], { cwd: DIR, timeout: 60000, stdio: 'ignore' }); }
  catch (e) { /* adl exit codes are noisy; the file is the evidence */ }
  airLines = readLines(AIR_TXT);
}

// ---------------------------------------------------------------- report -----
const pad = (s, n) => String(s).padEnd(n);
console.log('');
console.log('--- our AOT (exit ' + aotExit + ')'.padEnd(56) + '--- AIR 51.4.1 (reference)');
const rows = Math.max(aotLines.length, airLines.length, 1);
for (let i = 0; i < rows; i++) {
  console.log('    ' + pad(aotLines[i] === undefined ? '(never got here)' : aotLines[i], 48) + '    ' + (airLines[i] === undefined ? '(n/a)' : airLines[i]));
}
console.log('');

const airOk = airLines.length === 3
  && /is Array  = true/.test(airLines[0] || '')
  && /is Marker = false/.test(airLines[1] || '');
if (process.env.ASC_SKIP_AIR !== '1') {
  if (!airOk) {
    console.log('[g14] the AIR arm does not match the AS3 rule -- the REFERENCE itself disagrees.');
    console.log('      Do not conclude anything about our AOT until that is re-derived.');
    process.exit(2);
  }
  console.log('[g14] reference agrees with the AS3 rule (is Array = true, is Marker = false, no crash)');
}

const aotCrash = aotExit !== 0;
const aotWrongArray = !(aotLines[0] || '').match(/is Array  = true/);
if (aotCrash || aotWrongArray) {
  console.log('[g14] REPRODUCED on our AOT:'
    + (aotWrongArray ? ' `is Array` answered false' : '')
    + (aotWrongArray && aotCrash ? ' and' : '')
    + (aotCrash ? ' the process died (' + aotExit + ') on `is Marker`' : '')
    + '.');
  console.log('[g14] see reviews/handoff-g14-to-compiler-2026-10-23.md for the two fixes leads.');
  process.exit(0);
}
console.log('[g14] NOT reproduced: our AOT now matches AIR on both questions.');
console.log('[g14] If this is a real fix, update: compiler-gaps.md G14,');
console.log('      probes/obj-array-identity/expect.json (knownAotDeviations), and');
console.log('      ui-demo/CheckUi.as section 8. Then re-run tools/gates.cjs.');
process.exit(1);

// probes/g31-space/run.cjs -- the handoff package for compiler-gaps.md G31.
//
//   node probes/g31-space/run.cjs
//
// Builds BOTH arms of the same question and prints them side by side:
//
//   AOT  our compiler -> C -> native   (probes/g31-space/src/Main.as, --air-app)
//   AIR  mxmlc -> adl  (probes/g31-space/AirMain.as)   [ASC_SKIP_AIR=1 skips it]
//
// The question: is the space after "A" as wide as the space after other letters?
// Measured, not assumed: AIR lays a uniform 4 px gap after every letter; we lay 2 px
// after "A" and 3-5 px after the rest, while the TOTAL span of every string matches
// AIR exactly -- i.e. the glyphs are all there, their advances are just quantised.
//
// Exit code: 0 when the defect REPRODUCES (that is what this package is for),
// 1 when it does not (somebody fixed the advance rounding -- then update
// compiler-gaps.md G31), 2 on a harness failure (build failed, SDK missing).
//
// Options: ASC_CC=clang, AIRSDK_HOME=<sdk root>, ASC_SKIP_AIR=1.
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const { resolveAirSdk } = require('../../tools/air-sdk.cjs');
// mxmlc is a .bat on Windows -- spawned directly it fails with an empty error.
const { mxmlcRun, sdkBin } = require('../../tools/mxmlc-run.cjs');

const DIR = __dirname;
const UI = path.resolve(DIR, '..', '..');
const COMPILER = path.resolve(UI, '..', 'as3compiler');
const clang = process.env.ASC_CC || 'clang';

const AOT_TXT = path.join(DIR, 'g31-aot.txt');
const AIR_TXT = path.join(os.homedir(), 'g31-air.txt');
const AOT_EXE = path.join(DIR, 'g31aot.exe');
const AIR_SWF = path.join(DIR, 'AirMain.swf');

const clean = (p) => { if (fs.existsSync(p)) fs.unlinkSync(p); };
const parse = (p) => {
  if (!fs.existsSync(p)) return null;
  const rows = {};
  for (const line of fs.readFileSync(p, 'utf8').split(/\r?\n/)) {
    if (!line || line.startsWith('#')) continue;
    const [text, ink] = line.split('\t');
    if (text && ink) rows[text] = ink;
  }
  return rows;
};

// ------------------------------------------------------------------ our AOT ----
console.log('[g31] building the AOT arm (our compiler)');
clean(AOT_EXE); clean(AOT_TXT);
const build = spawnSync(process.execPath, [
  'src/index.ts',
  '--air-app', path.join(DIR, 'app.xml'),
  '--main-class', 'g31.Main',
  '--cc', clang,
  // Windows-only link inputs for the window/d3d backend. They live here, not in the
  // compiler: another platform simply omits them.
  ...(process.platform === 'win32' ? ['--cflag', '-ld3d12', '--cflag', '-ld3dcompiler'] : []),
], { cwd: COMPILER, encoding: 'utf8', timeout: 600000 });
if (build.status !== 0) {
  console.error('[g31] AOT BUILD FAILED (exit ' + build.status + ')');
  console.error((build.stdout || '') + (build.stderr || ''));
  process.exit(2);
}
// The app writes its file on the first frame and then exits by itself; the timeout is
// only a hang guard (a blocked showWindow never returns).
const aotRun = spawnSync(AOT_EXE, [], { cwd: DIR, encoding: 'utf8', timeout: 60000 });
if (!fs.existsSync(AOT_TXT)) {
  console.error('[g31] the AOT arm wrote no g31-aot.txt (exit ' + aotRun.status + ')');
  process.exit(2);
}

// --------------------------------------------------------------------- AIR ----
let airRows = null;
if (process.env.ASC_SKIP_AIR === '1') {
  console.log('[g31] AIR arm skipped (ASC_SKIP_AIR=1)');
} else {
  const info = resolveAirSdk();
  if (!info.root) {
    console.log('[g31] AIR SDK not found -- skipping the AIR arm (' + describeMissing(info) + ')');
  } else {
    console.log('[g31] building the AIR arm with mxmlc');
    clean(AIR_SWF); clean(AIR_TXT);
    const swf = mxmlcRun(sdkBin(info.root, 'mxmlc'),
      ['-output=' + AIR_SWF, path.join(DIR, 'AirMain.as')],
      { cwd: DIR, encoding: 'utf8', timeout: 300000 });
    if (swf.status !== 0) {
      console.error('[g31] mxmlc FAILED');
      console.error((swf.stdout || '') + (swf.stderr || ''));
      process.exit(2);
    }
    const adlRun = spawnSync(sdkBin(info.root, 'adl').replace(/.bat$/, '.exe'),
      [path.join(DIR, 'app-air.xml')],
      { cwd: DIR, encoding: 'utf8', timeout: 30000 });
    airRows = parse(AIR_TXT);
    if (!airRows) {
      console.error('[g31] the AIR arm wrote no ' + AIR_TXT + ' (adl exit ' + adlRun.status + ')');
      process.exit(2);
    }
  }
}

function describeMissing(info) {
  return info && info.reason ? info.reason : 'set AIRSDK_HOME';
}

// ------------------------------------------------------------------ compare ----
const aot = parse(AOT_TXT);
const keys = Object.keys(aot);
console.log('');
console.log('[g31] ink gaps, Arial 12   (AIR = the reference)');
console.log('  ' + 'text'.padEnd(18) + 'AIR'.padEnd(30) + 'ours');
for (const k of keys) {
  const a = airRows ? (airRows[k] || '(missing)') : '(air skipped)';
  console.log('  ' + k.padEnd(18) + a.padEnd(30) + aot[k]);
}

const spaceAfterA = (row) => {
  const m = /gaps=\[\s*(\d+)/.exec(row || '');
  return m ? Number(m[1]) : -1;
};
const oursA = spaceAfterA(aot['A |']);
console.log('');
if (!airRows) {
  console.log('[g31] ours: space after "A" = ' + oursA + 'px, after "b" = ' + spaceAfterA(aot['b |']) + 'px');
  console.log('RESULT: INCONCLUSIVE (no AIR arm)');
  process.exit(0);
}
const airA = spaceAfterA(airRows['A |']);
const airB = spaceAfterA(airRows['b |']);
const oursB = spaceAfterA(aot['b |']);
const sameTotal = (k) => {
  const grab = (r) => { const m = /span=(\d+)/.exec(r || ''); return m ? Number(m[1]) : -1; };
  return grab(aot[k]) === grab(airRows[k]);
};
const reproduced = oursA < airA;
console.log('[g31] space after "A":  AIR ' + airA + 'px   ours ' + oursA + 'px');
console.log('[g31] space after "b":  AIR ' + airB + 'px   ours ' + oursB + 'px');
console.log('[g31] total span matches AIR on "A box": ' + sameTotal('A box')
  + ', on "A card is a box": ' + sameTotal('A card is a box'));
console.log(reproduced
  ? 'RESULT: REPRODUCED -- our (A, space) gap is ' + (airA - oursA) + 'px narrower than AIR\'s'
  : 'RESULT: FIXED -- our (A, space) gap is no longer narrower than AIR\'s');
process.exit(reproduced ? 0 : 1);
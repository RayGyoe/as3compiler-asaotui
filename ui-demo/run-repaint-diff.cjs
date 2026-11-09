// ui-demo/run-repaint-diff.cjs -- build + run the incremental-vs-full repaint
// differential gate (RepaintDiff.as) and propagate its verdict.
//
// WHY A DRIVER: the gate needs a REAL window, because its oracle is the pixels
// `BitmapData.draw(stage)` reads back from the retained display list. A window
// BLOCKS until it is closed, so the sequence is: build, launch detached, wait for
// the app's `.done` file, kill the window, report. Same shape as
// layout-check/visual-check.cjs (which reads a framebuffer) and ui-demo/
// run-gallery.cjs (which waits for `gallery.done`).
//
// The verdict comes from the app, not from this script: RepaintDiff.as compares
// the two pictures itself (same state, one incremental frame, one full repaint)
// and writes PASS/FAIL with the first differing pixel. This driver must not
// re-implement that comparison -- duplicate oracles drift.
//
// Usage:  node run-repaint-diff.cjs
// Needs:  clang on PATH (or ASC_CC pointing at clang.exe), vendor/{skia,sdl2}.
//
// EXIT CODES: 0 pass, 1 anything else. NOT 3 on an infrastructure failure --
// `tools/gates.cjs` reads 3 as SKIP ("could not measure"), and a build that never
// produced a binary, or a window that never wrote its .done, must be a loud red
// here: nothing about it is expected, and a skipped gate certifies nothing.
'use strict';

const path = require('path');
const fs = require('fs');
const { spawn, spawnSync } = require('child_process');
const { ALL } = require('./kit-list.cjs');

const here = __dirname;
const compilerDir = path.resolve(here, '..', '..', 'as3compiler');
const SRC = path.join(here, 'RepaintDiff.as');
// The compiler appends the platform suffix itself; `-o` names the artifact
// WITHOUT it (same convention as layout-check/visual-check.cjs).
const EXE = path.join(here, process.platform === 'win32' ? 'RepaintDiff.exe' : 'RepaintDiff');
const DONE = path.join(here, 'repaint-diff.done');
const BMP_GLOB = /^repaint-(inc|full)-\d+\.bmp$/;

const clang = process.env.ASC_CC || 'clang';

function killDemo() {
  if (!fs.existsSync(EXE)) return;
  spawnSync(process.platform === 'win32' ? 'taskkill' : 'pkill',
    process.platform === 'win32' ? ['/F', '/IM', path.basename(EXE)] : ['-f', path.basename(EXE)],
    { encoding: 'utf8' });
}
function step(msg) { console.log('\n=== ' + msg + ' ==='); }

// ---- 1. clear the previous run -------------------------------------------
step('close any previous window and clear stale evidence');
killDemo();
for (let i = 0; i < 20 && fs.existsSync(EXE); i++) {
  try { fs.unlinkSync(EXE); } catch (e) { /* still locked; retry */ }
}
for (const f of [DONE, ...fs.readdirSync(here).filter((n) => BMP_GLOB.test(n))]) {
  const p = path.join(here, f);
  if (fs.existsSync(p)) fs.unlinkSync(p);
}

// ---- 2. build -------------------------------------------------------------
step('build with the WINDOW manifest (Skia + a real stage)');
const build = spawnSync(process.execPath, [
  path.join(compilerDir, 'src', 'index.ts'),
  SRC,
  ...ALL,
  '--cc', clang,
  // The window backend comes from the manifest, the single place that knows what
  // each host needs. `--manifest` is why this check is portable at all.
  '--manifest', 'examples/window.build.example.json',
  '-o', path.join(here, 'RepaintDiff'),
], { cwd: compilerDir, encoding: 'utf8', timeout: Number(process.env.ASC_BUILD_TIMEOUT_MS || 300000) });

const buildOut = ((build.stdout || '') + (build.stderr || ''));
const interesting = buildOut.split('\n').filter((l) => /Build (successful|failed)|rror/.test(l));
console.log(interesting.length ? interesting.join('\n') : buildOut.slice(-1200));
if (!fs.existsSync(EXE)) {
  console.error('BUILD FAILED: ' + EXE + ' was not produced');
  process.exit(1);
}
console.log('ok: ' + path.basename(EXE) + ' (' + fs.statSync(EXE).size + ' bytes)');

// ---- 3. run it detached (showWindow blocks) ------------------------------
step('run the window and wait for repaint-diff.done');
const launchAt = Date.now();
const win = spawn(EXE, [], { cwd: here, detached: true, stdio: 'ignore' });
win.unref();
console.log('pid ' + win.pid);

// A `.done` is only OURS if it was written AFTER this process started. Without
// that check a leftover file from an earlier run (a window that survived
// taskkill, a deleted-but-reopened file) is read as this run's verdict -- and a
// stale PASS is the one failure mode that makes a gate worthless.
const fresh = () => fs.existsSync(DONE) && fs.statSync(DONE).mtimeMs >= launchAt;

const deadline = Date.now() + Number(process.env.ASC_REPAINT_TIMEOUT_MS || 30000);
while (!fresh() && Date.now() < deadline) {
  // A blocking sleep without a child process; the app runs on its own thread of
  // control (detached), so this only paces the poll.
  spawnSync(process.execPath, ['-e', 'setTimeout(()=>{},150)']);
}
if (!fresh()) {
  console.error('TIMEOUT: the app never wrote ' + path.basename(DONE));
  killDemo();
  process.exit(1);
}

// ---- 4. report ------------------------------------------------------------
step('verdict');
const report = fs.readFileSync(DONE, 'utf8');
console.log(report.trim());
killDemo();

const pass = /REPAINT-DIFF: PASS /.test(report);
console.log('\n' + (pass ? 'GATE PASS' : 'GATE FAIL'));
process.exit(pass ? 0 : 1);

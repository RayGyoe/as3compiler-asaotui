// run-hymn.cjs -- build and launch the hymn book demo through the same
// `as-aot --air-app` path the gallery uses.
//
// Usage:  node run-hymn.cjs [--build-only] [--keep]
// Env:    ASC_CC=clang            compiler (default: clang on PATH)
//         ASC_HYMN_XML=app.xml    descriptor name inside hymn-demo/
//         ASC_KEEP_WINDOW=1       leave the window up after the beacon is read
//
// WHY ITS OWN RUNNER AND NOT run-gallery.cjs. The gallery runner is bound to the docs
// demo in three ways that are all correct there and wrong here: it stages
// ui-demo/demo/** into `air-gallery/src`, it names `demo.DocsMain` as the document
// class, and it measures eight `gallery-page*.png` files. This app keeps its sources
// in its own `src/` (no staging copy: there is nothing to stage) and its captures are
// its own (a splash, the page as it opens, a tuned hymn, and the light palette with the
// drawer away), so the shared parts are the DESCRIPTOR reader and the beacon poller
// (air-run.cjs) rather than the whole flow.
'use strict';

const path = require('path');
const fs = require('fs');
const { spawnSync, spawn } = require('child_process');
const { descriptorWindow, killImage, waitForFile, compilerTree } = require('./air-run.cjs');

const here = __dirname;
const compilerDir = path.resolve(here, '..', '..', 'as3compiler');
const clang = process.env.ASC_CC || 'clang';
const appDir = path.join(here, 'hymn-demo');
const descriptorName = process.env.ASC_HYMN_XML || 'app.xml';
const descriptor = path.join(appDir, descriptorName);
const EXE = process.platform === 'win32' ? 'HymnApp.exe' : 'HymnApp';
const exe = path.join(appDir, EXE);
const DONE = path.join(appDir, 'hymn.done');
// Every picture the capture plan in HymnMain.onFrame promises. A missing file is a
// failed run: the phase that writes it never reached its frame, and a demo that shows
// one state is not evidence for the other three.
const SHOTS = ['hymn-splash.png', 'hymn-page.png', 'hymn-tuned.png', 'hymn-light.png']
  .map((f) => path.join(appDir, f));
const RECTS = ['hymn-rects-page.txt', 'hymn-rects-tuned.txt', 'hymn-rects-light.txt']
  .map((f) => path.join(appDir, f));
const SHOT = SHOTS[1];
const RUN_LOG = path.join(appDir, 'hymn.run.log');

const argv = process.argv.slice(2);
const buildOnly = argv.includes('--build-only');
const keep = argv.includes('--keep') || process.env.ASC_KEEP_WINDOW === '1';

if (!fs.existsSync(descriptor)) {
  console.error('[hymn] descriptor not found: ' + descriptor);
  process.exit(2);
}

// A live window holds the exe on Windows; the next build would fail with EACCES.
function killWindow() {
  if (launchedPid) {
    for (const t of [-launchedPid, launchedPid]) {
      try { process.kill(t, 'SIGKILL'); } catch (e) { /* already gone */ }
    }
  }
  killImage(EXE);
}
let launchedPid = 0;

killWindow();
for (const f of [DONE, SHOT, RUN_LOG]) {
  if (fs.existsSync(f)) fs.unlinkSync(f);
}

const size = descriptorWindow(descriptor);
if (!size) {
  console.error('[hymn] ' + descriptor + ' has no <width>/<height>');
  process.exit(2);
}
console.log('[hymn] descriptor ' + descriptorName + ': window ' + size.w + 'x' + size.h
  + ', requestedDisplayResolution=' + size.resolution + ', renderMode=' + size.renderMode);

const args = [
  'src/index.ts',
  '--air-app', descriptor,
  // The inference matches any file whose name ENDS WITH `Main.as`; naming the
  // document class is what the AIR model does anyway (the descriptor has no slot).
  '--main-class', 'hymn.HymnMain',
  '--cc', clang,
  '--as-class-path', path.join(here, '..', 'seam'),
  '--as-class-path', path.join(here, '..', 'kit'),
];

// Windows link fixture, same one run-gallery.cjs carries: the vendored Skia archive
// references the D3D12 shader compiler even for a CPU-composited window (the GPU
// backend is compiled into the static lib, so its imports must resolve at link time),
// and `--air-app`'s link line does not name them yet. It is a COMPILER gap, not
// something this demo introduced.
if (process.platform === 'win32') args.push('--cflag', '-ld3d12', '--cflag', '-ld3dcompiler');

{
  const tree = compilerTree(compilerDir);
  console.log('[hymn] compiler tree: HEAD ' + tree.head + ', tracked modifications: '
    + (tree.tracked.length ? tree.tracked.join(' | ') : '(none)'));
}

const t0 = Date.now();
const r = spawnSync(process.execPath, args, {
  cwd: compilerDir, stdio: 'inherit',
  timeout: Number(process.env.ASC_BUILD_TIMEOUT_MS || 600000), killSignal: 'SIGKILL',
});
if (r.status !== 0) {
  console.error('[hymn] BUILD FAILED (exit ' + r.status + ')');
  process.exit(1);
}
console.log('[hymn] build ' + ((Date.now() - t0) / 1000).toFixed(1) + 's, exe '
  + (fs.existsSync(exe) ? fs.statSync(exe).size + ' B' : 'MISSING'));

const manifestPath = path.join(appDir, 'HymnApp.build.json');
if (fs.existsSync(manifestPath)) {
  const man = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  const defs = [].concat(man.defines || []).map(String);
  console.log('[hymn] manifest: ASC_DISPLAY_HIGH '
    + (defs.some((d) => /^ASC_DISPLAY_HIGH=1$/.test(d)) ? 'present' : 'ABSENT')
    + ', ASC_RENDER_WINGPU ' + (defs.includes('ASC_RENDER_WINGPU=1') ? 'present' : 'absent'));
}

if (buildOnly) process.exit(0);

if (!fs.existsSync(exe)) {
  console.error('[hymn] expected exe not found: ' + exe);
  process.exit(3);
}

const runFd = fs.openSync(RUN_LOG, 'w');
const child = spawn(exe, [], { cwd: appDir, detached: true, stdio: ['ignore', runFd, runFd] });
fs.closeSync(runFd);
launchedPid = child.pid;
child.unref();

const done = waitForFile(DONE, Number(process.env.ASC_TOUR_TIMEOUT_MS || 45000));
if (done === null) {
  console.error('[hymn] TIMEOUT: hymn.done was never written');
  if (fs.existsSync(RUN_LOG)) console.error(fs.readFileSync(RUN_LOG, 'utf8'));
  if (!keep) killWindow();
  process.exit(1);
}
console.log('[hymn] beacon: ' + done.trim());
if (fs.existsSync(RUN_LOG)) {
  const log = fs.readFileSync(RUN_LOG, 'utf8').trim();
  if (log) console.log('---- hymn.run.log ----\n' + log);
}
for (const p of SHOTS.concat(RECTS)) {
  if (!fs.existsSync(p)) {
    console.error('[hymn] MISSING capture: ' + path.basename(p));
    if (!keep) killWindow();
    process.exit(1);
  }
}
console.log('[hymn] captures ' + SHOTS.map((p) => path.basename(p) + ' '
  + fs.statSync(p).size + ' B').join(', '));
if (keep) {
  console.log('[hymn] window left up (--keep)');
} else {
  killWindow();
}

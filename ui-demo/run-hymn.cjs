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
// THE CAPTURE PLAN IS OPT-IN. HymnMain only runs its phases when `auto-tour` sits next
// to the executable, so double-clicking the exe gives a normal app and nothing else.
// This script creates it before the launch and deletes it on the way out (including on
// every early exit), so the marker never lingers to surprise a later manual run.
const TOUR_MARKER = path.join(appDir, 'auto-tour');
// Every picture the capture plan in HymnMain.onFrame promises. A missing file is a
// failed run: the phase that writes it never reached its frame, and a demo that shows
// one state is not evidence for the other three.
const SHOTS = ['hymn-splash.png', 'hymn-page.png', 'hymn-tuned.png', 'hymn-light.png',
  'hymn-playing.png', 'hymn-dark2.png']
  .map((f) => path.join(appDir, f));
const RECTS = ['hymn-rects-page.txt', 'hymn-rects-tuned.txt', 'hymn-rects-light.txt',
  'hymn-rects-dark2.txt']
  .map((f) => path.join(appDir, f));
// hymnbook's ported unit tests plus the tune/note join, written at load. It is a
// gate, not a note: a corpus that stops joining is exactly what the silent build used
// to hide.
const SELFTEST = path.join(appDir, 'hymn-selftest.txt');
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
for (const f of [DONE, SHOT, RUN_LOG, SELFTEST]) {
  if (fs.existsSync(f)) fs.unlinkSync(f);
}
fs.writeFileSync(TOUR_MARKER, 'created by run-hymn.cjs while the capture plan runs\n');
process.on('exit', () => {
  try { fs.unlinkSync(TOUR_MARKER); } catch (e) { /* already gone */ }
});

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

// CALLBACK ARITY, BEFORE THE BUILD. The kit invokes `onClick()` with no arguments and
// `onChange(v)` with exactly one (UiNode.as's contract note); a handler that declares
// the wrong arity compiles fine, throws `#1063` at the click, and the frame guard
// swallows it -- the widget simply never responds. This demo shipped sixteen such
// handlers and no capture noticed, because the capture called model verbs instead of
// clicking. The gate is cheap and it fails the run, so it runs here as a preflight.
{
  const gate = path.join(here, '..', 'tools', 'callback-arity.cjs');
  if (fs.existsSync(gate)) {
    const g = spawnSync(process.execPath, [gate], { cwd: path.join(here, '..'), stdio: 'inherit' });
    if (g.status !== 0) {
      console.error('[hymn] BUILD FAILED (callback arity)');
      process.exit(1);
    }
  }
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
for (const p of SHOTS.concat(RECTS, [SELFTEST])) {
  if (!fs.existsSync(p)) {
    console.error('[hymn] MISSING capture: ' + path.basename(p));
    if (!keep) killWindow();
    process.exit(1);
  }
}
console.log('[hymn] captures ' + SHOTS.map((p) => path.basename(p) + ' '
  + fs.statSync(p).size + ' B').join(', '));
{
  const st = fs.readFileSync(SELFTEST, 'utf8').trim();
  if (!st.startsWith('PASS')) {
    console.error('[hymn] SELFTEST FAILED:\n' + st);
    if (!keep) killWindow();
    process.exit(1);
  }
  console.log('[hymn] selftest ' + st);
}
{
  const bad = paletteCanary();
  if (bad.length) {
    console.error('[hymn] PALETTE FAILED:\n  ' + bad.join('\n  '));
    if (!keep) killWindow();
    process.exit(1);
  }
  console.log('[hymn] palette canary OK (dark + light fills and ink agree with the shot)');
}

// ---- the palette canary ---------------------------------------------------
//
// WHY A PIXEL GATE AND NOT ANOTHER BEACON LINE. A theme switch can fail in a way no
// amount of model introspection sees: the model and the resolver both hold the new
// palette -- `hymn-rects-light.txt` reports `root=15330030` (0xE9EAEE) and
// `reader=16777215` (white) -- while the PNG comes out with DARK panels and light-theme
// ink, because a fill that never got repainted keeps the previous palette. Measured
// once on 2026-11-12 (hymn-light.png, 121430 B against the usual ~177800). The beacon
// was green through all of it. FOUR PROBES, chosen to be layout-tolerant:
//   * one flat fill outside the cards (the window background)
//   * one flat fill inside the reader card, above the title block
//   * the ink luma of the title band, which must FLIP with the palette
// A point that lands on a glyph or a border is a probe author's error, not a palette
// bug, so each one is checked against BOTH palettes and a wrong-landing probe is
// reported as such instead of as a colour mismatch.
function paletteCanary() {
  const { decodePng } = require(path.join(here, '..', 'tools', 'pngread.cjs'));
  const out = [];
  const lum = (r, g, b) => 0.2126 * r + 0.7152 * g + 0.0722 * b;
  const shots = [
    { file: SHOTS[1], name: 'page(dark)', bg: 0x08090c, panel: 0x121419, inkHi: true },
    { file: SHOTS[3], name: 'light', bg: 0xe9eaee, panel: 0xffffff, inkHi: false },
    // THE DIRECTION NOTHING ELSE COVERS: light -> dark, driven by a real tap on the
    // titlebar sun. Its ink is checked because that is what breaks: on 2026-11-13 the
    // fills below swapped and all 86 text runs kept the light theme's 0x14161C, so the
    // reader body and the brand title were dark on dark.
    { file: SHOTS[5], name: 'back to dark', bg: 0x08090c, panel: 0x121419, inkHi: true },
  ];
  for (const s of shots) {
    let img;
    try { img = decodePng(s.file); } catch (e) {
      out.push(s.name + ': cannot decode ' + path.basename(s.file) + ' (' + e.message + ')');
      continue;
    }
    // The capture is the window at whatever DPR the backend picked; logical points are
    // what the layout is written in, so scale rather than assume 1x.
    const dpr = img.w / 1280;
    const px = (lx, ly) => {
      const x = Math.round(lx * dpr), y = Math.round(ly * dpr);
      const k = (y * img.w + x) * 4;
      return { x, y, hex: ((img.rgba[k] << 16) | (img.rgba[k + 1] << 8) | img.rgba[k + 2]) >>> 0 };
    };
    const hex = (v) => '#' + v.toString(16).padStart(6, '0');
    // (6,6): the window background, inside the rounded caption but outside every card.
    const a = px(6, 6);
    if (a.hex !== s.bg) out.push(s.name + ': window background at 6,6 is ' + hex(a.hex) + ', want ' + hex(s.bg) + ' (stale fill)');
    // (1240,110): inside the reader card, right of the toolbar and above the title. The
    // drawer's absence moves the card's LEFT edge, never its right one, so this point is
    // valid for both palettes and both drawer states.
    const b = px(1240, 110);
    if (b.hex !== s.panel) out.push(s.name + ': reader panel at 1240,110 is ' + hex(b.hex) + ', want ' + hex(s.panel) + ' (stale fill)');
    // The title band: the ink must be bright on dark and dark on light. Scanned rather
    // than sampled because a single probe can land between two glyphs.
    let lo = 255, hi = 0;
    const y0 = Math.round(175 * dpr), y1 = Math.round(203 * dpr);
    for (let y = y0; y < y1; y++) {
      for (let x = Math.round(300 * dpr); x < Math.round(900 * dpr); x++) {
        const k = (y * img.w + x) * 4;
        const l = lum(img.rgba[k], img.rgba[k + 1], img.rgba[k + 2]);
        if (l < lo) lo = l;
        if (l > hi) hi = l;
      }
    }
    if (s.inkHi && hi < 200) out.push(s.name + ': title ink peaks at luma ' + Math.round(hi) + ', want > 200 (light ink lost)');
    if (!s.inkHi && lo > 60) out.push(s.name + ': title ink bottoms at luma ' + Math.round(lo) + ', want < 60 (dark ink lost)');
    // The BRAND band, top left. Scanned separately from the reader title because it is
    // the one text run that never moves, never re-measures and therefore shows a stale
    // ink even when the reader happens to reload. This is the probe that tells
    // "the text layer kept the old palette" apart from "one label is wrong".
    let blo = 255, bhi = 0;
    for (let y = Math.round(8 * dpr); y < Math.round(26 * dpr); y++) {
      for (let x = Math.round(70 * dpr); x < Math.round(230 * dpr); x++) {
        const k = (y * img.w + x) * 4;
        const l = lum(img.rgba[k], img.rgba[k + 1], img.rgba[k + 2]);
        if (l < blo) blo = l;
        if (l > bhi) bhi = l;
      }
    }
    if (s.inkHi && bhi < 200) out.push(s.name + ': brand ink peaks at luma ' + Math.round(bhi) + ', want > 200 (the whole text layer kept the old palette)');
    if (!s.inkHi && blo > 60) out.push(s.name + ': brand ink bottoms at luma ' + Math.round(blo) + ', want < 60 (the whole text layer kept the old palette)');
  }
  return out;
}
if (keep) {
  console.log('[hymn] window left up (--keep)');
} else {
  killWindow();
}

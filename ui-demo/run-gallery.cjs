// run-gallery.cjs -- build and run the multi-page gallery demo the way the
// project now builds demos: `as-aot --air-app <descriptor>`, so the AIR
// application descriptor drives the window (size, title, renderMode,
// <requestedDisplayResolution>high) instead of a hand-written build manifest.
//
// Usage:   node run-gallery.cjs
// Env:     ASC_CC   path to clang (default: clang on PATH)
//          ASC_NO_OPEN=1  kill the window as soon as the verdict is read
//                          (default: leave it open for you to click through)
//          ASC_AIR_DIR    app dir to stage+build (default: air-gallery).
//                         check-dpi.cjs uses it with a `standard`-resolution twin.
//
// Steps:   1) kill a leftover GalleryApp.exe -- on Windows a live window holds the
//             file and the next build would fail with "permission denied"
//          2) delete stale gallery.done / gallery.txt, so a crash earlier in the
//             run can never be mistaken for a pass
//          3) stage-air.cjs: materialize <appDir>/src from seam + kit + demo
//             (--air-app compiles exactly `<appDir>/src` and nothing else)
//          4) build with `--air-app <appDir>/app.xml` (the generated manifest
//             carries every -I/-L/-l, so none are spelled out here)
//          5) launch the exe DETACHED, cwd = this directory
//          6) wait for gallery.done, print the tour, MEASURE the screenshots and
//             exit 0/1 on the verdict
//
// NOTE ON RETRIES: there is no retry any more. This runner used to retry the build
// because compiler-gaps.md G11 read as "an identical build of an identical source can
// fail in the generated C". G11 is closed as NOT a gap: the measurement was taken
// across an edit to the compiler's own sources, by another session on this machine.
// So the condition is now REPORTED (compilerTree) instead of retried -- retrying hid
// the cause and would also disguise a real defect as "succeeded on attempt 2".
'use strict';

const path = require('path');
const fs = require('fs');
const { spawnSync, spawn } = require('child_process');
// Shared with build-and-run.cjs (the login demo): the descriptor reader, the
// window killer, the result-file poller and the screenshot measurement. Two
// copies of "measure the PNG" is exactly the drift this workspace measures
// instead of trusting.
const { descriptorWindow, killImage, waitForFile, checkShot, compilerTree } = require('./air-run.cjs');

const here = __dirname;
const compilerDir = path.resolve(here, '..', '..', 'as3compiler');
const clang = process.env.ASC_CC || 'clang';
const OUT = 'gallery';
const EXE = 'GalleryApp.exe';
const appDirName = process.env.ASC_AIR_DIR || 'air-gallery';
const appDir = path.join(here, appDirName);
// EVERYTHING the app writes (gallery.txt, gallery.done, the page PNGs) is a
// RELATIVE path, so it lands in the process's cwd -- and that is deliberately the
// app dir, not the runner's own: two app dirs (the `high` demo and check-dpi.cjs's
// `standard` twin) must never overwrite each other's screenshots.
const outDir = appDir;
const descriptor = path.join(appDir, 'app.xml');

function killWindow() {
  killImage(EXE);
}

// The window's logical size and requested resolution come from the descriptor, and
// the tour's hand-computed rects are derived from it, so it is read rather than
// restated here -- if the descriptor changes, this runner must notice.
function descriptorSize() {
  const s = descriptorWindow(descriptor);
  if (!s) {
    console.error('[gallery] ' + descriptor + ' has no <width>/<height>');
    process.exit(2);
  }
  return s;
}

killWindow();
for (const f of [OUT + '.done', OUT + '.txt']) {
  const p = path.join(outDir, f);
  if (fs.existsSync(p)) fs.unlinkSync(p);
}

const size = descriptorSize();
console.log('[gallery] descriptor ' + appDirName + '/app.xml: window ' + size.w + 'x' + size.h
  + ', requestedDisplayResolution=' + size.resolution);

// ---- 3) stage -------------------------------------------------------------
{
  const r = spawnSync(process.execPath, ['stage-air.cjs', appDirName], { cwd: here, stdio: 'inherit' });
  if (r.status !== 0) {
    console.error('[gallery] STAGING FAILED (exit ' + r.status + ')');
    process.exit(1);
  }
}

// ---- 4) build -------------------------------------------------------------
const manifestPath = path.join(appDir, 'GalleryApp.build.json');
if (fs.existsSync(manifestPath)) fs.unlinkSync(manifestPath);

const args = [
  'src/index.ts',
  // Absolute: the AOT runs with cwd = the compiler repo, so a relative descriptor
  // path would be resolved against THAT.
  '--air-app', descriptor,
  // --main-class is NOT optional here even though `--air-app` can infer one: the
  // inference matches any file whose name ENDS WITH `Main.as`, so `GalleryMain.as`
  // makes it guess `demo.Main` (which does not exist) and the build dies in the
  // reachability closure. Naming the document class is also what the AIR model
  // does -- the descriptor does not carry it, the compiler is told.
  '--main-class', 'demo.GalleryMain',
  // --all-sources: REMOVED (阶段二百四十九). `--air-app`'s default face is the
  // class-reference closure from the document class, and that closure used to not
  // expand a class first discovered by a file carrying free functions
  // (compiler-gaps.md G13). Every widget in this toolkit is reached through a
  // lowercase factory FREE FUNCTION (`chip.as` -> ChipNode), so the closure kept
  // the node classes but dropped their superclass `Control` and the per-kind widget
  // objects their constructors register -- the build then stopped with
  // `unknown superclass 'Control' of 'asaot_ui_AvatarNode'`. G13 is fixed: the
  // plain closure keeps 94/97 and builds this app unchanged. If that error ever
  // comes back, the closure has regressed -- fix it there, do NOT re-add
  // --all-sources (it compiles all of src/, the pre-阶段一百二十四 face, and would
  // mask the defect again).
  '--cc', clang,
  // 阶段二百五十: the toolkit and the layout seam are compiled where they LIVE
  // (../seam, ../kit) instead of as a staged copy under src/asaot. stage-air.cjs
  // now stages only the demo's own sources; these two flags are what replaces the
  // 91-file copy every demo used to carry.
  '--as-class-path', path.join(here, '..', 'seam'),
  '--as-class-path', path.join(here, '..', 'kit')
];

console.log('[gallery] building GalleryApp with `--air-app ' + appDirName + '/app.xml`');
// The compiler's own tree state is part of the measurement (compiler-gaps.md G11):
// the one condition under which "the same source built twice" can emit different C
// is a COMPILER that changed in between, and another session on this machine does
// edit it. Printed every run, so a confusing failure can be read correctly.
{
  const tree = compilerTree(compilerDir);
  console.log('[gallery] compiler tree: HEAD ' + tree.head
    + ', tracked modifications: ' + (tree.tracked.length ? tree.tracked.join(' | ') : '(none)')
    + ', untracked: ' + (tree.untracked.length ? tree.untracked.join(' | ') : '(none)'));
  if (tree.tracked.length) {
    console.log('[gallery] NOTE: the compiler source is MODIFIED right now -- if the build fails in\n'
      + '          generated code that points at names you never wrote (G11: `_time` / `___restrict` /\n'
      + '          `socket`), that tree state is the cause, not this demo. Wait for the other session to\n'
      + '          commit, or check out a clean tree, then re-run. Do not "just try again".');
  }
}
{
  const r = spawnSync(process.execPath, args, { cwd: compilerDir, stdio: 'inherit' });
  if (r.status !== 0) {
    console.error('[gallery] BUILD FAILED (exit ' + r.status + ')');
    process.exit(1);
  }
}

// The descriptor's <requestedDisplayResolution> is only real if it reached the
// build, and the generated manifest is where that is visible (ASC_DISPLAY_HIGH).
// Asserting it here keeps the flag and the measured pixels tied to one source.
let highDefine = false;
if (fs.existsSync(manifestPath)) {
  const man = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  const defines = [].concat(man.defines || []);
  highDefine = defines.some((d) => /^ASC_DISPLAY_HIGH=1$/.test(String(d)));
  console.log('[gallery] generated manifest ' + path.basename(manifestPath)
    + ': ASC_DISPLAY_HIGH ' + (highDefine ? 'present' : 'ABSENT'));
} else {
  console.error('[gallery] generated manifest missing: ' + manifestPath);
  process.exit(3);
}

const exe = path.join(appDir, EXE);
if (!fs.existsSync(exe)) {
  console.error('[gallery] expected exe not found: ' + exe);
  process.exit(3);
}

// ---- 5) run ---------------------------------------------------------------
console.log('[gallery] launching ' + exe + ' (cwd ' + path.relative(here, outDir).split(path.sep).join('/')
  + ', detached)' + ', so the tour writes its evidence there');
const child = spawn(exe, [], { cwd: outDir, detached: true, stdio: 'inherit' });
child.unref();

const donePath = path.join(outDir, OUT + '.done');
const done = waitForFile(donePath, 60000);

const tourPath = path.join(outDir, OUT + '.txt');
if (fs.existsSync(tourPath)) {
  console.log('---- ' + OUT + '.txt ----');
  console.log(fs.readFileSync(tourPath, 'utf8'));
}

if (done === null) {
  console.error('[gallery] TIMEOUT: ' + OUT + '.done was never written -- the tour did not finish.');
  console.error('[gallery] the window is still up; look at it, then run:  taskkill /F /IM ' + EXE);
  process.exit(1);
}

// ---- 6) measure the screenshots (one per page, six pages) -----------------
// WHAT THIS PROVES: <requestedDisplayResolution>high makes Stage.render allocate
// its surface in PHYSICAL pixels and scale the canvas to match, so the PNG of a
// 700x560 stage comes out 1050x840 on a 150% display while the AS3 code keeps
// working in logical coordinates. A 1x PNG here would mean the descriptor never
// reached the build -- a blurry window that every rect assertion in the tour
// would still call perfect. That is why this is measured, not assumed.
const shots = [];
for (let k = 0; k < 6; k++) {
  const f = path.join(outDir, OUT + '-page' + k + '.png');
  const c = checkShot(f, size, OUT + '-page' + k + '.png');
  shots.push({ name: OUT + '-page' + k + '.png', bytes: fs.existsSync(f) ? fs.statSync(f).size : 0, size: c.size, scale: c.scale, problems: c.problems });
}
console.log('---- screenshots ----');
for (const s of shots) console.log('  ' + s.name + '  ' + (s.size ? s.size.w + 'x' + s.size.h : '?') + '  ' + s.bytes + ' B');
if (shots.length === 0) console.log('  (none written)');

const problems = [];
if (shots.length !== 6) problems.push('expected 6 screenshots, got ' + shots.length);
for (const s of shots) {
  for (const p of s.problems) problems.push(p);
  if (shots[0].size && s.size && (s.size.w !== shots[0].size.w || s.size.h !== shots[0].size.h)) problems.push(s.name + ' differs in size from the other pages');
}
const scale = shots.length && shots[0].size ? shots[0].scale : 0;
console.log('[gallery] logical ' + size.w + 'x' + size.h + ' -> PNG '
  + (shots.length && shots[0].size ? shots[0].size.w + 'x' + shots[0].size.h : '?')
  + ' (device scale ' + scale + ')');

if (size.resolution === 'high' && !highDefine) problems.push('descriptor says requestedDisplayResolution=high but ASC_DISPLAY_HIGH is not in the generated manifest');
if (size.resolution !== 'high' && highDefine) problems.push('descriptor does not say high but ASC_DISPLAY_HIGH is in the generated manifest');

console.log('---- verdict ----');
console.log(done);
if (problems.length) {
  console.error('[gallery] screenshot/hidpi problems:');
  for (const p of problems) console.error('  ' + p);
}
const pass = done.indexOf('PASS') === 0 && problems.length === 0;
if (process.env.ASC_NO_OPEN === '1') {
  killWindow();
} else {
  console.log('[gallery] the window is open -- click the tabs. Close it when done, or:  taskkill /F /IM ' + EXE);
}
console.log(pass ? '[gallery] RESULT: PASS' : '[gallery] RESULT: FAIL');
process.exit(pass ? 0 : 1);
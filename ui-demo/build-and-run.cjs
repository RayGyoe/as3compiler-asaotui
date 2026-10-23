// build-and-run.cjs -- build and run the asaot.ui LOGIN demo the way this project
// builds demos: `as-aot --air-app <descriptor>`, so the AIR application descriptor
// owns the window (size, title, renderMode, <requestedDisplayResolution>high) and
// the hand-written build manifest is gone.
//
// Usage:   node build-and-run.cjs
// Env:     ASC_CC   path to clang (default: clang on PATH)
//          ASC_NO_OPEN=1  kill the window as soon as the verdict is read
//                         (default: leave it open for you to click through)
//
// Steps:   1) kill a leftover UiDemo.exe -- on Windows a live window holds the file
//             and the next build would fail with "permission denied"
//          2) delete stale uidemo.done / uidemo.txt / uidemo-shot.png, so a crash
//             earlier in the run can never be mistaken for a pass
//          3) stage-air.cjs: materialize air-uidemo/src from seam + kit + demo
//             (--air-app compiles exactly `<appDir>/src` and nothing else)
//          4) build with `--air-app air-uidemo/app.xml` (the generated manifest
//             carries every -I/-L/-l, so none are spelled out here)
//          5) launch the exe DETACHED, cwd = this directory, so the demo writes its
//             evidence and screenshots next to the sources
//          6) wait for uidemo.done, print the rects, MEASURE the screenshot and
//             exit 0/1 on the verdict
//
// NOTE ON RETRIES: there is no retry any more. This runner used to retry the build
// because compiler-gaps.md G11 read as "an identical build of an identical source can
// fail in the generated C". G11 is closed as NOT a gap: the measurement was taken
// across an edit to the compiler's own sources, by another session on this machine.
// The tree state is REPORTED instead (compilerTree) -- retrying hid the cause and
// would also disguise a real defect as "succeeded on attempt 2".
//
// NOTE ON --all-sources: REMOVED (阶段二百四十九). It used to be required, because
// `--air-app`'s default face is the class-reference closure from the document
// class, and that closure did not expand a class first discovered by a file
// carrying free functions (compiler-gaps.md G13) -- and every widget in this
// toolkit is reached through a lowercase factory FREE FUNCTION (`chip.as` ->
// ChipNode). G13 is fixed: the plain closure now keeps 94/97 and builds this app
// unchanged, so the escape hatch is no longer needed here. If a build starts
// failing with `unknown superclass 'Control' of 'asaot_ui_…'`, the closure has
// regressed -- fix it there, do NOT paper over it by re-adding --all-sources.
'use strict';

const path = require('path');
const fs = require('fs');
const { spawnSync, spawn } = require('child_process');
const { descriptorWindow, killImage, waitForFile, checkShot, compilerTree } = require('./air-run.cjs');

const here = __dirname;
const compilerDir = path.resolve(here, '..', '..', 'as3compiler');
const clang = process.env.ASC_CC || 'clang';
const OUT = 'uidemo';
const EXE = 'UiDemo.exe';
const appDirName = 'air-uidemo';
const appDir = path.join(here, appDirName);
const descriptor = path.join(appDir, 'app.xml');

killImage(EXE);
const evidence = [OUT + '.done', OUT + '.txt', OUT + '-shot.png'];
for (const f of evidence) {
  const p = path.join(here, f);
  if (fs.existsSync(p)) fs.unlinkSync(p);
}

const size = descriptorWindow(descriptor);
if (!size) {
  console.error('[uidemo] ' + descriptor + ' has no <width>/<height>');
  process.exit(2);
}
console.log('[uidemo] descriptor ' + appDirName + '/app.xml: window ' + size.w + 'x' + size.h
  + ', requestedDisplayResolution=' + size.resolution);

// ---- 3) stage -------------------------------------------------------------
{
  const r = spawnSync(process.execPath, ['stage-air.cjs', appDirName], { cwd: here, stdio: 'inherit' });
  if (r.status !== 0) {
    console.error('[uidemo] STAGING FAILED (exit ' + r.status + ')');
    process.exit(1);
  }
}

// ---- 4) build -------------------------------------------------------------
const manifestPath = path.join(appDir, 'UiDemo.build.json');
if (fs.existsSync(manifestPath)) fs.unlinkSync(manifestPath);

const args = [
  'src/index.ts',
  // Absolute: the AOT runs with cwd = the compiler repo, so a relative descriptor
  // path would be resolved against THAT.
  '--air-app', descriptor,
  // --main-class cannot be left to inference: it matches any file whose name ENDS
  // WITH `Main.as`, so `UiDemoMain.as` makes it guess `demo.Main` (which does not
  // exist) and the build dies in the reachability closure. Naming the document
  // class is also what the AIR model does.
  '--main-class', 'demo.UiDemoMain',
  '--cc', clang,
  // 阶段二百五十: the toolkit and the layout seam are compiled where they LIVE
  // (../seam, ../kit) instead of as a staged copy under src/asaot. stage-air.cjs
  // now stages only the demo's own sources; these two flags are what replaces the
  // 91-file copy every demo used to carry.
  '--as-class-path', path.join(here, '..', 'seam'),
  '--as-class-path', path.join(here, '..', 'kit')
];

console.log('[uidemo] building UiDemo with `--air-app ' + appDirName + '/app.xml`');
// The compiler's own tree state is part of the measurement (compiler-gaps.md G11):
// the one condition under which "the same source built twice" can emit different C
// is a COMPILER that changed in between, and another session on this machine does
// edit it. Printed every run, so a confusing failure can be read correctly.
{
  const tree = compilerTree(compilerDir);
  console.log('[uidemo] compiler tree: HEAD ' + tree.head
    + ', tracked modifications: ' + (tree.tracked.length ? tree.tracked.join(' | ') : '(none)')
    + ', untracked: ' + (tree.untracked.length ? tree.untracked.join(' | ') : '(none)'));
  if (tree.tracked.length) {
    console.log('[uidemo] NOTE: the compiler source is MODIFIED right now -- if the build fails in\n'
      + '        generated code that points at names you never wrote (G11: `_time` / `___restrict` /\n'
      + '        `socket`), that tree state is the cause, not this demo. Wait for the other session to\n'
      + '        commit, or check out a clean tree, then re-run. Do not "just try again".');
  }
}
{
  const r = spawnSync(process.execPath, args, { cwd: compilerDir, stdio: 'inherit' });
  if (r.status !== 0) {
    console.error('[uidemo] BUILD FAILED (exit ' + r.status + ')');
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
  console.log('[uidemo] generated manifest ' + path.basename(manifestPath)
    + ': ASC_DISPLAY_HIGH ' + (highDefine ? 'present' : 'ABSENT'));
} else {
  console.error('[uidemo] generated manifest missing: ' + manifestPath);
  process.exit(3);
}

const exe = path.join(appDir, EXE);
if (!fs.existsSync(exe)) {
  console.error('[uidemo] expected exe not found: ' + exe);
  process.exit(3);
}

// ---- 5) run ---------------------------------------------------------------
console.log('[uidemo] launching ' + exe + ' (detached)');
const child = spawn(exe, [], { cwd: here, detached: true, stdio: 'inherit' });
child.unref();

const done = waitForFile(path.join(here, OUT + '.done'), 60000);
const reportPath = path.join(here, OUT + '.txt');
if (fs.existsSync(reportPath)) {
  console.log('---- ' + OUT + '.txt ----');
  console.log(fs.readFileSync(reportPath, 'utf8'));
}
if (done === null) {
  console.error('[uidemo] TIMEOUT: ' + OUT + '.done was never written -- the demo did not settle.');
  console.error('[uidemo] the window is still up; look at it, then run:  taskkill /F /IM ' + EXE);
  process.exit(1);
}

// ---- 6) measure the screenshot -------------------------------------------
// WHAT THIS PROVES: <requestedDisplayResolution>high makes Stage.render allocate its
// surface in PHYSICAL pixels and scale the canvas to match, so the PNG of a 500x375
// stage comes out 750x563 on a 150% display while the AS3 code keeps working in
// logical coordinates. A 1x PNG here would mean the descriptor never reached the
// build -- a blurry window that every rect assertion above would still call
// perfect. That is why this is measured, not assumed. check-dpi.cjs runs the same
// demo against a `standard` descriptor to show the difference is CAUSED by this
// one line (shared measurement: air-run.cjs::checkShot).
const shot = checkShot(path.join(here, OUT + '-shot.png'), size, OUT + '-shot.png');
console.log('---- screenshot ----');
console.log('  ' + OUT + '-shot.png  ' + (shot.size ? shot.size.w + 'x' + shot.size.h : '?') + '  '
  + (fs.existsSync(path.join(here, OUT + '-shot.png')) ? fs.statSync(path.join(here, OUT + '-shot.png')).size + ' B' : ''));
if (shot.size) console.log('[uidemo] logical ' + size.w + 'x' + size.h + ' -> PNG '
  + shot.size.w + 'x' + shot.size.h + ' (device scale ' + shot.scale + ')');

const problems = shot.problems.slice();
if (done !== 'PASS') problems.push('the demo reported ' + done);
if (size.resolution === 'high' && !highDefine) problems.push('descriptor says requestedDisplayResolution=high but ASC_DISPLAY_HIGH is not in the generated manifest');
if (size.resolution !== 'high' && highDefine) problems.push('descriptor does not say high but ASC_DISPLAY_HIGH is in the generated manifest');

console.log('---- verdict ----');
if (problems.length === 0) {
  console.log('PASS');
} else {
  for (const p of problems) console.error('FAIL: ' + p);
}

// The window can keep the user from re-running (Windows file lock) and from a
// scripted acceptance run, so ASC_NO_OPEN closes it the moment the verdict is known.
if (process.env.ASC_NO_OPEN === '1') {
  killImage(EXE);
  console.log('[uidemo] ASC_NO_OPEN=1: window closed');
} else if (problems.length === 0) {
  console.log('[uidemo] the window is open; close it to end the process.');
}
console.log('[uidemo] RESULT: ' + (problems.length === 0 ? 'PASS' : 'FAIL'));
process.exit(problems.length === 0 ? 0 : 1);
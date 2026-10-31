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
//          ASC_APP_XML    descriptor name inside that dir (default: app.xml).
//                         build.sh's `--gpu` derives `app.<mode>.xml` instead of
//                         editing the tracked descriptor -- see build.sh.
//          ASC_GPU_BACKEND  auto|d3d12|gl: which native API composites the window.
//                         Passed straight to `--gpu-backend`; the descriptor's
//                         <renderMode> alone only says "a GPU window, please".
//
// Steps:   1) kill a leftover GalleryApp.exe -- on Windows a live window holds the
//             file and the next build would fail with "permission denied"
//          2) delete stale gallery.done / gallery.txt, so a crash earlier in the
//             run can never be mistaken for a pass
//          3) stage-air.cjs: materialize <appDir>/src from seam + kit + demo
//             (--air-app compiles exactly `<appDir>/src` and nothing else)
//          4) build with `--air-app <appDir>/<descriptor>` (the generated manifest
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
// Shared with check-dpi.cjs (the descriptor A/B): the descriptor reader, the
// window killer, the result-file poller and the screenshot measurement. Two
// copies of "measure the PNG" is exactly the drift this workspace measures
// instead of trusting.
const { descriptorWindow, killImage, waitForFile, checkShot, compilerTree } = require('./air-run.cjs');

const here = __dirname;
const compilerDir = path.resolve(here, '..', '..', 'as3compiler');
const clang = process.env.ASC_CC || 'clang';
const OUT = 'gallery';
// The AOT appends `.exe` only on Windows; on macOS/Linux the artifact is the bare
// name. Keying the runner on the Windows spelling made every macOS run stop at
// "expected exe not found" -- a red gate about a file-name suffix, not about the
// tour. (Same class of defect as tools/probe.cjs's `.exe`-only discovery.)
const EXE = process.platform === 'win32' ? 'GalleryApp.exe' : 'GalleryApp';
// The tour's screenshot count: demo/DocsMain.as renders one PNG per entry in its
// `stops` list (start / box / button / image / select / table / tabs / dialog).
// Kept here as a number as well, so a page that silently stops being rendered is a
// red gate rather than a folder with one file fewer in it.
const PAGES = 8;
const appDirName = process.env.ASC_AIR_DIR || 'air-gallery';
const appDir = path.join(here, appDirName);
// EVERYTHING the app writes (gallery.txt, gallery.done, the page PNGs) is a
// RELATIVE path, so it lands in the process's cwd -- and that is deliberately the
// app dir, not the runner's own: two app dirs (the `high` demo and check-dpi.cjs's
// `standard` twin) must never overwrite each other's screenshots.
const outDir = appDir;
// The window's own stdout/stderr. NOT inherited: this program exits while the window
// is still up, and a grandchild holding the parent's pipe makes every `spawnSync`
// caller (tools/gates.cjs) block until the pipe closes -- which is what turned a 22s
// tour into two gates reported at the full 420s ceiling.
const RUN_LOG = path.join(outDir, OUT + '.run.log');
// Normally `<appDir>/app.xml`. build.sh's `--gpu <mode>` generates
// `app.<mode>.xml` beside it instead of editing the tracked descriptor, because
// check-dpi.cjs requires air-gallery/app.xml and its `standard` twin to differ in
// exactly one line -- a hand-flipped <renderMode> would make the DPI A/B
// two-variable and turn that gate red for a reason unrelated to the experiment.
//
// The two options come in as ARGUMENTS, and are also readable from the environment:
// arguments are what build.sh passes (a shell -> Windows-binary boundary in this
// workspace drops inline `VAR=value` prefixes -- measured: the same command typed by
// hand works, the one run from inside build.sh arrives with both variables empty),
// while `ASC_*` stays supported for callers that drive this runner by env.
const argv = process.argv.slice(2);
let appXmlArg = null;
let backendArg = null;
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === '--app-xml' || a === '--gpu-backend') {
    const v = argv[++i];
    if (!v) {
      console.error('[gallery] ' + a + ' needs a value');
      process.exit(2);
    }
    if (a === '--app-xml') appXmlArg = v; else backendArg = v;
  } else {
    console.error('[gallery] unknown argument: ' + a
      + '\n          usage: run-gallery.cjs [--app-xml <name>] [--gpu-backend <auto|d3d12|gl>]');
    process.exit(2);
  }
}
const descriptorName = appXmlArg || process.env.ASC_APP_XML || 'app.xml';
const gpuBackend = String(backendArg || process.env.ASC_GPU_BACKEND || '').trim().toLowerCase();
const descriptor = path.join(appDir, descriptorName);
if (!fs.existsSync(descriptor)) {
  console.error('[gallery] descriptor not found: ' + descriptor
    + (appXmlArg || process.env.ASC_APP_XML ? ' (named on the command line / by ASC_APP_XML)' : '')
    + '\n          build.sh generates it; run `./build.sh aot --gpu <mode>` from air-gallery/');
  process.exit(2);
}

function killWindow() {
  // BY PID FIRST. The window is the one WE launched, so its pid is exact; the image
  // sweep below only exists for a leftover from an earlier, unrelated run (and for
  // the early call that happens before anything is launched).
  if (launchedPid) {
    for (const target of [-launchedPid, launchedPid]) {
      try { process.kill(target, 'SIGKILL'); } catch (e) { /* already gone / win32 */ }
    }
  }
  killImage(EXE);
}
let launchedPid = 0;

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
console.log('[gallery] descriptor ' + appDirName + '/' + descriptorName + ': window ' + size.w + 'x' + size.h
  + ', requestedDisplayResolution=' + size.resolution + ', renderMode=' + size.renderMode
  + (gpuBackend && gpuBackend !== 'auto' ? ', gpu-backend=' + gpuBackend : ''));

// ---- 3) stage -------------------------------------------------------------
{
  const r = spawnSync(process.execPath, ['stage-air.cjs', appDirName], { cwd: here, stdio: 'inherit', timeout: 120000 });
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
  // inference matches any file whose name ENDS WITH `Main.as`, so `DocsMain.as`
  // makes it guess `demo.Main` (which does not exist) and the build dies in the
  // reachability closure. Naming the document class is also what the AIR model
  // does -- the descriptor does not carry it, the compiler is told.
  '--main-class', 'demo.DocsMain',
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
// Which native API composites the window (air-app.ts GPU_BACKENDS). It is NOT in
// the descriptor: AIR's schema has no slot for it (measured: `adt` refuses
// <windows><gpuBackend>), so the choice travels as a flag and lands in the
// generated manifest. `auto` is the platform default, i.e. saying nothing.
if (gpuBackend && gpuBackend !== 'auto') args.push('--gpu-backend', gpuBackend);

console.log('[gallery] building GalleryApp with `--air-app ' + appDirName + '/' + descriptorName + '`');
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
  // BOUNDED: a build that never returns would leave the window unlaunched and this
  // process alive for ever (measured: an as-aot run on a tree that another session was
  // editing hung instead of failing).
  const r = spawnSync(process.execPath, args, {
    cwd: compilerDir, stdio: 'inherit',
    timeout: Number(process.env.ASC_BUILD_TIMEOUT_MS || 300000), killSignal: 'SIGKILL',
  });
  if (r.status === null && r.signal) {
    console.error('[gallery] BUILD TIMED OUT -- the compiler never returned (raise ASC_BUILD_TIMEOUT_MS if it is just slow)');
    process.exit(1);
  }
  if (r.status !== 0) {
    console.error('[gallery] BUILD FAILED (exit ' + r.status + ')');
    process.exit(1);
  }
}

// The descriptor's <requestedDisplayResolution> is only real if it reached the
// build, and the generated manifest is where that is visible (ASC_DISPLAY_HIGH).
// Asserting it here keeps the flag and the measured pixels tied to one source.
let highDefine = false;
const manifestDefines = [];
if (fs.existsSync(manifestPath)) {
  const man = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  const defines = [].concat(man.defines || []);
  for (const d of defines) manifestDefines.push(String(d));
  highDefine = manifestDefines.some((d) => /^ASC_DISPLAY_HIGH=1$/.test(d));
  console.log('[gallery] generated manifest ' + path.basename(manifestPath)
    + ': ASC_DISPLAY_HIGH ' + (highDefine ? 'present' : 'ABSENT')
    + ', ASC_RENDER_WINGPU ' + (manifestDefines.includes('ASC_RENDER_WINGPU=1') ? 'present' : 'ABSENT'));
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
  + ', detached, stdout -> ' + path.basename(RUN_LOG) + ')' + ', so the tour writes its evidence there');
// `spawn` takes an FD, not a path (`spawnSync` would take a path): open, hand over,
// close on our side so the window is the only holder.
const runFd = fs.openSync(RUN_LOG, 'w');
const child = spawn(exe, [], { cwd: outDir, detached: true, stdio: ['ignore', runFd, runFd] });
fs.closeSync(runFd);
launchedPid = child.pid;
child.unref();

const donePath = path.join(outDir, OUT + '.done');
// 60s, because the tour is 8 stops of real clicks on a real window; anything longer is
// a hang, not slowness. `ASC_TOUR_TIMEOUT_MS` shortens it when only the STARTUP is
// being checked (a smoke run: does the window come up and paint at all?).
const done = waitForFile(donePath, Number(process.env.ASC_TOUR_TIMEOUT_MS || 60000));

const tourPath = path.join(outDir, OUT + '.txt');
if (fs.existsSync(tourPath)) {
  console.log('---- ' + OUT + '.txt ----');
  console.log(fs.readFileSync(tourPath, 'utf8'));
}

if (done === null) {
  console.error('[gallery] TIMEOUT: ' + OUT + '.done was never written -- the tour did not finish.');
  // A FAILED run kills its window. Leaving it up is what "the test just sits there"
  // looks like from the outside, and inside a gate run it is a leftover that steals
  // focus from the next probe. `ASC_KEEP_WINDOW=1` is the deliberate exception (you
  // want to look at the half-finished UI).
  if (process.env.ASC_KEEP_WINDOW === '1') {
    console.error('[gallery] the window is left up on purpose (ASC_KEEP_WINDOW=1).');
  } else {
    killWindow();
    console.error('[gallery] the window was killed (ASC_KEEP_WINDOW=1 to keep it).');
  }
  process.exit(1);
}

// ---- 6) measure the screenshots (one per page, PAGES of them) ---------------
// WHAT THIS PROVES: <requestedDisplayResolution>high makes Stage.render allocate
// its surface in PHYSICAL pixels and scale the canvas to match, so the PNG of a
// 700x560 stage comes out 1050x840 on a 150% display while the AS3 code keeps
// working in logical coordinates. A 1x PNG here would mean the descriptor never
// reached the build -- a blurry window that every rect assertion in the tour
// would still call perfect. That is why this is measured, not assumed.
const shots = [];
// STALE STOPS ARE PART OF THE GATE, NOT CLUTTER. The tour used to have 12 stops;
// when PAGES dropped to 8 the four extra PNGs stayed behind, still tracked in git,
// and a reader takes a file named `gallery-page8.png` for current evidence -- it was
// a 1.5x frame from the twelve-stop layout. `shots.length !== PAGES` cannot see
// them, because it counts what THIS run wrote. So the runner owns the naming: any
// `gallery-page<N>.png` at or beyond PAGES in the output dir is deleted and named.
for (const f of fs.readdirSync(outDir)) {
  const m = /^gallery-page(\d+)\.png$/.exec(f);
  if (m === null) continue;
  if (parseInt(m[1], 10) < PAGES) continue;
  fs.unlinkSync(path.join(outDir, f));
  console.log('[gallery] removed stale ' + f + ' (the tour has ' + PAGES + ' stops)');
}
for (let k = 0; k < PAGES; k++) {
  const f = path.join(outDir, OUT + '-page' + k + '.png');
  const c = checkShot(f, size, OUT + '-page' + k + '.png');
  shots.push({ name: OUT + '-page' + k + '.png', bytes: fs.existsSync(f) ? fs.statSync(f).size : 0, size: c.size, scale: c.scale, problems: c.problems });
}
console.log('---- screenshots ----');
for (const s of shots) console.log('  ' + s.name + '  ' + (s.size ? s.size.w + 'x' + s.size.h : '?') + '  ' + s.bytes + ' B');
if (shots.length === 0) console.log('  (none written)');

const problems = [];
// ---- the window's composition mode reached the build -----------------------
// Same reason as ASC_DISPLAY_HIGH below: a <renderMode> that never made it into
// the manifest produces a window that renders IDENTICALLY to the software one, so
// every rect assertion in the tour still passes and the flag looks honoured while
// changing nothing (§2.5). The manifest is where the choice is observable.
{
  const gpuWindow = size.renderMode === 'direct' || size.renderMode === 'gpu';
  const has = (d) => manifestDefines.includes(d);
  const wantBackend = gpuBackend === 'gl' ? 'ASC_RENDER_GL=1'
    : (gpuBackend === 'd3d12' || process.platform === 'win32') ? 'ASC_RENDER_D3D=1'
    : 'ASC_RENDER_METAL=1';
  if (gpuWindow && !has('ASC_RENDER_WINGPU=1')) {
    problems.push('descriptor says <renderMode>' + size.renderMode + '</renderMode> but the manifest has no ASC_RENDER_WINGPU=1: the build composes on the CPU');
  }
  if (gpuWindow && !has(wantBackend)) {
    problems.push('a GPU window is requested but the manifest has no ' + wantBackend
      + ' (gpu-backend "' + (gpuBackend || 'auto') + '" reached nothing)');
  }
  if (!gpuWindow && has('ASC_RENDER_WINGPU=1')) {
    problems.push('descriptor says <renderMode>' + size.renderMode + '</renderMode> but the manifest carries ASC_RENDER_WINGPU=1');
  }
}
if (shots.length !== PAGES) problems.push('expected ' + PAGES + ' screenshots, got ' + shots.length);
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
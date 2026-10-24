// tools/air-sweep.cjs -- run the docs app on the REFERENCE runtime (adl) over every
// page, with every popup opened, and fail on any runtime error it reports.
//
// WHY THIS GATE EXISTS (it is the only one that measures AIR at run time)
// ----------------------------------------------------------------------
// Our AOT is deliberately MORE FORGIVING than AIR in a few places, and every user
// report for two days has been a bug of exactly that shape:
//
//   * `toast({ tone: "info" })` -- our build threw, the frame guard swallowed it, the
//     page still rendered, and 41 screenshots of a render-only sweep looked fine;
//   * `onChange()` called with no argument -- #1063 on AVM2 (both runtimes), handler
//     never runs, only a console line;
//   * `setChildIndex(child, index)` with `index >= numChildren` -- **AIR throws
//     RangeError #2006 and aborts the frame; our runtime CLAMPS and carries on**
//     (see asaotui/compiler-gaps.md G24). So the select / combobox / datePicker pages
//     threw once per frame the moment a dropdown opened, and no AOT probe could see
//     it: a clamped index happens to be the right place for the last child, so the
//     picture was identical while the reference runtime was throwing.
//
// The AOT suite cannot close that class of difference by construction. This gate
// closes it the other way round: run the real runtime, over the whole catalog, and
// treat any error it reports as a failure of THIS workspace.
//
// WHAT "OPENING EVERY POPUP" IS FOR
// ---------------------------------
// The demos start with their dropdowns shut (`select({ open: m.bool("sel.open", false) })`).
// AIR cannot be scripted to click, so a page-by-page walk only ever sees the CLOSED
// state -- the state that works. `DocsAir` therefore flips every demo state key whose
// popup it can open (`m.bool("<x>.open")`), which is exactly the model write the docs
// page tells the reader to do ("open: true -- the boolean is the model's"). The key
// list is DERIVED FROM THE DEMO SOURCES here and passed in the driver file, so a new
// openable demo is covered without touching this tool.
//
// THE LOG IS A FILE, NOT STDOUT: `adl.exe` on Windows is a GUI-subsystem binary, so a
// parent that spawns it with pipes receives an empty stream while the window is up and
// working (measured). `ui-demo/demo/DocsAir.as` writes `air-trace.txt` instead, and
// captures errors with `loaderInfo.uncaughtErrorEvents` -- the errors AIR would
// otherwise print and forget.
//
// PASS CRITERIA (all of them; a sweep that dies early must never look green)
//   START present; every catalog page visited exactly once and IN ORDER;
//   `SWEEP DONE <n>` with n == the catalog size; `OPENED <k>` with k == the derived
//   popup-key count (0 means the open step silently stopped happening, which would
//   make this whole gate blind); `END errors=0`; and zero `ERROR ` lines.
//   PLUS the pointer drill: one `ROLL` line per page, `errors=0` on every one of them,
//   no `ROLLFAIL`, and at least ROLL_FLOOR nodes destroyed overall -- the drill has to
//   have torn something down, or it proves nothing about a torn-down node.
//
// AND A POINTER. AIR cannot be scripted to click, so until 2026-10-24 the sweep had
// no pointer at all -- and every pointer-driven bug slipped past it. The one that
// reached a user's screen was `TypeError #1009` out of `UiNode.setHover`: `mouseOut`
// is delivered ONE BEAT AFTER the frame that removed the node, so a listener left
// behind by a torn-down node ran into nulled fields, once per torn-down node, on the
// accordion / dialog / drawer / menu pages. `DocsAir` now hovers every leaf of the
// page it is about to leave and delivers the roll-out one tick after the switch; the
// `ROLL` line reports how many were captured and how many had really died.
//
// USAGE (from asaotui/):      node tools/air-sweep.cjs [--sdk <AIR SDK root>] [--keep-open]
// Env: AIRSDK_HOME (SDK root), AIR_SWEEP_TIMEOUT (seconds, default 240).
// Exit: 0 all criteria met; 1 a criterion failed; 3 no AIR SDK on this box (nothing
// measured -- gates.cjs reports that as SKIP, never as a pass).
'use strict';

const fs = require('fs');
const path = require('path');
const { spawnSync, spawn } = require('child_process');

const UI = path.resolve(__dirname, '..');
const DEMO = path.join(UI, 'ui-demo');
const APP = path.join(DEMO, 'air-gallery');
const logFile = path.join(APP, 'air-trace.txt');
const modeFile = path.join(APP, 'air-mode.txt');
const swf = path.join(APP, 'GalleryApp.swf');

const argv = process.argv.slice(2);
let sdkArg = null;
for (let i = 0; i < argv.length; i++) {
  if (argv[i] === '--sdk') sdkArg = argv[++i];
  else { console.error('[air-sweep] unknown argument ' + argv[i]); process.exit(2); }
}
const timeoutS = Number(process.env.AIR_SWEEP_TIMEOUT || 240);

// ---- the AIR SDK ------------------------------------------------------------
function sdkFromPath() {
  const dirs = (process.env.PATH || '').split(path.delimiter);
  for (let d of dirs) {
    if (!d) continue;
    const m = /^\/mnt\/([A-Za-z])\/(.*)$/.exec(d);      // WSL spelling -> Windows
    if (m) d = m[1].toUpperCase() + ':/' + m[2];
    for (const n of ['adl.exe', 'adl', 'mxmlc.bat', 'mxmlc']) {
      if (fs.existsSync(path.join(d, n))) return path.resolve(d, '..');
    }
  }
  return null;
}
const sdk = sdkArg || process.env.AIRSDK_HOME || sdkFromPath();
if (!sdk) {
  console.log('[air-sweep] no AIR SDK: pass --sdk <root>, set AIRSDK_HOME, or put its bin/ on PATH');
  process.exit(3);
}
const win = process.platform === 'win32';
const adl = path.join(sdk, 'bin', win ? 'adl.exe' : 'adl');
if (!fs.existsSync(adl)) {
  console.log('[air-sweep] no adl at ' + adl + ' -- is the SDK root right?');
  process.exit(3);
}
console.log('[air-sweep] AIR SDK: ' + sdk);

// ---- derive the catalog and the popup keys from the sources -----------------
// Comments are blanked (string-aware is not needed here: no demo string contains
// `//` followed by m.bool( ... ). The HEADER comments do mention the pattern --
// `DocsAir.as` documents `m.bool("<x>.open")` -- and grading a placeholder as a key
// would make the expected popup count wrong.
function stripComments(text) {
  return text.replace(/\/\*[\s\S]*?\*\//g, (m) => m.replace(/[^\n]/g, ' '))
    .replace(/(^|[^:])\/\/[^\n]*/g, (m, p1) => p1 + ' '.repeat(m.length - p1.length));
}

function demoFiles() {
  return fs.readdirSync(path.join(DEMO, 'demo'))
    .filter((f) => f.endsWith('.as'))
    .map((f) => path.join(DEMO, 'demo', f));
}

const catalogText = fs.readFileSync(path.join(DEMO, 'demo', 'DocsCatalog.as'), 'utf8');
const pages = [];
for (const m of stripComments(catalogText).matchAll(/new\s+DocPage\s*\(\s*"([^"]+)"/g)) pages.push(m[1]);
if (pages.length < 10) {
  console.log('[air-sweep] FAIL: parsed only ' + pages.length + ' page(s) out of DocsCatalog.as');
  process.exit(1);
}

const keySet = new Set();
for (const f of demoFiles()) {
  const text = stripComments(fs.readFileSync(f, 'utf8'));
  for (const m of text.matchAll(/m\s*\.\s*bool\s*\(\s*"([^"]+\.open)"/g)) keySet.add(m[1]);
}
const openKeys = [...keySet];
console.log('[air-sweep] ' + pages.length + ' page(s) in the catalog, '
  + openKeys.length + ' popup key(s): ' + openKeys.join(', '));

// ---- build with the reference compiler --------------------------------------
// `--src ui-demo` (not `demo`): the classes are `package demo`, so the root has to be
// the directory the `demo/` folder sits in.
const build = spawnSync(process.execPath, [
  path.join(UI, 'tools', 'mxmlc-check.cjs'),
  '--sdk', sdk,
  '--root', 'ui-demo/demo/DocsAir.as',
  '--src', 'ui-demo', '--src', 'kit', '--src', 'seam',
  '--out', 'ui-demo/air-gallery/GalleryApp.swf',
], { cwd: UI, encoding: 'utf8', maxBuffer: 1 << 28 });
const buildOut = (build.stdout || '') + (build.stderr || '');
if (build.status !== 0) {
  console.log(buildOut);
  console.log('[air-sweep] FAIL: mxmlc rejected the AIR arm -- nothing was measured');
  process.exit(1);
}
console.log('[air-sweep] mxmlc: ' + (/OK: compiled by AIR -- (\d+) bytes/.exec(buildOut) || [])[1] + ' bytes');

// ---- run it ----------------------------------------------------------------
// The driver file is how AIR is told what to do (no argv: mxmlc rejects
// `NativeApplication.argv`; see ui-demo/demo/DocsAir.as).
try { fs.unlinkSync(logFile); } catch (e) { /* no previous run */ }
fs.writeFileSync(modeFile, 'sweep ' + logFile + ' open=' + openKeys.join(',') + '\n');

const readLog = () => { try { return fs.readFileSync(logFile, 'utf8'); } catch (e) { return ''; } };
const child = spawn(adl, ['app.xml'], { cwd: APP });
let spawnFailed = null;
child.on('error', (e) => { spawnFailed = e.message; });

const killChild = () => {
  try {
    if (win) spawnSync('taskkill', ['/F', '/PID', String(child.pid)], { stdio: 'ignore' });
    else child.kill('SIGKILL');
  } catch (e) { /* already gone */ }
};

// Poll the app's own log. A timeout is a FAILURE, not a pass: it means the window
// never finished the sweep (a crash, a modal, a page that hung).
const deadline = Date.now() + timeoutS * 1000;
let timedOut = false;
while (Date.now() < deadline) {
  const text = readLog();
  if (/^END errors=\d+/m.test(text)) break;
  if (spawnFailed) break;
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 120);
}
if (!/^END errors=\d+/m.test(readLog())) timedOut = true;
killChild();
try { fs.unlinkSync(modeFile); } catch (e) {}
if (spawnFailed) {
  console.log('[air-sweep] FAIL: could not start adl -- ' + spawnFailed);
  process.exit(1);
}

// ---- grade -----------------------------------------------------------------
const log = readLog();
const lines = log.split(/\r?\n/).filter((l) => l.length > 0);
const failures = [];

if (!/^START$/m.test(log)) failures.push('no START line: the app never reached the sweep');

// Every page, exactly once, in catalog order. A missing tail is the signature of a
// window that died at page N -- which must not look any different from a pass.
const seen = lines.filter((l) => l.startsWith('PAGE ')).map((l) => l.slice(5).trim());
if (seen.length !== pages.length) failures.push('visited ' + seen.length + '/' + pages.length + ' pages');
for (let i = 0; i < Math.min(seen.length, pages.length); i++) {
  if (seen[i] !== pages[i]) {
    failures.push('page ' + (i + 1) + ' was "' + seen[i] + '", catalog says "' + pages[i] + '"');
    break;
  }
}

const done = /^SWEEP DONE (\d+)$/m.exec(log);
if (!done) failures.push('no SWEEP DONE line' + (timedOut ? ' (timed out after ' + timeoutS + 's)' : ''));
else if (Number(done[1]) !== pages.length) failures.push('SWEEP DONE ' + done[1] + ' != ' + pages.length + ' catalog pages');

// The open step must be MEASURED, not assumed: `OPENED <k>` is counted from the model
// after the flip, so a sweep whose flip silently stopped happening reports 0 here and
// fails -- otherwise this gate would go blind without saying so.
const opened = /^OPENED (\d+)$/m.exec(log);
if (!opened) failures.push('no OPENED line: the popup-open step never reported');
else if (Number(opened[1]) !== openKeys.length) {
  failures.push('OPENED ' + opened[1] + ' of ' + openKeys.length + ' popup key(s) -- the open step did not take effect');
}

const endLine = /^END errors=(\d+)$/m.exec(log);if (!endLine) failures.push('no END line (the window did not finish)');
else if (Number(endLine[1]) !== 0) failures.push('END errors=' + endLine[1]);

const errors = lines.filter((l) => l.startsWith('ERROR '));
if (errors.length) failures.push(errors.length + ' runtime error(s) reported by AIR');

// The pointer drill. `ROLL` is emitted once per page, AFTER the targeted tree was
// replaced, so `destroyed` is a fact about this app and not about the driver: if it
// collapses the roll-out stopped meeting dead nodes and this gate is blind again.
// 348 of 3107 hovered nodes were destroyed on the first measured run (2026-10-24);
// the floor is a third of that, so harmless layout drift will not fail a green app
// while a real loss of coverage will.
const ROLL_FLOOR = 100;
const rollLines = lines.filter((l) => l.startsWith('ROLL '));
const rollFails = lines.filter((l) => l.startsWith('ROLLFAIL '));
let rollHovered = 0;
let rollDestroyed = 0;
for (const l of rollLines) {
  const m = /^ROLL \S+ hovered=(\d+) destroyed=(\d+) errors=(\d+)$/.exec(l);
  if (!m) {
    failures.push('unreadable pointer-drill line: ' + l.slice(0, 90));
    continue;
  }
  rollHovered += Number(m[1]);
  rollDestroyed += Number(m[2]);
  if (Number(m[3]) !== 0) failures.push('a roll-out threw on page "' + l.split(' ')[1] + '"');
}
if (rollLines.length !== pages.length) {
  failures.push('the pointer drill reported ' + rollLines.length + '/' + pages.length + ' page(s)');
}
if (rollDestroyed < ROLL_FLOOR) {
  failures.push('the pointer drill destroyed ' + rollDestroyed + ' of ' + rollHovered
    + ' hovered node(s) (floor ' + ROLL_FLOOR + ') -- it stopped meeting torn-down nodes');
}
if (rollFails.length) {
  failures.push(rollFails.length + ' roll-out(s) threw at a torn-down node');
}

console.log('[air-sweep] ' + seen.length + '/' + pages.length + ' page(s) visited, '
  + (opened ? opened[1] : '?') + '/' + openKeys.length + ' popup(s) opened, '
  + errors.length + ' runtime error(s), '
  + rollHovered + ' node(s) hovered and ' + rollDestroyed + ' of them destroyed by a switch; log: '
  + path.relative(UI, logFile).split(path.sep).join('/'));
for (const l of rollFails.slice(0, 5)) console.log('  ' + l);
if (errors.length) {
  // The first error of each page, with its stack: one line per broken page is the
  // difference between "somewhere in 41 pages" and a fix.
  const byPage = new Map();
  for (let i = 0; i < lines.length; i++) {
    if (!lines[i].startsWith('ERROR ')) continue;
    const page = lines[i].split(' ')[1];
    if (!byPage.has(page)) byPage.set(page, lines.slice(i, i + 3).join(' | '));
  }
  for (const [page, detail] of byPage) console.log('  [' + page + '] ' + detail);
}
if (failures.length === 0) {
  console.log('AIR SWEEP: PASS');
  process.exit(0);
}
console.log('[air-sweep] ' + failures.length + ' failure(s):');
for (const f of failures) console.log('  - ' + f);
console.log('AIR SWEEP: FAIL');
process.exit(1);
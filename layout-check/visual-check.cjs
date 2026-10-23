// layout-check/visual-check.cjs -- one command for the VISUAL half of the layout
// acceptance harness: build the native window with our own AOT compiler, run it,
// read the framebuffer it wrote, assert against the hand-computed rectangles, and
// close the window again.
//
// WHY A DRIVER: the manual sequence has four steps and three traps --
//   1. the window must be built with the WINDOW manifest (Skia + SDL2), not the default one;
//   2. it BLOCKS until closed, so it has to be launched detached, not awaited;
//   3. the process holds a lock on the .exe, so a rerun must kill the previous one first.
// Encoding that here is what makes the check repeatable instead of a one-off.
//
// The picture is read back for the reason given in verify-visual.cjs: CheckMain.as
// asserts what layoutGet RETURNS, this asserts what was RASTERIZED.
//
// Usage: node visual-check.cjs
// Exit: 0 = built, ran, and the picture matched; non-zero = the first failing step.
const { spawn, spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const HERE = __dirname;
const REPO = path.resolve(HERE, '..', '..', 'as3compiler'); // <root>/as3compiler
const EXE = path.join(HERE, 'VisualDemo.exe');
const BMP = path.join(HERE, 'visual-demo.bmp');

function step(msg) { console.log('\n=== ' + msg + ' ==='); }

// ---- 1. make sure no previous window is holding the .exe -------------------
step('close any running VisualDemo');
spawnSync('taskkill', ['/F', '/IM', 'VisualDemo.exe'], { encoding: 'utf8' });
for (let i = 0; i < 20 && fs.existsSync(EXE); i++) {
  try { fs.unlinkSync(EXE); } catch (e) { /* still locked; retry */ }
  if (fs.existsSync(EXE)) spawnSync('node', ['-e', 'setTimeout(()=>{},150)']);
}
if (fs.existsSync(EXE)) { console.error('could not remove ' + EXE + ' (still locked?)'); process.exit(3); }

// ---- 2. build: our AOT compiler, native target, window manifest ------------
step('build VisualDemo.exe with our AOT compiler');
const SRC = [
  '../asaotui/layout-check/VisualDemo.as',
  '../asaotui/seam/asaot/ui/LayoutConstants.as',
  '../asaotui/seam/asaot/ui/LayoutEngine.as',
  '../asaotui/seam/asaot/ui/as3/As3LayoutNode.as',
  '../asaotui/seam/asaot/ui/as3/As3LayoutEngine.as',
];
const build = spawnSync('node', ['src/index.ts', ...SRC,
  '--manifest', 'examples/window.build.example.json',
  '-o', '../asaotui/layout-check/VisualDemo'], { cwd: REPO, encoding: 'utf8' });
const buildOut = ((build.stdout || '') + (build.stderr || ''));
console.log(buildOut.split('\n').filter((l) => /Build (successful|failed)|rror/.test(l)).join('\n') || buildOut.slice(-800));
if (!fs.existsSync(EXE)) { console.error('BUILD FAILED: ' + EXE + ' was not produced'); process.exit(3); }
console.log('ok: ' + EXE + ' (' + fs.statSync(EXE).size + ' bytes)');

// ---- 3. run it detached (it blocks until the window is closed) -------------
step('run the window and wait for it to write its framebuffer');
if (fs.existsSync(BMP)) fs.unlinkSync(BMP);
const win = spawn(EXE, [], { cwd: HERE, detached: true, stdio: 'ignore' });
win.unref();
console.log('pid ' + win.pid + ', waiting for ' + path.basename(BMP) + ' ...');

const DEADLINE = Date.now() + 20000;
while (!fs.existsSync(BMP) && Date.now() < DEADLINE) {
  spawnSync('node', ['-e', 'setTimeout(()=>{},200)']);
}
if (!fs.existsSync(BMP)) {
  console.error('TIMEOUT: the window never wrote ' + BMP);
  spawnSync('taskkill', ['/F', '/IM', 'VisualDemo.exe'], { encoding: 'utf8' });
  process.exit(3);
}
console.log('ok: ' + fs.statSync(BMP).size + ' bytes');

// ---- 4. read the picture back and assert -----------------------------------
step('read the picture back');
const verify = spawnSync('node', [path.join(HERE, 'verify-visual.cjs'), BMP], { cwd: HERE, encoding: 'utf8' });
console.log(verify.stdout || '');
if (verify.stderr) console.error(verify.stderr);

// ---- 5. clean up -----------------------------------------------------------
step('close the window');
spawnSync('taskkill', ['/F', '/IM', 'VisualDemo.exe'], { encoding: 'utf8' });
console.log('closed');

process.exit(verify.status === 0 ? 0 : 1);

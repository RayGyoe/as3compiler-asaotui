// tools/probe.cjs -- ONE command that compiles a windowed probe with OUR AOT,
// runs it, verifies its output against a HAND-WRITTEN expect file, and reports
// pass/fail.
//
// Why this exists: every widget needs the same evidence -- "the engine put it at
// THESE coordinates" and "these exact pixels have THESE exact colours". Both are
// integer-exact when the frame buffer is read back with `bd.draw(stage)` (a 1:1
// copy of the compositor output; unlike a screen grab it has no DPI scaling and
// no window chrome). Hand-computed expectations live in `<probe>/expect.json`, so
// nothing is ever "verified" by copying the program's own output.
//
// USAGE (from asaotui/):
//   node tools/probe.cjs probes/widgets/chip
//   node tools/probe.cjs probes/widgets/chip --keep      (leave the window up)
//   node tools/probe.cjs probes/widgets/chip --rebuild-only
//
// A probe directory contains:
//   Main.as              the probe program (see the CHIP reference probe)
//   expect.json          { "w":.., "h":.., "rects": {"key":[x,y,w,h]},
//                          "points": [{"x":..,"y":..,"rgb":"#RRGGBB"}] }
// and may contain extra .as units (they are passed to the compiler).
//
// The program protocol (the probe MUST follow it):
//   * after mounting, `setTimeout(finish, 900)`
//   * in finish(): write `<name>.rects.txt` lines "key x,y,w,h",
//     write `<name>.bmp` (the BMP writer is copied from probes/kit-fill/Cards.as),
//     then write `<name>.done` containing "PASS" or "FAIL <reason>".
'use strict';

const fs = require('fs');
const path = require('path');
const { spawnSync, spawn, execSync } = require('child_process');
const { ALL } = require('../ui-demo/kit-list.cjs');

const UI = path.resolve(__dirname, '..');
const COMPILER = path.resolve(UI, '..', 'as3compiler');
const clang = process.env.ASC_CC || 'clang';
const ICU = path.join(UI, 'ui-demo', 'icudtl.dat');
const MANIFEST = 'examples/window.build.example.json';

const argv = process.argv.slice(2);
const dirArg = argv.find((a) => !a.startsWith('--'));
if (!dirArg) { console.error('usage: node tools/probe.cjs <probe-dir>'); process.exit(2); }
const keep = argv.includes('--keep');
const rebuildOnly = argv.includes('--rebuild-only');
const dir = path.resolve(UI, dirArg);
const name = path.basename(dir);

if (!fs.existsSync(path.join(dir, 'Main.as'))) {
  console.error('[probe] no Main.as in ' + dir);
  process.exit(2);
}

// ---- 1: clean previous evidence (a stale artifact has faked a pass before) ---
const OUTS = [name + '.bmp', name + '.bmp.rects.txt', name + '.rects.txt', name + '.done', name + '.log',
  // A probe may leave a stage breadcrumb here (see probes/widgets/scrollbar): the
  // file is the probe's own, and printing it on TIMEOUT names the stage that died.
  name + '.step'];
for (const f of OUTS) {
  const p = path.join(dir, f);
  if (fs.existsSync(p)) fs.unlinkSync(p);
}

// The window backend needs icudtl.dat in its cwd; copy it once per probe dir.
if (fs.existsSync(ICU) && !fs.existsSync(path.join(dir, 'icudtl.dat'))) {
  fs.copyFileSync(ICU, path.join(dir, 'icudtl.dat'));
  console.log('[probe] seeded icudtl.dat');
}

// ---- 2: build --------------------------------------------------------------
const extra = fs.readdirSync(dir)
  .filter((f) => f.endsWith('.as') && f !== 'Main.as')
  .sort()
  .map((f) => path.join(dir, f));

console.log('[probe] building ' + name);

// The AOT names the executable after the INPUT FILE's basename, not the probe
// directory, so locate it by mtime rather than guessing.
const args = [
  'src/index.ts',
  path.join(dir, 'Main.as'),
  ...extra,
  ...ALL,
  '--manifest', MANIFEST,
  '--cc', clang,
  '-I', './vendor/curl/include',
  '-L', './vendor/curl/lib/windows-x64',
  '-l', 'zlib'
];

const buildStarted = Date.now();
// BOUNDED. `as-aot` can hang on its own inputs (a tree mid-edit under another session
// produced a build that never returned), and an unbounded spawnSync here would hang the
// whole gate run without printing anything.
const b = spawnSync(process.execPath, args, {
  cwd: COMPILER, encoding: 'utf8',
  timeout: Number(process.env.ASC_BUILD_TIMEOUT_MS || 300000),
  killSignal: 'SIGKILL',
});
const buildOut = (b.stdout || '') + (b.stderr || '');
if (b.status === null && b.signal) {
  console.error('[probe] BUILD TIMED OUT (killed after '
    + Math.round(Number(process.env.ASC_BUILD_TIMEOUT_MS || 300000) / 1000) + 's)');
  console.error(buildOut.split(/\r?\n/).slice(-20).join('\n'));
  process.exit(1);
}
if (b.status !== 0) {
  console.error('[probe] BUILD FAILED (exit ' + b.status + ')');
  console.error(buildOut.split(/\r?\n/).slice(-40).join('\n'));
  process.exit(1);
}

function newestExe() {
  // The AOT names the executable after the INPUT FILE's basename; on Windows that
  // is `Main.exe`, on macOS/Linux it is plain `Main` with no extension. Discovery
  // therefore cannot key on `.exe` -- it keys on "a FRESH regular file that the
  // filesystem marks executable and that is not one of the artifacts this tool
  // itself produces". (Keying on the extension made every probe here report
  // "build succeeded but no freshly built .exe" on macOS.)
  let best = null;
  for (const f of fs.readdirSync(dir)) {
    const p = path.join(dir, f);
    let st;
    try { st = fs.statSync(p); } catch (e) { continue; }
    if (!st.isFile()) continue;
    if (st.mtimeMs + 5000 < buildStarted) continue;   // stale artifact
    const isExe = process.platform === 'win32'
      ? f.toLowerCase().endsWith('.exe')
      : (st.mode & 0o111) !== 0 && !/\.(c|as|json|txt|log|bmp|done|step|dat|png|swf)$/i.test(f);
    if (!isExe) continue;
    if (best == null || st.mtimeMs > fs.statSync(best).mtimeMs) best = p;
  }
  return best;
}

const exe = newestExe();
if (exe == null) {
  console.error('[probe] build succeeded but no freshly built .exe in ' + dir);
  process.exit(1);
}
console.log('[probe] built ' + path.relative(UI, exe));
if (rebuildOnly) process.exit(0);

// ---- 3: run (detached: the window blocks main) ------------------------------
const child = spawn(exe, [], { cwd: dir, detached: true, stdio: 'ignore' });
child.unref();

function kill() {
  // Windows holds the .exe open while the window is up, so the process must die
  // before the next build; on POSIX the file stays writable, but a leftover window
  // would still steal the focus of the next probe -- so kill there too.
  //
  // BY PID, NOT BY NAME. This used to run `pkill -f "Main"`: `-f` matches a
  // substring of the whole command line, so the cleanup reached ANY process whose
  // argv contains "Main" -- every probe here is built as `Main`, and so is anything
  // else that spells it. The pid we spawned is exact; taskkill /T also takes the
  // tree, which is what a window backend that forks a helper needs.
  try { process.kill(child.pid, 'SIGKILL'); } catch (e) { /* already gone */ }
  try {
    execSync(process.platform === 'win32'
      ? 'taskkill /F /T /PID ' + child.pid
      : 'kill -9 ' + child.pid,
      { stdio: 'ignore' });
  } catch (e) { /* already gone */ }
}

// ---- 4: wait for the program to publish its verdict ------------------------
const donePath = path.join(dir, name + '.done');
const deadline = Date.now() + 30000;
let verdict = null;
while (Date.now() < deadline) {
  if (fs.existsSync(donePath)) {
    verdict = fs.readFileSync(donePath, 'utf8').trim();
    break;
  }
  // Busy-wait in ~120ms slices without coreutils `sleep`.
  const until = Date.now() + 120;
  while (Date.now() < until) { /* spin */ }
}
if (!keep) kill();

if (verdict == null) {
  console.error('[probe] TIMEOUT: ' + name + ' never wrote ' + name + '.done (window never settled?)');
  const stepP = path.join(dir, name + '.step');
  if (fs.existsSync(stepP)) console.error('[probe] last stage: ' + fs.readFileSync(stepP, 'utf8').trim());
  const log = path.join(dir, name + '.log');
  if (fs.existsSync(log)) console.error(fs.readFileSync(log, 'utf8'));
  process.exit(1);
}

// ---- 5: verify against the HAND-WRITTEN expectations ----------------------
const expectPath = path.join(dir, 'expect.json');
if (!fs.existsSync(expectPath)) {
  console.error('[probe] no expect.json -- refusing to report a pass without expectations');
  process.exit(1);
}
const expect = JSON.parse(fs.readFileSync(expectPath, 'utf8'));

let checks = 0;
const failures = [];
function ok(cond, msg) {
  checks++;
  if (!cond) failures.push(msg);
}

// The program's own verdict counts as one check (it may assert things the BMP
// cannot show, e.g. a binding wrote back).
ok(verdict === 'PASS', 'program verdict: ' + verdict);

// 5a: rects -----------------------------------------------------------------
const rectsPath = path.join(dir, name + '.rects.txt');
const actual = {};
if (fs.existsSync(rectsPath)) {
  for (const line of fs.readFileSync(rectsPath, 'utf8').split(/\r?\n/)) {
    const m = line.trim().match(/^(\S+)\s+(-?[\d.]+),(-?[\d.]+),(-?[\d.]+),(-?[\d.]+)$/);
    if (m) actual[m[1]] = [Number(m[2]), Number(m[3]), Number(m[4]), Number(m[5])];
  }
}
for (const key of Object.keys(expect.rects || {})) {
  const want = expect.rects[key];
  const got = actual[key];
  if (!got) { ok(false, 'rect ' + key + ': not reported by the probe'); continue; }
  for (let i = 0; i < 4; i++) {
    ok(got[i] === want[i], 'rect ' + key + '[' + 'x y w h'.split(' ')[i] + '] want ' + want[i] + ' got ' + got[i]);
  }
}

// 5b: exact pixels ----------------------------------------------------------
const bmpPath = path.join(dir, name + '.bmp');
if ((expect.points || []).length) {
  if (!fs.existsSync(bmpPath)) {
    ok(false, 'no ' + name + '.bmp written');
  } else {
    const bmp = loadBmp(bmpPath);
    if (expect.w) ok(bmp.w === expect.w, 'bmp width want ' + expect.w + ' got ' + bmp.w);
    if (expect.h) ok(bmp.h === expect.h, 'bmp height want ' + expect.h + ' got ' + bmp.h);
    for (const p of expect.points) {
      const got = bmp.at(p.x, p.y);
      const want = parseHex(p.rgb);
      ok(got[0] === want[0] && got[1] === want[1] && got[2] === want[2],
        'pixel (' + p.x + ',' + p.y + ') want ' + p.rgb + ' got ' + toHex(got));
    }
  }
}

// ---- 6: report -------------------------------------------------------------
console.log('');
console.log('PROBE ' + name + ': ' + checks + ' checks, ' + failures.length + ' failures');
for (const f of failures) console.log('  FAIL  ' + f);
console.log(failures.length === 0 ? 'RESULT: PASS' : 'RESULT: FAIL');
process.exit(failures.length === 0 ? 0 : 1);

// ---- helpers ---------------------------------------------------------------
function parseHex(h) {
  const s = h.replace('#', '');
  return [parseInt(s.slice(0, 2), 16), parseInt(s.slice(2, 4), 16), parseInt(s.slice(4, 6), 16)];
}

function toHex(rgb) {
  return '#' + rgb.slice(0, 3).map((v) => v.toString(16).padStart(2, '0')).join('');
}

// 32-bit BMP, bottom-up rows, BGRA. Written by the AS3 probe with
// `bd.getPixels()` (ARGB byte order) re-ordered to BGRA.
function loadBmp(p) {
  const buf = fs.readFileSync(p);
  if (buf.readUInt16LE(0) !== 0x4d42) throw new Error('not a BMP: ' + p);
  const offBits = buf.readUInt32LE(10);
  const w = buf.readInt32LE(18);
  const hRaw = buf.readInt32LE(22);
  const bpp = buf.readUInt16LE(28);
  if (bpp !== 32) throw new Error('expected 32bpp, got ' + bpp);
  const h = Math.abs(hRaw);
  const bottomUp = hRaw > 0;
  if (buf.length < offBits + w * h * 4) throw new Error('truncated BMP: ' + p);
  return {
    w, h,
    at(x, y) {
      if (x < 0 || y < 0 || x >= w || y >= h) throw new Error('pixel out of range ' + x + ',' + y);
      const row = bottomUp ? (h - 1 - y) : y;
      const i = offBits + (row * w + x) * 4;
      return [buf[i + 2], buf[i + 1], buf[i]];   // BGR -> RGB
    }
  };
}
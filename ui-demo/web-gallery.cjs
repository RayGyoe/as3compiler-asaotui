// web-gallery.cjs -- build the component documentation app as a BROWSER page
// (`--target wasm --package web`, Emscripten/emcc) and, by default, serve it.
//
// Usage:   node web-gallery.cjs [--no-serve|--serve-only] [--port <n>] [--app-dir <name>] [--check]
//          (build.sh calls this for `./build.sh web`; see that file's header)
//
// WHY A THIRD ARM NEEDS ITS OWN RUNNER
// ------------------------------------
// `run-gallery.cjs` is the AOT arm's whole recipe: stage -> `--air-app` -> launch
// the exe -> wait for the tour's `.done` file -> measure the PNGs. NONE of those
// steps has a browser equivalent. There is no process to launch (the page is
// loaded by a browser the script does not own), no writable app directory to drop
// `gallery.done` in, and no `Stage.render` to measure a frame with. What replaces
// them is what a browser can do: serve the directory and let a human (or the
// AgentPilot preview panel) look at it. So the verdict on this arm is "the page
// loads and renders", which is observed, not asserted -- and this runner says so
// instead of inventing a pass/fail it cannot compute.
//
// WHY A SEPARATE APP DIRECTORY (air-gallery-web)
// ----------------------------------------------
// A web build turns the app directory into a FILESYSTEM IMAGE (`<base>.data`) that
// the page downloads before it can start. `air-gallery/` after a native build also
// holds the native executable, its import library, the generated 3 MB `.c`, eight
// 1500x1050 gallery screenshots and `icudtl.dat` (9.7 MB, which only the native
// window backend reads) -- none of which the browser can use. Packing that tree
// would put ~15 MB of dead weight in front of the first paint and would make the
// page's load time depend on whether the AOT arm had been built recently.
//
// So the web arm stages its own app dir and keeps it to what the page needs:
//
//     app.xml        byte-for-byte copy of air-gallery/app.xml (the descriptor stays
//                    the single source of truth for the window; the copy is a build
//                    artifact and is verified against its source on every run)
//     as-image.png   the one asset the `image` page loads through `src` (relative
//                    URL -> resolved against the page, so it has to sit beside it)
//     fonts/*.ttf    the browser sandbox has no system fonts, so text draws as
//                    NOTHING unless a font is shipped (as-aot warns about this too)
//     src/           the demo's own sources, staged by stage-air.cjs
//     GalleryApp.*   the products (html + js + wasm + data)
//
// It is generated, gitignored, and re-created from the tracked sources on demand:
// delete it whenever, the next `./build.sh web` rebuilds it.
//
// WINDOWS: THE EMCC LAUNCHER SHIM (compiler-gaps.md G27)
// ------------------------------------------------------
// `as-aot` spawns `$EMSDK_HOME/upstream/emscripten/emcc` DIRECTLY, with no shell
// (src/build.ts::emccPath + spawnSync). On the SDK that path is a `#!/bin/sh`
// wrapper -- a POSIX script Windows cannot CreateProcess -- so a web build on
// Windows stops with "cannot build for --package web: emcc not found: ..." before
// it reads a single flag, even though `emcc.bat` next to it works fine. The driver
// also hands the child `env = { PATH: ... }` with POSIX ':' separators, which a
// Windows PATH cannot parse, and throws the rest of the environment away
// (EM_CONFIG, EMSDK_PYTHON).
//
// This runner therefore builds a 100-line PE launcher (tools/emcc-launcher.c) that
// lives at `<shim>/upstream/emscripten/emcc.exe`, restores that environment from a
// 4-line config file beside it, and forwards argv to `emcc.bat`. The compiler is
// unchanged; `EMSDK_HOME` points at the shim tree. On macOS/Linux the SDK's own
// `emcc` works and none of this happens.
'use strict';

const path = require('path');
const fs = require('fs');
const http = require('http');
const crypto = require('crypto');
const { spawnSync, spawn } = require('child_process');
const { descriptorWindow } = require('./air-run.cjs');

const here = __dirname;                                   // asaotui/ui-demo/
const UI = path.resolve(here, '..');                      // asaotui/
const compilerDir = path.resolve(UI, '..', 'as3compiler');
const clang = process.env.ASC_CC || 'clang';
const shimHome = path.join(UI, '.scratch', 'emcc-shim');
const launcherSrc = path.join(UI, 'tools', 'emcc-launcher.c');

// The source roots the build compiles IN ADDITION to `<appDir>/src`. Kept in step
// with stage-air.cjs's SHARED_ROOTS (that file prints them; this one has to pass
// them to as-aot).
const SHARED_ROOTS = [path.join(UI, 'seam'), path.join(UI, 'kit')];

// ---- arguments --------------------------------------------------------------
let appDirName = 'air-gallery-web';
let sourceAppDirName = 'air-gallery';
let serve = true;
let serveOnly = false;
let port = 8080;
{
  const argv = process.argv.slice(2);
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--no-serve') serve = false;
    else if (a === '--serve') serve = true;
    else if (a === '--serve-only') { serve = true; serveOnly = true; }
    else if (a === '--check') { /* handled after the SDK is resolved */ }
    else if (a === '--port') port = Number(argv[++i]);
    else if (a === '--app-dir') appDirName = argv[++i];
    else {
      console.error('[web] unknown argument: ' + a
        + '\n      usage: web-gallery.cjs [--no-serve|--serve-only|--check] [--port <n>] [--app-dir <name>]');
      process.exit(2);
    }
  }
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    console.error('[web] --port needs a TCP port number');
    process.exit(2);
  }
}

const appDir = path.join(here, appDirName);
const sourceAppDir = path.join(here, sourceAppDirName);
const sourceDescriptor = path.join(sourceAppDir, 'app.xml');
const BASE = 'GalleryApp';
const outputBase = path.join(appDir, BASE);

// The argv the compiler gets. ONE definition, two consumers: the build execs this
// array and `--check` prints it. A described-but-not-passed flag is the failure mode
// that makes a self-describing build lie, so there is nothing to keep in sync.
function aotArgv() {
  return [
    'src/index.ts',
    // `--air-app` reads the descriptor for the window (canvas size, title) exactly as
    // it does for the native arms, and switches its own manifest to the browser
    // backend because `--package web` is on the command line.
    '--air-app', path.join(appDir, 'app.xml'),
    // DocsWeb, not DocsMain: the tour hooks (dispatchMouse/render) exist only on the
    // native AOT, and DocsAir does not compile for wasm at all (it uses
    // UncaughtErrorEvent, which this compiler does not implement). See DocsWeb.as.
    '--main-class', 'demo.DocsWeb',
    '--target', 'wasm',
    '--package', 'web',
    '-o', outputBase,
    '--as-class-path', SHARED_ROOTS[0],
    '--as-class-path', SHARED_ROOTS[1],
  ];
}
if (!fs.existsSync(sourceDescriptor)) {
  console.error('[web] no descriptor at ' + sourceDescriptor
    + ' -- it is the tracked source of truth for the window; this script never writes it');
  process.exit(2);
}
const win = descriptorWindow(sourceDescriptor);
if (!win) {
  console.error('[web] ' + sourceDescriptor + ' has no <width>/<height> under <initialWindow>');
  process.exit(2);
}

// ---- the Emscripten SDK -----------------------------------------------------
// Same resolution order as the compiler's own (EMSDK_HOME, then EMSDK), plus the
// workspace layout so `./build.sh web` works without the variable being exported.
// The compiler treats a missing SDK as an error at build time; naming the reason
// here -- before a 3 MB codegen pass -- is the difference between a two-second
// failure and a two-minute one.
function findEmsdk() {
  const tried = [];
  const fromEnv = process.env.EMSDK_HOME || process.env.EMSDK || '';
  if (fromEnv) {
    tried.push(fromEnv);
    // `EMSDK` may carry forward slashes; Windows accepts either.
    if (fs.existsSync(path.join(fromEnv, 'upstream', 'emscripten', 'emcc'))
      || fs.existsSync(path.join(fromEnv, 'upstream', 'emscripten', 'emcc.bat'))) return fromEnv;
    // An explicitly-named SDK that is not one is an ERROR, not a miss: falling
    // through to the workspace's copy would build the page with a DIFFERENT
    // toolchain than the one asked for, and nothing in the output would say so
    // (AGENTS.md 2.5). The search below is only for the case nobody named one.
    console.error('[web] EMSDK_HOME/EMSDK is set but is not an emsdk root: ' + fromEnv
      + '\n      expected ' + path.join(fromEnv, 'upstream', 'emscripten', 'emcc')
      + ' (or emcc.bat on Windows)');
    process.exit(2);
  }
  // This workspace keeps the Skia source tree (and therefore the emsdk it built
  // skia with) one level above the toolkit repo.
  const workspace = path.resolve(UI, '..');
  for (const rel of [
    path.join('build-tools', 'skia-src', 'third_party', 'externals', 'emsdk'),
    path.join('build-tools', 'emsdk'),
  ]) {
    const p = path.join(workspace, rel);
    tried.push(p);
    if (fs.existsSync(path.join(p, 'upstream', 'emscripten', 'emcc'))
      || fs.existsSync(path.join(p, 'upstream', 'emscripten', 'emcc.bat'))) return p;
  }
  console.error('[web] no Emscripten SDK found. Looked at:\n  '
    + tried.join('\n  ')
    + '\n      Install one and point EMSDK_HOME at its root (the directory holding'
    + '\n      upstream/emscripten/emcc), e.g.:  EMSDK_HOME=/path/to/emsdk ./build.sh web');
  process.exit(2);
}
const emsdk = findEmsdk();
console.log('[web] emsdk: ' + emsdk);

// Windows needs the PE launcher (see the header). `clang` compiles it once; the
// result is cached under .scratch/ and rebuilt when the source changes.
function shimHomeForWindows() {
  const em = path.join(shimHome, 'upstream', 'emscripten');
  fs.mkdirSync(em, { recursive: true });
  const exe = path.join(em, 'emcc.exe');
  const src = launcherSrc;
  if (!fs.existsSync(src)) {
    console.error('[web] missing ' + src + ' (the Windows emcc launcher)');
    process.exit(2);
  }
  const stale = !fs.existsSync(exe)
    || fs.statSync(src).mtimeMs > fs.statSync(exe).mtimeMs;
  if (stale) {
    console.log('[web] building the emcc launcher (tools/emcc-launcher.c -> ' + path.relative(UI, exe) + ')');
    const r = spawnSync(clang, ['-O2', '-o', exe, src], { encoding: 'utf8' });
    if (r.status !== 0) {
      console.error('[web] could not compile the emcc launcher with ' + clang + ':');
      console.error((r.stdout || '') + (r.stderr || ''));
      process.exit(2);
    }
  }
  // The environment the compiler throws away: emcc.bat needs a python to run
  // emcc.py with, the SDK's config (which itself is what tells emcc where clang,
  // node and wasm-ld are), and a Windows-shaped PATH.
  const w = (p) => p.replace(/\//g, '\\');
  const python = [
    'python/3.9.2-nuget_64bit/python.exe',
  ].map((r) => path.join(emsdk, r)).find((p) => fs.existsSync(p));
  const cfg = [
    path.join(emsdk, '.emscripten'),            // EM_CONFIG
    python || '',                               // EMSDK_PYTHON ('' = let emcc.bat find python)
    path.join(emsdk, 'upstream', 'emscripten', 'emcc.bat'),
    [
      w(path.join(emsdk, 'upstream', 'bin')),
      w(path.join(emsdk, 'upstream', 'emscripten')),
      w(path.join(emsdk, 'node', '16.20.0_64bit')),
      w(path.join(emsdk, 'node', '16.20.0_64bit', 'bin')),
      'C:\\Windows\\System32',
      'C:\\Windows',
    ].filter(Boolean).join(';'),
  ];
  fs.writeFileSync(path.join(em, 'emcc-launcher.txt'), cfg.join('\n') + '\n');
  return shimHome;
}
const isWindows = process.platform === 'win32';
const emsdkHome = isWindows ? shimHomeForWindows() : emsdk;
if (isWindows) console.log('[web] EMSDK_HOME -> the launcher shim (' + path.relative(UI, emsdkHome) + ')');

// ---- --check ---------------------------------------------------------------
// Prove the toolchain the way as-aot will use it -- spawn `<EMSDK_HOME>/upstream/
// emscripten/emcc` with no shell and with ONLY a PATH in the environment -- and
// print the argv the build would hand to as-aot. No compilation, no staging, ~1 s.
//
// This exists because BOTH failure modes of this arm are invisible from a file
// listing: a `emcc` that cannot be spawned (the Windows gap this runner works
// around) and a web build whose flags were assembled wrong (a native build of the
// same app still looks perfect). tools/buildsh-web.cjs runs exactly this and pins
// the printed argv, so the wiring is checked by the thing that consumes it.
if (process.argv.includes('--check')) {
  let ok = true;
  const say = (label, value) => console.log('[web] check  ' + label + ': ' + value);
  const bad = (label, value) => { ok = false; console.log('[web] CHECK FAILED  ' + label + ': ' + value); };

  // 1) the launcher/emcc itself, under the environment the compiler builds
  const emcc = path.join(emsdkHome, 'upstream', 'emscripten', 'emcc');
  // The PATH is assembled with ':' on purpose: that is exactly what the compiler's
  // webCompileEnv() builds, and on Windows it produces a PATH the shell cannot use --
  // which is precisely the condition the launcher has to survive. A check that used
  // the platform's own delimiter would test an environment the build never has.
  const compilerPath = [path.join(emsdkHome, 'upstream', 'emscripten'),
    path.join(emsdkHome, 'upstream', 'bin'), process.env.PATH || ''].join(':');
  const emccRun = spawnSync(emcc, ['--version'], { encoding: 'utf8', env: { PATH: compilerPath } });
  if (emccRun.error || emccRun.status !== 0) {
    bad('emcc', (emccRun.error && emccRun.error.code)
      || ((emccRun.stderr || '') + (emccRun.stdout || '')).trim().split('\n')[0]
      || ('exit ' + emccRun.status));
  } else {
    say('emcc', (emccRun.stdout || '').trim().split('\n')[0]);
  }

  // 2) the descriptor the page's canvas comes from, and the class that mounts it
  say('descriptor', path.relative(UI, sourceDescriptor) + ' (' + win.w + 'x' + win.h + ')' );
  say('main class', 'demo.DocsWeb');
  if (!fs.existsSync(path.join(here, 'demo', 'DocsWeb.as'))) bad('DocsWeb.as', 'missing under ui-demo/demo/');
  // The staged copy is only meaningful if it is CURRENT -- report a drift instead of
  // letting the next build quietly replace a descriptor someone edited in place.
  const staged = path.join(appDir, 'app.xml');
  if (fs.existsSync(staged)) {
    const same = sha256(staged) === sha256(sourceDescriptor);
    if (same) say('staged descriptor', path.relative(UI, staged) + ' matches the source');
    else bad('staged descriptor', path.relative(UI, staged) + ' DIFFERS from ' + path.relative(UI, sourceDescriptor));
  } else {
    say('staged descriptor', path.relative(UI, appDir) + '/ does not exist yet (not built here)');
  }

  // 3) the flags. The array `web` execs, printed in order, so the gate can pin every
  //    one of them from this output alone.
  say('as-aot', aotArgv().slice(1).join(' '));
  say('output', path.relative(UI, path.join(appDir, BASE)) + '.{html,js,wasm,data}');
  console.log('[web] check ' + (ok ? 'PASS' : 'FAIL'));
  process.exit(ok ? 0 : 1);
}

// ---- stage the web app directory -------------------------------------------
// Everything in it is derived, so the copy is verified rather than trusted: a
// descriptor that silently drifted from the tracked one would move the window
// (canvas size, title) for a reason nobody could find later. Same rule stage-air.cjs
// applies to the sources.
function sha256(p) {
  return crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
}

function stageAppDir() {
  fs.mkdirSync(appDir, { recursive: true });

  // 1) the descriptor, byte for byte
  fs.copyFileSync(sourceDescriptor, path.join(appDir, 'app.xml'));
  if (sha256(sourceDescriptor) !== sha256(path.join(appDir, 'app.xml'))) {
    console.error('[web] the staged descriptor does not match ' + sourceDescriptor);
    process.exit(2);
  }

  // 2) the assets the page loads by relative URL
  const image = path.join(sourceAppDir, 'as-image.png');
  if (fs.existsSync(image)) fs.copyFileSync(image, path.join(appDir, 'as-image.png'));

  // 3) a font. The wasm sandbox enumerates no system fonts, so without one every
  //    TextField renders nothing (the symptom is an app that looks like empty
  //    boxes -- as-aot warns about it, and this arm would rather not ship it).
  const fontsDir = path.join(appDir, 'fonts');
  fs.mkdirSync(fontsDir, { recursive: true });
  if (fs.readdirSync(fontsDir).some((n) => /\.(ttf|otf|ttc)$/i.test(n))) return; // already staged
  const candidates = [
    path.join(process.env.WINDIR || 'C:\\Windows', 'Fonts', 'arial.ttf'),
    '/System/Library/Fonts/Supplemental/Arial.ttf',
    '/Library/Fonts/Arial.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    // The compiler repo ships the same font for its own web examples; used last so
    // a machine with no system font still gets a buildable page.
    path.join(compilerDir, 'examples', 'web', 'fonts', 'Arial.ttf'),
  ];
  const font = candidates.find((p) => fs.existsSync(p));
  if (font) {
    fs.copyFileSync(font, path.join(fontsDir, path.basename(font)));
    console.log('[web] font: ' + path.basename(font) + '  (from ' + font + ')');
  } else {
    console.error('[web] WARNING: no .ttf found to ship -- every TextField in this page will be blank.'
      + '\n             Drop one into ' + path.relative(UI, fontsDir) + '/ and re-run.');
  }
}

if (serveOnly) {
  // Look at a page that was already built (a rebuild is minutes, re-looking is
  // free). Products are still verified below, so "serve nothing" fails instead of
  // handing the browser a 404.
  console.log('[web] --serve-only: serving what is already in ' + appDirName + '/, nothing rebuilt');
} else {
  console.log('[web] staging ' + appDirName + '/ from ' + sourceAppDirName + '/app.xml + demo/');
  stageAppDir();
  {
    // stage-air.cjs copies `demo/**` into <appDir>/src and verifies it byte for byte
    // (a stale copy is the one thing a staging step must never leave behind).
    const r = spawnSync(process.execPath, ['stage-air.cjs', appDirName], { cwd: here, stdio: 'inherit' });
    if (r.status !== 0) {
      console.error('[web] STAGING FAILED (exit ' + r.status + ')');
      process.exit(1);
    }
  }

  // ---- build ----------------------------------------------------------------
  const manifestPath = path.join(appDir, BASE + '.build.json');
  if (fs.existsSync(manifestPath)) fs.unlinkSync(manifestPath);

  const args = aotArgv();

  console.log('[web] building ' + BASE + ' with `--air-app ' + appDirName + '/app.xml --target wasm --package web`');
  console.log('[web] this takes a couple of minutes: emcc compiles the Skia glue for wasm32 too');
  const built = spawnSync(process.execPath, args, {
    cwd: compilerDir,
    stdio: 'inherit',
    // EMSDK_HOME (not an inline `VAR=value` prefix: this workspace's shells drop
    // those across the bash -> node.exe boundary) plus whatever the caller had.
    env: { ...process.env, EMSDK_HOME: emsdkHome },
  });
  if (built.status !== 0) {
    console.error('[web] BUILD FAILED (exit ' + built.status + ')');
    process.exit(1);
  }
}

// ---- what came out ----------------------------------------------------------
const products = ['.html', '.js', '.wasm', '.data'];
const out = [];
for (const ext of products) {
  const p = outputBase + ext;
  if (fs.existsSync(p)) out.push({ name: BASE + ext, bytes: fs.statSync(p).size });
}
for (const o of out) console.log('  ' + o.name + '  ' + (o.bytes / 1048576).toFixed(2) + ' MB');
for (const ext of ['.html', '.js', '.wasm']) {
  if (!out.some((o) => o.name === BASE + ext)) {
    console.error('[web] expected product missing: ' + BASE + ext
      + '\n      (a failed LINK leaves the previous .wasm in place -- see html5-web.md section 1)');
    process.exit(3);
  }
}
console.log('[web] page: ' + path.relative(UI, outputBase + '.html') + '  (' + win.w + 'x' + win.h + ' logical, from ' + sourceAppDirName + '/app.xml)');

// ---- serve ------------------------------------------------------------------
// `file://` cannot load a .wasm (the browser refuses to instantiate from a file
// URL), so a page that is only built is a page nobody can look at. The server below
// is deliberately tiny and local-only; what it does have to get right is the MIME
// type: `.wasm` must be `application/wasm`, or Chrome falls back to ArrayBuffer
// instantiation with two red console lines (harmless, but they read like a crash --
// html5-web.md section 2).
const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.wasm': 'application/wasm',
  '.data': 'application/octet-stream',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.ttc': 'font/collection',
  '.xml': 'application/xml; charset=utf-8',
  '.txt': 'text/plain; charset=utf-8',
};

function startServer(preferredPort, tries) {
  const server = http.createServer((req, res) => {
    const url = decodeURIComponent((req.url || '/').split('?')[0]);
    const rel = url === '/' ? '/' + BASE + '.html' : url;
    const file = path.join(appDir, path.normalize(rel).replace(/^[\\/]+/, ''));
    // Refuse anything that escaped the app dir: this listens on a real port, and a
    // static server is exactly the shape a `..` traversal needs.
    if (!file.startsWith(appDir)) {
      res.writeHead(403).end('forbidden');
      return;
    }
    fs.readFile(file, (err, buf) => {
      if (err) {
        res.writeHead(404, { 'content-type': 'text/plain' }).end('404 ' + rel);
        return;
      }
      res.writeHead(200, {
        'content-type': MIME[path.extname(file).toLowerCase()] || 'application/octet-stream',
        'cache-control': 'no-store',
      }).end(buf);
    });
  });
  server.on('error', (e) => {
    if (e.code === 'EADDRINUSE' && tries > 0) {
      console.log('[web] port ' + preferredPort + ' is busy, trying ' + (preferredPort + 1));
      startServer(preferredPort + 1, tries - 1);
      return;
    }
    console.error('[web] server error: ' + e.message);
    process.exit(1);
  });
  server.listen(preferredPort, '127.0.0.1', () => {
    const url = 'http://127.0.0.1:' + preferredPort + '/' + BASE + '.html';
    console.log('[web] serving ' + path.relative(UI, appDir) + '  ->  ' + url);
    // A browser opened on the page is the whole point of this arm, and the same
    // ASC_NO_OPEN switch the native runner honours keeps an automated call quiet.
    if (process.env.ASC_NO_OPEN !== '1') {
      if (process.platform === 'win32') spawn('cmd', ['/c', 'start', '', url], { stdio: 'ignore', detached: true }).unref();
      else if (process.platform === 'darwin') spawn('open', [url], { stdio: 'ignore', detached: true }).unref();
      else spawn('xdg-open', [url], { stdio: 'ignore', detached: true }).unref();
    }
    console.log('[web] the page is live -- Ctrl-C stops the server (the build products stay on disk)');
  });
}

if (serve) {
  startServer(port, 20);
} else {
  console.log('[web] --no-serve: serve ' + path.relative(UI, appDir)
    + '/ over HTTP to open it (a .wasm cannot be loaded from file://)');
}
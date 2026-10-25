// buildsh-web.cjs -- pin `ui-demo/air-gallery/build.sh web`.
//
// WHY THIS EXISTS. The web arm is the one arm whose failure is invisible from a file
// listing. A native build that went wrong produces no exe and you notice; a web build
// can produce `GalleryApp.html/.js/.wasm` that load, paint the wrong thing, or load the
// PREVIOUS build off the server cache, and every one of those looks like a directory
// with three files in it. Two specific ways to get there:
//
//   1) The toolchain is not really reachable. `as-aot --package web` launches emcc
//      itself -- on Windows through cmd.exe, because the SDK's `emcc` is a POSIX
//      wrapper (compiler-gaps.md G27, fixed in v0.4.240). Before that fix this gate
//      had to spawn emcc through a hand-built environment and pinned the PE launcher
//      this workspace stood in front of it. Both are gone: the question "can emcc
//      start?" is now answered by the compiler (`as-aot doctor`), and the gate
//      checks that answer instead of re-implementing it.
//   2) The flags are assembled wrong. `--target wasm` without `--package web` builds a
//      wasm executable nobody can open; `--package web` without `--target wasm` is
//      refused by the compiler; a native main class compiles fine and produces a page
//      that never mounts (DocsAir cannot compile for wasm at all -- it imports
//      UncaughtErrorEvent -- and DocsMain drives Stage.render, an AOT-only test hook).
//
// SO WHAT IS PINNED, exactly:
//   A. the toolchain: `web --check` exits 0 and reports a program that STARTED and
//      answered -- the one the compiler named, inside the SDK root, with nothing in
//      between -- and the mirror image: an SDK whose emcc exists but exits nonzero is
//      NOT reported as usable (a stub that looks like a toolchain must not pass);
//   B. the argv: wasm target, web package, `demo.DocsWeb` and no other entry class,
//      the web app dir's descriptor and output prefix, both shared class roots, and no
//      native window backend;
//   C. the descriptor is the window: the size the check reports is the one in app.xml
//      (read here, not hard-coded, so resizing the window is not a gate failure), and
//      the tracked app.xml is byte-identical afterwards;
//   D. refusals, because an option that is silently accepted is worse than one that is
//      absent: `--gpu` on this arm (a browser composites itself), an unknown flag, and
//      an EMSDK_HOME that points at something which is not an emsdk;
//   E. the generated app dir stays untracked -- including its app.xml and as-image.png,
//      which the `air-*` negations in .gitignore would otherwise re-include.
//
// WHAT IT DOES NOT DO: compile anything. The full build takes ~3 minutes and its
// product was measured by hand (page0 sample grid + colour histogram against
// air-gallery/gallery-page0.png, re-measured after v0.4.239 turned antialiasing on in
// both arms: 46/48 sample points identical, ink within 0.85%, and the leftovers are all
// glyphs -- the page ships its own font). `--check` is the same decision path with the
// build left out, which is what a gate can afford to run on every invocation (~0.3 s).
//
//   usage:    node tools/buildsh-web.cjs
//   exit:     0 all checks pass, 1 some check failed
'use strict';
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const HERE = __dirname;                       // .../asaotui/tools
const UI = path.dirname(HERE);                // .../asaotui
const APP = path.join(UI, 'ui-demo', 'air-gallery');
const WEBAPP = path.join(UI, 'ui-demo', 'air-gallery-web');
const XML = path.join(APP, 'app.xml');

const checks = [];
function check(ok, what, detail) {
  checks.push({ ok, what, detail });
  if (!ok && detail) console.log('  FAIL: ' + what + '\n        ' + detail);
}

const read = (f) => fs.readFileSync(f, 'utf8');
const rm = (f) => { try { fs.unlinkSync(f); } catch (e) { /* absent */ } };

function buildsh(args, env) {
  const r = spawnSync('bash', ['build.sh', ...args], {
    cwd: APP, encoding: 'utf8', env: env ? { ...process.env, ...env } : process.env,
  });
  const out = ((r.stdout || '') + (r.stderr || '')).replace(/\r/g, '');
  return { out, status: r.status, lines: out.split('\n') };
}

// NOTHING STALE MAY SURVIVE THE START. A descriptor this gate once derived, or a
// hand-made one, would satisfy "was it created?" without build.sh doing anything.
for (const m of ['gl', 'd3d12', 'gpu', 'cpu', 'direct']) rm(path.join(APP, 'app.' + m + '.xml'));

const appXml = read(XML);
const appXmlBefore = appXml;
const size = (re) => (re.exec(appXml) || [])[1];
const wantW = size(/<width>(\d+)<\/width>/);
const wantH = size(/<height>(\d+)<\/height>/);

// ---- A + B + C: one `--check`, which is the arm's own decision path ----------
const r = buildsh(['web', '--check']);
check(r.status === 0, '`build.sh web --check` exits 0', 'exit ' + r.status + '\n' + r.out.slice(-600));
check(/check PASS/.test(r.out), 'the check reports PASS', r.out.slice(-400));

// A1. The compiler must be able to start emcc. `--check` asks `as-aot doctor`, so the
// verdict comes from the same function the build runs before it starts (and from the
// same platform branch). "The file exists" would pass with a 0-byte emcc; a version
// triple from our own spawn -- what this gate used to pin -- only proves a COPY of
// the launch logic works, which is exactly how G27 stayed invisible for a round.
const emccLine = r.lines.find((l) => /check\s+emcc:/.test(l)) || '';
check(/check\s+emcc:\s+ok -- \S/.test(emccLine),
  'the compiler can start emcc for a web build', emccLine || 'no emcc line');
// ...and the program it named is the SDK's own entry point. This is the anti-shim
// assertion: anything standing between the compiler and emcc lives OUTSIDE
// $EMSDK_HOME/upstream/emscripten, so `path.relative` stops naming exactly that one file.
{
  const sdk = (r.lines.find((l) => /check\s+emsdk:/.test(l)) || '').split(/check\s+emsdk:\s*/)[1] || '';
  const program = (emccLine.split(' -- ')[1] || '').trim();
  const want = path.join('upstream', 'emscripten', process.platform === 'win32' ? 'emcc.bat' : 'emcc');
  const rel = (sdk && program) ? path.relative(sdk.trim(), program) : '';
  check(rel === want,
    'the program it names is the SDK\u2019s own ' + want.replace(/\\/g, '/') + ' (nothing in between)',
    'doctor named ' + (program || '?') + ' (SDK ' + (sdk || '?') + ')');
}

// A2. The mirror image, because a check that only ever sees a working toolchain
// cannot tell "it works" from "I stopped looking". An SDK whose emcc EXISTS but exits
// nonzero must come back unusable -- that is the G27 shape seen from the other side:
// a stub that looks exactly like a toolchain in a directory listing.
{
  const fake = path.join(UI, '.scratch', 'fake-emsdk');
  const em = path.join(fake, 'upstream', 'emscripten');
  fs.mkdirSync(em, { recursive: true });
  const entry = path.join(em, process.platform === 'win32' ? 'emcc.bat' : 'emcc');
  fs.writeFileSync(entry, process.platform === 'win32' ? '@echo off\r\nexit /b 1\r\n' : '#!/bin/sh\nexit 1\n');
  if (process.platform !== 'win32') fs.chmodSync(entry, 0o755);
  try {
    const f = buildsh(['web', '--check'], { EMSDK_HOME: fake, EMSDK: '' });
    check(f.status !== 0 && /CHECK FAILED\s+emcc/.test(f.out),
      'an emcc that exists but exits nonzero is NOT reported as usable',
      'exit ' + f.status + '\n' + f.out.slice(-400));
  } finally {
    fs.rmSync(fake, { recursive: true, force: true });
  }
}

// B. the argv, token by token. Pinning the whole line would fail on a path rename;
// pinning nothing would pass on a `--target native`.
const aot = (r.lines.find((l) => /check\s+as-aot:/.test(l)) || '').split(/check\s+as-aot:\s*/)[1] || '';
const has = (s) => aot.includes(s);
check(has('--target wasm'), 'the build asks for the wasm target', aot);
check(has('--package web'), 'the build asks for the web package', aot);
check(has('--main-class demo.DocsWeb'), 'the entry class is demo.DocsWeb', aot);
// The two entry classes that MUST NOT be used here, each for its own reason.
check(!/--main-class demo\.Docs(Air|Main)\b/.test(aot),
  'not DocsAir/DocsMain (wasm cannot compile the first; the second drives Stage.render)', aot);
check(has('--air-app ') && has('air-gallery-web' + path.sep + 'app.xml'),
  'the descriptor is the web app dir copy, not air-gallery/app.xml', aot);
check(has('-o ') && has(path.join('air-gallery-web', 'GalleryApp')),
  'the products land in the web app dir', aot);
// The two shared source roots are passed by ABSOLUTE path (app.xml does not live next
// to them), so the tail segment is what identifies them.
check(/--as-class-path \S*[\\/]seam(\s|$)/.test(aot) && /--as-class-path \S*[\\/]kit(\s|$)/.test(aot),
  'both shared class roots are passed (seam, kit)', aot);
check(!has('--gpu-backend'), 'no native window backend is passed to a browser build', aot);

// C1. The size in the report is the size in app.xml -- both, never a constant.
const sized = r.lines.find((l) => /check\s+descriptor:/.test(l)) || '';
check(wantW && wantH && sized.includes('(' + wantW + 'x' + wantH + ')'),
  'the reported page size is app.xml\"s <width>x<height> (' + wantW + 'x' + wantH + ')',
  sized || 'no descriptor line');
// C2. The staged copy is verified byte-for-byte, and only when it exists.
if (fs.existsSync(path.join(WEBAPP, 'app.xml'))) {
  const staged = r.lines.find((l) => /check\s+staged descriptor:/.test(l)) || '';
  check(/matches the source/.test(staged), 'the staged descriptor matches air-gallery/app.xml', staged);
}
// C3. No arm may rewrite the tracked descriptor.
check(read(XML) === appXmlBefore, 'air-gallery/app.xml is untouched by the web arm');

// ---- D: refusals ------------------------------------------------------------
{
  // `--check` keeps this bounded: if the guard ever stops firing, the arm proceeds
  // and the check still exits in ~1 s instead of starting a three-minute wasm build.
  const g = buildsh(['web', '--gpu', 'gl', '--check']);
  check(g.status !== 0 && /--gpu does not apply to the web arm/.test(g.out),
    '`web --gpu gl` is refused with a reason', 'exit ' + g.status + '\n' + g.out.slice(-300));
}
{
  const u = buildsh(['web', '--nonsense']);
  check(u.status === 2 && /unknown option/.test(u.out),
    'an unknown web flag is an error (not ignored)', 'exit ' + u.status + '\n' + u.out.slice(-300));
}
{
  // A named-but-wrong SDK must not fall back to the workspace copy (that would build
  // the page with a toolchain nobody asked for, silently).
  const bad = path.join(UI, '.scratch', 'no-such-emsdk');
  const e = buildsh(['web', '--check'], { EMSDK_HOME: bad, EMSDK: '' });
  check(e.status !== 0 && /is not an emsdk root/.test(e.out),
    'an EMSDK_HOME that is not an emsdk is an error, not a fallback', 'exit ' + e.status + '\n' + e.out.slice(-300));
}

// ---- E: the generated dir stays out of the index ----------------------------
// The `air-*` block in .gitignore re-includes app.xml / as-image.png / build.sh, which
// is right for the two tracked AIR apps and wrong for the derived web one. Order
// matters in .gitignore, so this is checked through git rather than by reading the file.
for (const f of ['app.xml', 'as-image.png', 'build.sh']) {
  const p = path.join('ui-demo', 'air-gallery-web', f);
  const g = spawnSync('git', ['check-ignore', '-q', '--no-index', p], { cwd: UI });
  check(g.status === 0, 'ui-demo/air-gallery-web/' + f + ' is git-ignored', 'git check-ignore says: not ignored');
}
// ...while the tracked sources it is built FROM stay tracked.
for (const f of ['app.xml', 'as-image.png', 'build.sh']) {
  const p = path.join('ui-demo', 'air-gallery', f);
  const g = spawnSync('git', ['check-ignore', '-q', '--no-index', p], { cwd: UI });
  check(g.status !== 0, 'ui-demo/air-gallery/' + f + ' is NOT ignored (it is the input)', 'it became ignored');
}

// ---- F: the usage text and the code agree ----------------------------------
{
  const h = buildsh(['--help']);
  check(h.status === 0 && /\bweb\b/.test(h.out) && /--check/.test(h.out),
    '`--help` documents the web arm and its flags', h.out.slice(0, 400));
}

const bad = checks.filter((c) => !c.ok);
console.log('buildsh-web: ' + checks.length + ' checks, ' + bad.length + ' failures');
for (const c of checks) console.log('  ' + (c.ok ? 'ok  ' : 'FAIL') + ' ' + c.what);
process.exit(bad.length === 0 ? 0 : 1);
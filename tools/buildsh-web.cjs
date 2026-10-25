// buildsh-web.cjs -- pin `ui-demo/air-gallery/build.sh web`.
//
// WHY THIS EXISTS. The web arm is the one arm whose failure is invisible from a file
// listing. A native build that went wrong produces no exe and you notice; a web build
// can produce `GalleryApp.html/.js/.wasm` that load, paint the wrong thing, or load the
// PREVIOUS build off the server cache, and every one of those looks like a directory
// with three files in it. Two specific ways to get there:
//
//   1) The toolchain is not really reachable. `as-aot --package web` spawns
//      `<EMSDK_HOME>/upstream/emscripten/emcc` directly, with no shell, and hands it an
//      env whose ONLY entry is a PATH. On this box that file is a `#!/bin/sh` script, so
//      the spawn fails (compiler-gaps.md G27) and `web-gallery.cjs` stands a PE launcher
//      in front of it. Whether that launcher works cannot be checked by looking at it:
//      it is checked by spawning `emcc --version` through the same env the build uses.
//   2) The flags are assembled wrong. `--target wasm` without `--package web` builds a
//      wasm executable nobody can open; `--package web` without `--target wasm` is
//      refused by the compiler; a native main class compiles fine and produces a page
//      that never mounts (DocsAir cannot compile for wasm at all -- it imports
//      UncaughtErrorEvent -- and DocsMain drives Stage.render, an AOT-only test hook).
//
// SO WHAT IS PINNED, exactly:
//   A. the toolchain: `web --check` exits 0 and reports a real `emcc <version>`;
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
// product was measured by hand when the arm landed (page0 sample grid + colour
// histogram against air-gallery/gallery-page0.png: 44/48 sample points identical, and
// the 8 most common colours within 0.3% -- the differences are glyph antialiasing).
// `--check` is the same decision path with the build left out, which is what a gate can
// afford to run on every invocation.
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

// A1. emcc really ran. A version triple is the cheapest proof that a process started
// and answered; "the file exists" would pass with a 0-byte emcc.
const emccLine = r.lines.find((l) => /check\s+emcc:/.test(l)) || '';
check(/\d+\.\d+\.\d+/.test(emccLine), 'emcc is spawnable and answers --version', emccLine || 'no emcc line');
// ...and it must be the SHIM's emcc on Windows, because that is what the build uses.
if (process.platform === 'win32') {
  const home = r.lines.find((l) => /EMSDK_HOME ->/.test(l)) || '';
  check(/launcher shim/.test(home), 'EMSDK_HOME points at the launcher shim on Windows', home || 'no EMSDK_HOME line');
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
// buildsh-gpu.cjs -- pin `ui-demo/air-gallery/build.sh --gpu <mode>`.
//
// WHY THIS EXISTS. `--gpu` changes three things at once and none of them change the
// picture: the same 42 pages render the same pixels whether the window composes on
// the CPU, on a GPU, or through an OpenGL bridge. So "I ran it and it looked fine"
// proves nothing at all -- a mode that is parsed and then dropped is invisible.
// What is observable is the DESCRIPTOR and the ARGV, which is what this checks:
//
//   1) The mode table. `gl`/`d3d12` mean renderMode=gpu PLUS a named backend, `cpu`
//      and `direct` mean their own renderMode and no backend, `gpu` means
//      renderMode=gpu with the platform's own choice. A wrong mapping here is the
//      whole feature being wrong.
//   2) app.xml is NOT TOUCHED. `ui-demo/check-dpi.cjs` requires air-gallery/app.xml
//      and air-gallery-standard/app.xml to differ in exactly ONE line
//      (requestedDisplayResolution). A `--gpu` that rewrote the tracked descriptor
//      would make the DPI A/B two-variable and redden it for a reason unrelated to
//      HiDPI -- which happened once, by hand. So: sha256 unchanged, and each derived
//      descriptor is required to be app.xml with exactly one line replaced.
//   3) The default arm stays byte-for-byte the old behaviour: no `--gpu` passes
//      neither `--app-xml` nor `--gpu-backend`.
//   4) A typo is refused, not silently treated as the default (AGENTS.md section 2.5).
//
// HOW IT RUNS IN TWO SECONDS: the `desc` arm derives the descriptor and prints the
// argv the `aot` arm would exec -- both come from the same variables (`$DESC`,
// `$BACKEND`) and the same `aot_args()` function, so this is not a re-implementation
// of the build, it is the build's own decision path with the build left out. The two
// consumer arms (adl, as-aot) were measured for real on 2026-10-25: `aot --gpu gl`
// built with ASC_RENDER_GL=1 and toured 41/42 pages, `aot --gpu gpu` with
// ASC_RENDER_D3D=1, `air --gpu gl` opened under adl -- and `run-gallery.cjs` asserts
// on every future run that a gpu mode really reached the generated manifest.
//
// PATHS: `bash` here is the WSL/bash.exe this project's scripts already run under; it
// resolves `/mnt/<drive>/...` but not `/c/...` (measured), and a `C:\...` argument
// loses its backslashes on the way in. So the script is invoked by its RELATIVE name
// with cwd = the app dir, which needs no conversion at all.
//
//   usage:    node tools/buildsh-gpu.cjs        (exit 0 = all checks pass)
//   mutation: tools/mutation-buildsh-gpu.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const HERE = __dirname;                       // .../asaotui/tools
const UI = path.dirname(HERE);                // .../asaotui
const APP = path.join(UI, 'ui-demo', 'air-gallery');
const XML = path.join(APP, 'app.xml');

const checks = [];
function check(ok, what, detail) {
  checks.push({ ok, what, detail });
  if (!ok && detail) console.log('  FAIL: ' + what + '\n        ' + detail);
}

const sha = (f) => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const read = (f) => fs.readFileSync(f, 'utf8');
const rm = (f) => { try { fs.unlinkSync(f); } catch (e) { /* absent */ } };

const MODES = [
  { flag: 'cpu', render: 'cpu', backend: null },
  { flag: 'gpu', render: 'gpu', backend: null },
  { flag: 'd3d12', render: 'gpu', backend: 'd3d12' },
  { flag: 'gl', render: 'gpu', backend: 'gl' },
  { flag: 'direct', render: 'direct', backend: null },
];

// NOTHING STALE MAY SURVIVE THE START: a descriptor left behind by an earlier run or
// by hand would satisfy "was it written?" without build.sh producing anything.
for (const m of MODES) rm(path.join(APP, 'app.' + m.flag + '.xml'));

function buildsh(args) {
  const r = spawnSync('bash', ['build.sh', ...args], { cwd: APP, encoding: 'utf8' });
  const out = (r.stdout || '') + (r.stderr || '');
  return { out, status: r.status, args: out.split(/\r?\n/).filter((l) => l.includes('[build]')).join('\n') };
}

const appXmlBefore = sha(XML);
const appXml = read(XML);
const appRender = (/<renderMode>([^<]*)<\/renderMode>/.exec(appXml) || [])[1];
const derived = [];

// `gl` is the WGL/OpenGL bridge: Windows-only, and build.sh REFUSES it elsewhere
// (macOS composites on Metal). That refusal is a fact worth pinning too, so the mode
// is not dropped from the table -- it is asserted against the expectation the host
// can actually have. Without this the gate reported two reds on every macOS run for
// a behaviour that is correct.
const WINDOWS_ONLY = new Set(['gl']);
for (const m of MODES) {
  const r = buildsh(['desc', '--gpu', m.flag]);
  const name = 'app.' + m.flag + '.xml';
  const file = path.join(APP, name);
  if (WINDOWS_ONLY.has(m.flag) && process.platform !== 'win32') {
    check(r.status !== 0, '--gpu ' + m.flag + ' is refused off Windows', 'exit ' + r.status);
    check(/Windows-only/.test(r.out), '--gpu ' + m.flag + ' refusal says why', r.out.slice(-400));
    check(!fs.existsSync(file), '--gpu ' + m.flag + ' writes no descriptor when refused', name);
    continue;
  }
  check(r.status === 0, '--gpu ' + m.flag + ' exits 0', 'exit ' + r.status + '\n' + r.out.slice(-400));
  if (!fs.existsSync(file)) {
    check(false, '--gpu ' + m.flag + ' derives ' + name, 'not written\n' + r.args);
    continue;
  }
  derived.push(name);
  const text = read(file);

  const tag = /<renderMode>([^<]*)<\/renderMode>/.exec(text);
  check(tag !== null && tag[1] === m.render,
    '--gpu ' + m.flag + ' writes <renderMode>' + m.render + '</renderMode>',
    tag ? 'got ' + JSON.stringify(tag[1]) : 'no <renderMode> at all');

  // app.xml with ONLY its <renderMode> line replaced -- the invariant that keeps the
  // DPI A/B meaningful, checked literally rather than by eye. `--gpu cpu` derives a
  // file identical to app.xml (that IS the tracked mode), so zero differences is
  // correct there and a second differing line is never correct.
  const a = appXml.split(/\r?\n/);
  const b = text.split(/\r?\n/);
  // NB: app.xml's header COMMENT also mentions `<renderMode>` (prose, no closing tag),
  // so the line is located with the full pattern rather than the opening tag alone.
  const renderLine = a.findIndex((l) => /<renderMode>[^<]*<\/renderMode>/.test(l));
  const diffs = [];
  if (a.length !== b.length) diffs.push('line count ' + a.length + ' -> ' + b.length);
  else for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) diffs.push(i + 1);
  const allowed = m.render === appRender ? 0 : 1;
  check(diffs.length === allowed && (diffs.length === 0 || diffs[0] === renderLine + 1),
    '--gpu ' + m.flag + ' changes nothing but the <renderMode> line',
    'differs on line(s) ' + JSON.stringify(diffs) + ' (renderMode is line ' + (renderLine + 1) +
    ', app.xml already says ' + JSON.stringify(appRender) + ')');

  // What the aot arm would be told.
  check(r.out.includes('--app-xml ' + name), '--gpu ' + m.flag + ' passes --app-xml ' + name, r.args);
  const wantBackend = m.backend ? '--gpu-backend ' + m.backend : null;
  if (wantBackend) {
    check(r.out.includes(wantBackend), '--gpu ' + m.flag + ' passes ' + wantBackend, r.args);
  } else {
    check(!r.out.includes('--gpu-backend'),
      '--gpu ' + m.flag + ' names no backend (the platform default)', r.args);
  }
}

// The default arm: no --gpu at all.
{
  const r = buildsh(['desc']);
  check(r.status === 0, 'plain `desc` exits 0', 'exit ' + r.status + '\n' + r.out.slice(-300));
  check(/tracked app\.xml/.test(r.out) && !r.out.includes('--app-xml'),
    'plain `desc` says it builds from the tracked app.xml, passing no extra args', r.args);
}

// A typo must not build the default window while claiming otherwise.
{
  const r = buildsh(['desc', '--gpu', 'gl2']);
  check(r.status !== 0 && /unknown --gpu/.test(r.out),
    'an unknown --gpu mode is refused', 'exit ' + r.status + '\n' + r.out.slice(-300));
}

check(sha(XML) === appXmlBefore, 'app.xml is byte-identical after all of the above');

// Housekeeping: the derived descriptors are this gate's own artifacts (also gitignored
// via `/ui-demo/air-*/*`), removed so a later `git status` stays clean.
for (const n of derived) rm(path.join(APP, n));

const bad = checks.filter((c) => !c.ok);
console.log('buildsh-gpu: ' + checks.length + ' checks, ' + bad.length + ' failures');
for (const c of checks) if (c.ok) console.log('  ok   ' + c.what);
process.exit(bad.length === 0 ? 0 : 1);
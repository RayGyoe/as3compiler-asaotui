// stage-air.cjs -- materialize the AIR app source tree that `as-aot --air-app`
// insists on, WITHOUT copying the shared toolkit into it.
//
// Usage:   node stage-air.cjs <app-dir>      e.g. node stage-air.cjs air-gallery
//
// WHY THIS EXISTS (and why it got smaller, 阶段二百五十)
// -----------------------------------------------------
// Our toolkit (`../kit/asaot/ui/**`) and the layout seam (`../seam/asaot/ui/**`)
// are trees shared with the probes, the layout checks and CheckUi. Until
// `--as-class-path` existed, `--air-app` walked exactly `<appDir>/src` and nothing
// else, so the ONLY way to make the AIR-app path see them was to copy them in --
// and every demo ended up carrying a byte-identical 91-file copy of the toolkit
// under its own `src/asaot/`.
//
// `--as-class-path <dir>` (repeatable) makes those trees source ROOTS, so the
// build reads them where they live. This script now stages ONLY the demo's own
// sources (the app's real `src/`), and prints the two roots the build must name.
//
// The two roots are passed to the compiler by run-gallery.cjs / check-dpi.cjs
// (see SHARED_ROOTS below, which is the single place they are listed). A stale or
// divergent copy can no longer exist: there is no copy.
//
// Why the app's own sources are still copied rather than named as a root: `src/`
// is what an AIR project actually has, and `--air-app` resolves the descriptor's
// fonts / preload tree / extension dirs relative to the APP DIRECTORY, so the
// app-shaped tree is worth keeping intact. The demo is one tree, not three.
//
// Copies are only trustworthy if they are provably current, so this file:
//   * wipes `<appDir>/src` first (never patches it up: a deleted source must not
//     survive as a stale copy),
//   * copies the app's own `demo/**` sources,
//   * re-reads every staged file and compares it BYTE FOR BYTE against its
//     source, loudly failing otherwise,
//   * prints a content hash of the staged tree, so a build log identifies the
//     exact bytes that were compiled.
//
// `<appDir>/app.xml` is NOT generated here: the descriptor is a reviewed source
// file (it is where requestedDisplayResolution/renderMode/size live), and this
// script refuses to run without one.
'use strict';

const path = require('path');
const fs = require('fs');
const crypto = require('crypto');

const UI = path.resolve(__dirname, '..');          // asaotui/
const here = __dirname;                            // asaotui/ui-demo/

// The source roots the build compiles IN ADDITION to `<appDir>/src`. Listed here
// once so the stager, the log and the two runners cannot drift apart.
const SHARED_ROOTS = [
  path.join(UI, 'seam'),
  path.join(UI, 'kit'),
];

// The demo's own sources (package `demo`). Both demos share this package, and
// reach.ts prunes whatever the document class cannot reach.
const APP_ROOT = path.join(here, 'demo');

function walk(dir, out) {
  if (!fs.existsSync(dir)) return out;
  const entries = fs.readdirSync(dir, { withFileTypes: true })
    .sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
  for (const e of entries) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    // `.as` only: `NativeLayoutEngine.as.doc` is documentation for a
    // compiler-emitted built-in, so it is not a compilation unit.
    else if (e.name.endsWith('.as')) out.push(p);
  }
  return out;
}

const appDirName = process.argv[2];
if (!appDirName) {
  console.error('usage: node stage-air.cjs <app-dir>     (e.g. air-gallery)');
  process.exit(2);
}
const appDir = path.resolve(here, appDirName);
const descriptor = path.join(appDir, 'app.xml');
if (!fs.existsSync(descriptor)) {
  console.error('[stage-air] no descriptor at ' + descriptor
    + ' -- the descriptor is a reviewed source file, not something this script writes');
  process.exit(2);
}

const src = path.join(appDir, 'src');
fs.rmSync(src, { recursive: true, force: true });
fs.mkdirSync(src, { recursive: true });

const hash = crypto.createHash('sha256');
let staged = 0;
const problems = [];

for (const f of walk(APP_ROOT, [])) {
  const rel = path.relative(APP_ROOT, f).split(path.sep).join('/');
  const dst = path.join(src, rel.split('/').join(path.sep));
  fs.mkdirSync(path.dirname(dst), { recursive: true });
  const bytes = fs.readFileSync(f);
  fs.writeFileSync(dst, bytes);
  // Verify the copy is current, byte for byte. A silent short/mismatched write
  // would make the build compile something nobody wrote.
  const back = fs.readFileSync(dst);
  if (!back.equals(bytes)) problems.push(rel + ' (staged bytes differ from ' + f + ')');
  hash.update(rel).update('\0').update(bytes);
  staged++;
}

if (problems.length) {
  console.error('[stage-air] STAGING NOT FAITHFUL:');
  for (const p of problems) console.error('  ' + p);
  process.exit(1);
}

const digest = hash.digest('hex').slice(0, 16);
console.log('[stage-air] ' + appDirName + '/src <- demo = ' + staged + ' .as units, content ' + digest);
console.log('[stage-air] shared roots (pass as --as-class-path, NOT copied):');
for (const r of SHARED_ROOTS) console.log('[stage-air]   ' + path.relative(here, r).split(path.sep).join('/'));
console.log('[stage-air] descriptor ' + path.relative(UI, descriptor).split(path.sep).join('/')
  + ' (requestedDisplayResolution/renderMode/size come from here)');
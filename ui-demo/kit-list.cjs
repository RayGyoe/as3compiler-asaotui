// kit-list.cjs -- the asaot.ui source units, as paths RELATIVE TO as3compiler/.
//
// The layout seam (LayoutEngine + the pure-AS3 As3LayoutEngine) and the toolkit
// are separate source trees, and the AOT driver needs every .as unit named
// explicitly (it has no per-source-path auto-discovery). This list is derived by
// WALKING the two trees instead of being hand-maintained, so adding a widget
// file never means editing this file (and two parallel authors never collide
// here).
//
// STAGING OVERLAY (ASC_KIT_OVERLAY)
// ---------------------------------
// Set `ASC_KIT_OVERLAY=staging/<name>[;<dir>...]` to build against a directory
// that MIRRORS the `asaot/ui/...` layout. A file in an overlay shadows the
// base-kit file at the same relative path, and new files are simply added.
//
// Why: several authors work on different widgets at the same time, and each
// build compiles the WHOLE kit. Without an overlay, one author's half-written
// trio would break every other author's build. With it, each author iterates in
// their own staging dir and only lands complete files in `kit/`.
//
// NOTE ON FILE NAMES: mxmlc (the AIR reference compiler) requires every
// externally-visible definition to live in a file named after it, and this box
// has a case-insensitive filesystem. That is why the top-level factories live in
// lowercase files (`box.as`) while their classes are `BoxNode.as`.
//
// NOTE ON `.as.doc`: `seam/asaot/ui/native/NativeLayoutEngine.as.doc` is
// documentation for a compiler-emitted built-in class, NOT a compilable unit.
// The `.as` suffix filter excludes it by construction.
'use strict';

const fs = require('fs');
const path = require('path');

const UI = path.resolve(__dirname, '..');

function walk(dir, out) {
  if (!fs.existsSync(dir)) return out;
  const entries = fs.readdirSync(dir, { withFileTypes: true })
    .sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
  for (const e of entries) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.as')) out.push(p);
  }
  return out;
}

const rel = (p) => '../asaotui/' + path.relative(UI, p).split(path.sep).join('/');

const overlayDirs = (process.env.ASC_KIT_OVERLAY || '')
  .split(';')
  .map((d) => d.trim())
  .filter(Boolean)
  .map((d) => path.resolve(UI, d));

// relInKit -> absolute path, for every overlay unit.
const shadow = new Map();
const overlayFiles = [];
for (const d of overlayDirs) {
  for (const f of walk(d, [])) {
    const key = path.relative(d, f).split(path.sep).join('/');
    shadow.set(key, f);
    overlayFiles.push(f);
  }
}

const SEAM = walk(path.join(UI, 'seam'), []).map(rel);

const KIT = [];
for (const f of walk(path.join(UI, 'kit'), [])) {
  // A base-kit file is replaced by an overlay file at the same relative path.
  const key = path.relative(path.join(UI, 'kit'), f).split(path.sep).join('/');
  if (shadow.has(key)) continue;
  KIT.push(rel(f));
}
for (const f of overlayFiles) KIT.push(rel(f));

module.exports = { SEAM, KIT, ALL: SEAM.concat(KIT) };

// `node kit-list.cjs` prints the resolved list (handy when a build fails with
// "class not found": confirm the file is actually in the list).
if (require.main === module) {
  if (overlayDirs.length) console.log('OVERLAY: ' + overlayDirs.map((d) => path.relative(UI, d)).join(' ; '));
  console.log('SEAM (' + SEAM.length + ')');
  for (const f of SEAM) console.log('  ' + f);
  console.log('KIT (' + KIT.length + ')');
  for (const f of KIT) console.log('  ' + f);
  console.log('TOTAL ' + (SEAM.length + KIT.length));
}
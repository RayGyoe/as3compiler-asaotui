// tools/hex-scan.cjs -- who still hard-codes a colour, and how many.
//
// WHY THIS EXISTS: since 2026-10-27 the kit ships a dark palette, so a literal
// `0xRRGGBB` in a widget is no longer a style choice -- it is a THEME DEFECT that only
// shows up after `Theme.setTheme(ThemeTokens.dark())`. This is the maintenance scan
// behind `reviews/theme-2026-10-27.md` §6 and the colour rule in
// CONTRIBUTING-widget.md §2e.
//
// NOT every hit is a defect. The legitimate ones, and the only ones left in `kit/`:
//   * `ThemeTokens.as` -- that file IS the palette (the literals are the point);
//   * `style/Fill.as`   -- alpha/mask sentinels and the `<= 0xFFFFFF` opaque shortcut;
//   * `style/BoxShadow.as` -- shadow ink, not a surface colour;
//   * `anim/Anim.as`, `PaintKit.as` -- animation/mask constants;
//   * `kind/IconWidget.as`, `kind/DividerWidget.as`, `kind/TableWidget.as` -- measured
//      and classified in the review (icon fallback ink, hairline, transparent hit rect).
// Anything NEW outside `ThemeTokens.as` needs the same treatment: read the palette.
//
// USAGE (from asaotui/):
//   node tools/hex-scan.cjs            # every hit, file by file, plus the total
//   node tools/hex-scan.cjs --count    # just `path (n)` lines and the total
'use strict';

const fs = require('fs');
const path = require('path');

const UI = path.resolve(__dirname, '..');
const countOnly = process.argv.indexOf('--count') >= 0;

function walk(dir, out) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.name === '.git' || e.name === 'node_modules') continue;
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (p.endsWith('.as')) out.push(p);
  }
  return out;
}

const rows = [];
let total = 0;
for (const f of walk(path.join(UI, 'kit'), [])) {
  const rel = path.relative(UI, f).split(path.sep).join('/');
  const hits = [];
  fs.readFileSync(f, 'utf8').split('\n').forEach((l, i) => {
    const code = l.replace(/\/\/.*$/, '');
    if (!/0x[0-9A-Fa-f]{6,8}\b/.test(code)) return;
    hits.push({ n: i + 1, t: l.trim() });
  });
  if (hits.length) { rows.push({ rel, hits }); total += hits.length; }
}

rows.sort((a, b) => b.hits.length - a.hits.length);
for (const r of rows) {
  console.log(r.rel + '  (' + r.hits.length + ')');
  if (countOnly) continue;
  for (const h of r.hits) console.log('    ' + h.n + ': ' + h.t);
}
console.log('=== total literals: ' + total);
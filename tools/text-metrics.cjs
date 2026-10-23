// text-metrics.cjs -- measure rendered text geometry from a PNG screenshot.
//
// WHY: "the letters look wrong" is an impression. A text renderer is a glyph
// advance table, so the honest question is "how many pixels separate the ink of
// consecutive glyphs", and that is measurable: project the ink of one text line
// onto x, find the runs of inked columns, and report the gap between them.
//
// This tool exists because a screenshot made "the note reads 'T wo-way'" look like
// a glyph-advance defect, and the honest way to answer that is to measure it: the
// gutters in that line are 1 px between glyphs and 4-5 px at word spaces, which is
// ordinary spacing for fontSize 12 -- the impression was a viewing artifact. Measure
// before filing a gap (compiler-gaps.md has no text-entry for exactly this reason).
//
// Usage:
//   node tools/text-metrics.cjs <file.png> <x> <y> <w> <h> [--bg=RRGGBB] [--thresh=N]
//
//   <x> <y> <w> <h>  the band that contains ONE line of text (a little slack is
//                    fine: only inked pixels inside it are counted)
//   --bg             background colour treated as "not ink" (default 0xFFFFFF).
//                    A pixel is inked when its max channel distance from the
//                    background exceeds --thresh.
//   --thresh         per-channel distance that counts as ink (default 64, which
//                    keeps anti-aliased fringes out of the measurement)
'use strict';
const path = require('path');
const { decodePng } = require(path.join(__dirname, 'pngread.cjs'));

const [file, ...rest] = process.argv.slice(2);
const nums = rest.filter((a) => !a.startsWith('--')).map(Number);
const flag = (name, dflt) => {
  const a = rest.find((v) => v.startsWith('--' + name + '='));
  return a ? Number(a.split('=')[1]) : dflt;
};
const bgArg = rest.find((v) => v.startsWith('--bg='));
const bg = bgArg ? parseInt(bgArg.split('=')[1], 16) : 0xffffff;
const thr = flag('thresh', 64);
const [x, y, w, h] = nums;
if (!file || nums.length < 4) {
  console.log('usage: node tools/text-metrics.cjs <file.png> <x> <y> <w> <h> [--bg=RRGGBB] [--thresh=N]');
  process.exit(2);
}

const img = decodePng(file);
const bgR = (bg >> 16) & 255, bgG = (bg >> 8) & 255, bgB = bg & 255;

// Column projection: how many inked pixels in each x column of the band.
const cols = [];
for (let xx = x; xx < x + w; xx++) {
  let n = 0;
  for (let yy = y; yy < y + h; yy++) {
    if (xx < 0 || yy < 0 || xx >= img.w || yy >= img.h) continue;
    const d = (yy * img.w + xx) * 4;
    const dr = Math.abs(img.rgba[d] - bgR), dg = Math.abs(img.rgba[d + 1] - bgG), db = Math.abs(img.rgba[d + 2] - bgB);
    if (dr > thr || dg > thr || db > thr) n++;
  }
  cols.push(n);
}

// Collapse into ink runs (>= 1 inked column) separated by gaps (0 inked columns).
const runs = [];
let start = -1;
for (let i = 0; i <= cols.length; i++) {
  const ink = i < cols.length && cols[i] > 0;
  if (ink && start < 0) start = i;
  if (!ink && start >= 0) { runs.push([x + start, x + i - 1]); start = -1; }
}

console.log(file + '  band (' + x + ',' + y + ' ' + w + 'x' + h + ')  bg=#' + bg.toString(16).padStart(6, '0') + '  thresh=' + thr);
console.log('  ' + runs.length + ' ink runs (glyphs / glyph clusters):');
let prevEnd = null;
for (const [a, b] of runs) {
  const gap = prevEnd === null ? '' : String(a - prevEnd - 1);
  console.log('    x ' + String(a).padStart(4) + '..' + String(b).padStart(4) + '  w=' + String(b - a + 1).padStart(3) +
    '   gap-before=' + gap.padStart(3));
  prevEnd = b;
}
const first = runs.length ? runs[0][0] : x, last = runs.length ? runs[runs.length - 1][1] : x;
console.log('  ink spans x ' + first + '..' + last + '  (' + (last - first + 1) + ' px)');
const gaps = [];
for (let i = 1; i < runs.length; i++) gaps.push(runs[i][0] - runs[i - 1][1] - 1);
gaps.sort((a, b) => a - b);
if (gaps.length) {
  console.log('  gaps sorted: ' + gaps.join(' '));
  console.log('  min gap ' + gaps[0] + '   max gap ' + gaps[gaps.length - 1]);
}
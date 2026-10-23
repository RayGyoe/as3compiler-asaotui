// asaotui/tools/bmpdiff.cjs -- compare two 32-bit BMPs that two toolchains each
// rasterized from the same drawing code, and report the difference in PIXELS
// (not just in bytes), because "0 differing bytes" and "0 differing pixels" are
// different claims: BMP headers can differ harmlessly while the images match.
//
// WHY THIS EXISTS: reviews/probe-pixel-dump-2026-10-22.md showed our AOT native
// build and real AIR can both rasterize a display list into a BMP. That makes
// "the same .as source, two toolchains" comparable at the PIXEL level, which is
// a far stronger statement than comparing layout rectangles.
//
// Usage:
//   node bmpdiff.cjs a.bmp b.bmp               # summary + first differing clusters
//   node bmpdiff.cjs a.bmp b.bmp --pixels      # + a per-row/column histogram
//   node bmpdiff.cjs a.bmp b.bmp --tolerance=2 # allow +-N per channel per pixel
//
// Exit codes: 0 = images match (within tolerance), 1 = they differ, 2 = bad input.
const fs = require('fs');

function readBmp(file) {
  const b = fs.readFileSync(file);
  if (b.length < 54 || b[0] !== 0x42 || b[1] !== 0x4d) throw new Error(file + ': not a BMP');
  const dataOffset = b.readUInt32LE(10);
  const headerSize = b.readUInt32LE(14);
  const w = b.readInt32LE(18);
  const rawH = b.readInt32LE(22);
  const bpp = b.readUInt16LE(28);
  const compression = b.readUInt32LE(30);
  if (bpp !== 32) throw new Error(file + ': expected 32bpp, got ' + bpp);
  if (compression !== 0) throw new Error(file + ': expected BI_RGB, got ' + compression);
  const h = Math.abs(rawH);
  const bottomUp = rawH > 0;
  // Pixel(x, y) in TOP-DOWN coordinates -> BGRA bytes.
  const px = (x, y) => {
    const row = bottomUp ? h - 1 - y : y;
    const i = dataOffset + (row * w + x) * 4;
    return [b[i + 2], b[i + 1], b[i], b[i + 3]]; // R, G, B, A
  };
  return { w, h, px, headerSize, dataOffset, size: b.length };
}

const args = process.argv.slice(2);
const files = args.filter((a) => !a.startsWith('--'));
const tolerance = Number((args.find((a) => a.startsWith('--tolerance=')) || '--tolerance=0').split('=')[1]);
const wantHistogram = args.includes('--pixels');

if (files.length !== 2) {
  console.error('usage: node bmpdiff.cjs <a.bmp> <b.bmp> [--tolerance=N] [--pixels]');
  process.exit(2);
}

let A, B;
try { A = readBmp(files[0]); B = readBmp(files[1]); } catch (e) { console.error(String(e.message)); process.exit(2); }

console.log('a = ' + files[0] + '  ' + A.w + 'x' + A.h + '  ' + A.size + ' bytes');
console.log('b = ' + files[1] + '  ' + B.w + 'x' + B.h + '  ' + B.size + ' bytes');
if (A.w !== B.w || A.h !== B.h) {
  console.log('*** CANVAS SIZE DIFFERS -- nothing to compare ***');
  process.exit(1);
}

let differing = 0;
let maxChannelDelta = 0;
const clusters = [];
const rowsWithDiff = new Map();
const colsWithDiff = new Map();
for (let y = 0; y < A.h; y++) {
  for (let x = 0; x < A.w; x++) {
    const a = A.px(x, y);
    const b = B.px(x, y);
    let delta = 0;
    for (let c = 0; c < 4; c++) delta = Math.max(delta, Math.abs(a[c] - b[c]));
    if (delta > tolerance) {
      differing++;
      if (delta > maxChannelDelta) maxChannelDelta = delta;
      rowsWithDiff.set(y, (rowsWithDiff.get(y) || 0) + 1);
      colsWithDiff.set(x, (colsWithDiff.get(x) || 0) + 1);
      if (clusters.length < 12) clusters.push({ x, y, a, b, delta });
    }
  }
}

const hex = (p) => '#' + p.slice(0, 3).map((v) => v.toString(16).padStart(2, '0')).join('') + ' a' + p[3].toString(16).padStart(2, '0');

console.log('\ncanvas     : ' + A.w + 'x' + A.h + ' = ' + (A.w * A.h) + ' pixels');
console.log('tolerance  : +-' + tolerance + ' per channel');
console.log('differing  : ' + differing + ' pixels'
  + (differing ? ' (' + ((differing / (A.w * A.h)) * 100).toFixed(2) + '%), max channel delta ' + maxChannelDelta : ''));

if (differing === 0) {
  console.log('\nRESULT: the two images are PIXEL-IDENTICAL');
  process.exit(0);
}

console.log('\nfirst differing pixels:');
for (const c of clusters) console.log('  (' + c.x + ',' + c.y + ')  a=' + hex(c.a) + '  b=' + hex(c.b) + '  delta=' + c.delta);

if (wantHistogram) {
  const top = (m) => [...m.entries()].sort((p, q) => q[1] - p[1]).slice(0, 10)
    .map(([k, v]) => k + ':' + v).join('  ');
  console.log('\nrows with most differences : ' + top(rowsWithDiff));
  console.log('cols with most differences : ' + top(colsWithDiff));
}

console.log('\nRESULT: the two images DIFFER');
process.exit(1);

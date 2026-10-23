// tools/pngread.cjs -- minimal PNG -> RGBA reader + region probing.
//
// WHY: a screenshot is the only evidence that a UI actually LOOKS right, and the
// eye is not a measurement. "The button looks empty" is an impression; "the 400x40
// region centred at (280,284) is 100% #FFFFFF" is a fact a test can gate on. This
// decodes a PNG (8-bit, non-interlaced, grey/RGB/RGBA/with-or-without alpha --
// what our window backend and the Windows screenshot path emit) into raw RGBA and
// answers questions about regions of it.
//
// Zero dependencies: zlib is a Node built-in, and PNG's pixel data is just
// zlib(deflate) over scanlines with a per-scanline filter byte.
//
// Usage:
//   node pngread.cjs info <file.png>
//   node pngread.cjs top  <file.png> <x> <y> <w> <h> [rows]
//   node pngread.cjs scan <file.png> <x> <y> <w> <h> <step>
'use strict';

const fs = require('fs');
const zlib = require('zlib');

function decodePng(file) {
  const buf = fs.readFileSync(file);
  if (buf.readUInt32BE(0) !== 0x89504E47) throw new Error('not a PNG: ' + file);

  let off = 8, w = 0, h = 0, depth = 0, colorType = 0, interlace = 0;
  const idat = [];
  let palette = null, trns = null;
  while (off < buf.length) {
    const len = buf.readUInt32BE(off);
    const type = buf.toString('ascii', off + 4, off + 8);
    const data = buf.subarray(off + 8, off + 8 + len);
    if (type === 'IHDR') {
      w = data.readUInt32BE(0); h = data.readUInt32BE(4);
      depth = data[8]; colorType = data[9]; interlace = data[12];
    } else if (type === 'PLTE') palette = data;
    else if (type === 'tRNS') trns = data;
    else if (type === 'IDAT') idat.push(data);
    else if (type === 'IEND') break;
    off += 12 + len;   // len + type(4) + data + crc(4)
  }
  if (depth !== 8) throw new Error('only 8-bit channels supported, got depth=' + depth);
  if (interlace !== 0) throw new Error('interlaced PNG not supported');

  const channels = { 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 }[colorType];
  if (!channels) throw new Error('unsupported colorType=' + colorType);

  const raw = zlib.inflateSync(Buffer.concat(idat));
  const bpp = channels;                    // bytes per pixel (8-bit channels)
  const stride = w * bpp;
  const out = Buffer.alloc(w * h * 4);
  let prev = Buffer.alloc(stride);
  let p = 0;

  for (let y = 0; y < h; y++) {
    const ft = raw[p++];
    const line = Buffer.from(raw.subarray(p, p + stride));
    p += stride;
    // PNG filters operate on bytes; Paeth/Sub/Average/Up undo left/up context.
    for (let i = 0; i < stride; i++) {
      const a = i >= bpp ? line[i - bpp] : 0;
      const b = prev[i];
      const c = i >= bpp ? prev[i - bpp] : 0;
      let v = line[i];
      if (ft === 1) v = (v + a) & 0xFF;
      else if (ft === 2) v = (v + b) & 0xFF;
      else if (ft === 3) v = (v + ((a + b) >> 1)) & 0xFF;
      else if (ft === 4) {
        const pa = Math.abs(b - c), pb = Math.abs(a - c), pc = Math.abs(a + b - 2 * c);
        const pr = (pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c);
        v = (v + pr) & 0xFF;
      }
      line[i] = v;
    }
    for (let x = 0; x < w; x++) {
      const s = x * bpp, d = (y * w + x) * 4;
      if (colorType === 6) { out[d] = line[s]; out[d + 1] = line[s + 1]; out[d + 2] = line[s + 2]; out[d + 3] = line[s + 3]; }
      else if (colorType === 2) { out[d] = line[s]; out[d + 1] = line[s + 1]; out[d + 2] = line[s + 2]; out[d + 3] = 255; }
      else if (colorType === 0) { out[d] = out[d + 1] = out[d + 2] = line[s]; out[d + 3] = 255; }
      else if (colorType === 4) { out[d] = out[d + 1] = out[d + 2] = line[s]; out[d + 3] = line[s + 1]; }
      else if (colorType === 3) {
        const pi = line[s] * 3;
        out[d] = palette[pi]; out[d + 1] = palette[pi + 1]; out[d + 2] = palette[pi + 2];
        out[d + 3] = (trns && line[s] < trns.length) ? trns[line[s]] : 255;
      }
    }
    prev = line;
  }
  return { w, h, colorType, depth, rgba: out };
}

const hex = (r, g, b, a) => '#' + [r, g, b].map((v) => v.toString(16).padStart(2, '0')).join('') +
  (a === 255 ? '' : '/' + a.toString(16).padStart(2, '0'));

function top(img, x, y, w, h, rows) {
  const counts = new Map();
  for (let yy = y; yy < y + h; yy++) {
    for (let xx = x; xx < x + w; xx++) {
      if (xx < 0 || yy < 0 || xx >= img.w || yy >= img.h) continue;
      const d = (yy * img.w + xx) * 4;
      const k = (img.rgba[d] << 24 | img.rgba[d + 1] << 16 | img.rgba[d + 2] << 8 | img.rgba[d + 3]) >>> 0;
      counts.set(k, (counts.get(k) || 0) + 1);
    }
  }
  const total = w * h;
  const list = [...counts.entries()].sort((a, b) => b[1] - a[1]);
  console.log('region (' + x + ',' + y + ' ' + w + 'x' + h + ') of ' + w * h + ' px, ' + list.length + ' distinct colours');
  for (const [k, n] of list.slice(0, rows || 6)) {
    const r = (k >>> 24) & 255, g = (k >>> 16) & 255, b = (k >>> 8) & 255, a = k & 255;
    console.log('   ' + hex(r, g, b, a).padEnd(12) + String(n).padStart(8) + '  ' + (100 * n / total).toFixed(1) + '%');
  }
}

function main() {
const [cmd, file, ...rest] = process.argv.slice(2);
const img = decodePng(file);
if (cmd === 'info') {
  console.log(file + ': ' + img.w + 'x' + img.h + '  colorType=' + img.colorType + ' depth=' + img.depth);
} else if (cmd === 'top') {
  const [x, y, w, h, rows] = rest.map(Number);
  top(img, x, y, w, h, rows);
} else if (cmd === 'scan') {
  const [x, y, w, h, step] = rest.map(Number);
  for (let yy = y; yy < y + h; yy += step || 1) {
    const line = [];
    for (let xx = x; xx < x + w; xx += step || 1) {
      const d = (yy * img.w + xx) * 4;
      line.push(hex(img.rgba[d], img.rgba[d + 1], img.rgba[d + 2], img.rgba[d + 3]).padEnd(11));
    }
    console.log(String(yy).padStart(4) + ' ' + line.join(' '));
  }
} else if (cmd === 'runs') {
  // Collapse a row or column into runs of equal colour. This is the honest way to
  // locate geometry in a screenshot: it reports where each colour STARTS and ENDS
  // instead of assuming the screenshot is 1:1 with layout coordinates.
  const [axis, fixed, from, to] = rest;
  const f = fixed === undefined ? 0 : Number(fixed);
  const lim = axis === 'col' ? img.h : img.w;
  const a = from === undefined ? 0 : Number(from);
  const b = to === undefined ? lim : Number(to);
  let runStart = a, prevKey = null, prevHex = null;
  const flush = (end) => {
    if (prevHex !== null) console.log('  ' + axis + '=' + f + '  ' + String(runStart).padStart(4) + '..' + String(end - 1).padStart(4) +
      '  (' + String(end - runStart).padStart(4) + ' px)  ' + prevHex);
  };
  for (let i = a; i < b; i++) {
    const x = axis === 'col' ? f : i, y = axis === 'col' ? i : f;
    if (x < 0 || y < 0 || x >= img.w || y >= img.h) continue;
    const d = (y * img.w + x) * 4;
    const key = (img.rgba[d] << 24 | img.rgba[d + 1] << 16 | img.rgba[d + 2] << 8 | img.rgba[d + 3]) >>> 0;
    if (key !== prevKey) { flush(i); runStart = i; prevKey = key; prevHex = hex(img.rgba[d], img.rgba[d + 1], img.rgba[d + 2], img.rgba[d + 3]); }
  }
  flush(b);
} else {
  console.log('usage: node pngread.cjs info|top|scan|runs <file.png> ...');
  process.exit(2);
}
}

// Reusable as a library: text-metrics.cjs and others measure geometry, they do not
// re-implement PNG decoding.
if (require.main === module) main();
module.exports = { decodePng, hex };
// layout-check/verify-visual.cjs -- read the PICTURE back and check it against the
// hand-computed rectangles.
//
// WHY THIS IS NOT REDUNDANT WITH CheckMain.as: CheckMain.as asserts what
// `layoutGet` RETURNS. This asserts what was actually RASTERIZED. A bug that
// computes the right numbers but draws them at the wrong place -- a bad origin
// accumulation in the paint walk, a DPI scale, a clipped scene -- would pass
// CheckMain.as and fail here. Same idea as comparing our compiler against `adl`:
// assert at the level the user can observe, not at the level we control.
//
// HOW THE PICTURE IS READ (deliberately assumption-free):
//   visual-demo.bmp is the window framebuffer at 1:1 -- no DPI scaling and no
//   window chrome, unlike a screenshot. Every box in the demo is drawn with an
//   OPAQUE 1px stroke, and the stroke colour is chosen by depth, so "where are
//   the box borders" is answered by exact integer colour equality. No alpha
//   blending, no premultiplication and no gamma assumptions enter the check.
//
//   Boxes that are direct children of a scene root are painted at depth 1, i.e.
//   in 0xE0603C. Their left and right borders therefore appear as single pixels
//   of exactly that colour on a row through the middle of the box. Contiguous
//   boxes share a border pixel (which is itself a correct observation: with
//   justify-content: center the items are contiguous, only the leading offset
//   moves), so the expected arrays below list shared edges once.
//
// Usage: node verify-visual.cjs [path/to/visual-demo.bmp]
// Exit: 0 all assertions pass, 1 any mismatch, 2 bad input.
const fs = require('fs');
const path = require('path');

const file = process.argv[2] || path.join(__dirname, 'visual-demo.bmp');
let b;
try { b = fs.readFileSync(file); } catch (e) { console.error('cannot read ' + file); process.exit(2); }
if (b.length < 54 || b[0] !== 0x42 || b[1] !== 0x4d) { console.error(file + ': not a BMP'); process.exit(2); }

const dataOffset = b.readUInt32LE(10);
const W = b.readInt32LE(18);
const rawH = b.readInt32LE(22);
const bpp = b.readUInt16LE(28);
const H = Math.abs(rawH);
const bottomUp = rawH > 0;
if (bpp !== 32) { console.error('expected 32bpp, got ' + bpp); process.exit(2); }

// The BMP rows are stored bottom-up; (x, y) below is always TOP-DOWN.
function rgb(x, y) {
  const row = bottomUp ? H - 1 - y : y;
  const i = dataOffset + (row * W + x) * 4;
  return [b[i + 2], b[i + 1], b[i]];
}
function isColor(x, y, c) {
  const p = rgb(x, y);
  return p[0] === ((c >> 16) & 255) && p[1] === ((c >> 8) & 255) && p[2] === (c & 255);
}
function rowColor(x, y, c) {
  const out = [];
  for (let x2 = x[0]; x2 <= x[1]; x2++) if (isColor(x2, y, c)) out.push(x2);
  return out;
}
function colColor(y, x, c) {
  const out = [];
  for (let y2 = y[0]; y2 <= y[1]; y2++) if (isColor(x, y2, c)) out.push(y2);
  return out;
}

const ORANGE = 0xE0603C; // depth 1 -- a scene root's direct children
const BLUE = 0x2F6FED;   // depth 0 -- a scene root itself

let checks = 0;
let failures = 0;
function expectList(what, got, want) {
  checks++;
  const ok = got.length === want.length && got.every((v, i) => v === want[i]);
  if (!ok) failures++;
  console.log((ok ? 'PASS  ' : 'FAIL  ') + what);
  if (!ok) {
    console.log('        got : ' + (got.join(',') || '(none)'));
    console.log('        want: ' + (want.join(',') || '(none)'));
  }
}

// ---- geometry shared with VisualDemo.as -------------------------------------
// Kept as literals on purpose: these are the numbers a human works out on paper.
// If VisualDemo.as moves a panel, this file must be re-derived BY HAND -- that is
// the whole point, and it is why the two files are not allowed to share code.
const GX = 20, GY = 56, PW = 300, PH = 282, GAP = 20;
const innerX = (px) => px + 12;
const innerY = (py) => py + 34;
const P2X = GX + PW + GAP;          // 340
const P3X = GX + 2 * (PW + GAP);    // 660
const P5X = GX + PW + GAP;          // 340
const I2X = innerX(P2X), I2Y = innerY(GY);                        // 352, 90
const I3X = innerX(P3X), I3Y = innerY(GY);                        // 672, 90
const I5X = innerX(P5X), I5Y = innerY(GY + PH + GAP);             // 352, 392

console.log('scanning ' + file + '  (' + W + 'x' + H + ', ' + b.length + ' bytes)');
console.log('canvas matches the demo design: ' + (W === 960 && H === 660 ? 'yes' : 'NO -- assertions below will be meaningless') + '\n');

// ---- sanity: an empty spot is the page background, so the BMP is the page ---
checks++;
{
  const p = rgb(478, H - 3);
  const ok = p[0] === 0xF2 && p[1] === 0xF4 && p[2] === 0xF8;
  if (!ok) failures++;
  console.log((ok ? 'PASS  ' : 'FAIL  ') + 'page background at (478,' + (H - 3) + ') = rgb(' + p.join(',') + '), want rgb(242,244,248)');
}

// ---- panel 3: justify-content -------------------------------------------------
// Four strips of 276 x 52, three 44-wide boxes each. Justify-content distributes
// the free space (276 - 3*44 = 144) but the items stay CONTIGUOUS, so only the
// leading offset changes: center -> 72, space-between -> gaps of 72,
// space-evenly -> gaps of 36, flex-end -> 144.
{
  const STRIPH = 52, STRIPGAP = 12, BOXW = 44;
  const my = (k) => I3Y + k * (STRIPH + STRIPGAP) + 26; // row through box middles
  const X = [650, 959]; // panel 3's column, keeps other panels' boxes out
  // NOTE ON STROKE GEOMETRY (a drawing detail, not a layout claim): a rect drawn
  // as (x, y, w, h) puts its 1px border on the pixel rows/columns at the path, i.e.
  // the LEFT border lands on x and the RIGHT border on x + w (not x + w - 1). So
  // every expected edge list below uses `left + width`, and the column scan below
  // uses `top + height`. This was read off the framebuffer, not assumed.
  const contiguous = (lead) => [I3X + lead, I3X + lead + BOXW, I3X + lead + 2 * BOXW, I3X + lead + 3 * BOXW];
  const spread = (lead, gap) => [I3X + lead, I3X + lead + BOXW,
                                 I3X + lead + BOXW + gap, I3X + lead + 2 * BOXW + gap,
                                 I3X + lead + 2 * BOXW + 2 * gap, I3X + lead + 3 * BOXW + 2 * gap];
  expectList('p3 strip 0 justify=center      edges ' + contiguous(72).join('/'),
    rowColor(X, my(0), ORANGE), contiguous(72));
  expectList('p3 strip 1 justify=space-between edges ' + spread(0, 72).join('/'),
    rowColor(X, my(1), ORANGE), spread(0, 72));
  expectList('p3 strip 2 justify=space-evenly  edges ' + spread(36, 36).join('/'),
    rowColor(X, my(2), ORANGE), spread(36, 36));
  // flex-end has no trailing gap, so the three boxes stay contiguous like center
  // -- with gap 0 the shared borders collapse to one pixel, exactly as for center.
  expectList('p3 strip 3 justify=flex-end      edges ' + contiguous(144).join('/'),
    rowColor(X, my(3), ORANGE), contiguous(144));
}

// ---- panel 2: flex-grow 1:2:3 with basis 0 -----------------------------------
// Free space 276 split 1:2:3 -> 46 / 92 / 138. The three boxes have different
// heights (50/70/90), so the scan row sits inside the SHORTEST one, where all
// three borders must still be present.
{
  checks++;
  const y = I2Y + 44;
  const got = rowColor([P2X, P2X + PW], y, ORANGE);
  const want = [I2X, I2X + 46, I2X + 46 + 92, I2X + 46 + 92 + 138];
  const ok = got.length === want.length && got.every((v, i) => v === want[i]);
  if (!ok) failures++;
  console.log((ok ? 'PASS  ' : 'FAIL  ') + 'p2 flex-grow 1:2:3 -> 46/92/138 wide (edges ' + want.join('/') + ')');
  if (!ok) { console.log('        got : ' + (got.join(',') || '(none)')); console.log('        want: ' + want.join(',')); }
}

// ---- panel 5: flex-wrap -------------------------------------------------------
// 7 boxes of 60 wide, column-gap 10, in 276 -> floor((276+10)/70) = 4 per line.
{
  // 7 boxes of 60 wide with a 10 gap: each box contributes BOTH borders, so the
  // expected list alternates left/right per box (they are not shared here).
  const BW = 60, PITCH = 70;
  const lineY = (k) => I5Y + (36 + 10) * k + 18; // row through box middles
  const lineEdges = (n) => {
    const a = [];
    for (let i = 0; i < n; i++) { a.push(I5X + i * PITCH, I5X + i * PITCH + BW); }
    return a;
  };
  const X = [P5X, P5X + PW];
  expectList('p5 wrap line 0 -> 4 boxes (edges ' + lineEdges(4).join('/') + ')',
    rowColor(X, lineY(0), ORANGE), lineEdges(4));
  expectList('p5 wrap line 1 -> 3 boxes (edges ' + lineEdges(3).join('/') + ')',
    rowColor(X, lineY(1), ORANGE), lineEdges(3));
}

// ---- panel 4: align-items, read DOWN a column ---------------------------------
// Four strips (align-items = flex-start / center / flex-end / stretch), each with
// four 44-wide boxes of height 10/20/30 and the last one auto (so `stretch` shows).
// Scanning a COLUMN through box 2 (height 30) gives that box's top and bottom
// border, so the vertical placement of the SAME box under four alignment modes
// becomes four pairs of numbers.
{
  const STRIPH = 52, STRIPGAP = 12, BOXW = 44, PAD = 6;
  const I4X = innerX(GX), I4Y = innerY(GY + PH + GAP); // 32, 392
  const ay = (k) => I4Y + k * (STRIPH + STRIPGAP);
  const colX = I4X + PAD + 2 * BOXW + 22; // through box 2
  // box 2 is 30 tall; free = (52 - 2*PAD) - 30 = 10. Borders land on
  // top and top+30 (see the stroke-geometry note above).
  const at = (k, off) => [ay(k) + PAD + off, ay(k) + PAD + off + 30];
  expectList('p4 align-items=flex-start box#2 top/bottom',
    colColor([ay(0), ay(0) + STRIPH], colX, ORANGE), at(0, 0));
  expectList('p4 align-items=center     box#2 top/bottom',
    colColor([ay(1), ay(1) + STRIPH], colX, ORANGE), at(1, 5));
  expectList('p4 align-items=flex-end   box#2 top/bottom',
    colColor([ay(2), ay(2) + STRIPH], colX, ORANGE), at(2, 10));
  expectList('p4 align-items=stretch    box#2 keeps its explicit height 30',
    colColor([ay(3), ay(3) + STRIPH], colX, ORANGE), at(3, 0));
}

console.log('\n' + checks + ' checks, ' + failures + ' failures');
if (failures) {
  console.log('RESULT: the rasterized picture does NOT match the hand-computed rectangles');
  process.exit(1);
}
console.log('RESULT: every scanned border matches the hand-computed rectangle -- the engine both COMPUTED and DREW them in the right place');
process.exit(0);
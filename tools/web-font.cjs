#!/usr/bin/env node
// tools/web-font.cjs -- the CJK font the web arm ships, and the check that keeps it
// in step with the text the demo can actually put on screen.
//
// WHY THIS EXISTS. A wasm page has no system font to enumerate, so `web-gallery.cjs`
// stages ONE ttf into `fonts/` and the page fetches + registers it before main().
// The font it picked (a system `arial.ttf`) has no CJK coverage at all -- measured on
// the staged copy: U+6C49 / U+4E2D / U+6587 / U+7EC4 / U+4EF6 all map to glyph 0 --
// so the moment the docs app carried Chinese prose, every translated paragraph would
// have painted as .notdef boxes IN THE BROWSER while rendering correctly natively
// (native resolves text through the host's font stack, which does cascade to a CJK
// face). A page whose headline feature is "switch language" cannot ship a locale that
// draws nothing, and it must not do so SILENTLY.
//
// WHY A SUBSET. The demo + kit sources contain 1050 distinct non-ASCII codepoints;
// the full `MiSans-Regular.ttf` is 7.56 MB and every visitor would wait for it before
// the first frame (the page registers fonts BEFORE running main). Cut down to the
// codepoints that can appear, it is ~0.22 MB.
//
// WHY ONE FACE AND NOT TWO (measured, not assumed). Registering Arial *and* MiSans
// looks like the obvious split -- Latin where Latin is best, CJK as a fallback -- and
// it does not work. A TextField whose family is "Arial" matches the Arial face, and
// when a Han codepoint is missing from it the paragraph asks the font manager for a
// per-character fallback, which the web font manager (SkFontMgr_New_Custom_Data) does
// not provide. Measured on the built page: with both faces registered every Chinese
// paragraph painted as .notdef boxes; with only MiSans registered the same page
// rendered the Chinese correctly -- and ASCII went to boxes, because that subset held
// non-ASCII only. So the page ships exactly ONE face, and that face has to cover
// everything the app can print, which is why ASCII, Latin-1 and the punctuation /
// symbol ranges are in the subset as well. The cost is stated rather than hidden:
// English pages render in MiSans instead of Arial. Cascading mixed-script text
// properly needs a fallback implementation in the font manager (compiler-gaps.md G39).
//
// WHY IT IS COMMITTED. Regenerating needs `fontTools` (python), which is not a
// dependency this repo may take (AGENTS.md: zero third-party deps). So the subset is
// a checked-in artifact, and `--check` -- pure Node, no python -- re-derives the
// codepoint set from the CURRENT sources and proves the committed font still covers
// every one of them. Add a translation with a glyph the font lacks and the check goes
// red instead of the page going to tofu.
//
// Usage:
//   node tools/web-font.cjs            write ui-demo/fonts/MiSans-DemoSubset.ttf
//   node tools/web-font.cjs --check    verify the committed subset covers the sources
//
// Source font: <compiler repo>/examples/air-native/fonts/MiSans-Regular.ttf (the same
// file that example already ships). MiSans is free for commercial use; the subset
// keeps the original name table, so the family and the provenance stay visible.

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const UI = path.resolve(__dirname, '..');
const OUT = path.join(UI, 'ui-demo', 'fonts', 'MiSans-DemoSubset.ttf');
const SOURCE = path.resolve(UI, '..', 'as3compiler', 'examples', 'air-native', 'fonts', 'MiSans-Regular.ttf');
const TMP_CHARS = path.join(UI, 'temp', 'web-font-chars.txt');

// Every tree whose strings can reach a TextField on the web page. `demo/` is the app;
// `kit/asaot/ui/` is the chrome it composes (date pickers, placeholders, month names);
// `seam/` is the platform layer, which renders no text of its own.
const SOURCE_DIRS = [
  path.join(UI, 'ui-demo', 'demo'),
  path.join(UI, 'kit', 'asaot', 'ui'),
];

// Above U+007F is where the SOUTH ASIAN/EAST ASIAN text lives; ASCII alone is what a
// Latin face already covers. Both end up in the same subset -- see generate()'s note
// on WHY THE PAGE SHIPS ONE FACE AND NOT TWO.
function collectCodepoints() {
  const set = new Set();
  // Printable ASCII + Latin-1 supplement: identifiers, digits, code samples, and every
  // number the app formats. Both are in the subset because the page ships ONE face
  // (see the header): whatever a Latin face would have covered has to be in here too.
  for (let cp = 0x20; cp <= 0x7e; cp++) set.add(cp);
  for (let cp = 0xa0; cp <= 0xff; cp++) set.add(cp);
  const walk = (dir) => {
    for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
      const p = path.join(dir, ent.name);
      if (ent.isDirectory()) walk(p);
      else if (/\.as$/.test(ent.name)) {
        // The whole file, not just string literals: comments are full of Chinese too
        // and a superset costs a few dozen glyphs, while a missed literal is tofu.
        for (const ch of fs.readFileSync(p, 'utf8')) {
          if (ch.codePointAt(0) > 0x7f) set.add(ch.codePointAt(0));
        }
      }
    }
  };
  for (const d of SOURCE_DIRS) walk(d);
  // Fixed punctuation a locale-independent string may still produce at runtime. Named
  // one codepoint at a time, not as whole blocks: a block would demand glyphs the font
  // never had (unassigned and formatting codepoints), and "uncovered" has to mean a
  // real gap, not a codepoint no string can contain.
  for (const cp of [0x00b7, 0x2013, 0x2014, 0x2018, 0x2019, 0x201c, 0x201d, 0x2026, 0x20ac, 0x00a5]) set.add(cp);
  return set;
}

// ---- cmap reading (format 4 + 12) -------------------------------------------
// Pure Node on purpose: `--check` has to run in a gate on a machine with no python.
function cmapLookup(buf, cp) {
  const numTables = buf.readUInt16BE(4);
  let cmapOff = 0;
  for (let i = 0; i < numTables; i++) {
    const o = 12 + i * 16;
    if (buf.toString('ascii', o, o + 4) === 'cmap') cmapOff = buf.readUInt32BE(o + 8);
  }
  if (!cmapOff) throw new Error('no cmap table');
  const n = buf.readUInt16BE(cmapOff + 2);
  // Prefer a full-repertoire subtable, then any Unicode BMP one.
  let best = 0;
  for (let i = 0; i < n; i++) {
    const o = cmapOff + 4 + i * 8;
    const plat = buf.readUInt16BE(o);
    const enc = buf.readUInt16BE(o + 2);
    const off = cmapOff + buf.readUInt32BE(o + 4);
    if (plat === 3 && enc === 10) { best = off; break; }
    if (!best && plat === 3) best = off;
  }
  if (!best) throw new Error('no unicode cmap subtable');
  const fmt = buf.readUInt16BE(best);
  if (fmt === 12) {
    const ng = buf.readUInt32BE(best + 12);
    for (let i = 0; i < ng; i++) {
      const o = best + 16 + i * 12;
      const sc = buf.readUInt32BE(o);
      const ec = buf.readUInt32BE(o + 4);
      if (cp >= sc && cp <= ec) return buf.readUInt32BE(o + 8) + (cp - sc);
    }
    return 0;
  }
  const segX2 = buf.readUInt16BE(best + 6);
  const seg = segX2 / 2;
  const endO = best + 14;
  const startO = endO + segX2 + 2;
  const deltaO = startO + segX2;
  const rangeO = deltaO + segX2;
  for (let i = 0; i < seg; i++) {
    if (cp > buf.readUInt16BE(endO + i * 2)) continue;
    if (cp < buf.readUInt16BE(startO + i * 2)) break;
    const delta = buf.readInt16BE(deltaO + i * 2);
    const ro = buf.readUInt16BE(rangeO + i * 2);
    if (ro === 0) return (cp + delta) & 0xffff;
    const g = buf.readUInt16BE(rangeO + i * 2 + ro + (cp - buf.readUInt16BE(startO + i * 2)) * 2);
    return g === 0 ? 0 : (g + delta) & 0xffff;
  }
  return 0;
}

function verify(file, codepoints) {
  const buf = fs.readFileSync(file);
  const missing = [];
  for (const cp of codepoints) {
    if (cmapLookup(buf, cp) === 0) missing.push(cp);
  }
  return { bytes: buf.length, missing };
}

function fmtCp(cp) {
  return 'U+' + cp.toString(16).toUpperCase().padStart(4, '0') + ' ' + String.fromCodePoint(cp);
}

function check() {
  const cps = [...collectCodepoints()].sort((a, b) => a - b);
  if (!fs.existsSync(OUT)) {
    console.log('MISSING: ' + path.relative(UI, OUT) + ' -- run: node tools/web-font.cjs');
    process.exit(1);
  }
  const r = verify(OUT, cps);
  console.log('web-font: ' + path.relative(UI, OUT) + '  ' + (r.bytes / 1048576).toFixed(2) + ' MB, '
    + cps.length + ' required codepoint(s)');
  if (r.missing.length) {
    console.log('  UNCOVERED: ' + r.missing.slice(0, 20).map(fmtCp).join('  ')
      + (r.missing.length > 20 ? '  (+' + (r.missing.length - 20) + ' more)' : ''));
    console.log('RESULT: FAIL -- regenerate with: node tools/web-font.cjs');
    process.exit(1);
  }
  console.log('  covered: all ' + cps.length);
  console.log('RESULT: PASS');
}

function generate() {
  if (!fs.existsSync(SOURCE)) {
    console.error('source font missing: ' + SOURCE + '\n(the compiler repo ships it for its air-native example)');
    process.exit(2);
  }
  const cps = [...collectCodepoints()].sort((a, b) => a - b);
  fs.mkdirSync(path.dirname(OUT), { recursive: true });
  fs.mkdirSync(path.dirname(TMP_CHARS), { recursive: true });
  fs.writeFileSync(TMP_CHARS, cps.map((c) => String.fromCodePoint(c)).join(''));
  const py = [
    'import os, sys',
    'from fontTools import subset',
    'src, textfile, out = sys.argv[1], sys.argv[2], sys.argv[3]',
    'text = open(textfile, encoding="utf-8").read()',
    'opts = subset.Options()',
    'opts.layout_features = ["*"]',
    'opts.name_IDs = ["*"]            # the subset keeps the font identity, so provenance stays readable',
    'opts.notdef_outline = True',
    'opts.recalc_bounds = True',
    'f = subset.load_font(src, opts)',
    's = subset.Subsetter(options=opts)',
    's.populate(text=text)',
    's.subset(f)',
    'subset.save_font(f, out, opts)',
    'print("subset: %.2f MB (from %.2f MB)" % (os.path.getsize(out) / 1048576, os.path.getsize(src) / 1048576))',
  ].join('\n');
  const r = spawnSync('python', ['-c', py, SOURCE, TMP_CHARS, OUT], { encoding: 'utf8' });
  if (r.status !== 0) {
    console.error('fontTools subsetting failed (python + fontTools required):');
    console.error((r.stdout || '') + (r.stderr || ''));
    process.exit(3);
  }
  process.stdout.write(r.stdout);
  fs.rmSync(TMP_CHARS, { force: true });
  const v = verify(OUT, cps);
  console.log('wrote ' + path.relative(UI, OUT) + ': ' + (v.bytes / 1048576).toFixed(2) + ' MB, '
    + cps.length + ' codepoint(s)');
  if (v.missing.length) {
    // Not expected (the subsetter was given exactly these), but the check is the
    // same one the gate runs, so a silent failure here is impossible.
    console.log('RESULT: FAIL -- ' + v.missing.slice(0, 10).map(fmtCp).join('  '));
    process.exit(1);
  }
  console.log('RESULT: PASS');
}

if (process.argv.includes('--check')) check();
else generate();
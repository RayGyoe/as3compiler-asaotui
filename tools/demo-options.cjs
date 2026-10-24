// demo-options.cjs -- every option key the docs demos pass must be one the factory
// (or the style shorthand) actually reads.
//
// WHY THIS IS A GATE: the docs app builds each page from an object literal AND
// prints that same literal as the page's source, so a wrong key is not a typo in
// prose -- it is a page teaching an API that does not exist. Three such pages had
// shipped by 2026-10-24 (progress `tone`, which progress() never read; tooltip
// `tone: "info"`, a STRING where the bubble wants a fill COLOUR; toast
// `tone: "info"`, a chip tone the toast vocabulary does not have -- that one
// THREW). Found by clicking the pages; this scan is how the list stops depending on
// someone clicking.
//
// WHAT COUNTS AS AN OPTION KEY (three sources, all real):
//   1. StyleRefinement.from(o) -- OptionSupport.applyOpts falls back to it when
//      there is no `style`, so its shorthand keys (size/gap/padding/flexGrow/
//      background/text/...) are options of EVERY factory. Without this the scan
//      reports box({gap}) as unknown.
//   2. OptionSupport.applyOpts -- key/style/keyContext/role/ariaName/visible/
//      disabled/onClick.
//   3. the factory body -- `opts.<name>` and `OptionSupport.opt(opts, "x")`.
//
// WHAT IT CANNOT SEE: values. `tone: "info"` is a known KEY with a bad VALUE, so
// this scan is silent about it; that class is covered behaviourally, by the tour
// clicking the demo (ui-demo/demo/DocsMain.as, stage "6d toastHost").
//
// Snippets are scanned on purpose: a string in DocsData/Docs* IS the documentation,
// and the reader copies it. Object literals are found as top-level ARGUMENTS, so
// both shapes work -- `toast({...})` and `row({...}, [children])`.
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const KIT = path.join(ROOT, 'kit', 'asaot', 'ui');
const DEMO = path.join(ROOT, 'ui-demo', 'demo');

function walk(dir, ext, out) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const f = path.join(dir, e.name);
    if (e.isDirectory()) walk(f, ext, out);
    else if (e.name.endsWith(ext)) out.push(f);
  }
  return out;
}

// ---- the shared key set ----------------------------------------------------
const SHARED = ['key', 'style', 'keyContext', 'role', 'ariaName', 'visible', 'disabled', 'onClick'];
const STYLE_SRC = fs.readFileSync(path.join(KIT, 'style', 'StyleRefinement.as'), 'utf8');
const FROM_SRC = STYLE_SRC.slice(STYLE_SRC.indexOf('static function from'));
const STYLE_KEYS = [...new Set([...FROM_SRC.matchAll(/o\.(\w+)\s*!=/g)].map((m) => m[1]))];

// ---- the factories and the keys they read ---------------------------------
// A factory is a `public function <name>(` declared at the top level of a file in
// kit/asaot/ui/ (kind/ subdirectories hold the widgets, not the factories).
const accepted = new Map();
for (const f of walk(KIT, '.as', [])) {
  if (path.dirname(f) !== KIT) continue;
  const src = fs.readFileSync(f, 'utf8');
  const re = /public function (\w+)\s*\(/g;
  let m;
  while ((m = re.exec(src)) !== null) {
    let i = src.indexOf('{', m.index);
    let depth = 0, j = i;
    for (; j < src.length; j++) {
      if (src[j] === '{') depth++;
      else if (src[j] === '}' && --depth === 0) break;
    }
    const keys = new Set([...SHARED, ...STYLE_KEYS]);
    const read = /opts\.(\w+)|opt\(opts,\s*"(\w+)"/g;
    let h;
    while ((h = read.exec(src.slice(i, j))) !== null) keys.add(h[1] || h[2]);
    accepted.set(m[1], keys);
  }
}
if (accepted.size < 50) {
  console.log('DEMO OPTIONS: FAIL -- found only ' + accepted.size + ' factories; the scan is broken');
  process.exit(1);
}
const everRead = new Set();
for (const keys of accepted.values()) for (const k of keys) everRead.add(k);

// ---- the top-level keys of one `{ ... }` literal --------------------------
function literalKeys(src, open) {
  const keys = [];
  let depth = 0, tokenStart = -1;
  for (let i = open; i < src.length; i++) {
    const c = src[i];
    if (c === '{' || c === '[' || c === '(') { depth++; continue; }
    if (c === '}' || c === ']' || c === ')') { depth--; if (depth === 0) break; continue; }
    if (depth !== 1) continue;
    if (c === ':') {
      const name = tokenStart >= 0 ? src.slice(tokenStart, i).trim() : '';
      if (/^[A-Za-z_]\w*$/.test(name)) keys.push(name);
      tokenStart = -1;
    } else if (c === ',') {
      tokenStart = -1;
    } else if (tokenStart < 0 && !/\s/.test(c)) {
      tokenStart = i;
    }
  }
  return keys;
}

// ---- every call site -------------------------------------------------------
const rows = [];
for (const f of walk(DEMO, '.as', [])) {
  const src = fs.readFileSync(f, 'utf8');
  for (const [name, keys] of accepted) {
    const re = new RegExp('(^|[^\\w.])' + name + '\\s*\\(', 'g');
    let m;
    while ((m = re.exec(src)) !== null) {
      const open = m.index + m[0].length - 1;
      // the arguments: split on top-level commas, keep the ones that ARE a literal
      let depth = 0;
      const starts = [open + 1];
      let end = open;
      for (let i = open; i < src.length; i++) {
        const c = src[i];
        if (c === '(' || c === '[' || c === '{') depth++;
        else if (c === ')' || c === ']' || c === '}') { depth--; if (depth === 0) { end = i; break; } }
        else if (c === ',' && depth === 1) starts.push(i + 1);
      }
      const line = src.slice(0, m.index).split(/\r?\n/).length;
      for (const s0 of starts) {
        let s = s0;
        while (s < end && /\s/.test(src[s])) s++;
        if (src[s] !== '{') continue;
        for (const k of literalKeys(src, s)) {
          if (keys.has(k)) continue;
          rows.push({ file: path.relative(ROOT, f), line, factory: name, key: k, other: everRead.has(k) });
        }
      }
    }
  }
}

// ---- report ----------------------------------------------------------------
const seen = new Set();
const unique = rows.filter((r) => {
  const k = r.file + ':' + r.line + ':' + r.factory + ':' + r.key;
  if (seen.has(k)) return false;
  seen.add(k);
  return true;
});
unique.sort((a, b) => a.file.localeCompare(b.file) || a.line - b.line);
console.log('factories: ' + accepted.size + '  (options: ' + SHARED.length + ' shared + '
  + STYLE_KEYS.length + ' style shorthands + each factory\'s own reads)');
console.log('demo call sites with an unknown option key: ' + unique.length);
for (const r of unique) {
  console.log('  ' + r.file + ':' + r.line + '  ' + r.factory + ' -> "' + r.key + '"  '
    + (r.other ? '(a DIFFERENT factory reads it -- copy-paste from another widget)'
               : '(no factory reads it at all)'));
}
console.log('DEMO OPTIONS: ' + (unique.length === 0 ? 'PASS' : 'FAIL'));
process.exit(unique.length === 0 ? 0 : 1);
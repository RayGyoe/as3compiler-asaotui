// kind-coverage.cjs -- every widget kind the kit REGISTERS must be shown by the
// gallery demo.
//
// WHY THIS IS A GATE AND NOT A CHECKLIST
// -------------------------------------
// The gallery is the only place a human (and a screenshot) can see that a widget
// exists at all. Twice now a new kind shipped, passed its own probe, and was never
// added to the demo: `virtualList`/`tree`/`combobox`/`datePicker` were all written
// before this tool existed, and the STATUS.md claim "scrollView is the only kind
// not in the gallery" was off by six. A hand-maintained list cannot be right for
// long -- the same reason the fingerprint tool is a gate rather than a habit.
//
// HOW A KIND IS TRACED
//   kind  -> the file that calls `Widgets.register("<kind>", ...)`  (its node class)
//   class -> every kit file containing `new <Class>(`               (its factories)
//   fn    -> `public function <fn>(` in those files
// `label` is an ALIAS of `text` and registers no kind, so it cannot appear here.
// A kind with NO factory at all is reported separately: that is an author-facing
// gap, not a missing gallery entry, and it must be a deliberate choice.
//
// A factory listed here is not "used" unless the gallery CALLS it: the search is
// `\bfn\s*\(` over the demo sources, i.e. a call or a reference to one.
//
// Usage:   node tools/kind-coverage.cjs [--verbose]
// Exit:    0 = every kind is shown, 1 = at least one is not, 2 = cannot measure.
'use strict';

const fs = require('fs');
const path = require('path');

const UI = path.resolve(__dirname, '..');
const KIT = path.join(UI, 'kit/asaot/ui');
// The DEMO sources, not the staged copy: `stage-air.cjs` rebuilds
// `<app>-src/` from `ui-demo/demo/` on every run, so the staged tree is an
// artifact. Checking it would certify whichever build happened last.
const DEMO = path.join(UI, 'ui-demo/demo');
const verbose = process.argv.includes('--verbose');

// Comments out, code in. Two of this tool's first false answers came from reading
// prose as code: `// ... the second tree (the page below ...` matched a `tree(` CALL,
// and `// the class gained ...` was read as the declaration `class gained`. A scan
// that cannot tell a comment from a statement certifies the wrong thing.
function strip(src) {
  let out = '';
  let i = 0;
  const n = src.length;
  while (i < n) {
    const c = src[i];
    const d = src[i + 1];
    if (c === '/' && d === '/') {
      while (i < n && src[i] !== '\n') i++;
      continue;
    }
    if (c === '/' && d === '*') {
      i += 2;
      while (i < n && !(src[i] === '*' && src[i + 1] === '/')) i++;
      i += 2;
      continue;
    }
    if (c === '"' || c === "'") {
      const q = c;
      out += c;
      i++;
      while (i < n) {
        if (src[i] === '\\') { out += src[i] + (src[i + 1] || ''); i += 2; continue; }
        out += src[i];
        if (src[i] === q) { i++; break; }
        i++;
      }
      continue;
    }
    out += c;
    i++;
  }
  return out;
}

// The DEMO side needs one more step: a factory call that appears inside a STRING is a
// code snippet printed on a page, not a rendering. `strip` keeps string bodies on
// purpose (the kit scan reads `register("tree", ...)` out of one), so the demo gets
// its own pass that empties them. Without it a page could satisfy this gate by
// PRINTING the source of a call it never makes -- the string-shaped twin of the
// comment bug that made this tool report `tree` as shown in its first version.
function stripStrings(src) {
  let out = '';
  let i = 0;
  const n = src.length;
  while (i < n) {
    const q = src[i];
    if (q !== '"' && q !== "'" && q !== '`') { out += q; i++; continue; }
    out += q;
    i++;
    while (i < n) {
      if (src[i] === '\\') { i += 2; continue; }
      if (src[i] === q) { out += q; i++; break; }
      i++;
    }
  }
  return out;
}

function readKit() {
  const out = [];
  const walk = (dir) => {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      const p = path.join(dir, e.name);
      if (e.isDirectory()) walk(p);
      else if (e.name.endsWith('.as')) out.push({ rel: path.relative(KIT, p).split(path.sep).join('/'), src: strip(fs.readFileSync(p, 'utf8')) });
    }
  };
  walk(KIT);
  return out;
}

const kit = readKit();
if (!kit.length) {
  console.error('[kind-coverage] no kit sources found under ' + KIT);
  process.exit(2);
}

// ---- 1) kinds, and the class each one is registered from ---------------------
const kinds = []; // { kind, file, cls }
for (const f of kit) {
  for (const m of f.src.matchAll(/\bregister\s*\(\s*"([^"]+)"/g)) {
    const kind = m[1];
    if (kinds.some((k) => k.kind === kind)) continue;
    const cls = /\bpublic\s+class\s+([A-Za-z_$][\w$]*)/.exec(f.src);
    kinds.push({ kind, file: f.rel, cls: cls ? cls[1] : null });
  }
}
kinds.sort((a, b) => (a.kind < b.kind ? -1 : a.kind > b.kind ? 1 : 0));
if (!kinds.length) {
  console.error('[kind-coverage] no `register("…")` calls found -- the scan is broken, not the kit');
  process.exit(2);
}

// ---- 2) factories per kind ---------------------------------------------------
const demo = fs.readdirSync(DEMO)
  .filter((f) => f.endsWith('.as'))
  .map((f) => stripStrings(strip(fs.readFileSync(path.join(DEMO, f), 'utf8'))))
  .join('\n');
if (demo.trim() === '') {
  console.error('[kind-coverage] the demo sources are empty -- cannot certify anything');
  process.exit(2);
}

const rows = [];
for (const k of kinds) {
  const factories = new Set();
  if (k.cls) {
    const ctor = new RegExp('new\\s+' + k.cls.replace(/\$/g, '\\$') + '\\s*\\(');
    for (const f of kit) {
      if (!ctor.test(f.src)) continue;
      for (const m of f.src.matchAll(/public function ([A-Za-z_$][\w$]*)\s*\(/g)) {
        // A factory is a function that RETURNS a node; the node classes' own
        // methods are excluded because those files are `*Node.as`.
        if (/-?Node\.as$/.test(f.rel) || /^kind\//.test(f.rel)) continue;
        factories.add(m[1]);
      }
    }
  }
  const list = [...factories].sort();
  const called = list.filter((fn) => new RegExp('\\b' + fn.replace(/\$/g, '\\$') + '\\s*\\(').test(demo));
  rows.push({ kind: k.kind, file: k.file, cls: k.cls, factories: list, called });
}

// ---- 3) verdict --------------------------------------------------------------
const shown = rows.filter((r) => r.called.length > 0);
const noFactory = rows.filter((r) => r.factories.length === 0);
const notShown = rows.filter((r) => r.factories.length > 0 && r.called.length === 0);

if (verbose) {
  for (const r of rows) {
    console.log((r.called.length ? 'SHOWN  ' : 'MISSING') + '  ' + r.kind.padEnd(12)
      + ' factories: ' + (r.factories.join(' ') || '(none)')
      + (r.called.length ? '  -> gallery calls ' + r.called.join(' ') : ''));
  }
}

console.log('[kind-coverage] ' + shown.length + '/' + rows.length + ' registered kinds are shown by ui-demo/demo'
  + ' (' + noFactory.length + ' with no factory)');
for (const r of noFactory) {
  console.log('  NO-FACTORY ' + r.kind + '  (registered by ' + r.file + ') -- author-facing gap?');
}
if (notShown.length) {
  console.error('[kind-coverage] NOT SHOWN BY THE GALLERY (' + notShown.length + '):');
  for (const r of notShown) {
    console.error('  ' + r.kind + '  (class ' + r.cls + ', factories: ' + r.factories.join(' ') + ')');
  }
  console.error('[kind-coverage] add each one to its own page under ui-demo/demo/Docs*.as'
    + ' (and to DocsCatalog\'s page list) so the docs keep being the place a widget can be LOOKED at.');
  process.exit(1);
}
console.log('[kind-coverage] RESULT: PASS');
// tools/find-bound-truthy.cjs -- lint for compiler-gaps.md G9.
//
// THE BUG: `Boolean(x)` where `x` is statically DECLARED `Object` is lowered to a
// plain pointer test `(x != NULL)`. An `Object`-typed variable holds a boxed
// value (an `Object*` wrapper, produced by `as_value_to_obj`), so a boxed
// `false` is a non-NULL pointer and reads as TRUE. Measured on this toolchain:
//
//     var s:Object = binding.get();   // model field is Boolean false
//     Boolean(s)   ->  true      WRONG
//     String(s)    ->  "false"   ok
//     s == null    ->  false     ok
//     s is Boolean ->  true      ok
//     var t:* = binding.get(); Boolean(t) -> false   ok  <-- the fix
//     if (s)       ->  false     ok  (the `if` form does NOT take the shortcut)
//
// So the dangerous shape is narrow but easy to write by hand:
//   a local DECLARED `Object` (usually fed by `*.get()` or a dynamic read),
//   later used as a condition -- `Boolean(x)`, `if (x)`, `x ? a : b`, `!x`.
//
// This scans every file for those two halves and reports the pairs. Exit code is
// non-zero when any pair is found, so it can be a gate.
//
// LIMITATION (deliberate, stated rather than hidden): this is a line-oriented
// scan, not a parser. It treats variable names as file-scoped, which
// over-approximates per-function scope -- that can only produce extra warnings,
// never miss a real one.
'use strict';
const fs = require('fs');
const path = require('path');

const compilerGaps = 'compiler-gaps.md G9';
const roots = process.argv.slice(2);
if (roots.length === 0) {
  console.error('usage: node tools/find-bound-truthy.cjs <dir>...');
  process.exit(2);
}

const files = [];
function walk(d) {
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const q = path.join(d, e.name);
    if (e.isDirectory()) walk(q);
    else if (e.name.endsWith('.as')) files.push(q);
  }
}
for (const r of roots) walk(r);

const DECL = /^\s*(?:var|const)\s+(\w+)\s*:\s*Object\s*=/;
const USE = (n) => new RegExp('(Boolean\\s*\\(\\s*' + n + '\\s*\\)|[?!]\\s*\\(' + n + '\\s*\\)|if\\s*\\(\\s*' + n + '\\s*\\)|if\\s*\\(\\s*!' + n + '\\b|::\\s*' + n + '\\b)');

let declarations = 0;
const findings = [];
for (const f of files.sort()) {
  const lines = fs.readFileSync(f, 'utf8').split(/\r?\n/);
  const objLocals = new Map();          // name -> line number of its declaration
  lines.forEach((l, i) => {
    const m = DECL.exec(l);
    if (m && !objLocals.has(m[1])) objLocals.set(m[1], i + 1);
  });
  declarations += objLocals.size;
  for (const [name, declLine] of objLocals) {
    const re = USE(name);
    lines.forEach((l, i) => {
      if (i + 1 === declLine) return;
      if (re.test(l)) findings.push({ file: f, name, declLine, useLine: i + 1, text: l.trim() });
    });
  }
}

for (const x of findings) {
  console.log('G9-RISK  ' + x.file.split(path.sep).join('/') + ':' + x.useLine);
  console.log('         `' + x.name + '` is declared `:Object` at line ' + x.declLine + ', then used as a condition:');
  console.log('         ' + x.text.slice(0, 150));
}
console.log('--- ' + files.length + ' files, ' + declarations + ' Object-typed locals, ' + findings.length + ' risky use(s) ---');
if (findings.length) {
  console.log('FIX: declare the local `*` instead of `Object` (Boolean(*) lowers to as_v_truthy).');
  console.log('See ' + compilerGaps + '.');
  process.exit(1);
}
console.log('RESULT: PASS (no Object-typed local is used as a condition)');
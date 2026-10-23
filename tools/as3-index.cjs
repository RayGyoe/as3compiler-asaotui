// asaotui/tools/as3-index.cjs -- index the declared package / class / package-level
// functions of every .as file under a directory.
//
// WHY: AIR's compiler resolves an import `a.b.C` to the FILE `a/b/C.as` and does
// not scan a source tree for definitions. So a package-level function declared in
// a file whose name does not match the function is invisible to mxmlc (it lives
// in, say, asaot/ui/Factories.as, but `import asaot.ui.box` makes mxmlc look for
// asaot/ui/box.as). Our own AOT takes an explicit file list and does not care.
// The mismatch is therefore invisible until you actually compile with AIR -- which
// is exactly what this index is for.
//
// Usage: node as3-index.cjs [dir]
const fs = require('fs');
const path = require('path');

const root = process.argv[2] || '.';
const rows = [];
(function walk(d) {
  let ents;
  try { ents = fs.readdirSync(d); } catch (e) { return; }
  for (const f of ents) {
    const q = path.join(d, f);
    let st;
    try { st = fs.statSync(q); } catch (e) { continue; }
    if (st.isDirectory()) { walk(q); continue; }
    if (!f.endsWith('.as')) continue;
    const src = fs.readFileSync(q, 'utf8');
    const pkgMatch = src.match(/^\s*package\s+([\w.]+)?/m);
    const pkg = pkgMatch ? (pkgMatch[1] || '(default)') : '(none)';
    const clsMatch = src.match(/^\s*public\s+(?:final\s+|abstract\s+)?(class|interface)\s+(\w+)/m);
    const cls = clsMatch ? clsMatch[2] : null;
    // package-level functions: declared OUTSIDE any class body, i.e. at indent 4
    // inside the package block, with no class seen before them.
    const fns = [];
    {
      const lines = src.split('\n');
      let inClass = false;
      let depth = 0;
      for (const line of lines) {
        const t = line.trim();
        if (/\b(class|interface)\b/.test(line) && !t.startsWith('//') && !t.startsWith('*')) inClass = true;
        if (inClass) continue;
        const m = line.match(/^\s{4}public\s+function\s+(\w+)/);
        if (m) fns.push(m[1]);
      }
    }
    // the file that mxmlc WOULD look for, given each declared name
    const reachableAs = cls ? pkg + '.' + cls : null;
    const expectedFileForCls = cls ? path.join(...pkg.split('.'), cls + '.as') : null;
    const clsResolvable = expectedFileForCls ? q.endsWith(expectedFileForCls) : false;
    rows.push({ q: q.split(path.sep).join('/'), pkg, cls, fns, reachableAs, clsResolvable });
  }
})(root);

rows.sort((a, b) => a.q.localeCompare(b.q));
let problems = 0;
for (const r of rows) {
  const name = r.cls ? r.pkg + '::' + r.cls : r.pkg + '::(no class)';
  const flag = [];
  if (r.cls && !r.clsResolvable) flag.push('CLASS-FILE-NAME-MISMATCH');
  if (r.fns.length) flag.push('PKG-LEVEL-FNS(not mxmlc-importable): ' + r.fns.join(','));
  if (!r.cls && !r.fns.length) flag.push('NOTHING-PUBLIC');
  if (flag.length) problems++;
  console.log(name.padEnd(32) + r.q.padEnd(46) + (flag.length ? '  << ' + flag.join(' | ') : ''));
}
console.log('\n' + rows.length + ' files, ' + problems + ' with a portability flag');
console.log('(AIR resolves `import a.b.C` to the file a/b/C.as; a package-level function in a');
console.log(' differently-named file cannot be reached that way, even though it is valid AS3.)');
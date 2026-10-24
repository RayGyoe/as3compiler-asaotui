// reach-dump.cjs -- print which files `--air-app`'s reachability closure keeps.
//
// Diagnostic for the AIR-app build path (see ui-demo/stage-air.cjs): when the
// build dies with "unknown superclass 'X'", the question is whether X's FILE was
// pruned by `src/reach.ts` or whether codegen lost the class some other way. This
// answers it by running the real closure over the staged tree.
//
// Usage:  node tools/reach-dump.cjs <src-dir> <main-class-fqn> [more roots ...]
//
// The closure spans every source root the build names (阶段二百五十): `<appDir>/src`
// plus the `--as-class-path` roots. Pass them after the main class, in the same order
// the build passes them.
'use strict';

const fs = require('fs');
const path = require('path');
const { pathToFileURL } = require('url');

const UI = path.resolve(__dirname, '..');
const COMPILER = path.resolve(UI, '..', 'as3compiler');

function walk(dir, out) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.as')) out.push(p);
  }
  return out;
}

(async () => {
  const srcDir = path.resolve(process.argv[2] || path.join(UI, 'ui-demo', 'air-gallery', 'src'));
  const mainClass = process.argv[3] || 'demo.DocsMain';
  // The extra roots: what the build names with --as-class-path (seam + kit, see
  // ui-demo/stage-air.cjs SHARED_ROOTS). Without them the dump would report a
  // closure over the demo's six files only.
  const roots = [srcDir, ...process.argv.slice(4).map((d) => path.resolve(d))];
  const reach = await import(pathToFileURL(path.join(COMPILER, 'src', 'reach.ts')).href);

  const files = roots.flatMap((r) => walk(r, [])).sort();
  const parsed = reach.prepareReachFiles(files, roots);
  const res = reach.computeReachable(parsed, mainClass);

  const rel = (p) => path.relative(srcDir, p).split(path.sep).join('/');
  if (process.env.ASC_DECLS === '1') {
    for (const f of parsed) {
      for (const s of f.body) {
        if (s.kind === 'ClassDecl') console.log('DECL ' + rel(f.path) + '  name=' + s.name + ' pkg=' + s.packageName + ' extends=' + s.superClass + ' fileId=' + s.fileId);
        else if (s.kind === 'InterfaceDecl') console.log('DECL ' + rel(f.path) + '  interface ' + s.name + ' pkg=' + s.packageName);
      }
    }
  }

  console.log('main=' + mainClass + '  kept ' + res.kept.length + '/' + files.length + '  edges ' + res.edges);
  console.log('roots: ' + res.roots.join(', '));
  console.log('KEPT (' + res.kept.length + '):');
  for (const d of res.kept) console.log('  ' + rel(d));
  console.log('DROPPED (' + res.dropped.length + '):');
  for (const d of res.dropped) console.log('  ' + rel(d));
  process.exit(0);
})();

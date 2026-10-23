import { readFileSync } from 'node:fs';
const buf = readFileSync(process.argv[2]);
const mod = new WebAssembly.Module(buf);
const imports = WebAssembly.Module.imports(mod);
const byMod = {};
for (const i of imports) { byMod[i.module] ??= new Set(); byMod[i.module].add(i.name); }
for (const [m, names] of Object.entries(byMod)) {
  console.log(`${m}: ${names.size} imports`);
  if (m.includes('wasi')) console.log('   ' + [...names].sort().join(', '));
}
console.log('total import functions:', imports.length);
const exps = WebAssembly.Module.exports(mod);
console.log('exports:', exps.map(e => e.name).join(', '));

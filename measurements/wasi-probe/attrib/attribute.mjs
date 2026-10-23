// attribute.mjs -- split a linked wasm's CODE (per-symbol sizes from llvm-nm)
// across the static archives it was linked from, so we can say how much of the
// wasip1 delta is "Yoga's own code" vs "the wasi libc/libc++ it drags in".
//
//   node attribute.mjs <gw.wasm> <archive:tag> [<archive:tag> ...]
//
// For each defined symbol in the wasm, find which archive defines it and sum.
//
// Gotcha (measured): `llvm-nm` prints *mangled* C++ names for ELF/COFF members
// inside an archive, but the wasm `name` section already carries *demangled*
// names (llvm-nm --no-demangle does not undo it). So archive names are piped
// through `llvm-cxxfilt` before matching; `-` (stdin) is passed as-is.
import { execFileSync } from 'node:child_process';

const NM = 'C:/Program Files/LLVM/bin/llvm-nm.exe';
const FILT = 'C:/Program Files/LLVM/bin/llvm-cxxfilt.exe';
const [wasm, ...specs] = process.argv.slice(2);
if (!wasm || specs.length === 0) {
  console.error('usage: node attribute.mjs <file.wasm> <archive.a:tag> ...');
  process.exit(2);
}

// MSYS/bash auto-converts /c/... when launching a native exe; node does not.
const win = (p) => p.replace(/^\/([a-zA-Z])\//, (_, d) => d.toUpperCase() + ':/');

function nmLines(file) {
  const out = execFileSync(NM, ['--print-size', '--defined-only', win(file)], {
    maxBuffer: 1 << 30,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'ignore'],
  });
  return out.split(/\r?\n/);
}

function demangle(names) {
  if (names.length === 0) return [];
  const out = execFileSync(FILT, [], {
    input: names.join('\n') + '\n',
    maxBuffer: 1 << 30,
    encoding: 'utf8',
  });
  return out.split(/\r?\n/);
}

const perArchive = [];
for (const spec of specs) {
  const i = spec.lastIndexOf(':');
  const path = spec.slice(0, i);
  const tag = spec.slice(i + 1);
  const map = new Map();
  let member = '?';
  const raw = []; // {size, member, name}
  for (const line of nmLines(path)) {
    if (!line.trim()) continue;
    if (/:\s*$/.test(line) && !/^\S+\s+\S+\s+/.test(line)) {
      member = line.replace(/:\s*$/, '');
      continue;
    }
    const m = line.match(/^([0-9a-f]+)\s+([0-9a-f]+)\s+([A-Za-z])\s+(.*)$/);
    if (!m) continue;
    const size = parseInt(m[2], 16);
    const type = m[3];
    const name = m[4];
    if (size === 0 || type === 'U' || type === 'w') continue;
    if (/^\.(debug|reloc|comment)/.test(name)) continue;
    raw.push({ size, member, name });
  }
  const dem = demangle(raw.map((r) => r.name));
  raw.forEach((r, i) => {
    const n = dem[i] ?? r.name;
    if (!map.has(n)) map.set(n, { size: r.size, member: r.member });
  });
  perArchive.push({ tag, path, map });
}

// walk the wasm's own symbols
const sums = new Map();
const memberSums = new Map();
const unmatched = new Map();
let total = 0;
for (const line of nmLines(wasm)) {
  const m = line.match(/^([0-9a-f]+)\s+([0-9a-f]+)\s+([A-Za-z])\s+(.*)$/);
  if (!m) continue;
  const size = parseInt(m[2], 16);
  if (!size) continue;
  const name = m[4];
  if (/^\.(debug|reloc|comment)/.test(name)) continue;
  total += size;
  let found = null;
  for (const { tag, map } of perArchive) {
    if (map.has(name)) { found = { tag, member: map.get(name).member }; break; }
  }
  if (found) {
    sums.set(found.tag, (sums.get(found.tag) ?? 0) + size);
    const k = `${found.tag}/${found.member}`;
    memberSums.set(k, (memberSums.get(k) ?? 0) + size);
  } else {
    unmatched.set(name, (unmatched.get(name) ?? 0) + size);
  }
}

const kib = (b) => (b / 1024).toFixed(1);
console.log(`wasm: ${wasm}`);
console.log(`sum(defined symbol sizes) = ${total} B (${kib(total)} KiB)`);
console.log('--- by archive ---');
for (const [tag, b] of [...sums].sort((a, b) => b[1] - a[1])) {
  console.log(`  ${tag.padEnd(34)} ${String(b).padStart(8)} B  ${kib(b).padStart(7)} KiB  ${(100 * b / total).toFixed(1)}%`);
}
const un = [...unmatched.values()].reduce((a, b) => a + b, 0);
console.log(`  ${'(unmatched: crt/wasm glue/data)'.padEnd(34)} ${String(un).padStart(8)} B  ${kib(un).padStart(7)} KiB  ${(100 * un / total).toFixed(1)}%`);
console.log('--- top members ---');
for (const [k, b] of [...memberSums].sort((a, b) => b[1] - a[1]).slice(0, 34)) {
  console.log(`  ${k.padEnd(50)} ${String(b).padStart(7)} B  ${kib(b).padStart(7)} KiB`);
}
console.log('--- unmatched total by prefix ---');
const byPrefix = new Map();
for (const [k, b] of unmatched) {
  const p = k.startsWith('facebook::yoga') || k.startsWith('_ZN8facebook')
    ? 'Yoga C++ (unmatched)' : k.startsWith('.') ? 'linker data/rodata' : 'other';
  byPrefix.set(p, (byPrefix.get(p) ?? 0) + b);
}
for (const [p, b] of [...byPrefix].sort((a, b) => b[1] - a[1])) {
  console.log(`  ${p.padEnd(30)} ${String(b).padStart(8)} B  ${kib(b)} KiB`);
}

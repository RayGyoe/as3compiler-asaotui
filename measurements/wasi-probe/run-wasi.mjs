// Minimal WASI preview1 runner for the U1 precheck probes.
//
//   node --no-warnings run-wasi.mjs <file.wasm> [args...]
//
// Why this exists: the U1 gate needs the seam to *run* on the strict
// `wasm32-wasip1` target, not merely to compile. This host has no wasmtime /
// wasmer, but Node >= 20 ships `node:wasi`, which is enough for a
// `-mexec-model=command` module built with the wasi-sdk sysroot.
import { readFileSync } from 'node:fs';
import { WASI } from 'node:wasi';

const file = process.argv[2];
if (!file) {
  console.error('usage: node run-wasi.mjs <file.wasm> [args...]');
  process.exit(2);
}

const wasi = new WASI({
  version: 'preview1',
  args: [file, ...process.argv.slice(3)],
  env: {},
  returnOnExit: true,
});

const module = new WebAssembly.Module(readFileSync(file));
const instance = new WebAssembly.Instance(module, {
  wasi_snapshot_preview1: wasi.wasiImport,
});

const code = wasi.start(instance);
process.exit(code ?? 0);

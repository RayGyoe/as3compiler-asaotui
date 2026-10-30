// run-check.cjs -- compile + RUN CheckUi.as through our own AOT and propagate
// its exit code. Zero failures => exit 0; any assertion failure throws inside the
// program, which the AOT runtime turns into a non-zero exit.
//
// Usage:  node run-check.cjs
// Needs:  clang on PATH (or ASC_CC pointing at clang.exe).
'use strict';

const path = require('path');
const { spawnSync } = require('child_process');
const { ALL } = require('./kit-list.cjs');

const here = __dirname;
const compilerDir = path.resolve(here, '..', '..', 'as3compiler');
const check = path.join(here, 'CheckUi.as');

const clang = process.env.ASC_CC || 'clang';
const args = [
  path.join(compilerDir, 'src', 'index.ts'),
  check,
  ...ALL,
  '--run',
  '--cc', clang,
  // Include/link flags come from the manifest, which is the single place that
  // knows what each host needs. Hand-spelling the Windows curl import library and
  // `-l zlib` here made this check unrunnable on macOS (clang looks for a file
  // named "libzlib.a" and stops).
  '--manifest', 'examples/window.build.example.json'
];

console.log('[run-check] compiling + running CheckUi.as via our AOT');
const r = spawnSync(process.execPath, args, { cwd: compilerDir, stdio: 'inherit' });
console.log('[run-check] aot exit code:', r.status);
process.exit(r.status == null ? 1 : r.status);

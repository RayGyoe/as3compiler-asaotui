// probes/kit-crash/run.cjs -- compile + run StaticInit2.as through our own AOT and
// report the exit status in BOTH forms (decimal and the Windows NTSTATUS hex),
// because a crash shows up as a large decimal number that looks like a normal
// exit code at a glance. 3221225477 == 0xC0000005 == EXCEPTION_ACCESS_VIOLATION.
'use strict';

const path = require('path');
const { spawnSync } = require('child_process');
const fs = require('fs');
const { ALL } = require('../../ui-demo/kit-list.cjs');

const here = __dirname;
const compilerDir = path.resolve(here, '..', '..', '..', 'as3compiler');
const src = path.join(here, 'StaticInit2.as');

const log = path.join(here, 'static2.txt');
if (fs.existsSync(log)) fs.unlinkSync(log);

const clang = process.env.ASC_CC || 'clang';
const r = spawnSync(process.execPath, [
  path.join(compilerDir, 'src', 'index.ts'),
  src, ...ALL,
  '--run', '--cc', clang,
  '-I', './vendor/curl/include',
  '-L', './vendor/curl/lib/windows-x64',
  '-l', 'zlib'
], { cwd: compilerDir, encoding: 'buffer' });

const status = r.status;
const hex = status == null ? 'null' : '0x' + (status >>> 0).toString(16).toUpperCase();
const out = (r.stdout || Buffer.alloc(0)).toString('utf8');
const err = (r.stderr || Buffer.alloc(0)).toString('utf8');

console.log('--- stdout (' + out.length + ' B) ---');
console.log(out);
console.log('--- stderr (' + err.length + ' B) ---');
console.log(err);
console.log('--- static2.txt ---');
console.log(fs.existsSync(log) ? fs.readFileSync(log, 'utf8') : '(no log written)');
console.log('status=' + status + '  (' + hex + ')');
if (hex === '0xC0000005') console.log('=> EXCEPTION_ACCESS_VIOLATION (segfault)');
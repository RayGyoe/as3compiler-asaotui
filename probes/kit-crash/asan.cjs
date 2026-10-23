// probes/kit-crash/asan.cjs -- get the FAULTING LINE instead of guessing.
//
// Every step-trace probe survived, so guessing which construct crashes was burning
// time. AddressSanitizer names the exact function and line of an access violation,
// and our AOT keeps the generated C ("Generated C kept at: ..."), so the move is:
//
//   1. let the AOT emit <target>.c and build it normally (proves the program
//      compiles and reproduces the crash),
//   2. recompile THAT SAME .c by hand with -fsanitize=address --debug-info/-g,
//   3. run it and print ASan's report.
//
// Step 2 is deliberate: `--opt` accepts a SINGLE flag (passing
// "-O1 -fsanitize=address" makes clang read it as one malformed argument), and a
// bare `-g` on the CLI is rejected outright ("unknown argument: -g"), so there is
// no sanctioned one-shot way to inject ASan. Compiling the kept .c ourselves is
// the same translation unit the AOT produced -- nothing about the AS3 program
// changes.
//
// Usage:  node asan.cjs <path-to-.as>
'use strict';

const path = require('path');
const { spawnSync } = require('child_process');
const fs = require('fs');
const { ALL } = require('../../ui-demo/kit-list.cjs');

const here = __dirname;
const compilerDir = path.resolve(here, '..', '..', '..', 'as3compiler');
const target = path.resolve(process.argv[2] || path.join(here, '..', '..', 'ui-demo', 'CheckUi.as'));
const stem = target.replace(/\.[^./\\]+$/, '');
const cFile = stem + '.c';
const clang = process.env.ASC_CC || 'clang';

// ---- 1. emit C + build normally -------------------------------------------
const build = spawnSync(process.execPath, [
  path.join(compilerDir, 'src', 'index.ts'),
  target, ...ALL,
  '--cc', clang,
  '-I', './vendor/curl/include',
  '-L', './vendor/curl/lib/windows-x64',
  '-l', 'zlib'
], { cwd: compilerDir, encoding: 'buffer' });

const buildOut = (build.stdout || Buffer.alloc(0)).toString('utf8');
if (build.status !== 0 || !fs.existsSync(cFile)) {
  console.log('--- build stdout (tail) ---');
  console.log(buildOut.split('\n').slice(-15).join('\n'));
  console.log('--- build stderr (errors) ---');
  console.log((build.stderr || Buffer.alloc(0)).toString('utf8')
    .split('\n').filter((l) => /error:|fatal/.test(l)).slice(0, 20).join('\n'));
  console.log('BUILD FAILED, status=' + build.status);
  process.exit(1);
}

// ---- 2. recompile the SAME .c with ASan ------------------------------------
const asanExe = stem + '.asan.exe';
const cc = spawnSync(clang, [
  '-O1', '-g', '-fsanitize=address', '-fno-omit-frame-pointer', '-ffp-contract=off',
  '-w',                                   // the 175 deprecation warnings are noise here
  '-o', asanExe, cFile,
  '-l', 'shell32',
  '-I', path.join(compilerDir, 'vendor/curl/include'),
  '-L', path.join(compilerDir, 'vendor/curl/lib/windows-x64'),
  '-l', 'zlib'
], { cwd: compilerDir, encoding: 'buffer' });

if (cc.status !== 0) {
  console.log('--- clang -fsanitize=address failed ---');
  console.log((cc.stderr || Buffer.alloc(0)).toString('utf8').split('\n').slice(0, 25).join('\n'));
  process.exit(2);
}

// ---- 3. run it -------------------------------------------------------------
// clang's ASan runtime is a DLL (clang_rt.asan_dynamic-x86_64.dll) that lives in
// clang's own bin directory; without that on PATH the process dies with
// 0xC0000135 (STATUS_DLL_NOT_FOUND) and prints no report at all.
const whereClang = spawnSync('where', ['clang'], { encoding: 'utf8' });
const clangBin = (whereClang.stdout || '').split('\n')[0].trim();
const clangDir = clangBin ? path.dirname(clangBin) : '';
const llvmRoot = clangDir ? path.dirname(clangDir) : '';
const env = { ...process.env };
if (clangDir) env.PATH = clangDir + ';' + (env.PATH || '');
// The ASan DLL is NOT in bin/ -- it ships under lib/clang/<major>/lib/windows.
// Find it instead of hardcoding the version, and put that directory on PATH.
let asanDir = '';
try {
  const major = fs.readdirSync(path.join(llvmRoot, 'lib', 'clang'))[0];
  asanDir = path.join(llvmRoot, 'lib', 'clang', major, 'lib', 'windows');
  if (env.PATH.split(';').indexOf(asanDir) < 0) env.PATH = asanDir + ';' + env.PATH;
} catch (e) { /* fall through: the DLL-not-found message below explains it */ }

const run = spawnSync(asanExe, [], { timeout: 120000, encoding: 'buffer', env });
const status = run.status;
const hex = status == null ? 'null' : '0x' + (status >>> 0).toString(16).toUpperCase();
const err = (run.stderr || Buffer.alloc(0)).toString('utf8');
const out = (run.stdout || Buffer.alloc(0)).toString('utf8');

console.log('--- program stdout ---');
console.log(out.split('\n').filter((l) => l.trim()).slice(0, 40).join('\n') || '(empty)');
console.log('--- AddressSanitizer ---');
const asan = err.split('\n').filter((l) =>
  /AddressSanitizer|SUMMARY|^\s+#\d+|READ of size|WRITE of size|SEGV|is located|allocated by|Uncaught/.test(l));
console.log(asan.length ? asan.slice(0, 40).join('\n') : '(no ASan report; stderr len=' + err.length + ')');
console.log('status=' + status + '  (' + hex + ')');
if (hex === '0xC0000135') console.log('=> STATUS_DLL_NOT_FOUND (ASan runtime DLL not on PATH; looked in ' + asanDir + ')');
if (hex === '0xC0000005') console.log('=> EXCEPTION_ACCESS_VIOLATION');
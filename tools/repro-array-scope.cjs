// tools/repro-array-scope.cjs -- reproducible witness for compiler gaps G11 and G12
// (see compiler-gaps.md). One command, two possible verdicts, because the program
// under it fails in one of two independent ways:
//
//   G11 -- the BUILD fails (sometimes, on unchanged source): the generated C does
//          not compile, with errors pointing into code nobody wrote
//   G12 -- the BUILD passes and the RUN hangs: the process stays alive, the frame
//          loop keeps ticking, and the log stops at the statement after a ~134 KB
//          byte-buffer allocation
//
//   node tools/repro-array-scope.cjs
//
// Verdicts:
//   REPRODUCED (codegen)  -- build failed with errors in generated code
//   REPRODUCED (uncaught) -- the run printed "Uncaught exception: ..." to stderr: the
//                            frame loop survives, a callback died, and the log simply
//                            stops -- which reads as a hang unless stderr is kept
//   REPRODUCED (runtime)  -- build was fine, no uncaught error, the run stalled
//   NOT REPRODUCED        -- build was fine and the log reached DONE
//
// stderr MUST be forwarded (it was not, until G12 was closed): the runtime reports an
// uncaught error there and keeps running, so discarding stderr turns a TypeError into
// an apparent infinite hang. G12 was exactly that -- see compiler-gaps.md.
//
// Re-run it on a build failure: G11 is intermittent, so a second run often gets past
// it, and the two are worth seeing separately.
'use strict';
const fs = require('fs');
const path = require('path');
const { spawnSync, spawn, execSync } = require('child_process');
const { ALL } = require('../ui-demo/kit-list.cjs');

const UI = path.resolve(__dirname, '..');
const COMPILER = path.resolve(UI, '..', 'as3compiler');
const clang = process.env.ASC_CC || 'clang';
const dir = path.join(UI, 'probes', 'array-scope');
const LOG = path.join(dir, 'array-scope.log.txt');
const DONE = path.join(dir, 'array-scope.done');
const args = [
  'src/index.ts', path.join(dir, 'Main.as'), ...ALL,
  '--manifest', 'examples/window.build.example.json',
  '--cc', clang, '-I', './vendor/curl/include', '-L', './vendor/curl/lib/windows-x64', '-l', 'zlib'
];

for (const f of [LOG, DONE]) if (fs.existsSync(f)) fs.unlinkSync(f);
const icu = path.join(UI, 'ui-demo', 'icudtl.dat');
if (fs.existsSync(icu) && !fs.existsSync(path.join(dir, 'icudtl.dat'))) fs.copyFileSync(icu, path.join(dir, 'icudtl.dat'));

console.log('[repro] building array-scope (the whole kit is compiled in, as in a real app)');
const started = Date.now();
const b = spawnSync(process.execPath, args, { cwd: COMPILER, encoding: 'utf8' });
if (b.status !== 0) {
  const out = (b.stdout || '') + (b.stderr || '');
  const errs = out.split(/\r?\n/).filter((l) => /error:/.test(l));
  console.log('---- build errors (' + errs.length + ') ----');
  console.log(errs.slice(0, 10).join('\n'));
  console.log('---- verdict ----');
  if (errs.length > 0) {
    console.log('REPRODUCED (codegen): the generated C does not compile. This is G11, not a runtime');
    console.log('fault -- the program never ran at all.');
    process.exit(0);
  }
  console.error('[repro] BUILD FAILED for a reason other than a C error (exit ' + b.status + ')');
  console.error(out.split(/\r?\n/).slice(-30).join('\n'));
  process.exit(1);
}

let exe = null;
for (const f of fs.readdirSync(dir)) {
  if (!f.toLowerCase().endsWith('.exe')) continue;
  const p = path.join(dir, f);
  if (fs.statSync(p).mtimeMs + 5000 >= started) exe = p;
}
if (exe == null) { console.error('[repro] build succeeded but no fresh .exe in ' + dir); process.exit(1); }
const exeName = path.basename(exe);
console.log('[repro] built ' + path.relative(UI, exe));

const child = spawn(exe, [], { cwd: dir, detached: true, stdio: ['ignore', 'ignore', 'pipe'] });
let errOut = '';
child.stderr.on('data', (d) => { errOut += d.toString(); });
child.unref();

setTimeout(function () {
  let alive = false;
  try {
    execSync('tasklist /FI "IMAGENAME eq ' + exeName + '"', { stdio: 'ignore' });
    alive = true;
  } catch (e) { alive = false; }
  try { execSync('taskkill /F /IM "' + exeName + '"', { stdio: 'ignore' }); } catch (e) { /* gone */ }

  const log = fs.existsSync(LOG) ? fs.readFileSync(LOG, 'utf8') : '';
  const done = fs.existsSync(DONE) ? fs.readFileSync(DONE, 'utf8') : null;
  console.log('---- program log ----');
  console.log(log === '' ? '(empty)' : log.replace(/\s+$/, ''));
  console.log('---- stderr ----');
  console.log(errOut.trim() === '' ? '(empty)' : errOut.trim());
  console.log('---- verdict ----');
  console.log('process alive when observed: ' + alive);
  console.log('done file: ' + (done === null ? '(none)' : done));

  // The last "step N enter" without its matching "step N OK" is the killed statement.
  const lines = log.split(/\r?\n/).filter((l) => l.trim() !== '');
  const last = lines.length ? lines[lines.length - 1] : '';
  if (done !== null && done.indexOf('PASS') === 0) {
    console.log('NOT REPRODUCED: the build was fine and the log reached DONE.');
    process.exit(0);
  }
  const uncaught = errOut.split(/\r?\n/).filter((l) => /Uncaught exception/.test(l));
  if (uncaught.length > 0) {
    console.log('REPRODUCED (uncaught): the program did NOT hang. A callback threw and the runtime');
    console.log('reported it on stderr (which this tool used to discard, which is what made G12');
    console.log('look like a heap hang):');
    console.log('  ' + uncaught.join('\n  '));
    console.log('The log stops at "' + last + '" because that callback never re-armed itself.');
    process.exit(0);
  }
  console.log('REPRODUCED (runtime): the log stops at "' + last + '" -- whatever that step does in the source killed the process.');
  process.exit(0);
}, 2500);

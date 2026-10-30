// run.cjs -- one command that pins compiler-gaps.md G13 (FIXED), with every face
// measured in the same run.
//
//   measurement 1  closure dump    MUST keep 5/5 files (Base and Helper included)
//   arm A          --air-app       same source, plain closure
//                                  MUST build, link, run to exit 0
//   arm B          --all-sources   same source, same descriptor
//                                  MUST still build and run (the escape hatch has
//                                  to keep working; it is no longer needed, but a
//                                  fix that broke it would be a regression)
//
// Before the fix (compiler HEAD 721e12f) arm A failed with
// `unknown superclass 'Base' of 'p_Leaf'` and the closure kept 3/5: classes whose
// only entry point is a forced file were marked reachable but never expanded, so
// their superclass and referenced classes were pruned. --all-sources masked it by
// turning pruning off.
//
// Keeping both arms in one command is what makes the claim falsifiable in BOTH
// directions: if the closure regresses, arm A goes red here; if someone "fixes" it
// by disabling pruning, arm B is the control that says the two faces must agree.
//
// A build-free measurement comes first: the closure itself, dumped by
// tools/reach-dump.cjs. It is the crispest evidence (5/5 kept, 0 dropped) and it
// costs a second, so it is asserted before any compilation.
//
// Usage:   node probes/reach-freefn/run.cjs
// Env:     ASC_CC        clang to use (default `clang` on PATH)
'use strict';

const path = require('path');
const fs = require('fs');
const { spawnSync } = require('child_process');

const UI = path.resolve(__dirname, '..', '..');
const COMPILER = path.resolve(UI, '..', 'as3compiler');
const HERE = __dirname;
const clang = process.env.ASC_CC || 'clang';
// The AOT appends `.exe` only on Windows; on macOS/Linux the artifact is the bare
// name, so a Windows-spelled path made both arms report "emitted ..." FAIL even
// though the link exited 0.
const EXE_NAME = process.platform === 'win32' ? 'ReachFreeFn.exe' : 'ReachFreeFn';
const EXE = path.join(HERE, EXE_NAME);

const sh = (args, cwd) => spawnSync(process.execPath, args, { cwd, encoding: 'utf8', maxBuffer: 1 << 28 });
const both = (r) => (r.stdout || '') + (r.stderr || '');
const tail = (s, n) => s.split(/\r?\n/).filter((l) => l.trim() !== '').slice(-n).join('\n');

const fails = [];
function check(ok, label, detail) {
  console.log((ok ? '  ok   ' : '  FAIL ') + label);
  if (!ok) fails.push(label + (detail ? '\n' + tail(detail, 10) : ''));
}

// --- measurement 1: the closure, no compilation ------------------------------
console.log('== closure dump (tools/reach-dump.cjs) ==');
{
  const r = sh([path.join(UI, 'tools', 'reach-dump.cjs'), path.join(HERE, 'src'), 'p.Main'], UI);
  const out = both(r);
  console.log(tail(out, 12).split('\n').map((l) => '     ' + l).join('\n'));
  const kept = (out.match(/^KEPT \((\d+)\)/m) || [])[1];
  const dropped = (out.match(/^DROPPED \((\d+)\)/m) || [])[1];
  // Read the two file names from the KEPT section only. Testing the whole output
  // would stay green if they leaked into DROPPED as well (the pre-fix version of
  // this probe had exactly that bug; mutation.cjs caught it).
  const keptBlock = out.slice(out.indexOf('KEPT ('), out.indexOf('DROPPED ('));
  check(r.status === 0, 'closure dump exits 0', out);
  check(kept === '5', 'closure keeps 5/5 files (expect 5: Main, Fac, Leaf, Base, Helper)', out);
  check(dropped === '0', 'closure drops nothing', out);
  check(/^  p\/Base\.as$/m.test(keptBlock) && /^  p\/Helper\.as$/m.test(keptBlock),
    'closure KEEPS p/Base.as and p/Helper.as (reached through the forced file)', out);
}

// --- arms A and B: same source, two faces, both must build and run -----------
function build(extraArgs, label) {
  if (fs.existsSync(EXE)) fs.unlinkSync(EXE);   // a stale exe would fake a pass
  const r = sh(['src/index.ts', '--air-app', path.join(HERE, 'app.xml'),
    '--main-class', 'p.Main', ...extraArgs, '--cc', clang], COMPILER);
  const out = both(r);
  console.log('== ' + label + ' ==');
  console.log('     exit ' + r.status + '  ' + (r.error ? String(r.error) : ''));
  console.log(tail(out, 4).split('\n').map((l) => '     ' + l).join('\n'));
  return { r, out, exe: fs.existsSync(EXE) };
}

function buildAndRun(extraArgs, label) {
  const b = build(extraArgs, label);
  check(b.r.status === 0, label + ' builds and links (exit 0)', b.out);
  check(b.exe, label + ' emitted ' + EXE_NAME, '');
  if (!b.exe) return;
  const r = spawnSync(EXE, [], { cwd: HERE, encoding: 'utf8', maxBuffer: 1 << 24 });
  const out = both(r);
  console.log('     run: exit ' + r.status + '  ' + tail(out, 3).replace(/\n/g, ' | '));
  check(r.status === 0, label + ' runs to exit 0', out);
  check(/rendered/.test(out), label + ' printed its render line', out);
}

buildAndRun([], 'arm A: plain --air-app closure (was the defect)');
buildAndRun(['--all-sources'], 'arm B: --all-sources (control: must still work)');

console.log('');
if (fails.length) {
  console.log('==== G13 PROBE: FAIL (' + fails.length + ') ====');
  for (const f of fails) console.log('  ' + f);
  process.exit(1);
}
console.log('==== G13 PROBE: PASS -- closure keeps 5/5, both --air-app faces build and run ====');
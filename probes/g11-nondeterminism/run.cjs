// run.cjs -- the closing measurement for compiler-gaps.md G11.
//
// G11 was registered as "the same source, built twice, produced DIFFERENT C -- the
// generator is nondeterministic". That reading is wrong, and this probe is the
// evidence path that replaced it:
//
//   A. the compiler tree state is PRINTED (HEAD + every dirty path). A dirty tree
//      is the one condition under which two builds of the same program really do
//      emit different C -- because the thing that changed is the COMPILER, not the
//      input. This is not a hypothesis: see measurement D.
//   B. N builds of the same program, same command, same tree -> ONE hash. If the
//      generator were nondeterministic this is where it would show, and it is the
//      only measurement that could show it. The generator's own bytes are sampled
//      around EVERY build, not once at the two ends: an edit that is put in place and
//      then REVERTED inside the window leaves both endpoints identical, so the
//      endpoint pair cannot tell "the generator is unstable" from "someone compiled a
//      mutant and put it back". Revert-in-place is what the compiler session's own
//      mutation harness does, and it produced a false red here on 2026-10-23.
//   C. a spelling tripwire on the freshly generated C: the three built-in fields
//      G11 named (Date._time, TextField.___restrict, ServerSocketConnectEvent.socket)
//      must be spelled the BLOCK-scope way in the struct, in the props table AND in
//      the hand-written body literal -- the three places that have to agree.
//   D. the three surviving artifacts from the 84-second window in which the naming
//      rewrite was on disk (阶段二百四十七). Same program, three different generated
//      C files; clang's error count decays 20 -> 1 -> 0. A generator that "sometimes"
//      misspells a field does not converge monotonically in 84 seconds; a human
//      edit does.
//
// Usage:   node probes/g11-nondeterminism/run.cjs
// Env:     ASC_G11_RUNS  number of builds in measurement B (default 5)
//          ASC_CC        clang to use (default: clang on PATH)
//          ASC_G11_FORCE_SKIP=1     mutation hook: the end-of-run re-hash sees a move
//          ASC_G11_FORCE_ITER=<n>   mutation hook: the per-build sample at n sees a move
//          ASC_G11_EVIDENCE=off     do not append to the evidence file
//
// Evidence: probes/g11-nondeterminism/run-<date>.txt   (APPENDED, never overwritten
//           -- an earlier green must not be erasable by a later red).
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const HERE = __dirname;                                  // asaotui/probes/g11-nondeterminism
const UI = path.resolve(HERE, '..', '..');               // asaotui
const REPO = path.resolve(UI, '..', 'as3compiler');
const clang = process.env.ASC_CC || 'clang';
const RUNS = Number(process.env.ASC_G11_RUNS || 5);
const PROBE = path.join(UI, 'probes', 'array-scope');    // the G11 witness program
const GEN = path.join(PROBE, 'Main.c');
const { ALL } = require(path.join(UI, 'ui-demo', 'kit-list.cjs'));

const out = [];
const say = (s) => { console.log(s); out.push(s); };
const sha16 = (f) => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex').slice(0, 16);

// A content hash over the compiler's own sources: `git status` says WHICH files
// differ from HEAD, this says WHICH TREE the measurement actually saw. A build can
// only be reproduced later if the tree identity travels with the evidence, and on
// this machine another session is editing the compiler while we measure (observed
// live: clean at 21:56, three tracked modifications at 21:59).
function srcTreeHash() {
  const h = crypto.createHash('sha256');
  const walk = (d) => {
    for (const e of fs.readdirSync(d, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
      const p = path.join(d, e.name);
      if (e.isDirectory()) { if (e.name !== 'node_modules') walk(p); continue; }
      h.update(e.name); h.update(fs.readFileSync(p));
    }
  };
  walk(path.join(REPO, 'src'));
  return h.digest('hex').slice(0, 16);
}
const errLines = (s) => (s || '').split(/\r?\n/).filter((l) => /error:/.test(l));

// The one decision this probe exists to make, isolated so mutation.cjs can drive it
// directly: N builds differed. That is EITHER nondeterminism OR the generator's own
// bytes changed under one of the builds -- and in the second case it is not evidence of
// anything at all. Only the first reading is a defect. (`movedBuilds` comes from the
// per-build samples in B, never from the endpoint pair: an edit that is reverted inside
// the window leaves both endpoints identical, so the endpoints cannot answer this.)
function distinctVerdict(uniqSize, runs, movedBuilds) {
  if (uniqSize === 1) return { label: 'ONE output for one input' };
  if (movedBuilds > 0) {
    return {
      label: 'the generator MOVED mid-run (see the src/ stamp on each build above)'
        + ' -- NOT evidence of nondeterminism'
    };
  }
  return {
    label: 'THE GENERATOR IS NONDETERMINISTIC',
    failure: 'the ' + runs + ' builds produced ' + uniqSize + ' distinct C files'
  };
}

// ---------------------------------------------------------------------------
// The one checker both this probe and its mutation use: compile the generated C
// with the SAME flags the build uses, and count clang's errors. Nothing about the
// naming is parsed here -- clang is the authority on whether a struct field and
// the code that touches it agree, which is exactly the thing that broke.
// NOTE: clang's default -ferror-limit is 20, so a file that breaks the SAME way in
// many places reports the CAP, not its real count (artifact-1 ends with
// `fatal error: too many errors emitted`). The expectation for that file is
// therefore `truncated`, not `20` -- asserting a cap would make the probe red on a
// clang upgrade and teaches nothing.
// ---------------------------------------------------------------------------
const CC_FLAGS = [
  '-fsyntax-only',
  '--target=x86_64-pc-windows-msvc',
  '-fms-runtime-lib=static',
  '-O2',
  '-ffp-contract=off',
  '-D', 'ASC_USE_SKIA=1',
  '-D', 'ASC_USE_WINDOW=1',
  '-D', 'ASC_HAVE_TEXT',
  '-I', './vendor/skia',
  '-I', './vendor/sdl2/include/windows-x64',
  '-I', './vendor/curl/include'
];

function cErrors(cfile) {
  const r = spawnSync(clang, [...CC_FLAGS, cfile], { cwd: REPO, encoding: 'utf8', maxBuffer: 1 << 28 });
  const errs = [];
  const stderr = r.stderr || '';
  for (const rec of stderr.split(/\r?\n/)) {
    const m = /^(.+?):(\d+):(\d+): error: (.*)$/.exec(rec);
    if (m) errs.push({ line: Number(m[2]), col: Number(m[3]), msg: m[4] });
  }
  const gen = /(\d+) errors? generated/.exec(stderr);
  return {
    status: r.status,
    errors: errs,
    truncated: /too many errors emitted/.test(stderr),
    summary: gen ? Number(gen[1]) : null,
    // The hazard kinds, e.g. "Date._time": what broke, not how many times.
    // clang spells this two ways -- `in 'struct Date'` for a variable and `in 'Date'`
    // for a type -- and only the second one appeared in the M1 mutant, so the
    // optional `struct ` is required, not cosmetic.
    kinds: [...new Set(errs.map((e) => {
      const k = /member named '([^']+)' in '(?:struct )?(\w+)'/.exec(e.msg);
      return k ? k[2] + '.' + k[1] : 'other';
    }))].sort()
  };
}

// ---------------------------------------------------------------------------
// C. spelling tripwire. The three fields G11 named, in the three places that must
// agree. A struct field and the body that touches it are renamed by the same
// cIdent() call -- but the body is a hand-written C string inside emit.ts, so it
// is a LITERAL, and that is the seam G11 fell through.
// ---------------------------------------------------------------------------
const TRIPWIRE = [
  { struct: 'Date', field: '_time', body: 'o->_time' },
  { struct: 'TextField', field: '___restrict', body: 'tf->___restrict' },
  { struct: 'ServerSocketConnectEvent', field: 'socket', body: '->socket' }
];

function structFieldNames(text, struct) {
  const lines = text.split('\n');
  const names = new Set();
  for (let i = 0; i < lines.length; i++) {
    if (lines[i] !== 'struct ' + struct + ' {') continue;
    for (let j = i + 1; j < lines.length && lines[j] !== '};'; j++) {
      const m = /([A-Za-z_]\w*)\s*(\[\d+\])?\s*;/.exec(lines[j]);
      if (m) names.add(m[1]);
      const fp = /\(\*([A-Za-z_]\w*)\)/.exec(lines[j]);
      if (fp) names.add(fp[1]);
    }
    break;
  }
  return names;
}

function spellingProblems(text) {
  const problems = [];
  for (const t of TRIPWIRE) {
    const fields = structFieldNames(text, t.struct);
    if (fields.size === 0) { problems.push('struct ' + t.struct + ' not found in the generated C'); continue; }
    if (!fields.has(t.field)) {
      problems.push('struct ' + t.struct + ' declares no `' + t.field + '` (has: ' + [...fields].join(', ') + ')');
    }
    if (!text.includes('offsetof(' + t.struct + ', ' + t.field + ')')) {
      problems.push('the props table has no offsetof(' + t.struct + ', ' + t.field + ')');
    }
    if (!text.includes(t.body)) {
      problems.push('the hand-written body literal `' + t.body + '` is gone; struct and body would disagree');
    }
  }
  // every offsetof(S, X) must name a field struct S actually declares
  const re = /offsetof\(([A-Za-z_]\w*), ([A-Za-z_]\w*)\)/g;
  let m;
  const checked = new Set();
  while ((m = re.exec(text))) {
    if (checked.has(m[1])) continue;
    checked.add(m[1]);
    const fields = structFieldNames(text, m[1]);
    if (fields.size === 0) continue;
    if (!fields.has(m[2])) problems.push('offsetof(' + m[1] + ', ' + m[2] + ') but struct ' + m[1] + ' declares ' + [...fields].slice(0, 8).join('/'));
  }
  return problems;
}

// ---------------------------------------------------------------------------
// D. the historical artifacts. Same program, 84 seconds apart.
// ---------------------------------------------------------------------------
const ARTIFACTS = [
  {
    file: 'artifact-1-struct-time__.c', mtime: '2026-10-23 04:00:10 +0800', truncated: true, minErrors: 16,
    kinds: ['Date._time', 'ServerSocketConnectEvent.socket', 'TextField.___restrict'],
    note: 'struct Date { double time__; } + offsetof(Date, time__) while the body literal is o->_time'
  },
  {
    file: 'artifact-2-struct-socket-1-error.c', mtime: '2026-10-23 04:00:50 +0800', truncated: false, exact: 1,
    kinds: ['ServerSocketConnectEvent.socket'],
    note: 'Date repaired; the remaining break is ServerSocketConnectEvent.socket'
  },
  {
    file: 'artifact-3-consistent.c', mtime: '2026-10-23 04:01:34 +0800', truncated: false, exact: 0,
    kinds: [],
    note: 'all three spellings agree; this is the first state that links'
  }
];

// MY OWN failing build, 9 seconds after artifact-1: the same three hazards. This is
// the link between the two artifacts -- they are not two coincidences, they are two
// observations of one on-disk compiler state.
const MY_FAILED_LOG = path.join(UI, 'probes', 'array-scope', 'cc.txt');

function logKinds(file) {
  const text = fs.readFileSync(file, 'utf8');
  const kinds = new Set();
  for (const rec of text.split(/\r?\n/)) {
    const m = /no member named '([^']+)' in '(?:struct )?(\w+)'/.exec(rec);
    if (m) kinds.add(m[2] + '.' + m[1]);
  }
  return [...kinds].sort();
}

function main() {
  const failures = [];   // a measurement that came out WRONG
  const blockers = [];   // the compiler source MOVED mid-run: nothing can be certified
  say('== G11 closing measurement ==  ' + new Date().toISOString());
  say('');

  // Captured before A prints and again after B finishes. This -- not "dirty vs HEAD" --
  // is what makes the measurement valid: determinism is a property of a GENERATOR
  // REVISION, so what matters is that the generator's own bytes did not change while
  // we built five times. A tree modified relative to HEAD but stable is measurable; a
  // tree whose sources change mid-run is not. (Another session on this machine edits
  // src/ regularly, so this distinction is the difference between a usable gate and a
  // coin flip.)
  const srcHashBefore = srcTreeHash();

  // ---- A: the compiler tree state -----------------------------------------
  const git = (...a) => spawnSync('git', ['-C', REPO, ...a], { encoding: 'utf8' });
  const head = git('rev-parse', '--short', 'HEAD').stdout.trim();
  const porcelain = git('status', '--porcelain', '-z').stdout;
  const dirty = [];
  for (const rec of porcelain.split('\0')) {
    if (rec === '') continue;
    if (rec.length < 4 || rec[2] !== ' ') { dirty.push('UNPARSED:' + JSON.stringify(rec)); continue; }
    dirty.push(rec.slice(0, 2) + ' ' + rec.slice(3));
  }
  // Only a TRACKED modification can change what the compiler emits. An untracked
  // data file (icudtl.dat) is copied next to the build and is not source.
  const tracked = dirty.filter((d) => d[0] !== '?' && d[1] !== '?');
  say('A. compiler tree: HEAD ' + head + ', src/ content hash ' + srcHashBefore);
  say('   tracked modifications: ' + (tracked.length ? tracked.join(' | ') : '(none)'));
  say('   untracked: ' + (dirty.length - tracked.length ? dirty.filter((d) => d[0] === '?').join(' | ') : '(none)'));
  if (tracked.length) {
    say('   -> a modified tree is where "two builds of one program emit different C" came from');
    say('      (another session here edits the compiler). It does NOT by itself invalidate this');
    say('      run: what does is the src/ hash MOVING during it, which is checked after B.');
  }
  say('');

  // ---- B: N builds, one hash ----------------------------------------------
  // The claim is "same input, same output", so BOTH sides are hashed: the input
  // sources (the program and the whole kit it pulls in) and the generated C. A
  // determinism claim without the input hash cannot tell "the generator is stable"
  // from "the sources changed under us too".
  // `ALL` holds paths relative to the COMPILER repo (the build's cwd), e.g.
  // `../asaotui/kit/asaot/ui/BoxNode.as` -- resolve them there, not against the kit.
  const inputFiles = [path.join(PROBE, 'Main.as'), ...ALL.map((f) => path.resolve(REPO, f))];
  const inputHash = () => {
    const h = crypto.createHash('sha256');
    for (const f of inputFiles) { h.update(f); h.update(fs.existsSync(f) ? fs.readFileSync(f) : Buffer.from('MISSING')); }
    return h.digest('hex').slice(0, 16);
  };
  say('B. ' + RUNS + ' builds of probes/array-scope/Main.as, same command, same tree');
  const input0 = inputHash();
  say('   input: ' + inputFiles.length + ' .as files, sha256/16 ' + input0
    + ' (' + inputFiles.filter((f) => !fs.existsSync(f)).length + ' missing)');
  const args = [
    'src/index.ts', path.join(PROBE, 'Main.as'), ...ALL,
    '--manifest', 'examples/window.build.example.json',
    '--cc', clang, '-I', './vendor/curl/include', '-L', './vendor/curl/lib/windows-x64', '-l', 'zlib'
  ];
  const hashes = [];
  const fieldProblems = [];
  const srcSamples = [];   // the generator's own bytes immediately before/after EVERY build
  for (let i = 1; i <= RUNS; i++) {
    if (fs.existsSync(GEN)) fs.unlinkSync(GEN);
    // Sampled around EACH build, not once at the two ends of the run. A before/after
    // pair taken only at the ends cannot see an edit that is put in place and REVERTED
    // inside the window -- and revert-in-place is exactly what the compiler session's
    // own mutation harness (as3compiler/temp/g14/mutate.cjs) does: it writes a mutant,
    // runs the unit group, then writes the ORIGINAL BYTES back and hashes them to prove
    // it. Both endpoints then agree while a build in between compiled the mutant.
    // Observed live 2026-10-23 08:45 +0800: run 4 of 5 differed by 82 B from the other
    // four, inside exactly such a window, with srcHashBefore == srcHashAfter.
    const before = process.env.ASC_G11_FORCE_ITER === String(i) ? srcHashBefore + '-moved' : srcTreeHash();
    const t0 = Date.now();
    const r = spawnSync(process.execPath, args, { cwd: REPO, encoding: 'utf8', maxBuffer: 1 << 28, timeout: 600000 });
    const secs = ((Date.now() - t0) / 1000).toFixed(1);
    const after = srcTreeHash();
    srcSamples.push({ i, before, after });
    const stamp = '  [src ' + before.slice(0, 8) + (after === before ? '' : ' -> ' + after.slice(0, 8))
      + (before !== srcSamples[0].before || after !== before ? ' MOVED' : '') + ']';
    if (r.status !== 0 || !fs.existsSync(GEN)) {
      const errs = errLines((r.stdout || '') + (r.stderr || ''));
      say('   run ' + i + ': BUILD FAILED (exit ' + r.status + ', ' + errs.length + ' C errors, ' + secs + 's)' + stamp);
      for (const e of errs.slice(0, 3)) say('       ' + e.slice(-140));
      if (errs.length) say('       -> this is the G11 SYMPTOM. Check the dirty list in A before anything else.');
      failures.push('run ' + i + ' did not build');
      continue;
    }
    const h = sha16(GEN);
    const size = fs.statSync(GEN).size;
    hashes.push(h);
    const sp = spellingProblems(fs.readFileSync(GEN, 'utf8'));
    fieldProblems.push(...sp.map((p) => 'run ' + i + ': ' + p));
    say('   run ' + i + ': ' + size + ' B  sha256/16 ' + h + '  (' + secs + 's)' + stamp);
  }
  const uniq = new Set(hashes);
  const input1 = inputHash();
  // Mutation hooks, both used by mutation.cjs. They can only turn a PASS into a SKIP,
  // never the other way round. ASC_G11_FORCE_SKIP fakes the END-of-run re-hash moving;
  // ASC_G11_FORCE_ITER=<n> fakes the per-build sample at iteration n moving.
  const srcHashAfter = process.env.ASC_G11_FORCE_SKIP === '1' ? srcHashBefore + '-moved' : srcTreeHash();
  say('   input hash after the runs: ' + input1 + (input1 === input0 ? ' (unchanged)' : ' (CHANGED -- the measurement is void)'));
  say('   src/ content hash after the runs: ' + srcHashAfter
    + (srcHashAfter === srcHashBefore ? ' (unchanged -> the generator revision was stable)'
                                      : ' (CHANGED -> the compiler moved mid-run)'));
  if (input1 !== input0) failures.push('the input sources changed during the measurement (' + input0 + ' -> ' + input1 + ')');
  if (srcHashAfter !== srcHashBefore) blockers.push('the compiler source changed mid-run (' + srcHashBefore + ' -> ' + srcHashAfter + ')');
  // A build that overlapped an in-place edit compiled a generator revision that exists
  // nowhere on disk now, so whatever it emitted counts neither for nor against
  // determinism. This is the reading the endpoint pair misses.
  const movedBuilds = srcSamples.filter((s) => s.before !== srcSamples[0].before || s.after !== s.before);
  for (const s of movedBuilds) blockers.push('the compiler source changed during build ' + s.i + ' (' + s.before + ' -> ' + s.after + ')');
  const v = distinctVerdict(uniq.size, hashes.length, movedBuilds.length);
  say('   distinct hashes: ' + uniq.size + ' of ' + hashes.length + '  -> ' + v.label);
  if (v.failure) failures.push(v.failure);
  say('');

  // ---- C: spelling tripwire on the fresh C --------------------------------
  say('C. spelling tripwire on the freshly generated C (struct / props table / body literal)');
  if (fieldProblems.length === 0) {
    say('   all ' + TRIPWIRE.length + ' built-in fields agree in all three places');
  } else {
    for (const p of fieldProblems.slice(0, 10)) say('   ' + p);
    failures.push(fieldProblems.length + ' spelling problem(s) in the generated C');
  }
  say('');

  // ---- D: the three historical artifacts ----------------------------------
  say('D. the three surviving artifacts from the 84-second window that rewrote the naming');
  let prev = Infinity;
  for (const a of ARTIFACTS) {
    const p = path.join(HERE, a.file);
    if (!fs.existsSync(p)) { say('   ' + a.file + ': MISSING'); failures.push('fixture missing: ' + a.file); prev = Infinity; continue; }
    const c = cErrors(p);
    const got = c.errors.length;
    const first = c.errors.length ? c.errors[0] : null;
    const want = a.truncated ? '>=' + a.minErrors + ' (capped)' : String(a.exact);
    say('   ' + a.file + '  ' + a.mtime);
    say('       ' + fs.statSync(p).size + ' B, sha256/16 ' + sha16(p) + ', clang errors ' + got + ' (want ' + want + ')'
      + ', clang summary ' + c.summary + ', truncated ' + c.truncated
      + (got ? ', first: ' + first.line + ':' + first.col + ' ' + first.msg : ''));
    say('       kinds: ' + (c.kinds.length ? c.kinds.join(', ') : '(none)'));
    say('       ' + a.note);
    if (a.truncated) {
      if (!c.truncated) failures.push(a.file + ': expected clang to hit its error cap, it did not');
      if (got < a.minErrors) failures.push(a.file + ': ' + got + ' errors, expected at least ' + a.minErrors);
    } else if (got !== a.exact) {
      failures.push(a.file + ': clang reported ' + got + ' errors, expected ' + a.exact);
    }
    if (c.kinds.join(',') !== a.kinds.join(',')) {
      failures.push(a.file + ': kinds [' + c.kinds.join(', ') + '] != expected [' + a.kinds.join(', ') + ']');
    }
    if (got > prev) failures.push(a.file + ': error count rose (' + prev + ' -> ' + got + '); a human edit converges, a random generator does not');
    prev = got;
  }
  say('   -> same program, three different C files, errors decaying to zero in 84 s: the tree was mid-edit.');
  say('');

  // ---- E: the link to MY failing build -------------------------------------
  say('E. the failing build this gap was registered from (probes/array-scope/cc.txt, 04:00:19 +0800)');
  if (!fs.existsSync(MY_FAILED_LOG)) {
    say('   cc.txt MISSING -- the cross-check cannot run');
    failures.push('probes/array-scope/cc.txt is gone; the link to the registered failure is unverifiable');
  } else {
    const mine = logKinds(MY_FAILED_LOG);
    const theirs = ARTIFACTS[0].kinds;
    say('   my build broke on:      ' + mine.join(', '));
    say('   artifact-1 (04:00:10) broke on: ' + theirs.join(', '));
    say('   -> identical hazard set, from two different programs, 9 seconds apart: one tree state.');
    if (mine.join(',') !== theirs.join(',')) {
      failures.push('the failing log and artifact-1 do not share one hazard set (' + mine.join(',') + ' vs ' + theirs.join(',') + ')');
    }
  }
  say('');

  say('---- verdict ----');
  if (failures.length === 0 && blockers.length === 0) {
    say('PASS: ' + Math.max(hashes.length, 1) + ' builds of one input on the generator revision '
      + srcHashBefore + ' produced ONE generated C;');
    say('      the built-in spellings agree in all three places, and the only surviving failure');
    say('      artifacts are from a compiler tree that was being edited.');
    if (tracked.length) {
      say('      NOTE: HEAD ' + head + ' has ' + tracked.length + ' modified source file(s) ('
        + tracked.join(', ') + '). Determinism is certified for the CONTENT hash above,');
      say('      i.e. for that tree state -- not for the commit.');
    }
  } else if (failures.length === 0) {
    // Not a pass and not a failure: nothing above was violated, but the compiler MOVED
    // during the run, so "same source, same C" cannot be certified. Exit 3 keeps this
    // out of both other buckets -- a green would certify a tree we never pinned, and a
    // red would blame this workspace for someone else's edit.
    say('INCONCLUSIVE: every measurement above is green, but the compiler source MOVED:');
    for (const b of blockers) say('  blocked by: ' + b);
    say('      Re-run when the tree is stable. (No retry loop hides this: see ui-demo/air-run.cjs.)');
  } else {
    for (const f of failures) say('FAIL: ' + f);
  }

  const ev = process.env.ASC_G11_EVIDENCE === 'off' ? null
    : path.join(HERE, 'run-' + new Date().toISOString().slice(0, 10) + '.txt');
  if (ev) {
    fs.appendFileSync(ev, '\n' + out.join('\n') + '\n');
    console.log('---- evidence appended to ' + path.relative(UI, ev) + ' ----');
  } else {
    console.log('---- evidence not written (ASC_G11_EVIDENCE=off; mutation run) ----');
  }
  process.exit(failures.length === 0 ? (blockers.length === 0 ? 0 : 3) : 1);
}

if (require.main === module) main();
module.exports = { cErrors, spellingProblems, structFieldNames, logKinds, distinctVerdict };

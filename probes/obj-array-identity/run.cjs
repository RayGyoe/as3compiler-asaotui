// probes/obj-array-identity/run.cjs -- ONE command, BOTH arms.
//
// Question: in AS3 a `Number` / `String` / `Boolean` / `Array` is a legal value
// for an `Object`-typed variable. Does our AOT keep such a value's identity, the
// way real AIR does?  The style layer (Size/LengthEdges/Edges/Corners/Fill/Style)
// splits `fromAny(o:Object)` from `fromArray(a:Array)` on the claim that it does
// NOT -- and that a following `is <userClass>` can even crash. This measures the
// claim instead of trusting it.
//
// USAGE (from asaotui/):   node probes/obj-array-identity/run.cjs
//   ASC_CC=clang                  override the C compiler
//   AIRSDK_HOME=<sdk root>        AIR SDK root (default: the known local 51.4.1)
//   ASC_SKIP_AIR=1                AOT arm only (no mxmlc/adl)
//
// Arms:
//   AOT  one process PER CASE (a SIGSEGV must not eat the rest of the table)
//   AIR  one mxmlc build + one adl run, all cases in-process (nothing crashes)
//
// The expectation file is HAND-WRITTEN from the AS3 language rules; the AIR arm
// is checked against it, so "AIR is the reference" is itself a measured claim.
'use strict';

const fs = require('fs');
const path = require('path');
const { spawnSync, execFileSync } = require('child_process');

const DIR = __dirname;
const UI = path.resolve(DIR, '..', '..');
const COMPILER = path.resolve(UI, '..', 'as3compiler');
const clang = process.env.ASC_CC || 'clang';
const SDK = process.env.AIRSDK_HOME || 'D:/Adobe/Flex_Sdk/AIRSDK_51.4.1';
const skipAir = process.env.ASC_SKIP_AIR === '1';

const OUT_TXT = path.join(DIR, 'out.txt');
const SELECT = path.join(DIR, 'select.txt');
const AIR_GOT = path.join(DIR, 'objarr-air.txt');
const AOT_GOT = path.join(DIR, 'aot-got.txt');
const AIR_SWF = path.join(DIR, 'CaseAir.swf');
const AOT_EXE = path.join(DIR, 'aot-case.exe');

const expect = JSON.parse(fs.readFileSync(path.join(DIR, 'expect.json'), 'utf8'));

function clean(p) { if (fs.existsSync(p)) fs.unlinkSync(p); }

// Value = everything after the LAST '=' on the line ("id=3 desc (is Marker)=false").
function valueOf(line) {
  const i = line.lastIndexOf('=');
  return i < 0 ? null : line.slice(i + 1).trim();
}

// ---------------------------------------------------------------- AOT arm ----
console.log('[run] building the AOT arm');
clean(AOT_EXE);
const build = spawnSync(process.execPath, [
  'src/index.ts',
  path.join(DIR, 'CaseAot.as'),
  path.join(DIR, 'Cases.as'),
  path.join(DIR, 'Marker.as'),
  '-o', AOT_EXE,
  '--cc', clang,
  '-w',
  '-I', './vendor/curl/include',
  '-L', './vendor/curl/lib/windows-x64',
  '-l', 'zlib',
], { cwd: COMPILER, encoding: 'utf8' });
if (build.status !== 0) {
  console.error('[run] AOT BUILD FAILED (exit ' + build.status + ')');
  console.error(((build.stdout || '') + (build.stderr || '')).split(/\r?\n/).slice(-30).join('\n'));
  process.exit(2);
}
if (!fs.existsSync(AOT_EXE)) { console.error('[run] no exe at ' + AOT_EXE); process.exit(2); }

const aot = {};   // id -> { value, exit }
console.log('[run] running ' + expect.count + ' AOT cases (one process each)');
for (let id = 1; id <= expect.count; id++) {
  fs.writeFileSync(SELECT, String(id));
  clean(OUT_TXT);
  const r = spawnSync(AOT_EXE, [], { cwd: DIR, encoding: 'utf8' });
  const code = r.status === null ? 'signal ' + r.signal : r.status;
  if (fs.existsSync(OUT_TXT)) {
    aot[id] = { value: valueOf(fs.readFileSync(OUT_TXT, 'utf8').trim()), exit: code };
  } else {
    aot[id] = { value: null, exit: code };   // died before publishing
  }
}
clean(SELECT);
clean(OUT_TXT);

// ---------------------------------------------------------------- AIR arm ----
let air = null;
if (!skipAir) {
  const mxmlc = path.join(SDK, 'bin', process.platform === 'win32' ? 'mxmlc.bat' : 'mxmlc');
  const adl = path.join(SDK, 'bin', process.platform === 'win32' ? 'adl.exe' : 'adl');
  if (!fs.existsSync(mxmlc) || !fs.existsSync(adl)) {
    console.error('[run] AIR SDK not found under ' + SDK + ' (set AIRSDK_HOME, or ASC_SKIP_AIR=1)');
    process.exit(2);
  }
  console.log('[run] building the AIR arm with mxmlc');
  clean(AIR_SWF); clean(AIR_GOT);
  const m = spawnSync('cmd', ['/c', mxmlc, '-output=' + AIR_SWF, '-source-path=' + DIR, path.join(DIR, 'CaseAir.as')],
    { cwd: DIR, encoding: 'utf8' });
  if (m.status !== 0 || !fs.existsSync(AIR_SWF)) {
    console.error('[run] mxmlc FAILED (exit ' + m.status + ')');
    console.error(((m.stdout || '') + (m.stderr || '')).split(/\r?\n/).slice(-30).join('\n'));
    process.exit(2);
  }
  console.log('[run] running the AIR arm under adl');
  try {
    execFileSync(adl, [path.join(DIR, 'app.xml')], { cwd: DIR, timeout: 60000, encoding: 'utf8', stdio: 'ignore' });
  } catch (e) { /* adl exit codes are noisy; the evidence is the file */ }
  if (!fs.existsSync(AIR_GOT)) { console.error('[run] adl wrote no ' + AIR_GOT); process.exit(2); }
  air = {};
  for (const line of fs.readFileSync(AIR_GOT, 'utf8').split(/\r?\n/)) {
    const m2 = line.match(/^id=(\d+)\s+(.*)$/);
    if (m2) air[Number(m2[1])] = valueOf(line);
  }
}

// ------------------------------------------------------------- compare -------
const rows = [];
const fails = [];
for (let id = 1; id <= expect.count; id++) {
  const want = expect.truth[String(id)];
  const gotAir = air ? air[id] : '(skipped)';
  const gotAot = aot[id].value;
  rows.push({ id, want, air: gotAir, aot: gotAot, exit: aot[id].exit });

  if (air) {
    if (gotAir !== want) fails.push('id ' + id + ': AIR says "' + gotAir + '" but the AS3 rule says "' + want + '" -- the REFERENCE disagrees, re-derive the rule');
  }
}

// The AOT arm is compared against AIR (or against the written rule when AIR is skipped).
const aotDeviations = [];
for (const r of rows) {
  const ref = air ? r.air : r.want;
  if (r.aot !== ref) aotDeviations.push(r);
}
const known = expect.knownAotDeviations.map(Number).sort((a, b) => a - b);
const gotIds = aotDeviations.map((r) => r.id).sort((a, b) => a - b);
const missing = gotIds.filter((i) => !known.includes(i));      // new/regressed behaviour
const closed = known.filter((i) => !gotIds.includes(i));       // documented deviation is gone

// ---------------------------------------------------------------- report -----
const w = (s, n) => String(s == null ? '(crashed)' : s).padEnd(n);
console.log('');
console.log('id  ' + w('case', 52) + w('AS3 rule', 12) + w('AIR', 12) + w('our AOT', 12) + 'AOT exit');
for (const r of rows) {
  const mark = r.aot !== (air ? r.air : r.want) ? '   <-- DIFFERS' : '';
  console.log(String(r.id).padStart(2) + '  ' + w(expect.label[String(r.id)], 52)
    + w(r.want, 12) + w(r.air, 12) + w(r.aot, 12) + r.exit + mark);
}

// Persist both arms verbatim (evidence, not summary).
fs.writeFileSync(AOT_GOT, rows.map((r) => 'id=' + r.id + ' ' + (r.aot == null ? '<<CRASH exit ' + r.exit + '>>' : r.aot)).join('\n') + '\n');

console.log('');
console.log('AOT deviations from ' + (air ? 'AIR' : 'the AS3 rule') + ': ' + (gotIds.length ? gotIds.join(', ') : 'none'));

if (fails.length) { for (const f of fails) console.log('  FAIL  ' + f); console.log('RESULT: FAIL (reference disagrees with the written rule)'); process.exit(1); }
if (missing.length) { console.log('  FAIL  undocumented deviations appeared: ' + missing.join(', ')); console.log('RESULT: FAIL'); process.exit(1); }
if (closed.length) {
  console.log('  NOTE  documented deviation(s) ' + closed.join(', ') + ' are GONE -- if this is a real fix, update compiler-gaps.md and expect.json; if it is a silent behaviour change, find out which.');
  console.log('RESULT: GAP-CHANGED');
  process.exit(1);
}
console.log('RESULT: PASS (' + expect.count + ' cases; ' + gotIds.length + ' documented deviation(s), unchanged)');

// probes/g20-settextformat/run.cjs -- ONE command, BOTH arms.
//
// Question: when the SAME range gets a format twice (which is what a repaint path
// does), does the field still lay the text out once? AIR: yes -- setTextFormat
// replaces the formatting of the range. Our AOT appended a run every time, and the
// layout side copies text[start..end) per run, so the same characters were added once
// per call (symptom in the app: textWidth 28.88 -> 56.73 -> 84, "the text got copied").
//
// Every case is RELATIONAL (two fields measured in the same process, then compared),
// so the probe never depends on AIR and this build sharing a text engine -- they do
// not, and absolute widths legitimately differ.
//
// USAGE (from asaotui/):   node probes/g20-settextformat/run.cjs
//   ASC_CC=clang                  override the C compiler
//   AIRSDK_HOME=<sdk root>        AIR SDK root (default: the known local 51.4.1)
//   ASC_SKIP_AIR=1                AOT arm only (no mxmlc/adl)
//
// EXIT CODES
//   0  both arms agree with the hand-derived answers (and with each other)
//   1  they do not  (with G20 unfixed this is the expected result: cases 2, 3, 4, 7
//      and 8 fail on the AOT arm while AIR passes all of them)
//   2  a build/run step failed (build error, missing SDK, adl wrote nothing)
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

const AOT_TXT = path.join(DIR, 'g20-settextformat-aot.txt');
const AIR_TXT = path.join(DIR, 'g20-settextformat-air.txt');
const AOT_EXE = path.join(DIR, 'AotMain.exe');
const AIR_SWF = path.join(DIR, 'AirMain.swf');
const RESULTS = path.join(DIR, 'g20-settextformat-results.txt');

const expect = JSON.parse(fs.readFileSync(path.join(DIR, 'expect.json'), 'utf8'));
const clean = (p) => { if (fs.existsSync(p)) fs.unlinkSync(p); };

function parse(file) {
  const out = { ids: {}, raw: [] };
  if (!fs.existsSync(file)) return out;
  for (const line of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
    if (!line) continue;
    const m = line.match(/^id=(\d+)\s+(\S+)$/);
    if (m) out.ids[Number(m[1])] = m[2];
    else out.raw.push(line.replace(/^raw /, ''));
  }
  return out;
}

// --------------------------------------------------------------- AOT arm -----
console.log('[g20] building the AOT arm');
clean(AOT_EXE); clean(AOT_TXT);
const build = spawnSync(process.execPath, [
  'src/index.ts',
  path.join(DIR, 'AotMain.as'),
  path.join(DIR, 'SetFmtCases.as'),
  '--manifest', path.join(COMPILER, 'examples', 'draw-over.build.json'),
  '-o', AOT_EXE,
  '--cc', clang,
  '-w',
], { cwd: COMPILER, encoding: 'utf8' });
if (build.status !== 0) {
  console.error('[g20] AOT BUILD FAILED (exit ' + build.status + ')');
  console.error(((build.stdout || '') + (build.stderr || '')).split(/\r?\n/).slice(-30).join('\n'));
  process.exit(2);
}
console.log('[g20] running the AOT arm');
const aotRun = spawnSync(AOT_EXE, [], { cwd: DIR, encoding: 'utf8' });
const aot = parse(AOT_TXT);
const aotExit = aotRun.status === null ? 'signal ' + aotRun.signal : aotRun.status;

// --------------------------------------------------------------- AIR arm -----
let air = null;
if (!skipAir) {
  const mxmlc = path.join(SDK, 'bin', process.platform === 'win32' ? 'mxmlc.bat' : 'mxmlc');
  const adl = path.join(SDK, 'bin', process.platform === 'win32' ? 'adl.exe' : 'adl');
  if (!fs.existsSync(mxmlc) || !fs.existsSync(adl)) {
    console.error('[g20] AIR SDK not found under ' + SDK + ' (set AIRSDK_HOME, or ASC_SKIP_AIR=1)');
    process.exit(2);
  }
  console.log('[g20] building the AIR arm with mxmlc');
  clean(AIR_SWF); clean(AIR_TXT);
  const m = spawnSync('cmd', ['/c', mxmlc,
    '-output=' + AIR_SWF,
    '-source-path=' + DIR,
    path.join(DIR, 'AirMain.as'),
  ], { cwd: DIR, encoding: 'buffer' });
  if (m.status !== 0 || !fs.existsSync(AIR_SWF)) {
    console.error('[g20] mxmlc FAILED (exit ' + m.status + ')');
    console.error(new TextDecoder('gbk').decode(m.stderr || Buffer.alloc(0)).split(/\r?\n/).slice(-30).join('\n'));
    process.exit(2);
  }
  console.log('[g20] running the AIR arm');
  let adlErr = '';
  try { execFileSync(adl, [path.join(DIR, 'app.xml')], { cwd: DIR, timeout: 120000, encoding: 'utf8', stdio: 'pipe' }); }
  catch (e) { adlErr = String((e && e.stderr) || ''); /* adl exit codes are noisy; the file is the evidence */ }
  if (!fs.existsSync(AIR_TXT)) {
    console.error('[g20] adl wrote no ' + AIR_TXT);
    if (adlErr) console.error('[g20] adl stderr:\n' + adlErr.trim());
    process.exit(2);
  }
  air = parse(AIR_TXT);
}

// -------------------------------------------------------------- compare ------
const one = (v) => (v === 'true' ? 'true' : v === 'false' ? 'false' : String(v == null ? '(MISSING)' : v));
const w = (s, n) => String(s == null ? '(MISSING)' : s).padEnd(n);
const fails = [];
const out = [];
out.push('');
out.push('id  ' + w('case', 52) + w('rule', 7) + w('AIR 51.4.1', 12) + w('our AOT', 12));
for (const id of Object.keys(expect.truth).map(Number).sort((a, b) => a - b)) {
  const want = expect.truth[String(id)];
  const gotAot = aot.ids[id];
  const gotAir = air ? air.ids[id] : '(skipped)';
  const mark = gotAot !== (air ? gotAir : want) ? '   <-- DIFFERS' : '';
  out.push(String(id).padStart(2) + '  ' + w(expect.label[String(id)], 52) + w(want, 7) + w(one(gotAir), 12) + w(one(gotAot), 12) + mark);
  if (air && gotAir !== want) {
    fails.push('id ' + id + ': AIR says "' + gotAir + '" but the derived answer is "' + want
      + '" -- the REFERENCE disagrees; re-derive the rule (see expect.json)');
  }
  const ref = air ? gotAir : want;
  if (gotAot !== ref) {
    fails.push('id ' + id + ': our AOT says "' + one(gotAot) + '" but ' + (air ? 'AIR' : 'the rule')
      + ' says "' + one(ref) + '"  (' + expect.label[String(id)] + ')');
  }
}

// Registered deviations (out of scope for G20): still measured, so a silent drift in
// either arm is noticed -- but the AOT value has to stay at what we KNOW it answers.
const knownIds = Object.keys(expect.known || {}).map(Number).sort((a, b) => a - b);
for (const id of knownIds) {
  const k = expect.known[String(id)];
  const gotAot = aot.ids[id];
  const gotAir = air ? air.ids[id] : '(skipped)';
  out.push(String(id).padStart(2) + '  ' + w(k.air + ' on AIR / ' + k.ours + ' here', 52)
    + w('known', 7) + w(one(gotAir), 12) + w(one(gotAot), 12) + '   (registered)');
  if (air && gotAir !== k.air) {
    fails.push('id ' + id + ': AIR says "' + gotAir + '" but the registered deviation records "'
      + k.air + '" -- re-measure ' + k.why);
  }
  if (gotAot !== k.ours) {
    fails.push('id ' + id + ': the AOT arm answers "' + one(gotAot) + '" but the registered deviation records "'
      + k.ours + '" -- if the deviation was just FIXED, delete it from expect.json.known (' + k.why + ')');
  }
}
for (const [name, arm, where] of [['AOT', aot, 'g20-settextformat-aot.txt'], ['AIR', air, 'g20-settextformat-air.txt']]) {
  if (arm == null) continue;
  const n = Object.keys(arm.ids).length;
  if (n < expect.count + knownIds.length) {
    fails.push(name + ' arm wrote only ' + n + '/' + (expect.count + knownIds.length) + ' answers in ' + where
      + ' (crash or early exit)');
  }
}

out.push('');
out.push('absolute metrics (INFORMATIONAL -- AIR and this build use different text engines):');
for (const [name, arm] of [['AOT', aot], ['AIR', air]]) {
  if (!arm) continue;
  for (const line of arm.raw) out.push('  ' + name + ': ' + line);
}
out.push('');
out.push('AOT exit: ' + aotExit);
out.push(fails.length
  ? 'RESULT: FAIL (' + fails.length + ' disagreement(s); repeated setTextFormat on one range is not idempotent)'
  : 'RESULT: PASS (' + Object.keys(expect.truth).length + ' relational cases; both arms treat a repeated range format as a replacement)');
for (const f of fails) out.push('  FAIL  ' + f);
const text = out.join('\n');
console.log(text);
fs.writeFileSync(RESULTS, text + '\n');

process.exit(fails.length === 0 ? 0 : 1);
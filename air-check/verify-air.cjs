// verify-air.cjs -- compile the shared seam library with the REAL AIR SDK, run it
// under adl, and print the GOT lines it produced (write to air-out.txt, because
// adl.exe on Windows has no stdout), then diff them against the Yoga/AOT arms.
//
// One command, no coreutils (this machine's bash has none):
//   node verify-air.cjs            # compile + run + diff against ../diff-check/*-got.txt
//   node verify-air.cjs --no-build # skip mxmlc, just re-run + diff
//
// AIRSDK_HOME defaults to the AIR SDK installed on this machine; override it
// with the AIRSDK_HOME environment variable (AGENTS.md forbids hardcoding paths
// in project docs -- this is a local runner, not a doc).
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const HERE = __dirname;
const AIR = process.env.AIRSDK_HOME || 'D:/Adobe/Flex_Sdk/AIRSDK_51.4.1';
const MXMLC = path.join(AIR, 'bin', 'mxmlc.bat');
const noBuild = process.argv.includes('--no-build');

function fail(msg) { console.error('FAIL ' + msg); process.exit(1); }

if (!fs.existsSync(MXMLC)) fail('no mxmlc at ' + MXMLC + ' (set AIRSDK_HOME)');

// ---- 1) mxmlc: compile the whole seam library (LayoutEngine.as + its impls) ----
if (!noBuild) {
  const t0 = fs.existsSync('aircheck.swf') ? fs.statSync('aircheck.swf').mtimeMs : 0;
  // A .bat needs cmd.exe: spawnSync of a .bat directly returns a null status.
  const r = spawnSync('cmd', ['/c', MXMLC,
    '-output=aircheck.swf', '-source-path=../seam', 'AirMain.as'],
    { cwd: HERE, encoding: 'utf8', timeout: 300000 });
  const out = ((r.stdout || '') + (r.stderr || '')).trim();
  const rebuilt = fs.existsSync('aircheck.swf') && fs.statSync('aircheck.swf').mtimeMs !== t0;
  console.log('mxmlc exit=' + r.status + '  rebuilt=' + rebuilt
    + '  swf=' + fs.statSync('aircheck.swf').size + ' bytes');
  if (out) console.log(out.split('\n').slice(0, 20).join('\n'));
  if (r.status !== 0 || /Error|错误/i.test(out)) fail('mxmlc reported errors');
}

// ---- 2) adl: run it (adl never exits by itself -> run-adl.cjs holds a timeout) ----
const t1 = fs.existsSync('air-out.txt') ? fs.statSync('air-out.txt').mtimeMs : 0;
const env = Object.assign({}, process.env, { AIRSDK_HOME: AIR });
const r2 = spawnSync(process.execPath, [path.join(HERE, 'run-adl.cjs'), 'app-air.xml', '90000'],
  { cwd: HERE, encoding: 'utf8', timeout: 180000, env });
console.log('adl exit=' + r2.status + '  ' + ((r2.stdout || '') + (r2.stderr || '')).trim().split('\n').slice(-3).join(' | '));
if (!fs.existsSync('air-out.txt')) fail('air-out.txt was never written -- the AIR app did not run');
const fresh = fs.statSync('air-out.txt').mtimeMs !== t1;
console.log('air-out.txt refreshed=' + fresh + '  bytes=' + fs.statSync('air-out.txt').size);

// ---- 3) diff the AIR GOT lines against the Yoga and AOT arms -------------------
const got = (f) => fs.readFileSync(f, 'utf8').split('\n').filter((l) => l.startsWith('GOT ')).map((l) => l.trim());
const air = got(path.join(HERE, 'air-out.txt'));
console.log('\nAIR GOT lines=' + air.length);

let overall = true;
// The AIR arm drives cases INLINE (AirMain.as) rather than reading cases.txt --
// see air-check/README.md for that trade-off, so compare prefix-wise.
for (const [label, file] of [['yoga', '../diff-check/yoga-got.txt'], ['as3 ', '../diff-check/as3-got.txt']]) {
  const f = path.join(HERE, file);
  if (!fs.existsSync(f)) { console.log('  ' + label + ': ' + file + ' missing -- skipped'); continue; }
  const other = got(f);
  const n = Math.min(air.length, other.length);
  const bad = [];
  for (let i = 0; i < n; i++) if (air[i] !== other[i]) bad.push(i);
  const ok = bad.length === 0 && air.length === other.length;
  console.log('  vs ' + label + ': ' + n + ' lines compared, ' + bad.length + ' mismatches'
    + (air.length === other.length ? '' : ' (length differs: ' + air.length + ' vs ' + other.length + ')')
    + (ok ? '  *** IDENTICAL ***' : '  *** DIVERGED ***'));
  for (const i of bad.slice(0, 10)) console.log('    @' + i + '\n      air : ' + air[i] + '\n      ' + label + ': ' + other[i]);
  if (!ok) overall = false;
}
console.log(overall ? '\nRESULT: AIR arm agrees with the other arms' : '\nRESULT: AIR arm DIVERGES');
process.exit(overall ? 0 : 1);

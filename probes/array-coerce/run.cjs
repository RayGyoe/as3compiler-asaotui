// probes/array-coerce/run.cjs -- ONE command, BOTH runtimes: what is `Array(x)`?
// Usage (from asaotui/): node probes/array-coerce/run.cjs
'use strict';
const fs = require('fs');
const path = require('path');
const { spawnSync, execFileSync } = require('child_process');

const DIR = __dirname;
const COMPILER = path.resolve(DIR, '..', '..', '..', 'as3compiler');
const SDK = process.env.AIRSDK_HOME || 'D:/Adobe/Flex_Sdk/AIRSDK_51.4.1';
const AOT_TXT = path.join(DIR, 'arr-aot.txt');
const AIR_TXT = path.join(DIR, 'arr-air.txt');
const clean = (p) => { if (fs.existsSync(p)) fs.unlinkSync(p); };

function parse(f) {
  const o = {};
  if (!fs.existsSync(f)) return o;
  for (const l of fs.readFileSync(f, 'utf8').split(/\r?\n/)) {
    const m = l.match(/^id=(\d+)\s(.*)$/);
    if (m) o[+m[1]] = m[2].trim();
  }
  return o;
}

clean(AOT_TXT);
clean(AIR_TXT);

console.log('[arr] building AOT arm');
const b = spawnSync(process.execPath, [
  'src/index.ts', path.join(DIR, 'AotMain.as'), path.join(DIR, 'Cases.as'),
  '-o', path.join(DIR, 'AotMain.exe'), '--cc', 'clang', '-w',
  '-I', './vendor/curl/include', '-L', './vendor/curl/lib/windows-x64', '-l', 'zlib',
], { cwd: COMPILER, encoding: 'utf8' });
if (b.status !== 0) {
  console.error('AOT BUILD FAILED\n' + ((b.stdout || '') + (b.stderr || '')).split(/\r?\n/).slice(-20).join('\n'));
  process.exit(2);
}
spawnSync(path.join(DIR, 'AotMain.exe'), [], { cwd: DIR, encoding: 'utf8' });
const aot = parse(AOT_TXT);

console.log('[arr] building AIR arm');
const mxmlc = path.join(SDK, 'bin', 'mxmlc.bat');
const adl = path.join(SDK, 'bin', 'adl.exe');
const swf = path.join(DIR, 'AirMain.swf');
clean(swf);
const m = spawnSync('cmd', ['/c', mxmlc, '-output=' + swf, '-source-path=' + DIR, path.join(DIR, 'AirMain.as')],
  { cwd: DIR, encoding: 'utf8' });
if (m.status !== 0 || !fs.existsSync(swf)) {
  console.error('mxmlc FAILED\n' + ((m.stdout || '') + (m.stderr || '')).split(/\r?\n/).slice(-20).join('\n'));
  process.exit(2);
}
try { execFileSync(adl, [path.join(DIR, 'app.xml')], { cwd: DIR, timeout: 90000, encoding: 'utf8', stdio: 'pipe' }); }
catch (e) { /* adl exit codes are noisy; the evidence is the file */ }
const air = parse(AIR_TXT);
if (Object.keys(air).length === 0) { console.error('adl wrote nothing'); process.exit(2); }

const lines = [];
let diff = 0;
for (let i = 1; i <= 8; i++) {
  const same = air[i] === aot[i];
  if (!same) diff++;
  lines.push((same ? '    ' : 'DIFF') + '  ' + String(air[i] == null ? '(missing)' : air[i]));
  if (!same) lines.push('      AOT: ' + (aot[i] == null ? '(missing)' : aot[i]));
}
console.log('\nAIR (reference) vs our AOT:');
console.log(lines.join('\n'));
console.log(diff === 0 ? '\nRESULT: AGREE' : '\nRESULT: ' + diff + ' disagreement(s)');
process.exit(0);
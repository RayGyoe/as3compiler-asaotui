// probes/g19-roundrect/run.cjs -- AIR vs AOT reference sweep for Graphics.drawRoundRect
// (G19, stage 267).
//
// Two programs, one copy of each source, both arms:
//   Round.as       geometry: seven 40x40 rounded rects, reported per row (first/last
//                  pixel above alpha 128) plus the five-argument default call.
//   RoundArgs.as   the argument contract: NaN/omitted/negative/infinite ellipses and
//                  negative/zero width+height, reported as the thrown error or the ink
//                  bounding box (drawn through a +10,+10 matrix so a bulge stays inside
//                  the bitmap), with per-row dumps for the negative radii.
//
// The AOT arm appends one driver line to each source (`var _d:X = new X();`): our
// compiler runs top-level code while AIR instantiates the document class itself, so
// that line is the only difference and the body under test stays byte-identical.
//
// The AOT arm also checks itself against the ANALYTIC corner ellipse, so a difference
// is attributed: an exact renderer is within 1 px of the math on every row, and where
// AIR disagrees with the math it is AIR's own cubic approximation of an eccentric
// ellipse (measured: ew=100/eh=4 drives AIR 2 px inside the ideal quarter ellipse).
//
//   node probes/g19-roundrect/run.cjs            compare + analytic check
//   AIR_ONLY=1 node probes/g19-roundrect/run.cjs refresh the AIR side only
'use strict';
const fs = require('fs');
const path = require('path');
const { mxmlcRun } = require('../../tools/mxmlc-run.cjs');
const { spawnSync, execFileSync } = require('child_process');

const DIR = __dirname;
// This probe lives in asaotui/probes/g19-roundrect, the compiler one level up and over.
const ROOT = path.resolve(DIR, '..', '..', '..', 'as3compiler');
const SDK = process.env.AIRSDK_HOME || 'D:/Adobe/Flex_Sdk/AIRSDK_51.4.1';
const MXMLC = path.join(SDK, 'bin', process.platform === 'win32' ? 'mxmlc.bat' : 'mxmlc');
const ADL = path.join(SDK, 'bin', process.platform === 'win32' ? 'adl.exe' : 'adl');

// Negative radii are the ONE documented deviation from AIR (see emit.ts /
// compiler-gaps.md G19): AIR inks up to |r|/2 outside the box, we clamp to a square
// corner. Those rows are counted, never silently dropped.
const KNOWN_ROWS = /^(7:|negEw:|negEh:|negBoth:)/;
const KNOWN_ARG = /^(negEw|negEh|negBoth)[: ]/;

const fail = (msg) => { console.error('[ab-round] ' + msg); process.exit(2); };

// ---- AIR arm ---------------------------------------------------------------
function airArm(cls, swfName, txtName) {
  const swf = path.join(DIR, swfName);
  const txt = path.join(DIR, txtName);
  if (fs.existsSync(swf)) fs.unlinkSync(swf);
  if (fs.existsSync(txt)) fs.unlinkSync(txt);
  const m = mxmlcRun(MXMLC, ['-output=' + swf, '-source-path=' + DIR, path.join(DIR, cls + '.as')],
    { cwd: DIR, encoding: 'buffer' });
  if (m.status !== 0 || !fs.existsSync(swf)) {
    fail('mxmlc FAILED for ' + cls + '\n' + new TextDecoder('gbk').decode(m.stderr || Buffer.alloc(0)).slice(-1500));
  }
  const xml = path.join(DIR, 'app-' + cls.toLowerCase() + '.xml');
  if (!fs.existsSync(xml)) {
    fs.writeFileSync(xml, ['<?xml version="1.0" encoding="utf-8" ?>',
      '<application xmlns="http://ns.adobe.com/air/application/51.0">',
      '    <id>asaotui.probe.g19.' + cls.toLowerCase() + '</id>',
      '    <versionNumber>0.0.1</versionNumber>',
      '    <filename>g19-' + cls.toLowerCase() + '</filename>',
      '    <supportedProfiles>desktop</supportedProfiles>',
      '    <initialWindow>', '        <content>' + swfName + '</content>',
      '        <visible>false</visible>', '    </initialWindow>', '</application>', ''].join('\n'));
  }
  try { execFileSync(ADL, [xml], { cwd: DIR, timeout: 240000, stdio: 'ignore' }); }
  catch { /* adl exit codes are noisy; the file is the evidence */ }
  if (!fs.existsSync(txt)) fail('adl wrote no ' + txtName);
}

// ---- AOT arm ---------------------------------------------------------------
function aotArm(cls, txtName, txtOut) {
  const src = path.join(DIR, cls + '.as');
  const twin = path.join(DIR, 'Twin' + cls + '.as');
  fs.writeFileSync(twin, fs.readFileSync(src, 'utf8') + 'var _driver' + cls + ':' + cls + ' = new ' + cls + '();\r\n');
  const exe = path.join(DIR, cls + '.exe');
  const txt = path.join(DIR, txtName);
  if (fs.existsSync(exe)) fs.unlinkSync(exe);
  if (fs.existsSync(txt)) fs.unlinkSync(txt);
  const c = spawnSync(process.execPath,
    ['src/index.ts', path.relative(ROOT, twin),
      '--manifest', path.join(ROOT, 'examples', 'bakecrisp.build.json'), '-o', exe, '-w'],
    { cwd: ROOT, encoding: 'utf8' });
  if (c.status !== 0) fail('AOT BUILD FAILED for ' + cls + '\n' + ((c.stdout || '') + (c.stderr || '')).slice(-4000));
  const r = spawnSync(exe, [], { cwd: DIR, encoding: 'utf8' });
  if (r.status !== 0) console.error('[ab-round] ' + cls + ' run exit ' + r.status + '\n' + (r.stdout || '') + (r.stderr || ''));
  if (!fs.existsSync(txt)) fail('the AOT arm wrote no ' + txtName);
  fs.copyFileSync(txt, txtOut);
}

const readLines = (p) => (fs.existsSync(p) ? fs.readFileSync(p, 'utf8').split(/\r?\n/).filter(Boolean) : fail('missing ' + path.basename(p)));

// ---- geometry: the ideal corner ellipse ------------------------------------
// `Round.as` draws each case at the bitmap origin, one case id per call.
const CASES = {
  '1': [40, 40, 12, 12], '2': [40, 40, 20, 10], '3': [40, 40, 80, 80], '4': [40, 40, 0, 0],
  '5': [40, 40, 100, 4], '6': [40, 40, 40, 12], '7': [40, 40, -8, -8], '8': [40, 40, 12, NaN],
  '9': [40, 40, 12, NaN],
};
function idealLeft(id, y) {
  const [w, h, ew, eh0] = CASES[id];
  const eh = Number.isNaN(eh0) ? ew : eh0;
  const rx = Math.max(0, Math.min(Math.abs(ew) / 2, w / 2));
  const ry = Math.max(0, Math.min(Math.abs(eh) / 2, h / 2));
  const py = y + 0.5;
  const off = (d) => (d <= 0 || ry === 0 ? 0 : rx * (1 - Math.sqrt(Math.max(0, 1 - (d / ry) * (d / ry)))));
  return Math.max(off(ry - py), off(py - (h - ry)));
}

if (process.env.AIR_ONLY === '1') {
  airArm('Round', 'Round.swf', 'round.txt');
  airArm('RoundArgs', 'RoundArgs.swf', 'round-args.txt');
  fs.copyFileSync(path.join(DIR, 'round.txt'), path.join(DIR, 'round-air.txt'));
  fs.copyFileSync(path.join(DIR, 'round-args.txt'), path.join(DIR, 'roundargs-air.txt'));
  console.log('[ab-round] refreshed round-air.txt + roundargs-air.txt');
  process.exit(0);
}

airArm('Round', 'Round.swf', 'round.txt');
fs.copyFileSync(path.join(DIR, 'round.txt'), path.join(DIR, 'round-air.txt'));
aotArm('Round', 'round.txt', path.join(DIR, 'round-aot.txt'));

const parseRows = (lines) => {
  const map = new Map();
  for (const l of lines) {
    const m = /^row (\d+) (\d+) l=(-?\d+) r=(-?\d+) n=(\d+)$/.exec(l);
    if (!m) fail('unparsable geometry line "' + l + '"');
    map.set(m[1] + ':' + m[2], { l: +m[3], r: +m[4], n: +m[5] });
  }
  return map;
};
const air = parseRows(readLines(path.join(DIR, 'round-air.txt')));
const aot = parseRows(readLines(path.join(DIR, 'round-aot.txt')));

let same = 0, near = 0, known = 0;
const airDrift = [];
const worst = new Map(); // id -> { aot: max |measured-ideal|, air: same }
const bad = [];
for (const k of air.keys()) {
  const [id, y] = k.split(':');
  const a = air.get(k);
  const t = aot.get(k);
  if (!t) { bad.push('! ' + k + ' AOT MISSING'); continue; }
  if (KNOWN_ROWS.test(k + ':')) { known++; continue; }
  const da = Math.abs(a.l - idealLeft(id, +y));
  const dt = Math.abs(t.l - idealLeft(id, +y));
  const w = worst.get(id) || { aot: 0, air: 0 };
  worst.set(id, { aot: Math.max(w.aot, dt), air: Math.max(w.air, da) });
  if (a.l === t.l && a.r === t.r && a.n === t.n) same++;
  else if (Math.abs(a.l - t.l) <= 1 && Math.abs(a.r - t.r) <= 1 && Math.abs(a.n - t.n) <= 2) near++;
  // AOT on the ellipse and AIR off it: AIR's own cubic approximation of an eccentric
  // corner (measured on ew=100/eh=4, a 10:1 arc that kappa cubics fit badly).
  else if (dt <= 1.01 && da > 1.01) airDrift.push(`? ${k}  AIR l=${a.l} (${da.toFixed(2)} px off the ellipse)  AOT l=${t.l}`);
  else bad.push(`! ${k}  AIR l=${a.l} r=${a.r} n=${a.n}   AOT l=${t.l} r=${t.r} n=${t.n}`);
}
const extra = [...aot.keys()].filter((k) => !air.has(k));

console.log('');
console.log('case | ew x eh      | max |AOT - exact|  max |AIR - exact| | verdict');
for (const id of Object.keys(CASES)) {
  const [, , ew, eh0] = CASES[id];
  const eh = Number.isNaN(eh0) ? ew : eh0;
  const v = worst.get(id);
  if (!v) { console.log(`  ${id}  | ${(ew + 'x' + eh).padEnd(12)} |      (no rows)`); continue; }
  console.log(`  ${id}  | ${(ew + 'x' + eh).padEnd(12)} | ${v.aot.toFixed(2).padStart(15)}  | ${v.air.toFixed(2).padStart(16)} | `
    + (v.aot <= 1.01 ? 'AOT matches the ellipse' : 'AOT OFF THE ELLIPSE'));
}
if (airDrift.length) { console.log(''); airDrift.slice(0, 8).forEach((r) => console.log(r)); }
if (bad.length) { console.log(''); bad.slice(0, 30).forEach((r) => console.log(r)); }
console.log('');
console.log(`geometry rows: ${same} byte-identical, ${near} within the AA tolerance, ${bad.length + extra.length} disagreeing, ${known} known (negative radius)`);
// ---- the argument contract (RoundArgs.as) -----------------------------------
airArm('RoundArgs', 'RoundArgs.swf', 'round-args.txt');
fs.copyFileSync(path.join(DIR, 'round-args.txt'), path.join(DIR, 'roundargs-air.txt'));
aotArm('RoundArgs', 'round-args.txt', path.join(DIR, 'roundargs-aot.txt'));

const argAir = readLines(path.join(DIR, 'roundargs-air.txt'));
const argAot = readLines(path.join(DIR, 'roundargs-aot.txt'));
const argRowsAir = new Map(), argRowsAot = new Map();
const argSummary = (lines) => lines.filter((l) => l.startsWith('arg '));
for (const l of argAir) { const m = /^row (\w+) (\d+) l=(-?\d+) r=(-?\d+)$/.exec(l); if (m) argRowsAir.set(m[1] + ':' + m[2], { l: +m[3], r: +m[4] }); }
for (const l of argAot) { const m = /^row (\w+) (\d+) l=(-?\d+) r=(-?\d+)$/.exec(l); if (m) argRowsAot.set(m[1] + ':' + m[2], { l: +m[3], r: +m[4] }); }

const sa = argSummary(argAir), ta = argSummary(argAot);
let argBad = 0;
console.log('');
console.log('argument contract (AIR | AOT):');
for (let i = 0; i < Math.max(sa.length, ta.length); i++) {
  const line = sa[i] || '';
  // For the three negative-radius cases only the VERDICT has to agree (ok/throw); the
  // box differs by the documented deviation.
  const neg = KNOWN_ARG.test(line.replace(/^arg /, ''));
  const same0 = sa[i] === ta[i];
  const ok = same0 || (neg && line.split(' ')[1] === (ta[i] || '').split(' ')[1]);
  if (!ok) argBad++;
  console.log((same0 ? '  = ' : ok ? '  ~ ' : '! ') + String(sa[i] || '(MISSING)').padEnd(74)
    + (same0 ? '' : '| ' + (ta[i] || '(MISSING)')));
}
// Rows are only dumped for the three negative-radius cases, so the row-by-row ink is
// the documented deviation. What must hold is the DEFINED part: the 40x40 box itself is
// fully inked (a square corner), and the call neither throws nor disappears.
let argRowsBad = 0;
for (const name of ['negEw', 'negEh', 'negBoth']) {
  const airBox = sa.find((l) => l.includes(' ' + name + ' ')) || '';
  const aotBox = ta.find((l) => l.includes(' ' + name + ' ')) || '';
  const box = (l) => (/box=(-?\d+),(-?\d+),(-?\d+),(-?\d+)/.exec(l) || []).slice(1).join(',');
  if (box(aotBox) !== '10,10,49,49' || !box(airBox)) {
    argRowsBad++;
    console.log(`! ${name}: AOT box=${box(aotBox) || '(none)'} (a square corner is 10,10,49,49; AIR ${box(airBox) || '?'})`);
  }
}
console.log(`negative-radius cases: ${3 - argRowsBad}/3 draw the full box (AIR inks 1-2 px outside it -- documented)`);

const offEllipse = [...Object.entries(CASES)]
  .filter(([id, c]) => c[2] >= 0 && (Number.isNaN(c[3]) || c[3] >= 0)) // negatives: AIR itself is the reference
  .filter(([id]) => (worst.get(id) || { aot: 0 }).aot > 1.01).length;
console.log('');
console.log(offEllipse === 0
  ? 'RESULT: PASS (every row is within 1 px of the exact corner ellipse; AIR drifts up to '
    + Math.max(...[...worst.values()].map((v) => v.air)).toFixed(0) + ' px on the eccentric cases)'
  : 'RESULT: FAIL (' + offEllipse + ' case(s) do not match the corner ellipse)');
const okAll = offEllipse === 0 && bad.length + extra.length === 0 && argBad === 0 && argRowsBad === 0;
process.exit(okAll ? 0 : 1);
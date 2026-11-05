// tools/frame-perf.cjs -- end-to-end frame cost of a kit tree, one case at a time.
//
// `probes/perf` reports the KIT's own phases (describe / solve / paint). This
// runner reports what the FRAME costs once the runtime has painted it, using the
// runtime's `ASC_FRAME_STATS` counter (p50/p95/p99 frame interval, over17ms
// count, live/cached subtree counts, Present-skip count).
//
// It builds `probes/frame/Main.as` ONCE with the same flags as tools/probe.cjs,
// then runs that executable once per case with `case.txt` written beforehand.
// One process per case: the runtime's percentile window is 512 frames and resets
// after each print, so a shared process would blend cases together.
//
//   node tools/frame-perf.cjs                 # build + all cases
//   node tools/frame-perf.cjs --no-build      # reuse the exe
//   node tools/frame-perf.cjs --cases idle,text
'use strict';

const fs = require('fs');
const path = require('path');
const { spawnSync, spawn } = require('child_process');
const { ALL } = require('../ui-demo/kit-list.cjs');

const UI = path.resolve(__dirname, '..');
const COMPILER = path.resolve(UI, '..', 'as3compiler');
const clang = process.env.ASC_CC || 'clang';
const ICU = path.join(UI, 'ui-demo', 'icudtl.dat');
const MANIFEST = 'examples/window.build.example.json';

const argv = process.argv.slice(2);
const noBuild = argv.includes('--no-build');
const casesArg = argv.includes('--cases') ? argv[argv.indexOf('--cases') + 1] : null;
const CASES = casesArg ? casesArg.split(',').map((s) => s.trim()).filter(Boolean)
  : ['idle', 'text', 'move', 'all'];

const dir = path.join(UI, 'probes', 'frame');
if (!fs.existsSync(path.join(dir, 'Main.as'))) {
  console.error('[frame] no probes/frame/Main.as');
  process.exit(2);
}
if (fs.existsSync(ICU) && !fs.existsSync(path.join(dir, 'icudtl.dat'))) {
  fs.copyFileSync(ICU, path.join(dir, 'icudtl.dat'));
}

function build() {
  const args = [
    'src/index.ts',
    path.join(dir, 'Main.as'),
    ...ALL,
    '--manifest', MANIFEST,
    '--cc', clang,
    '-I', './vendor/curl/include',
    '-L', './vendor/curl/lib/windows-x64',
    '-l', 'zlib',
  ];
  console.log('[frame] building');
  const b = spawnSync(process.execPath, args, {
    cwd: COMPILER, encoding: 'utf8',
    timeout: Number(process.env.ASC_BUILD_TIMEOUT_MS || 300000),
    killSignal: 'SIGKILL',
  });
  const out = (b.stdout || '') + (b.stderr || '');
  if (b.status !== 0) {
    console.error('[frame] BUILD FAILED (exit ' + b.status + ')');
    const errs = out.split(/\r?\n/).filter((l) => /\berror\b|Error #|Cannot|not found|Unhandled/i.test(l));
    if (errs.length) console.error(errs.slice(0, 25).join('\n'));
    console.error(out.split(/\r?\n/).slice(-15).join('\n'));
    process.exit(1);
  }
}

function exePath() {
  const cands = ['Main.exe', 'Main'].map((f) => path.join(dir, f)).filter((p) => fs.existsSync(p));
  if (!cands.length) { console.error('[frame] no executable'); process.exit(2); }
  return cands[0];
}

function runCase(exe, name) {
  fs.writeFileSync(path.join(dir, 'case.txt'), name);
  for (const f of ['frame.done', 'frame.samples.txt', 'frame.stderr.txt']) {
    const p = path.join(dir, f);
    if (fs.existsSync(p)) fs.unlinkSync(p);
  }
  return new Promise((resolve) => {
    const t0 = Date.now();
    const child = spawn(exe, [], {
      cwd: dir,
      env: { ...process.env, ASC_FRAME_STATS: '1' },
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    let err = '';
    child.stderr.on('data', (d) => { err += d.toString(); });
    child.stdout.on('data', (d) => { err += d.toString(); });
    const poll = setInterval(() => {
      if (!fs.existsSync(path.join(dir, 'frame.done'))) return;
      clearInterval(poll);
      setTimeout(() => {
        try { child.kill(); } catch (e) { /* already gone */ }
        let samples = '';
        try { samples = fs.readFileSync(path.join(dir, 'frame.samples.txt'), 'utf8').trim(); } catch (e) { /* none */ }
        fs.writeFileSync(path.join(dir, 'frame.stderr.' + name.replace(/[:\\/]/g, '_') + '.txt'), err);
        resolve({ name, ms: Date.now() - t0, samples, frames: parseFrames(err) });
      }, 250);
    }, 120);
    setTimeout(() => {
      clearInterval(poll);
      try { child.kill(); } catch (e) { /* gone */ }
      fs.writeFileSync(path.join(dir, 'frame.stderr.' + name.replace(/[:\\/]/g, '_') + '.txt'), err);
      resolve({ name, ms: Date.now() - t0, samples: '', frames: parseFrames(err), timeout: true });
    }, Number(process.env.ASC_FRAME_TIMEOUT_MS || 90000));
  });
}

function parseFrames(err) {
  const lines = err.split(/\r?\n/).filter((l) => l.startsWith('FRAME '));
  return lines.map((l) => {
    const g = (k) => { const m = l.match(new RegExp(k + '=([0-9.]+)')); return m ? Number(m[1]) : null; };
    return {
      n: g('n'), p50: g('p50'), p95: g('p95'), p99: g('p99'),
      over8: g('over8ms'), over17: g('over17ms'),
      live: g('live'), cached: g('cached'), skip: g('presentskip'),
      gcshare: (l.match(/gcshare=([0-9.]+)/) || [])[1],
      rss: (l.match(/rss=([0-9]+)/) || [])[1],
    };
  });
}

(async () => {
  if (!noBuild) build();
  const exe = exePath();
  const results = [];
  for (const c of CASES) {
    process.stdout.write('[frame] ' + c + ' ... ');
    const r = await runCase(exe, c);
    results.push(r);
    const last = r.frames[r.frames.length - 1];
    console.log((r.timeout ? 'TIMEOUT ' : '') + (last
      ? 'p50=' + last.p50 + ' p95=' + last.p95 + ' p99=' + last.p99
        + ' over17=' + last.over17 + ' live=' + last.live + ' cached=' + last.cached
        + ' skip=' + last.skip
      : 'no FRAME line'));
  }
  console.log('\n' + results.map((r) => {
    const last = r.frames[r.frames.length - 1] || {};
    return (r.name + '        ').slice(0, 7)
      + ' p50=' + String(last.p50).padStart(6)
      + ' p95=' + String(last.p95).padStart(6)
      + ' p99=' + String(last.p99).padStart(6)
      + ' over8=' + String(last.over8).padStart(3)
      + ' over17=' + String(last.over17).padStart(3)
      + ' live=' + String(last.live).padStart(5)
      + ' cached=' + String(last.cached).padStart(5)
      + ' skip=' + String(last.skip).padStart(4)
      + ' gc=' + String(last.gcshare).padStart(5) + '%'
      + ' rss=' + String(last.rss).padStart(5) + 'MB'
      + '  ' + r.samples;
  }).join('\n'));
  const anyTimeout = results.some((r) => r.timeout || !r.frames.length);
  process.exit(anyTimeout ? 1 : 0);
})();
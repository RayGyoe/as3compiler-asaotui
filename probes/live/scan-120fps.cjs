// probes/live/scan-120fps.cjs -- with vsync off + frameRate=120, the pacer
// no longer caps an explicit frameRate to the 60 Hz panel refresh. The FRAME
// p50 then reflects REAL work (a 120 fps frame is 8.33 ms; a tick that exceeds
// it drops the frame), which is what the runtime actually spends outside the
// kit's per-phase counters (Skia rasterization + present + pacer).
//
// Same build-once / sweep-N / restore-nothing contract as scan-rows.cjs, but it
// captures ASC_FRAME_STATS from stderr and reports p50/p95/p99/over17 alongside
// the kit's per-tick CPU phases.
'use strict';
const fs = require('fs');
const path = require('path');
const { spawnSync, spawn } = require('child_process');

const UI = path.resolve(__dirname, '..', '..');
const COMPILER = path.resolve(UI, '..', 'as3compiler');
const clang = process.env.ASC_CC || 'clang';
const MANIFEST = 'examples/window.build.example.json';
const { ALL } = require(path.join(UI, 'ui-demo', 'kit-list.cjs'));
const DIR = path.join(UI, 'probes', 'live');

const argv = process.argv.slice(2);
const noBuild = argv.includes('--no-build');
const rowsArg = argv.includes('--rows') ? argv[argv.indexOf('--rows') + 1] : null;
const ROWS = rowsArg ? rowsArg.split(',').map((s) => parseInt(s, 10)).filter((n) => n > 0)
  : [22, 100, 200, 500];

function build() {
  const args = [
    'src/index.ts', path.join(DIR, 'Main.as'), ...ALL,
    '--manifest', MANIFEST, '--cc', clang,
    '-I', './vendor/curl/include',
    '-L', './vendor/curl/lib/windows-x64',
    '-l', 'zlib',
  ];
  console.log('[scan120] building');
  const b = spawnSync(process.execPath, args, {
    cwd: COMPILER, encoding: 'utf8',
    timeout: Number(process.env.ASC_BUILD_TIMEOUT_MS || 300000),
    killSignal: 'SIGKILL',
  });
  const out = (b.stdout || '') + (b.stderr || '');
  if (b.status !== 0) {
    console.error('[scan120] BUILD FAILED');
    const errs = out.split(/\r?\n/).filter((l) => /\berror\b|Error #|Cannot|not found|Unhandled/i.test(l));
    if (errs.length) console.error(errs.slice(0, 25).join('\n'));
    console.error(out.split(/\r?\n/).slice(-15).join('\n'));
    return false;
  }
  return true;
}

function exePath() {
  const p = path.join(DIR, 'Main.exe');
  return fs.existsSync(p) ? p : null;
}

function parseFrames(err) {
  const lines = err.split(/\r?\n/).filter((l) => l.startsWith('FRAME '));
  if (!lines.length) return null;
  const l = lines[lines.length - 1];
  const g = (k) => { const m = l.match(new RegExp(k + '=([0-9.]+)')); return m ? Number(m[1]) : null; };
  return { p50: g('p50'), p95: g('p95'), p99: g('p99'), over17: g('over17ms'),
           gcshare: g('gcshare'), skip: g('presentskip'), raw: l };
}

function runCase(exe, n) {
  fs.writeFileSync(path.join(DIR, 'case.txt'), String(n));
  for (const f of ['live.done', 'live.samples.txt']) {
    const p = path.join(DIR, f);
    if (fs.existsSync(p)) fs.unlinkSync(p);
  }
  return new Promise((resolve) => {
    const t0 = Date.now();
    const child = spawn(exe, [], {
      cwd: DIR, detached: true, stdio: ['ignore', 'pipe', 'pipe'],
      env: { ...process.env, ASC_FRAME_STATS: '1' },
    });
    let err = '';
    child.stderr.on('data', (d) => { err += d.toString(); });
    const deadline = Date.now() + 45000;
    const poll = setInterval(() => {
      if (fs.existsSync(path.join(DIR, 'live.done'))) {
        clearInterval(poll);
        setTimeout(() => {
          try { child.kill(); } catch (e) { /* gone */ }
          let samples = '';
          try { samples = fs.readFileSync(path.join(DIR, 'live.samples.txt'), 'utf8').trim(); } catch (e) { /* none */ }
          resolve({ n, ms: Date.now() - t0, samples, frames: parseFrames(err), err });
        }, 250);
        return;
      }
      if (Date.now() > deadline) {
        clearInterval(poll);
        try { child.kill(); } catch (e) { /* gone */ }
        resolve({ n, ms: Date.now() - t0, samples: '', frames: parseFrames(err), err, timeout: true });
      }
    }, 120);
  });
}

function phase(samples, name) {
  const m = samples.match(new RegExp('^  ' + name + '\\s+([0-9.]+)', 'm'));
  return m ? Number(m[1]) : null;
}

(async () => {
  if (!noBuild && !build()) process.exit(1);
  const exe = exePath();
  if (!exe) { console.error('[scan120] no executable'); process.exit(2); }

  console.log('\n@120fps (vsync off), FRAME p50 is real work; 8.33ms = one 120fps frame');
  console.log('rows  nodes  kitMeasure  kitTotal   FRAME p50  p95  p99  over17  gcshare');
  for (const n of ROWS) {
    process.stdout.write('[scan120] rows=' + n + ' ... ');
    const r = await runCase(exe, n);
    const nodes = (r.samples.match(/nodes=(\d+)/) || [])[1];
    const measure = phase(r.samples, 'measure');
    const total = ['render', 'reconcile', 'measure', 'solve', 'arrange', 'paint']
      .map((k) => phase(r.samples, k) || 0).reduce((a, b) => a + b, 0);
    if (r.timeout) { console.log('TIMEOUT'); continue; }
    const f = r.frames;
    console.log('done ' + (r.ms / 1000).toFixed(1) + 's');
    console.log(
      String(n).padStart(5)
      + '  ' + String(nodes).padStart(6)
      + '  ' + (measure ?? 0).toFixed(2).padStart(9)
      + '  ' + total.toFixed(2).padStart(9)
      + '  ' + (f ? String(f.p50).padStart(9) : '   (none)'.padStart(9))
      + '  ' + (f ? String(f.p95).padStart(3) : '  -')
      + '  ' + (f ? String(f.p99).padStart(4) : '   -')
      + '  ' + (f ? String(f.over17).padStart(6) : '     -')
      + '  ' + (f ? String(f.gcshare).padStart(6) : '     -')
    );
  }
  console.log('\n(FRAME p50 close to 8.33 = the tick total work fits a 120fps frame)');
})();

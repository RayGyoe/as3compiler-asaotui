// probes/live/scan-rows.cjs -- sweep the live probe's row count WITHOUT
// recompiling. Build once, then for each N write case.txt, run the same exe,
// and read the per-tick phase breakdown back out.
//
// The signal is the KIT's per-tick CPU phases (UiApp.profile), not the runtime's
// FRAME line: on a 60 Hz panel with vsync on, the FRAME p50 is locked to ~17 ms
// regardless of how little work a tick does (verified: frameRate=1000 gave the
// same p50=17). The per-tick phases are pure CPU time and scale with row count.
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
  : [22, 100, 200, 500, 1000];

function build() {
  const args = [
    'src/index.ts', path.join(DIR, 'Main.as'), ...ALL,
    '--manifest', MANIFEST, '--cc', clang,
    '-I', './vendor/curl/include',
    '-L', './vendor/curl/lib/windows-x64',
    '-l', 'zlib',
  ];
  console.log('[scan] building');
  const b = spawnSync(process.execPath, args, {
    cwd: COMPILER, encoding: 'utf8',
    timeout: Number(process.env.ASC_BUILD_TIMEOUT_MS || 300000),
    killSignal: 'SIGKILL',
  });
  const out = (b.stdout || '') + (b.stderr || '');
  if (b.status !== 0) {
    console.error('[scan] BUILD FAILED');
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

function runCase(exe, n) {
  fs.writeFileSync(path.join(DIR, 'case.txt'), String(n));
  for (const f of ['live.done', 'live.samples.txt']) {
    const p = path.join(DIR, f);
    if (fs.existsSync(p)) fs.unlinkSync(p);
  }
  return new Promise((resolve) => {
    const t0 = Date.now();
    const child = spawn(exe, [], { cwd: DIR, detached: true, stdio: ['ignore', 'pipe', 'pipe'] });
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
          resolve({ n, ms: Date.now() - t0, samples, err });
        }, 250);
        return;
      }
      if (Date.now() > deadline) {
        clearInterval(poll);
        try { child.kill(); } catch (e) { /* gone */ }
        resolve({ n, ms: Date.now() - t0, samples: '', err, timeout: true });
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
  if (!exe) { console.error('[scan] no executable'); process.exit(2); }

  console.log('\nrows  nodes  render  reconcile  measure  solve  arrange  paint   total(ms)  wall(s)');
  const results = [];
  for (const n of ROWS) {
    process.stdout.write('[scan] rows=' + n + ' ... ');
    const r = await runCase(exe, n);
    const nodes = (r.samples.match(/nodes=(\d+)/) || [])[1];
    const total = ['render', 'reconcile', 'measure', 'solve', 'arrange', 'paint']
      .map((k) => phase(r.samples, k) || 0).reduce((a, b) => a + b, 0);
    results.push(r);
    if (r.timeout) { console.log('TIMEOUT'); continue; }
    console.log('done ' + (r.ms / 1000).toFixed(1) + 's');
    console.log(
      String(n).padStart(5)
      + '  ' + String(nodes).padStart(6)
      + '  ' + String(phase(r.samples, 'render') ?? 0).padStart(6)
      + '  ' + String(phase(r.samples, 'reconcile') ?? 0).padStart(9)
      + '  ' + String(phase(r.samples, 'measure') ?? 0).padStart(7)
      + '  ' + String(phase(r.samples, 'solve') ?? 0).padStart(5)
      + '  ' + String(phase(r.samples, 'arrange') ?? 0).padStart(7)
      + '  ' + String(phase(r.samples, 'paint') ?? 0).padStart(6)
      + '  ' + total.toFixed(2).padStart(8)
      + '  ' + (r.ms / 1000).toFixed(1).padStart(8)
    );
  }
  console.log('\n(per-tick ms, averaged over ~30 ticks; measure dominates at every size)');
})();

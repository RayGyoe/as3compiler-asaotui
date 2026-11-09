// probes/live/dissect.cjs -- split the live probe's frame time: measure vs
// sparkline rasterization vs solve.
//
// The `perf` probe and the gallery's own counters stop at the AS3 side:
// UiApp.profPaintMs counts only the time spent RECORDING Shape path commands in
// paintSelf. The actual rasterization of those commands (Skia turning 22
// 24-point polylines into pixels) happens later, inside the runtime's present
// pass, and NO kit counter sees it. So this script crosses the two sources:
//
//   * live.samples.txt  -- the kit's per-tick phase breakdown (render/reconcile/
//                          measure/solve/arrange/paint), from UiApp.profile
//   * ASC_FRAME_STATS   -- wall-clock frame intervals (p50/p95/p99/over17), from
//                          the runtime, env-gated (no recompile needed to turn on)
//
// It mutates the kit ONE file at a time, rebuilds, re-runs, and restores
// byte-identical (sha256), the same contract as reviews/perf-dissect2.cjs.
// Cases:
//   baseline            the live probe as written
//   no-spark-path       sparkline clears but draws nothing (isolate raster cost)
//   no-measure          measurePass skipped (confirm the perf report's finding
//                       that measure, not paint, is the layout cost)
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync, spawn } = require('child_process');

const UI = path.resolve(__dirname, '..', '..');
const COMPILER = path.resolve(UI, '..', 'as3compiler');
const clang = process.env.ASC_CC || 'clang';
const MANIFEST = 'examples/window.build.example.json';
const { ALL } = require(path.join(UI, 'ui-demo', 'kit-list.cjs'));
const DIR = path.join(UI, 'probes', 'live');
const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const SPARK = path.join(UI, 'kit', 'asaot', 'ui', 'kind', 'SparklineWidget.as');
const UIAPP = path.join(UI, 'kit', 'asaot', 'ui', 'UiApp.as');

// ---- build (same command as tools/probe.cjs) -------------------------------
function build() {
  const args = [
    'src/index.ts', path.join(DIR, 'Main.as'), ...ALL,
    '--manifest', MANIFEST, '--cc', clang,
    '-I', './vendor/curl/include',
    '-L', './vendor/curl/lib/windows-x64',
    '-l', 'zlib',
  ];
  const b = spawnSync(process.execPath, args, {
    cwd: COMPILER, encoding: 'utf8',
    timeout: Number(process.env.ASC_BUILD_TIMEOUT_MS || 300000),
    killSignal: 'SIGKILL',
  });
  const out = (b.stdout || '') + (b.stderr || '');
  if (b.status !== 0) {
    const errs = out.split(/\r?\n/).filter((l) => /\berror\b|Error #|Cannot|not found|Unhandled/i.test(l));
    console.error('[dissect] BUILD FAILED');
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

// ---- run: capture ASC_FRAME_STATS stderr + live.samples.txt ----------------
function run() {
  for (const f of ['live.done', 'live.samples.txt']) {
    const p = path.join(DIR, f);
    if (fs.existsSync(p)) fs.unlinkSync(p);
  }
  const exe = exePath();
  const child = spawn(exe, [], {
    cwd: DIR, detached: true, stdio: ['ignore', 'pipe', 'pipe'],
    env: { ...process.env, ASC_FRAME_STATS: '1' },
  });
  let err = '';
  child.stderr.on('data', (d) => { err += d.toString(); });
  return new Promise((resolve) => {
    const deadline = Date.now() + 30000;
    const poll = setInterval(() => {
      if (fs.existsSync(path.join(DIR, 'live.done'))) {
        clearInterval(poll);
        setTimeout(() => {
          try { child.kill(); } catch (e) { /* gone */ }
          let samples = '';
          try { samples = fs.readFileSync(path.join(DIR, 'live.samples.txt'), 'utf8').trim(); } catch (e) { /* none */ }
          resolve({ samples, frames: parseFrames(err), err });
        }, 250);
        return;
      }
      if (Date.now() > deadline) {
        clearInterval(poll);
        try { child.kill(); } catch (e) { /* gone */ }
        resolve({ samples: '', frames: parseFrames(err), err, timeout: true });
      }
    }, 120);
  });
}

function parseFrames(err) {
  const lines = err.split(/\r?\n/).filter((l) => l.startsWith('FRAME '));
  return lines.map((l) => {
    const g = (k) => { const m = l.match(new RegExp(k + '=([0-9.]+)')); return m ? Number(m[1]) : null; };
    return {
      p50: g('p50'), p95: g('p95'), p99: g('p99'), over17: g('over17ms'),
      gcshare: g('gcshare'), live: g('live'), cached: g('cached'), skip: g('presentskip'),
    };
  });
}

function phase(samples, name) {
  const m = samples.match(new RegExp('^  ' + name + '\\s+([0-9.]+)', 'm'));
  return m ? Number(m[1]) : null;
}

function show(tag, r) {
  console.log('=== ' + tag + ' ===');
  const f = r.frames[r.frames.length - 1];
  console.log(r.samples ? r.samples : '(no samples)');
  if (f) console.log('FRAME p50=' + f.p50 + ' p95=' + f.p95 + ' p99=' + f.p99
    + ' over17=' + f.over17 + ' gcshare=' + f.gcshare + '% live=' + f.live
    + ' cached=' + f.cached + ' skip=' + f.skip);
  else console.log('(no FRAME line; ' + (r.timeout ? 'TIMEOUT' : 'window <512 frames') + ')');
  if (r.timeout) console.log('--- stderr tail ---\n' + (r.err || '').split(/\r?\n/).slice(-8).join('\n'));
  return r;
}

(async () => {
  // baseline
  if (!build()) process.exit(1);
  const base = await run();
  show('baseline', base);
  if (base.timeout || !base.frames.length) {
    console.error('[dissect] baseline did not produce a FRAME line; abort');
    process.exit(1);
  }

  // M1: sparkline clears but draws nothing (no polyline/fill/dot commands)
  const sparkOrig = fs.readFileSync(SPARK, 'utf8');
  const sparkHash = sha(SPARK);
  const anchor = `            g.clear();

            var vals:Array = n.extra[SRC] as Array;`;
  if (!sparkOrig.includes(anchor)) {
    console.error('[dissect] M1 anchor missing in SparklineWidget.as');
  } else {
    fs.writeFileSync(SPARK, sparkOrig.replace(anchor,
      `            g.clear();
            return;  // DISSECT: record no path, so Skia rasterizes nothing

            var vals:Array = n.extra[SRC] as Array;`));
    const r1 = build() ? await run() : { samples: '', frames: [], timeout: true };
    show('M1 no-spark-path', r1);
    fs.writeFileSync(SPARK, sparkOrig);
    console.log('M1 restore: ' + (sha(SPARK) === sparkHash ? 'byte-identical' : 'HASH MISMATCH'));
  }

  // M2: skip measurePass entirely (validate measure, not paint, is layout cost)
  const uiOrig = fs.readFileSync(UIAPP, 'utf8');
  const uiHash = sha(UIAPP);
  const uiAnchor = `            this.measurePasses = this.measurePasses + 1;
            measurePass(r);`;
  if (!uiOrig.includes(uiAnchor)) {
    console.error('[dissect] M2 anchor missing in UiApp.as');
  } else {
    fs.writeFileSync(UIAPP, uiOrig.replace(uiAnchor,
      `            this.measurePasses = this.measurePasses + 1;
            // DISSECT: no measurePass`));
    const r2 = build() ? await run() : { samples: '', frames: [], timeout: true };
    show('M2 no-measure', r2);
    fs.writeFileSync(UIAPP, uiOrig);
    console.log('M2 restore: ' + (sha(UIAPP) === uiHash ? 'byte-identical' : 'HASH MISMATCH'));
  }
})();

// probes/live/dissect-paint.cjs -- AFTER subtree-level measure, what dominates
// the paint phase (11.59 ms @ 200 rows)?
//
// The kit's profPaintMs counts ONLY the AS3 side: TextField shaping (field.text
// rebuilds the run table, setTextFormat rebuilds it again, reading textWidth
// forces a synchronous shape) plus Graphics path-command RECORDING (moveTo/
// lineTo/drawRect). The actual Skia rasterization of those commands happens
// later in the runtime present pass, which no kit counter sees -- ASC_FRAME_STATS
// does. So this script splits the paint phase into:
//
//   M1 no-text-reshape   TextWidget.paint skips the measureField re-shape, so a
//                        fixed-size text's CHANGED content never reaches the
//                        field. Isolates the TextField shaping cost.
//   M2 no-spark-path     Sparkline clears but records nothing. Isolates the
//                        polyline command-recording cost (Skia rasterizes less).
//   M3 no-paintbox       PaintKit.paintBox + decorate skipped. Isolates box/
//                        border command-recording.
//
// Mutates the kit ONE file at a time, rebuilds, re-runs, restores byte-identical
// (sha256), the same contract as reviews/perf-dissect2.cjs and dissect.cjs.
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

const TEXT = path.join(UI, 'kit', 'asaot', 'ui', 'kind', 'TextWidget.as');
const SPARK = path.join(UI, 'kit', 'asaot', 'ui', 'kind', 'SparklineWidget.as');
const PAINTKIT = path.join(UI, 'kit', 'asaot', 'ui', 'PaintKit.as');

const argv = process.argv.slice(2);
const noBuild = argv.includes('--no-build');
const rowsArg = argv.includes('--rows') ? argv[argv.indexOf('--rows') + 1] : null;
const ROWS = rowsArg ? rowsArg.split(',').map((s) => parseInt(s, 10)).filter((n) => n > 0)
  : [200];

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
    console.error('[dp] BUILD FAILED');
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

function run(n) {
  fs.writeFileSync(path.join(DIR, 'case.txt'), String(n));
  for (const f of ['live.done', 'live.samples.txt']) {
    const p = path.join(DIR, f);
    if (fs.existsSync(p)) fs.unlinkSync(p);
  }
  const exe = exePath();
  if (!exe) return Promise.resolve({ samples: '', frames: [], timeout: true, err: 'no exe' });
  return new Promise((resolve) => {
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

function show(tag, r, n) {
  const f = r.frames.length ? r.frames[r.frames.length - 1] : null;
  const paint = phase(r.samples, 'paint');
  const total = ['render', 'reconcile', 'measure', 'solve', 'arrange', 'paint']
    .map((k) => phase(r.samples, k) || 0).reduce((a, b) => a + b, 0);
  console.log(tag.padEnd(22) + ' rows=' + String(n).padStart(4)
    + '  paint=' + (paint == null ? '   -' : paint.toFixed(2)).padStart(6)
    + '  kitTotal=' + total.toFixed(2).padStart(6)
    + (f ? ('  FRAME p50=' + String(f.p50).padStart(4)
      + ' p95=' + String(f.p95).padStart(4)
      + ' gcshare=' + String(f.gcshare).padStart(5) + '%'
      + ' live=' + String(f.live).padStart(5)
      + ' cached=' + String(f.cached).padStart(5)) : '  (no FRAME)'));
  if (r.timeout) console.log('--- stderr tail ---\n' + (r.err || '').split(/\r?\n/).slice(-6).join('\n'));
  return { paint, total, f };
}

(async () => {
  const n = ROWS[0];
  if (!noBuild && !build()) process.exit(1);
  if (!exePath()) { console.error('[dp] no executable'); process.exit(2); }

  const base = await run(n);
  const rb = show('baseline', base, n);

  // M1: text reshape skipped (fixed-size text's changed content never re-shaped)
  const tOrig = fs.readFileSync(TEXT, 'utf8');
  const tHash = sha(TEXT);
  const tAnchor = `                if (n.tf.text != want)
                {
                    PaintKit.measureField(n, n.tf, n.textContent, s, NaN);
                    placeRun(n, s);
                }`;
  if (!tOrig.includes(tAnchor)) {
    console.error('[dp] M1 anchor missing in TextWidget.as');
  } else {
    fs.writeFileSync(TEXT, tOrig.replace(tAnchor,
      `                if (false && n.tf.text != want) // DISSECT: no re-shape
                {
                    PaintKit.measureField(n, n.tf, n.textContent, s, NaN);
                    placeRun(n, s);
                }`));
    if (build()) show('M1 no-text-reshape', await run(n), n);
    fs.writeFileSync(TEXT, tOrig);
    console.log('M1 restore: ' + (sha(TEXT) === tHash ? 'byte-identical' : 'HASH MISMATCH'));
  }

  // M2: sparkline records nothing
  const sOrig = fs.readFileSync(SPARK, 'utf8');
  const sHash = sha(SPARK);
  const sAnchor = `            g.clear();

            var vals:Array = n.extra[SRC] as Array;`;
  if (!sOrig.includes(sAnchor)) {
    console.error('[dp] M2 anchor missing in SparklineWidget.as');
  } else {
    fs.writeFileSync(SPARK, sOrig.replace(sAnchor,
      `            g.clear();
            return;  // DISSECT: no path commands recorded

            var vals:Array = n.extra[SRC] as Array;`));
    if (build()) show('M2 no-spark-path', await run(n), n);
    fs.writeFileSync(SPARK, sOrig);
    console.log('M2 restore: ' + (sha(SPARK) === sHash ? 'byte-identical' : 'HASH MISMATCH'));
  }

  // M3: paintBox + decorate skipped
  const pOrig = fs.readFileSync(PAINTKIT, 'utf8');
  const pHash = sha(PAINTKIT);
  const pAnchor = `    public static function paintBox(`;
  if (!pOrig.includes(pAnchor)) {
    console.error('[dp] M3 anchor missing in PaintKit.as');
  } else {
    const before = pOrig.indexOf(pAnchor);
    // find the opening brace of paintBox and inject an early return
    const brace = pOrig.indexOf('{', before);
    fs.writeFileSync(PAINTKIT, pOrig.slice(0, brace + 1) + '\n        return; // DISSECT: no box/border commands\n' + pOrig.slice(brace + 1));
    if (build()) show('M3 no-paintbox', await run(n), n);
    fs.writeFileSync(PAINTKIT, pOrig);
    console.log('M3 restore: ' + (sha(PAINTKIT) === pHash ? 'byte-identical' : 'HASH MISMATCH'));
  }

  console.log('\n(paint is the AS3 side: shaping + command recording. Skia rasterization lives in FRAME live/cached)');
})();

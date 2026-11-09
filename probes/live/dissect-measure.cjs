// probes/live/dissect-measure.cjs -- inside the measure phase, what dominates?
//
// Two candidates for the per-tick measure cost (1.99 ms @ 22 rows, 10.46 ms @
// 200 rows):
//   (a) the whole-tree measurePass WALK (every node's measureSelf, cached hit
//       = a handful of scalar compares)  -> "subtree-level measure" would cut it
//   (b) the field.textWidth/textHeight READS on text whose content changed.
//       On a FIXED-WIDTH text (the live price column) those reads force the
//       engine to synchronously shape the run, yet the intrinsic size is never
//       fed to layout (autoW/autoH are false, so measure() never setPointSize).
//       -> only cutting those reads (or not re-shaping fixed text at all) helps;
//          subtree-level measure does NOT, because the text really changed.
//
// This dissects (b) by nulling the two reads after `field.text = text`: if the
// measure phase collapses, the reads are the cost and subtree-level measure is
// the wrong lever. M1 also tests (a)+(b) together by skipping measurePass
// entirely (already known ~1.99 ms @ 22 rows).
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
const PAINTKIT = path.join(UI, 'kit', 'asaot', 'ui', 'PaintKit.as');

const argv = process.argv.slice(2);
const noBuild = argv.includes('--no-build');
const rowsArg = argv.includes('--rows') ? argv[argv.indexOf('--rows') + 1] : null;
const ROWS = rowsArg ? rowsArg.split(',').map((s) => parseInt(s, 10)).filter((n) => n > 0)
  : [22, 100, 200];

function build() {
  const args = [
    'src/index.ts', path.join(DIR, 'Main.as'), ...ALL,
    '--manifest', MANIFEST, '--cc', clang,
    '-I', './vendor/curl/include',
    '-L', './vendor/curl/lib/windows-x64',
    '-l', 'zlib',
  ];
  console.log('[dm] building');
  const b = spawnSync(process.execPath, args, {
    cwd: COMPILER, encoding: 'utf8',
    timeout: Number(process.env.ASC_BUILD_TIMEOUT_MS || 300000),
    killSignal: 'SIGKILL',
  });
  const out = (b.stdout || '') + (b.stderr || '');
  if (b.status !== 0) {
    console.error('[dm] BUILD FAILED');
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

async function sweep(tag) {
  const exe = exePath();
  console.log('\n[' + tag + ']');
  for (const n of ROWS) {
    const r = await runCase(exe, n);
    if (r.timeout) { console.log('  rows=' + n + ' TIMEOUT'); continue; }
    console.log('  rows=' + String(n).padStart(5)
      + '  measure=' + (phase(r.samples, 'measure') ?? 0).toFixed(2)
      + '  paint=' + (phase(r.samples, 'paint') ?? 0).toFixed(2)
      + '  total=' + (['render','reconcile','measure','solve','arrange','paint']
        .map((k) => phase(r.samples, k) || 0).reduce((a, b) => a + b, 0)).toFixed(2) + 'ms');
  }
}

(async () => {
  if (!noBuild && !build()) process.exit(1);

  const pkOrig = fs.readFileSync(PAINTKIT, 'utf8');
  const pkHash = sha(PAINTKIT);

  // baseline
  await sweep('baseline');

  // M1: null the textWidth/textHeight reads for reshaped (changed) text
  const anchor = `            if (reshape)
            {
                n.state.measuredW = wrapped ? wrapW : field.textWidth;
                n.state.measuredH = field.textHeight;
                n.state.measureValid = 3;
            }`;
  if (!pkOrig.includes(anchor)) {
    console.error('[dm] M1 anchor missing in PaintKit.as');
  } else {
    fs.writeFileSync(PAINTKIT, pkOrig.replace(anchor,
      `            if (reshape)
            {
                // DISSECT: skip the two shape-forcing reads
                n.state.measuredW = wrapped ? wrapW : 0;
                n.state.measuredH = 0;
                n.state.measureValid = 3;
            }`));
    if (!build()) process.exit(1);
    await sweep('M1 no-textWidth-read');
    fs.writeFileSync(PAINTKIT, pkOrig);
    console.log('M1 restore: ' + (sha(PAINTKIT) === pkHash ? 'byte-identical' : 'HASH MISMATCH'));
  }
})();

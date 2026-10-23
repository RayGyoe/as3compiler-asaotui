// mutation-gallery-zerorect.cjs -- prove the gallery tour's tree diagnostic is a
// VERDICT and not a comment.
//
// This tour has always COUNTED the three conditions that make a node silently
// unplaced (no engine node / a zero rect / a backing that was never attached) and
// printed the counts -- but the counts never reached `problems`, so a new widget
// that quietly failed to place itself would have been a PASS with a 0 in a log
// file nobody reads. As of the component catalog page (page 4) those counts are
// asserted, and this mutation is the proof that the assertion can fail.
//
// M1  give the catalog page's `image` a 0x0 style box. The node is then measured
//     and placed, but its rect is 0,0,0,0 -- precisely the failure shape the
//     diagnostic exists for -- and the tour must say WHICH node by name
//     ("page 4 has N node(s) with a zero rect"), not merely exit non-zero. A
//     non-zero exit alone would also be produced by a broken build, which would
//     prove nothing.
//
// The mutation is undone in `finally` and the restoration is verified by hash: a
// mutation that leaves the tree dirty is worse than no mutation at all.
//
// USAGE (from asaotui/ui-demo/):   node mutation-gallery-zerorect.cjs
//   (needs AIRSDK_HOME if the surrounding tooling asks for it; ~2 gallery runs)
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const HERE = __dirname;
const VIEW = path.join(HERE, 'demo', 'GalleryView.as');

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

function runGallery() {
  const r = spawnSync(process.execPath, [path.join(HERE, 'run-gallery.cjs')], {
    cwd: HERE,
    encoding: 'utf8',
    maxBuffer: 64 * 1024 * 1024,
    timeout: 900000,
    env: { ...process.env, ASC_NO_OPEN: '1' },
  });
  return {
    code: r.status === null ? 'signal/timeout ' + (r.signal || '') : r.status,
    out: (r.stdout || '') + (r.stderr || ''),
  };
}

const rows = [];
const record = (name, ok, detail) => rows.push({ name, ok, detail });

// ---- baseline: unmutated, the tour must be green -----------------------------
{
  const r = runGallery();
  const pass = /\[gallery\] RESULT: PASS/.test(r.out);
  record('baseline (unmutated) gallery tour', r.code === 0 && pass,
    'exit=' + r.code + (pass ? ' + RESULT: PASS' : ' but the tour was not green -- a mutation run would prove nothing'));
  if (!pass) {
    console.log(r.out.split(/\r?\n/).slice(-15).join('\n'));
    for (const row of rows) console.log((row.ok ? 'MUTATION PASS  ' : 'MUTATION FAIL  ') + row.name + '   [' + row.detail + ']');
    process.exit(1);
  }
}

// ---- M1: a zero-rect node on the catalog page ---------------------------------
const before = fs.readFileSync(VIEW, 'utf8');
const beforeHash = sha(VIEW);
const FIND = 'private static const CAT_H:StyleRefinement = StyleRefinement.from({ size: [Length.pct(1), Length.px(72)] });';
const REPLACE = 'private static const CAT_H:StyleRefinement = StyleRefinement.from({ size: [Length.px(0), Length.px(0)] });';
let restored = false;
try {
  if (!before.includes(FIND)) throw new Error('mutation anchor not found in ' + VIEW);
  fs.writeFileSync(VIEW, before.replace(FIND, REPLACE));
  const r = runGallery();
  const named = /page 4 has \d+ node\(s\) with a zero rect/.test(r.out);
  const stillPassed = /\[gallery\] RESULT: PASS/.test(r.out);
  record('M1 catalog image sized 0x0 -> named red', r.code !== 0 && named && !stillPassed,
    'exit=' + r.code
      + (named ? ' + the zero-rect verdict named the page' : ' but the zero-rect verdict did not appear')
      + (stillPassed ? ' AND STILL PASSED (the verdict is decoration)' : ''));
} finally {
  fs.writeFileSync(VIEW, before);
  restored = sha(VIEW) === beforeHash;
}

console.log('');
for (const row of rows) console.log((row.ok ? 'MUTATION PASS  ' : 'MUTATION FAIL  ') + row.name + '   [' + row.detail + ']');
console.log('restore: ' + (restored ? 'GalleryView.as byte-identical' : 'TAMPERED'));
const bad = rows.filter((r) => !r.ok).length + (restored ? 0 : 1);
console.log('');
console.log('MUTATION gallery-zero-rect: ' + (bad === 0 ? 'PASS (1/1)' : 'FAIL (' + bad + ' problem(s))'));
process.exit(bad === 0 ? 0 : 1);
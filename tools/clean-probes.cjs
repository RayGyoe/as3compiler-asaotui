// tools/clean-probes.cjs -- drop build artifacts from probes/ so the workspace
// keeps the SOURCE and the EVIDENCE but not the multi-megabyte by-products.
//
// Kept:   *.as (the probe), *.bmp / *.rects.txt / *.log (the measurements)
// Dropped: *.c, *.exe, *.pdb (regenerable, and the .c files are 3 MB each)
//
// ONE EXCEPTION, learned the hard way (2026-10-25): `probes/g11-nondeterminism/artifact-*.c`
// are .c FILES THAT ARE THE EVIDENCE -- three full generated files committed so that
// "5 builds -> 1 C" can be checked by hash (see that probe's README). A blanket *.c sweep
// deleted all three from the working tree; they came back from git byte-identical, and the
// directory is now excluded here so the next sweep cannot eat them again.
'use strict';
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const probes = path.join(root, 'probes');
let n = 0, bytes = 0;
const killed = [];

// Directories whose *.c files are checked-in evidence, not by-products.
const KEEP_C = [path.join(probes, 'g11-nondeterminism')];

function walk(dir) {
  for (const f of fs.readdirSync(dir)) {
    const q = path.join(dir, f);
    let st;
    try { st = fs.statSync(q); } catch (e) { continue; }
    if (st.isDirectory()) { walk(q); continue; }
    const keepC = /\.c$/i.test(f) && KEEP_C.indexOf(dir) >= 0;
    if (!keepC && /\.(c|exe|pdb)$/i.test(f)) { bytes += st.size; fs.unlinkSync(q); n++; killed.push(path.relative(root, q)); }
  }
}
if (fs.existsSync(probes)) walk(probes);

// asan.cjs writes its instrumented binary next to whatever target it was pointed
// at, which may be a directory owned by another worker.
for (const f of ['CheckUi.asan.exe', 'CheckUi.asan.pdb', 'CheckUiDbg.asan.exe', 'CheckUiDbg.asan.pdb']) {
  const q = path.join(root, 'ui-demo', f);
  if (fs.existsSync(q)) { bytes += fs.statSync(q).size; fs.unlinkSync(q); n++; killed.push('ui-demo/' + f); }
}

for (const k of killed) console.log('  removed ' + k);
console.log('cleaned ' + n + ' build artifacts (' + (bytes / 1048576).toFixed(1) + ' MB)');
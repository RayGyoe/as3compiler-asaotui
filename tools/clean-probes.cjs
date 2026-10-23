// tools/clean-probes.cjs -- drop build artifacts from probes/ so the workspace
// keeps the SOURCE and the EVIDENCE but not the multi-megabyte by-products.
//
// Kept:   *.as (the probe), *.bmp / *.rects.txt / *.log (the measurements)
// Dropped: *.c, *.exe, *.pdb (regenerable, and the .c files are 3 MB each)
'use strict';
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const probes = path.join(root, 'probes');
let n = 0, bytes = 0;
const killed = [];

function walk(dir) {
  for (const f of fs.readdirSync(dir)) {
    const q = path.join(dir, f);
    let st;
    try { st = fs.statSync(q); } catch (e) { continue; }
    if (st.isDirectory()) { walk(q); continue; }
    if (/\.(c|exe|pdb)$/i.test(f)) { bytes += st.size; fs.unlinkSync(q); n++; killed.push(path.relative(root, q)); }
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
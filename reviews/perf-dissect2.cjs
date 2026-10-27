// Split the remaining 8ms of the layout phase: measure / solve / arrange / paint.
const fs = require('fs');
const crypto = require('crypto');
const { execFileSync } = require('child_process');
const FILE = 'kit/asaot/ui/UiApp.as';
const orig = fs.readFileSync(FILE, 'utf8');
const sha = (s) => crypto.createHash('sha256').update(s).digest('hex');
const origSha = sha(orig);

const CASES = [
  { name: 'no paint at all after a solve',
    find: `                if (this.root != null) paintDirty(this.root);
                if (this.overlayRoot != null) paintDirty(this.overlayRoot);`,
    replace: `                // MEASUREMENT: no paint` },
  { name: 'no measurePass',
    find: `            measurePass(r);`,
    replace: `            // MEASUREMENT: no measure` },
  { name: 'no arrangePass',
    find: `            arrangePass(r, 0, 0);`,
    replace: `            // MEASUREMENT: no arrange` }
];
function run() {
  execFileSync('node', ['tools/probe.cjs', 'probes/perf'], { stdio: 'pipe' });
  const s = fs.readFileSync('probes/perf/perf.samples.txt', 'utf8');
  return s.split(/\r?\n/).filter((l) => /layout|solve/.test(l)).join('\n');
}
try {
  console.log('=== baseline ===\n' + run());
  for (const c of CASES) {
    if (!orig.includes(c.find)) { console.log('ANCHOR MISSING ' + c.name); continue; }
    fs.writeFileSync(FILE, orig.replace(c.find, c.replace));
    console.log('=== ' + c.name + ' ===\n' + run());
    fs.writeFileSync(FILE, orig);
  }
} finally {
  fs.writeFileSync(FILE, orig);
  console.log('restore byte-identical: ' + (sha(fs.readFileSync(FILE, 'utf8')) === origSha));
}

// Dissect the 39ms describe pass: remove ONE mechanism at a time, rebuild,
// measure, restore byte-identically. This is a MEASUREMENT, not a fix.
const fs = require('fs');
const crypto = require('crypto');
const { execFileSync } = require('child_process');

const FILE = 'kit/asaot/ui/Reconciler.as';
const orig = fs.readFileSync(FILE, 'utf8');
const sha = (s) => crypto.createHash('sha256').update(s).digest('hex');
const origSha = sha(orig);

const CASES = [
  {
    name: 'A: no duplicate-key O(n^2) scan',
    find: `            for (i = 0; i < count; i++)
            {
                if (kids[i].key == null) continue;
                for (var j:int = i + 1; j < count; j++)
                {
                    if (kids[j].key == null) continue;
                    if (this.internKey(kids[i].key) == this.internKey(kids[j].key))
                    {
                        throw new Error('asaot.ui: duplicate key "' + String(kids[i].key)
                            + '" under parent kind "' + n.kind + '" (api-design section 1.2)');
                    }
                }
            }`,
    replace: `            // MEASUREMENT: duplicate-key scan removed`
  },
  {
    name: 'B: no engine/display re-order when nothing moved',
    find: `            this.fixEngineOrder(n, next);
            this.fixDisplayOrder(n, next);`,
    replace: `            if (reordered) { this.fixEngineOrder(n, next); this.fixDisplayOrder(n, next); }`
  }
];

function buildAndRun() {
  execFileSync('node', ['tools/probe.cjs', 'probes/perf'], { stdio: 'pipe' });
  return fs.readFileSync('probes/perf/perf.samples.txt', 'utf8');
}

try {
  console.log('=== baseline ===\n' + buildAndRun());
  for (const c of CASES) {
    if (!orig.includes(c.find)) { console.log('ANCHOR MISSING: ' + c.name); continue; }
    fs.writeFileSync(FILE, orig.replace(c.find, c.replace));
    console.log('=== ' + c.name + ' ===\n' + buildAndRun());
    fs.writeFileSync(FILE, orig);
  }
  // both at once
  let both = orig;
  for (const c of CASES) both = both.replace(c.find, c.replace);
  fs.writeFileSync(FILE, both);
  console.log('=== A+B together ===\n' + buildAndRun());
} finally {
  fs.writeFileSync(FILE, orig);
  console.log('restore byte-identical: ' + (sha(fs.readFileSync(FILE, 'utf8')) === origSha));
}

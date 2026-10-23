// probes/style-fromany/mutation.cjs -- proves run.cjs CAN go red.
//
// A probe that cannot fail is decoration. Each mutation below is a deliberate
// one-token change to the code the probe is supposed to be measuring; after it,
// `run.cjs` MUST exit non-zero. Every file is restored in `finally` and its
// sha256 is compared byte-for-byte with the pre-mutation hash, so a mutation run
// can never leave the library subtly altered.
//
// USAGE (from asaotui/):   node probes/style-fromany/mutation.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const DIR = __dirname;
const UI = path.resolve(DIR, '..', '..');
const RUN = path.join(DIR, 'run.cjs');
const RESULTS = path.join(DIR, 'style-fromany-mutation.txt');

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const MUTATIONS = [
  {
    id: 'M1',
    why: 'Size.fromAny loses its array branch -> case 1 must stop being (100px,50px)',
    file: 'kit/asaot/ui/style/Size.as',
    find: '            if (o is Array) return fromArray(o as Array);\n',
    replace: '',
  },
  {
    id: 'M2',
    why: 'Edges.fromArray swaps [h,v] -> case 5 must stop being (4,8,4,8)',
    file: 'kit/asaot/ui/style/Edges.as',
    find: 'if (a.length == 2) return hv(Number(a[0]), Number(a[1]));',
    replace: 'if (a.length == 2) return hv(Number(a[1]), Number(a[0]));',
  },
  {
    id: 'M3',
    why: 'the mechanism itself: `is Array` on an Object param hard-coded to false -> case 15 red',
    file: 'probes/style-fromany/StyleCases.as',
    find: '            return o is Array;',
    replace: '            return false;',
  },
  {
    id: 'M4',
    why: 'LengthEdges.fromArray swaps the [h,v] sides -> case 10 must change',
    file: 'kit/asaot/ui/style/LengthEdges.as',
    find: '                var h:Length = lenOf(a[0]);\n                var v:Length = lenOf(a[1]);',
    replace: '                var h:Length = lenOf(a[1]);\n                var v:Length = lenOf(a[0]);',
  },
];

const log = [];
const line = (s) => { console.log(s); log.push(s); };
let caught = 0;
let broken = 0;

for (const m of MUTATIONS) {
  const file = path.join(UI, m.file);
  const before = fs.readFileSync(file, 'utf8');
  const beforeHash = sha(file);
  if (before.indexOf(m.find) < 0) {
    line(m.id + '  SKIPPED -- anchor text not found in ' + m.file + ' (the probe file drifted; fix the mutation, do not ignore it)');
    broken++;
    continue;
  }
  try {
    fs.writeFileSync(file, before.split(m.find).join(m.replace));
    const r = spawnSync(process.execPath, [RUN], { cwd: UI, encoding: 'utf8' });
    const out = (r.stdout || '') + (r.stderr || '');
    const red = r.status !== 0;
    if (red) caught++; else broken++;
    const failedIds = [...out.matchAll(/FAIL  id (\d+)/g)].map((x) => x[1]);
    line(m.id + '  ' + (red ? 'CAUGHT (exit ' + r.status + ')' : 'MISSED (exit 0 -- THIS IS BAD)')
      + '  ' + m.why);
    if (failedIds.length) line('     failed cases: ' + [...new Set(failedIds)].join(', '));
  } finally {
    fs.writeFileSync(file, before);
  }
  const afterHash = sha(file);
  line('     restore: ' + (afterHash === beforeHash ? 'byte-identical (' + afterHash.slice(0, 16) + ')' : 'MISMATCH ' + beforeHash.slice(0, 16) + ' -> ' + afterHash.slice(0, 16) + '  THIS IS BAD'));
  if (afterHash !== beforeHash) broken++;
}

line('');
line('MUTATION ' + path.basename(DIR) + ': ' + caught + '/' + MUTATIONS.length + ' caught, ' + broken + ' problem(s)');
line(broken === 0 ? 'RESULT: PASS' : 'RESULT: FAIL');
fs.writeFileSync(RESULTS, log.join('\n') + '\n');
process.exit(broken === 0 && caught === MUTATIONS.length ? 0 : 1);
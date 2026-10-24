// tools/mutation-listener-wiring.cjs -- proves tools/listener-wiring.cjs goes red on
// each half of the rule it enforces, and names the site it should name.
//
// The gate exists for the AIR-only crash of 2026-10-24: a node's anonymous listeners
// stay attached to a display object that AIR keeps delivering to after the node was
// torn down (see the header of tools/listener-wiring.cjs). Three mutations, one per
// way the rule can be broken:
//   M1  a widget attaches straight to its backing again (the common case)
//   M2  the TextField listeners bypass listen() (they are on a DIFFERENT object, so a
//       scan that only looked at `backing` would miss them -- this is the mutation
//       that proves the scan covers both)
//   M3  destroySubtree stops calling releaseListeners (the release half: no raw attach
//       anywhere, everything recorded, and the node still keeps its listeners)
//
// Every file is restored in `finally` and its sha256 compared byte-for-byte.
//
// USAGE (from asaotui/):   node tools/mutation-listener-wiring.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const UI = path.resolve(__dirname, '..');
const RESULTS = path.join(UI, 'reviews', 'mutation-listener-wiring.txt');

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const MUTATIONS = [
  {
    id: 'M1',
    why: 'MenuWidget attaches its row-hover listener straight to the backing again',
    file: 'kit/asaot/ui/kind/MenuWidget.as',
    find: 'n.listen(n.backing, MouseEvent.MOUSE_OUT,',
    replace: 'n.backing.addEventListener(MouseEvent.MOUSE_OUT,',
    expect: 'MenuWidget.as'
  },
  {
    id: 'M2',
    why: 'InputWidget bypasses listen() for the TextField listeners (a scan that only watched '
      + '`.backing` would stay green)',
    file: 'kit/asaot/ui/kind/InputWidget.as',
    find: 'n.listen(n.tf, FocusEvent.FOCUS_OUT,',
    replace: 'n.tf.addEventListener(FocusEvent.FOCUS_OUT,',
    expect: 'InputWidget.as'
  },
  {
    id: 'M3',
    why: 'destroySubtree stops releasing: every listener stays on a dead node',
    file: 'kit/asaot/ui/UiNode.as',
    find: '            this.releaseListeners();\n',
    replace: '',
    expect: 'does not call releaseListeners'
  }
];

function run() {
  return spawnSync(process.execPath, ['tools/listener-wiring.cjs'], { cwd: UI, encoding: 'utf8' });
}

const log = [];
const line = (s) => { console.log(s); log.push(s); };
let caught = 0;
let broken = 0;

const base = run();
const baseOut = (base.stdout || '') + (base.stderr || '');
line('baseline (unmutated): ' + (/LISTENER WIRING: (\w+)/.exec(baseOut) || [, 'NO VERDICT'])[1]);
if (base.status !== 0) {
  line('the baseline is not green; a mutation run would be meaningless. Aborting.');
  for (const l of baseOut.split(/\r?\n/)) line('  ' + l);
  fs.writeFileSync(RESULTS, log.join('\n') + '\n');
  process.exit(1);
}
line('');

for (const m of MUTATIONS) {
  const file = path.join(UI, m.file);
  const before = fs.readFileSync(file, 'utf8');
  const beforeHash = sha(file);
  if (before.indexOf(m.find) < 0) {
    line(m.id + '  SKIPPED -- anchor text not found in ' + m.file
      + ' (the file drifted; fix the mutation, do not ignore it)');
    broken++;
    continue;
  }
  try {
    fs.writeFileSync(file, before.split(m.find).join(m.replace));
    const r = run();
    const out = (r.stdout || '') + (r.stderr || '');
    const failed = r.status !== 0 && /LISTENER WIRING: FAIL/.test(out);
    const saidIt = out.indexOf(m.expect) >= 0;
    const ok = failed && saidIt;
    if (ok) caught++; else broken++;
    line(m.id + '  ' + (ok ? 'CAUGHT' : 'MISSED (THIS IS BAD)') + '  ' + m.why);
    line('     exit ' + r.status + (saidIt ? '' : '  MISSING the expected line "' + m.expect + '"'));
    for (const l of out.split(/\r?\n/).filter((x) => /^  kit\//.test(x)).slice(0, 3)) line('     ' + l.trim());
  } finally {
    fs.writeFileSync(file, before);
  }
  const afterHash = sha(file);
  line('     restore: ' + (afterHash === beforeHash
    ? 'byte-identical (' + afterHash.slice(0, 16) + ')'
    : 'MISMATCH ' + beforeHash.slice(0, 16) + ' -> ' + afterHash.slice(0, 16) + '  THIS IS BAD'));
  if (afterHash !== beforeHash) broken++;
}

line('');
line('MUTATION listener-wiring: ' + caught + '/' + MUTATIONS.length + ' caught, ' + broken + ' problem(s)');
line(broken === 0 && caught === MUTATIONS.length ? 'RESULT: PASS' : 'RESULT: FAIL');
fs.mkdirSync(path.dirname(RESULTS), { recursive: true });
fs.writeFileSync(RESULTS, log.join('\n') + '\n');
process.exit(broken === 0 && caught === MUTATIONS.length ? 0 : 1);
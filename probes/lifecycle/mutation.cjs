// probes/lifecycle/mutation.cjs -- proves probes/lifecycle goes red when the fix is
// undone, and that it measures the CONTRACT (a destroyed node is unreachable) rather
// than one lucky method.
//
// The defect (measured on adl 51.4.1, air-trace.txt): `destroySubtree` takes the
// backing off the display list but the anonymous listeners it installed stay attached
// to that display object, and AIR delivers the roll-out to it one beat AFTER the node
// died -- "TypeError #1009 at asaot.ui::UiNode/setHover", once per click, on every page
// whose click tears down the control it was made on.
//
// M1 and M2 undo the fix at its two ends (the release, and the bookkeeping that makes
// the release possible). M3 is the interesting one: it releases exactly ONE listener
// per node -- enough to keep `mouseOver` quiet for the kinds that only have UiNode's
// own listeners, so a probe that sampled a single event on a single kind would stay
// green while menu/scrollView still crashed. M4 keeps the array but unhooks nothing.
//
// Every file is restored in `finally` and its sha256 compared byte-for-byte with the
// pre-mutation hash: a mutation run can never leave the kit subtly altered.
//
// USAGE (from asaotui/):   node probes/lifecycle/mutation.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const DIR = __dirname;
const UI = path.resolve(DIR, '..', '..');        // probes/lifecycle -> asaotui
const PROBE = 'probes/lifecycle';
const RESULTS = path.join(DIR, 'lifecycle-mutation.txt');

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const MUTATIONS = [
  {
    id: 'M1',
    why: 'destroySubtree stops releasing: every listener it installed stays on the display object AIR '
      + 'still holds, which is exactly the shipped bug',
    file: 'kit/asaot/ui/UiNode.as',
    find: '            this.releaseListeners();\n',
    replace: '',
    expect: 'threw'
  },
  {
    id: 'M2',
    why: 'listen() attaches but records nothing, so releaseListeners has nothing to unhook',
    file: 'kit/asaot/ui/UiNode.as',
    find: '            this.wired.push(target, type, fn);',
    replace: '            // mutation: the listener is attached and forgotten',
    expect: 'threw'
  },
  {
    id: 'M3',
    why: 'only the FIRST recorded listener is released -- UiNode\'s own mouseOver, so the reported '
      + 'setHover crash goes quiet while menu/scrollView keep their own handlers (the widget half of the '
      + 'contract is what this probe must not lose)',
    file: 'kit/asaot/ui/UiNode.as',
    find: 'for (var i:int = 0; i < this.wired.length; i += 3)',
    replace: 'for (var i:int = 0; i < 3; i += 3)',
    expect: 'menu mouseOut'
  },
  {
    id: 'M4',
    why: 'the bookkeeping is emptied without removing anything (a release that only looks like one: the '
      + 'array is clean, the display object is not)',
    file: 'kit/asaot/ui/UiNode.as',
    find: '                t.removeEventListener(String(this.wired[i + 1]), this.wired[i + 2] as Function);',
    replace: '                // mutation: the array is cleared, the listener is not',
    expect: 'threw'
  }
];

function runProbe() {
  return spawnSync(process.execPath, ['tools/probe.cjs', PROBE], { cwd: UI, encoding: 'utf8' });
}

const log = [];
const line = (s) => { console.log(s); log.push(s); };
let caught = 0;
let broken = 0;

const base = runProbe();
const baseOut = (base.stdout || '') + (base.stderr || '');
const baseVerdict = /RESULT: (PASS|FAIL)/.exec(baseOut);
line('baseline (unmutated): ' + (baseVerdict ? baseVerdict[0] : 'NO VERDICT -- build failure?'));
if (!baseVerdict || baseVerdict[1] !== 'PASS') {
  line('the baseline is not green; a mutation run would be meaningless. Aborting.');
  for (const l of baseOut.split(/\r?\n/).slice(-25)) line('  ' + l);
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
    const r = runProbe();
    const out = (r.stdout || '') + (r.stderr || '');
    const verdict = /RESULT: (PASS|FAIL)/.exec(out);
    const saidIt = out.indexOf(m.expect) >= 0;
    const buildFailed = /BUILD FAILED/.test(out);
    const timedOut = /TIMEOUT/.test(out);
    const ok = verdict != null && verdict[1] === 'FAIL' && saidIt && !buildFailed && !timedOut;
    if (ok) caught++; else broken++;
    line(m.id + '  ' + (ok ? 'CAUGHT' : 'MISSED (THIS IS BAD)') + '  ' + m.why);
    line('     verdict: ' + (verdict ? verdict[0] : 'none')
      + (buildFailed ? '  BUILD FAILED -- a mutation that does not compile proves nothing' : '')
      + (timedOut ? '  TIMEOUT -- an opaque failure is not a named one' : '')
      + (saidIt ? '' : '  MISSING the expected failure line "' + m.expect + '"'));
    const fails = out.split(/\r?\n/).filter((l) => /  FAIL  /.test(l));
    for (const f of fails.slice(0, 2)) line('     ' + f.trim().slice(0, 260));
    if (fails.length > 2) line('     ... and ' + (fails.length - 2) + ' more');
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
line('MUTATION lifecycle: ' + caught + '/' + MUTATIONS.length + ' caught, ' + broken + ' problem(s)');
line(broken === 0 && caught === MUTATIONS.length ? 'RESULT: PASS' : 'RESULT: FAIL');
fs.writeFileSync(RESULTS, log.join('\n') + '\n');
process.exit(broken === 0 && caught === MUTATIONS.length ? 0 : 1);
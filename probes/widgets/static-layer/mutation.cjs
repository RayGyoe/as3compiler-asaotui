// probes/widgets/static-layer/mutation.cjs -- proves probes/widgets/static-layer
// CAN go red on the round that added the `staticLayer` opt-in.
//
// Every mutation is one CONTRACT, not one bug: each removes exactly the mechanism
// whose absence the probe is supposed to see, so a green run after a mutation would
// mean the probe is measuring nothing.
//
//   M1 the opts mirror is dropped            -> `box({ staticLayer: true })` never
//                                               reaches the description, so stable's
//                                               backing.cacheAsBitmap stays false
//   M2 the retained flag never reaches the   -> the description says staticLayer but
//      display object                            nothing sets cacheAsBitmap
//   M3 the default flips to true             -> every node becomes a static layer, so
//                                               the undeclared ROOT also gets cached
//                                               (the opt-in stops being a choice)
//
// Each mutated file is restored in `finally` and its sha256 compared byte-for-byte
// with the pre-mutation hash: a mutation run can never leave the kit subtly altered.
//
// USAGE (from asaotui/):   node probes/widgets/static-layer/mutation.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const DIR = __dirname;
const UI = path.resolve(DIR, '..', '..', '..');
const PROBE = 'probes/widgets/static-layer';
const RESULTS = path.join(DIR, 'static-layer-mutation.txt');

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const MUTATIONS = [
  {
    id: 'M1',
    file: 'kit/asaot/ui/OptionSupport.as',
    why: 'THE OPTS MIRROR IS DROPPED: `box({ staticLayer: true })` never reaches the '
      + 'description, so stable\'s backing.cacheAsBitmap stays false -- the opt-in is '
      + 'decoration',
    find: '            if (opts.staticLayer != null) n.staticLayer = Boolean(opts.staticLayer);',
    replace: '            // (mutation) staticLayer opt is dropped',
    expect: 'stable cacheAsBitmap not true',
  },
  {
    id: 'M2',
    file: 'kit/asaot/ui/UiNode.as',
    why: 'THE RETAINED FLAG NEVER REACHES THE DISPLAY OBJECT: the description says '
      + 'staticLayer but nothing writes cacheAsBitmap, so the bake never happens',
    find: '                if (this.backing != null) this.backing.cacheAsBitmap = sl;',
    replace: '                // (mutation) the flag never reaches the display object',
    expect: 'stable cacheAsBitmap not true',
  },
  {
    id: 'M3',
    file: 'kit/asaot/ui/Element.as',
    why: 'THE DEFAULT FLIPS TO TRUE: every node becomes a static layer, so the '
      + 'undeclared ROOT is cached too -- the opt-in stops being a choice',
    find: '            this.staticLayer = false;',
    replace: '            this.staticLayer = true;',
    expect: 'root cacheAsBitmap not false',
  },
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
  line('--- baseline output (tail) ---');
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
    const ok = verdict != null && verdict[1] === 'FAIL' && saidIt && !buildFailed;
    if (ok) caught++; else broken++;
    line(m.id + '  ' + (ok ? 'CAUGHT' : 'MISSED (THIS IS BAD)') + '  ' + m.why);
    line('     verdict: ' + (verdict ? verdict[0] : 'none')
      + (buildFailed ? '  BUILD FAILED -- a mutation that does not compile proves nothing' : '')
      + (timedOut ? '  TIMEOUT -- the program never reached its verdict' : '')
      + (saidIt ? '' : '  MISSING the expected failure line "' + m.expect + '"'));
    const fails = out.split(/\r?\n/).filter((l) => /  FAIL  /.test(l));
    for (const f of fails.slice(0, 4)) line('     ' + f.trim());
    if (fails.length > 4) line('     ... and ' + (fails.length - 4) + ' more');
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
line('MUTATION static-layer: ' + caught + '/' + MUTATIONS.length + ' caught, ' + broken + ' problem(s)');
line(broken === 0 && caught === MUTATIONS.length ? 'RESULT: PASS' : 'RESULT: FAIL');
fs.writeFileSync(RESULTS, log.join('\n') + '\n');
process.exit(broken === 0 && caught === MUTATIONS.length ? 0 : 1);

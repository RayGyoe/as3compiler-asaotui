// probes/g22-closure-statics/mutation.cjs -- proves run.cjs CAN go red.
//
// A probe that cannot fail is decoration. Two mutations point at the COMPILER fix
// itself (the early `collectCinitClasses()` and the early `_cinit` forward
// declaration), so removing either half turns the probe red; the other two check
// that the reference arm and the hand-derived rule really do get compared.
// Every file -- including the compiler source -- is restored in `finally` and its
// sha256 compared byte-for-byte, so a mutation run can never leave the tree altered.
//
// USAGE (from asaotui/):   node probes/g22-closure-statics/mutation.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const DIR = __dirname;
const UI = path.resolve(DIR, '..', '..');
const ROOT = path.resolve(UI, '..');
const RUN = path.join(DIR, 'run.cjs');
const RESULTS = path.join(DIR, 'g22-closure-statics-mutation.txt');

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const CRLF = '\r\n';

// src/emit.ts is a CRLF file: the anchors below carry the line break explicitly so
// a "not found" here means the compiler source really changed, not that the editor
// normalised line endings.
const EMIT = 'as3compiler/src/emit.ts';

const MUTATIONS = [
  {
    id: 'M1',
    why: 'HALF 1 of the fix is load-bearing: drop the early `collectCinitClasses()` (the set is then still '
      + 'empty while closure bodies are emitted) -> every static read loses its guard again',
    file: EMIT,
    base: 'repo',
    find: '    this.collectCinitClasses();' + CRLF + '    for (const s of this.program.body) {',
    replace: '    // MUTATION M1: early collect disabled' + CRLF + '    for (const s of this.program.body) {',
    expectSubstring: 'RESULT: FAIL',
  },
  {
    id: 'M2',
    why: 'HALF 2 is load-bearing: without the early `_cinit` forward declaration the guarded call precedes '
      + 'any declaration of it, so C rejects the program instead of running it',
    file: EMIT,
    base: 'repo',
    find: '    for (const cname of this.cinitClasses) this.line(`static void ${cname}_cinit(void);`);' + CRLF
      + '    this.emitFunctionValues();',
    replace: '    // MUTATION M2: early forward declaration disabled' + CRLF + '    this.emitFunctionValues();',
    expectSubstring: 'AOT BUILD FAILED',
    expectExit: 2,
  },
  {
    id: 'M3',
    why: 'the RULE is checked, not assumed: expect.json claims case 1 is "alfa" while the source says '
      + '"beta" -> the runner must report that the REFERENCE disagrees with the derived answer',
    file: 'probes/g22-closure-statics/expect.json',
    find: '    "1": "beta",',
    replace: '    "1": "alfa",',
    expectSubstring: 'the REFERENCE disagrees',
  },
  {
    id: 'M4',
    why: 'the AIR arm is REBUILT from the source, not read off a stale file: renaming the second element '
      + 'must make AIR disagree with the unchanged rule',
    file: 'probes/g22-closure-statics/ClosureCases.as',
    find: 'private static const NAMES:Array = ["alpha", "beta", "gamma"];',
    replace: 'private static const NAMES:Array = ["alpha", "betax", "gamma"];',
    expectSubstring: 'the REFERENCE disagrees',
  },
];

const log = [];
const line = (s) => { console.log(s); log.push(s); };
let caught = 0;
let broken = 0;

for (const m of MUTATIONS) {
  const file = m.base === 'repo' ? path.join(ROOT, m.file) : path.join(UI, m.file);
  const before = fs.readFileSync(file, 'utf8');
  const beforeHash = sha(file);
  if (before.indexOf(m.find) < 0) {
    line(m.id + '  SKIPPED -- anchor text not found in ' + m.file
      + ' (the source drifted; fix the mutation, do not ignore it)');
    broken++;
    continue;
  }
  try {
    fs.writeFileSync(file, before.split(m.find).join(m.replace));
    const r = spawnSync(process.execPath, [RUN], { cwd: UI, encoding: 'utf8' });
    const out = (r.stdout || '') + (r.stderr || '');

    let ok = out.indexOf(m.expectSubstring) >= 0;
    let detail = ok ? '' : ' expected the runner to say "' + m.expectSubstring + '"';
    if (m.expectExit != null && r.status !== m.expectExit) {
      ok = false;
      detail += ' (exit ' + r.status + ', wanted ' + m.expectExit + ')';
    }
    if (ok) caught++; else broken++;
    line(m.id + '  ' + (ok ? 'CAUGHT' : 'MISSED (THIS IS BAD)') + '  ' + m.why + detail);
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
line('MUTATION ' + path.basename(DIR) + ': ' + caught + '/' + MUTATIONS.length + ' caught, ' + broken + ' problem(s)');
line(broken === 0 ? 'RESULT: PASS' : 'RESULT: FAIL');
fs.writeFileSync(RESULTS, log.join('\n') + '\n');
process.exit(broken === 0 && caught === MUTATIONS.length ? 0 : 1);
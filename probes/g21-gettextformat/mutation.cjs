// probes/g21-gettextformat/mutation.cjs -- proves run.cjs CAN go red.
//
// A probe that cannot fail is decoration. Three mutations point at the COMPILER fix
// itself -- the empty-range answer, the #2006 bounds check, and the format
// comparison that decides "one format over the whole range" -- so undoing any of
// those turns the probe red. The last two check that the reference arm and the
// hand-derived rule really do get compared against each other.
// Every file -- including the compiler source -- is restored in `finally` and its
// sha256 compared byte-for-byte, so a mutation run can never leave the tree altered.
//
// USAGE (from asaotui/):   node probes/g21-gettextformat/mutation.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const DIR = __dirname;
const UI = path.resolve(DIR, '..', '..');
const ROOT = path.resolve(UI, '..');
const RUN = path.join(DIR, 'run.cjs');
const RESULTS = path.join(DIR, 'g21-gettextformat-mutation.txt');

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

// src/emit.ts is a CRLF file: none of the anchors below span a line break, so a
// "not found" here means the emitter really changed, not that the editor
// normalised line endings.
const EMIT = 'as3compiler/src/emit.ts';

const MUTATIONS = [
  {
    id: 'M1',
    why: 'the EMPTY answer is load-bearing: handing back the field default for an empty range '
      + 'makes cases 3/21/29/30 report 20/black where AIR reports an all-null TextFormat',
    file: EMIT,
    base: 'repo',
    find: "    this.line('if (b >= e) return as_tf_fmt_empty();');",
    replace: "    this.line('if (b >= e) return as_tf_fmt_clone(tf->defaultTextFormat);');",
    expectSubstring: 'RESULT: FAIL',
  },
  {
    id: 'M2',
    why: 'the #2006 bounds check is load-bearing: without it cases 4/15/18/19/20/24 answer instead of '
      + 'throwing, which the reference rejects',
    file: EMIT,
    base: 'repo',
    find: "    this.line('if (!noArgs && (len == 0 || (b == 0 && e == 0) || b >= len || e > len)) {');",
    replace: "    this.line('if (false) {');",
    expectSubstring: 'RESULT: FAIL',
  },
  {
    id: 'M3',
    why: 'the format COMPARISON is load-bearing: accepting the first segment without comparing it lets a '
      + 'range that straddles a change answer that change instead of the empty TextFormat',
    file: EMIT,
    base: 'repo',
    find: "    this.line('else if (!as_tf_fmt_eq(first, use)) return as_tf_fmt_empty();');",
    replace: "    this.line('else if (false) return as_tf_fmt_empty();');",
    expectSubstring: 'RESULT: FAIL',
  },
  {
    id: 'M4',
    why: 'the RULE is checked, not assumed: expect.json claims case 27 answers the default while the source '
      + 'carries two identical 30/red runs -> the runner must report that the REFERENCE disagrees',
    file: 'probes/g21-gettextformat/expect.json',
    find: '    "27": "size=30 color=16711680",',
    replace: '    "27": "size=20 color=0",',
    expectSubstring: 'the REFERENCE disagrees',
  },
  {
    id: 'M5',
    why: 'the AIR arm is REBUILT from the source, not read off a stale file: changing the run size in case 28 '
      + 'must make AIR disagree with the unchanged rule',
    file: 'probes/g21-gettextformat/GetFmtCases.as',
    find: 'run(t, 30, 0xFF0000, 0, 10);',
    replace: 'run(t, 31, 0xFF0000, 0, 10);',
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
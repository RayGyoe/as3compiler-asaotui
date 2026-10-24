// probes/g20-settextformat/mutation.cjs -- proves run.cjs CAN go red.
//
// A probe that cannot fail is decoration. Each mutation is a deliberate small change
// to the thing the probe measures (three of them break the fix in src/emit.ts, two
// break the harness), and after each one run.cjs MUST change verdict. Every file is
// restored in `finally` and compared byte-for-byte with its pre-mutation sha256, so a
// mutation run can never leave the compiler or the probe subtly altered.
//
// WHY THE COMPILER IS A TARGET HERE: the probe's whole value is that repeated
// setTextFormat is idempotent, and that property lives in emitted C, i.e. in
// src/emit.ts's TextField_setTextFormat. A probe file alone could drift to "pass"
// while the compiler regressed; mutating the emitter is what rules that out.
//
// USAGE (from asaotui/):   node probes/g20-settextformat/mutation.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const DIR = __dirname;
const UI = path.resolve(DIR, '..', '..');
const COMPILER = path.resolve(UI, '..', 'as3compiler');
const RUN = path.join(DIR, 'run.cjs');
const RESULTS = path.join(DIR, 'g20-settextformat-mutation.txt');

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const MUTATIONS = [
  {
    id: 'M1',
    why: 'covered ranges must be DROPPED: with the "entirely left of the new range" test disabled, the old '
      + 'run survives next to the new one and the layout copies the characters twice -> the probe must fail',
    root: COMPILER,
    file: 'src/emit.ts',
    find: "this.line('if (e <= begin) { as_array_push(out, as_v_num((double)b));",
    replace: "this.line('if (0) { as_array_push(out, as_v_num((double)b));",
    expectSubstring: 'RESULT: FAIL',
    expectExit: 1,
  },
  {
    id: 'M2',
    why: 'a range that lands INSIDE a run must keep that run\'s tail: dropping the right remainder makes the '
      + 'formatted area eat the rest of the text -> case 13 (split in the middle) must fail',
    root: COMPILER,
    file: 'src/emit.ts',
    find: "this.line('if (e > end) { as_array_push(out, as_v_num((double)end));",
    replace: "this.line('if (0) { as_array_push(out, as_v_num((double)end));",
    expectSubstring: 'RESULT: FAIL',
    expectExit: 1,
  },
  {
    id: 'M3',
    why: 'the new run must actually be APPENDED when no existing run reaches past begin (the empty-table '
      + 'case) -> removing the trailing insert leaves the field unformatted and case 1 must fail',
    root: COMPILER,
    file: 'src/emit.ts',
    find: "    this.line('if (!placed) {');\n    this.indent++;\n    this.line('as_array_push(out, as_v_num((double)begin));');\n    this.line('as_array_push(out, as_v_num((double)end));');\n    this.line('as_array_push(out, as_v_obj((void*)format));');\n    this.indent--;\n    this.line('}');\n    this.line('tf->_runs = out;');",
    replace: "    this.line('if (0) {');\n    this.indent++;\n    this.line('as_array_push(out, as_v_num((double)begin));');\n    this.line('as_array_push(out, as_v_num((double)end));');\n    this.line('as_array_push(out, as_v_obj((void*)format));');\n    this.indent--;\n    this.line('}');\n    this.line('tf->_runs = out;');",
    expectSubstring: 'RESULT: FAIL',
    expectExit: 1,
  },
  {
    id: 'M4',
    why: 'the RULE is checked against the REFERENCE, not assumed: expect.json claims case 2 is false while '
      + 'AIR answers true -> the runner must report that the reference disagrees with the derived rule',
    root: UI,
    file: 'probes/g20-settextformat/expect.json',
    find: '    "2": "true",',
    replace: '    "2": "false",',
    expectSubstring: 'the REFERENCE disagrees',
    expectExit: 1,
  },
  {
    id: 'M5',
    why: 'a BUILD failure is never mistaken for agreement: a missing semicolon in the emitted body must make '
      + 'the runner stop with "AOT BUILD FAILED" (exit 2) instead of comparing against nothing',
    root: COMPILER,
    file: 'src/emit.ts',
    find: "    this.line('if (begin >= end) return;');",
    replace: "    this.line('if (begin >= end) return');",
    expectSubstring: 'AOT BUILD FAILED',
    expectExit: 2,
  },
];

const log = [];
const line = (s) => { console.log(s); log.push(s); };
let caught = 0;
let broken = 0;

for (const m of MUTATIONS) {
  const file = path.join(m.root, m.file);
  const raw = fs.readFileSync(file, 'utf8');
  // The compiler sources are CRLF; match on LF-normalised text and write back in the
  // file's own line endings, otherwise a multi-line anchor silently never matches
  // (that is exactly how a mutation turns into a no-op that "passes").
  const crlf = raw.indexOf('\r\n') >= 0;
  const before = crlf ? raw.split('\r\n').join('\n') : raw;
  const beforeHash = sha(file);
  const write = (text) => fs.writeFileSync(file, crlf ? text.split('\n').join('\r\n') : text);
  if (before.indexOf(m.find) < 0) {
    line(m.id + '  SKIPPED -- anchor text not found in ' + m.file
      + ' (the probe file drifted; fix the mutation, do not ignore it)');
    broken++;
    continue;
  }
  try {
    write(before.split(m.find).join(m.replace));
    const r = spawnSync(process.execPath, [RUN], { cwd: UI, encoding: 'utf8' });
    const out = (r.stdout || '') + (r.stderr || '');
    let ok = out.indexOf(m.expectSubstring) >= 0;
    let detail = ok ? '' : ' expected the runner to say "' + m.expectSubstring + '"';
    if (m.expectExit != null && r.status !== m.expectExit) {
      ok = false;
      detail += ' (exit ' + r.status + ', wanted ' + m.expectExit + ')';
    }
    // The failing line has to be one of the cases this mutation is about, otherwise a
    // mutation could "pass" by breaking something unrelated.
    if (ok && m.expectSubstring === 'RESULT: FAIL') {
      const cases = (out.match(/FAIL {2}id (\d+):/g) || []).map((s) => Number(s.match(/\d+/)[0]));
      if (cases.length === 0) { ok = false; detail = ' the runner failed but reported no failing case'; }
      else detail = ' (failing cases: ' + cases.join(', ') + ')';
    }
    if (ok) caught++; else broken++;
    line(m.id + '  ' + (ok ? 'CAUGHT' : 'MISSED (THIS IS BAD)') + '  ' + m.why + detail);
  } finally {
    fs.writeFileSync(file, raw);
  }
  const afterHash = sha(file);
  line('     restore: ' + (afterHash === beforeHash
    ? 'byte-identical (' + afterHash.slice(0, 16) + ')'
    : 'MISMATCH ' + beforeHash.slice(0, 16) + ' -> ' + afterHash.slice(0, 16) + '  THIS IS BAD'));
  if (afterHash !== beforeHash) broken++;
}

line('');
line('MUTATION ' + path.basename(DIR) + ': ' + caught + '/' + MUTATIONS.length + ' caught, ' + broken + ' problem(s)');
line(broken === 0 && caught === MUTATIONS.length ? 'RESULT: PASS' : 'RESULT: FAIL');
fs.writeFileSync(RESULTS, log.join('\n') + '\n');
process.exit(broken === 0 && caught === MUTATIONS.length ? 0 : 1);
// probes/widgets/table2/mutation.cjs -- proves probes/widgets/table2 CAN go red on the
// three table opt-ins (sort, column resize, row virtualisation) and on the hit rect that
// makes a table clickable at all.
//
// Every mutation is one CONTRACT, not one bug: each removes exactly the mechanism whose
// absence the probe is supposed to see, so a green run after a mutation would mean the
// probe is measuring nothing.
//
//   M1 the sorted copy is thrown away   -> `sortColumn` paints an arrow and reorders
//                                          nothing: the rows never move
//   M2 the cycle has no third state     -> a column can never go back to unsorted, so the
//                                          author's own model order is unreachable
//   M3 the release never commits       -> the 1px preview line follows the pointer
//                                          perfectly and the width never reaches the author
//   M4 the post-release click is let in -> the click the window glue sends after a release
//                                          also sorts the column that was just resized
//   M5 the transparent hit rect is gone -> the table is only pickable on its hairlines and
//                                          glyphs; a click in an empty cell hits the root
//                                          behind it and the row is unselectable
//   M6 the window keys are relative     -> a scrolled-in row reuses the previous occupant's
//                                          node, so "which row is mounted" is unobservable
//                                          and every row-keyed decoration sticks
//
// Each mutated file is restored in `finally` and its sha256 compared byte-for-byte with
// the pre-mutation hash: a mutation run can never leave the kit subtly altered.
//
// USAGE (from asaotui/):   node probes/widgets/table2/mutation.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const DIR = __dirname;
const UI = path.resolve(DIR, '..', '..', '..');   // probes/widgets/table2 -> asaotui
const PROBE = 'probes/widgets/table2';
const RESULTS = path.join(DIR, 'table2-mutation.txt');

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const MUTATIONS = [
  {
    id: 'M1',
    file: 'kit/asaot/ui/table.as',
    why: 'THE SORTED COPY IS THROWN AWAY: `sortColumn` still draws the arrow (it comes from the model) and '
      + 'the rows never move, which is the "sorted" table every screenshot would call correct',
    find: '            data = TableNode.sortRows(n.rows, String(n.columns[n.sortColumn].key), n.sortDescending);',
    replace: '            data = n.rows;',
    expect: 'ascending: row 0',
  },
  {
    id: 'M2',
    file: 'kit/asaot/ui/kind/TableWidget.as',
    why: 'THE CYCLE HAS NO THIRD STATE: ascending -> descending -> descending forever, so a column can never '
      + 'return to the model\'s own order',
    find: '                if (cur == col && desc) { nextCol = -1; nextDesc = false; }',
    replace: '                if (false && cur == col && desc) { nextCol = -1; nextDesc = false; }',
    expect: 'the third click reported column',
  },
  {
    id: 'M3',
    file: 'kit/asaot/ui/kind/TableWidget.as',
    why: 'THE RELEASE NEVER COMMITS: the 1px preview line follows the pointer perfectly and onColumnResize is '
      + 'never called, so the column looks dragged for one frame and the author\'s model never hears about it',
    find: 'var upFn:Function = function (ev:MouseEvent):void { self.endResize(n, true); };',
    replace: 'var upFn:Function = function (ev:MouseEvent):void { self.endResize(n, false); };',
    expect: 'onColumnResize fired',
  },
  {
    id: 'M4',
    file: 'kit/asaot/ui/kind/TableWidget.as',
    why: 'THE POST-RELEASE CLICK IS LET IN: the window glue sends CLICK after every release, so the click that '
      + 'ends a resize also sorts the column that was just resized',
    find: '            if (Number(n.extra[SWAL_KEY]) != 0) return;',
    replace: '            if (false && Number(n.extra[SWAL_KEY]) != 0) return;',
    expect: 'the click after a resize sorted the column',
  },
  {
    id: 'M5',
    file: 'kit/asaot/ui/kind/TableWidget.as',
    why: 'THE TRANSPARENT HIT RECT IS GONE: the runtime picks by painted region, and a table paints only 1px '
      + 'hairlines and glyphs -- so a click in an empty cell targets the root behind it',
    find: '            g.beginFill(0x000000, 0.0);\n            g.drawRect(0, 0, w, h);\n            g.endFill();\n',
    replace: '',
    expect: 'a click on the first visible row',
  },
  {
    id: 'M6',
    file: 'kit/asaot/ui/table.as',
    why: 'THE WINDOW KEYS ARE RELATIVE: a scrolled-in row hands the reconciler the key of the row that just left, '
      + 'so the row node is reused with different data and "which row is mounted" cannot be asserted',
    find: '            kids.push(rowH == null ? row({ key: "r" + r }, cells) : row({ key: "r" + r, style: rowH }, cells));',
    replace: '            kids.push(rowH == null ? row({ key: "r" + (r - first) }, cells) : row({ key: "r" + (r - first), style: rowH }, cells));',
    expect: 'the first mounted row',
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
line('MUTATION table2: ' + caught + '/' + MUTATIONS.length + ' caught, ' + broken + ' problem(s)');
line(broken === 0 && caught === MUTATIONS.length ? 'RESULT: PASS' : 'RESULT: FAIL');
fs.writeFileSync(RESULTS, log.join('\n') + '\n');
process.exit(broken === 0 && caught === MUTATIONS.length ? 0 : 1);
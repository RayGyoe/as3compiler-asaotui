// probes/widgets/choice/mutation.cjs -- proves the choice probe (tree + combobox +
// datePicker) CAN go red, one broken behaviour at a time.
//
// Every mutation names the assertion it must break. That is the whole point: a probe
// that goes red for an unrelated reason (a build error, a crashed process) is not
// evidence of coverage, so each mutation also has to produce the SPECIFIC failure line
// and must not be a build failure.
//
// Each file is restored in `finally` and its sha256 compared against the pre-mutation
// hash -- a mutation run can never leave the kit altered.
//
// USAGE (from asaotui/):   node probes/widgets/choice/mutation.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const DIR = __dirname;
const UI = path.resolve(DIR, '..', '..', '..');   // probes/widgets/choice -> asaotui
const PROBE = 'probes/widgets/choice';
const RESULTS = path.join(DIR, 'choice-mutation.txt');

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const MUTATIONS = [
  {
    id: 'M1',
    why: 'the tree indents by 0 instead of 18 per level -> a child row sits at its parent\'s x, '
      + 'so nesting is invisible',
    file: 'kit/asaot/ui/OverlayChrome.as',
    find: '        public static const TREE_INDENT:Number = 18;',
    replace: '        public static const TREE_INDENT:Number = 0;',
    expect: 'a depth-1 label starts at x=42',
  },
  {
    id: 'M2',
    why: 'the twisty hit zone disappears -> clicking a branch\'s arrow SELECTS the row instead of '
      + 'toggling it (the author never learns the branch should open)',
    file: 'kit/asaot/ui/kind/TreeWidget.as',
    find: '            if (Boolean(r.branch) && lx >= 0 && lx < left)',
    replace: '            if (Boolean(r.branch) && lx < 0)',
    expect: 'toggling src reported 0 times',
  },
  {
    id: 'M3',
    why: 'the factory forgets to deepen the stack frame -> an expanded branch\'s children are all '
      + 'rendered at depth 0 (flat list, no indentation)',
    file: 'kit/asaot/ui/tree.as',
    find: '            if (open) stack.push({ list: children, i: 0, depth: int(f.depth) + 1 });',
    replace: '            if (open) stack.push({ list: children, i: 0, depth: int(f.depth) });',
    expect: 'the child row\'s label is at 42,79',
  },
  {
    id: 'M4',
    why: 'the selected row loses its declarative background -> the tree shows no selection at all '
      + '(this one is caught by a PIXEL, not by a rect)',
    file: 'kit/asaot/ui/tree.as',
    find: '            if (n.selectedKey != null && n.selectedKey == key)',
    replace: '            if (n.selectedKey != null && n.selectedKey == key + "!")',
    expect: 'the selected row\'s background at (200,59)',
  },
  {
    id: 'M5',
    why: 'the combobox dropdown loses its top inset -> it covers the trigger instead of hanging '
      + 'under it',
    file: 'kit/asaot/ui/kind/ComboBoxWidget.as',
    find: '            eng.setPosition(e, LayoutConstants.EDGE_TOP, h, LayoutConstants.UNIT_POINT);',
    replace: '            eng.setPosition(e, LayoutConstants.EDGE_TOP, 0, LayoutConstants.UNIT_POINT);',
    expect: 'the dropdown is at',
  },
  {
    id: 'M6',
    why: 'the field stops reporting its edits -> type-to-filter silently does nothing (the author '
      + 'never receives onQuery)',
    file: 'kit/asaot/ui/combo.as',
    find: '                               onChange: n.onQuery }));',
    replace: '                               onChange: null }));',
    expect: 'typing reported query',
  },
  {
    id: 'M7',
    why: 'the calendar forgets which weekday the 1st is on -> every month starts on Sunday and the '
      + 'dates land under the wrong column',
    file: 'kit/asaot/ui/DateMath.as',
    find: '            return int(v % 7);',
    replace: '            return 0;',
    expect: 'the day-1 cell is',
  },
  {
    id: 'M8',
    why: 'the day click no longer walks up from the innermost hit -> clicking the NUMBER (a text '
      + 'child) does nothing, only the cell\'s margin works',
    file: 'kit/asaot/ui/kind/DatePickerWidget.as',
    find: '                node = node.parent;',
    replace: '                node = null;',
    expect: 'clicking the 15th reported',
  },
  {
    id: 'M9',
    why: 'the two month arrows swap -> "<" pages forward, so the picker moves the wrong way',
    file: 'kit/asaot/ui/kind/DatePickerWidget.as',
    find: '                    if (k == base + ":prev") { this.page(n, -1); return; }',
    replace: '                    if (k == base + ":prev") { this.page(n, 1); return; }',
    expect: 'the previous-month arrow reported 2026-11',
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
    const ok = verdict != null && verdict[1] === 'FAIL' && saidIt && !buildFailed;
    if (ok) caught++; else broken++;
    line(m.id + '  ' + (ok ? 'CAUGHT' : 'MISSED (THIS IS BAD)') + '  ' + m.why);
    line('     verdict: ' + (verdict ? verdict[0] : 'none')
      + (buildFailed ? '  BUILD FAILED -- a mutation that does not compile proves nothing' : '')
      + (saidIt ? '' : '  MISSING the expected failure line "' + m.expect + '"'));
    const fails = out.split(/\r?\n/).filter((l) => /  FAIL  /.test(l));
    for (const f of fails.slice(0, 3)) line('     ' + f.trim().slice(0, 300));
    if (fails.length > 3) line('     ... and ' + (fails.length - 3) + ' more');
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
line('MUTATION choice: ' + caught + '/' + MUTATIONS.length + ' caught, ' + broken + ' problem(s)');
line(broken === 0 && caught === MUTATIONS.length ? 'RESULT: PASS' : 'RESULT: FAIL');
fs.writeFileSync(RESULTS, log.join('\n') + '\n');
process.exit(broken === 0 && caught === MUTATIONS.length ? 0 : 1);
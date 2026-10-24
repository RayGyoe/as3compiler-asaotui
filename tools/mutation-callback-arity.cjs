// tools/mutation-callback-arity.cjs -- proves tools/callback-arity.cjs CAN go red,
// in BOTH directions it claims to check.
//
// A scan that cannot fail is decoration. Each mutation is a one-token change to a
// real call site or a real handler declaration:
//   * the four zero-argument invocations the toolkit actually shipped (they threw
//     #1063 on every click, which is the report that produced this gate);
//   * a docs handler that drops its parameter (the author-side direction);
//   * an onClick handler that declares one (also #1063 -- onClick is called with
//     no arguments at all).
//
// Every file is restored in `finally` and compared by sha256: a mutation run can
// never leave the kit or the docs subtly altered.
//
// USAGE (from asaotui/):   node tools/mutation-callback-arity.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const UI = path.resolve(__dirname, '..');
const RESULTS = path.join(UI, 'reviews', 'mutation-callback-arity.txt');

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const MUTATIONS = [
  {
    id: 'M1',
    why: 'THE REPORTED BUG, re-introduced: the slider calls onChange() with no argument while every '
      + 'handler declares `function (v:Number)` -> #1063, the handler never runs',
    file: 'kit/asaot/ui/kind/SliderWidget.as',
    find: 'if (n.onChange != null) n.onChange(v);',
    replace: 'if (n.onChange != null) n.onChange();',
    expect: 'SliderWidget.as'
  },
  {
    id: 'M2',
    why: 'the checkbox drops the new boolean from its report (the docs declare `function (v:Boolean)`)',
    file: 'kit/asaot/ui/kind/CheckboxWidget.as',
    find: 'else if (n.onChange != null) n.onChange(next);',
    replace: 'else if (n.onChange != null) n.onChange();',
    expect: 'CheckboxWidget.as'
  },
  {
    id: 'M3',
    why: 'the switch drops it too (same defect, different kind)',
    file: 'kit/asaot/ui/kind/SwitchWidget.as',
    find: 'else if (n.onChange != null) n.onChange(next);',
    replace: 'else if (n.onChange != null) n.onChange();',
    expect: 'SwitchWidget.as'
  },
  {
    id: 'M4',
    why: 'the radio drops the constant `true` it still has to pass',
    file: 'kit/asaot/ui/kind/RadioWidget.as',
    find: 'else if (n.onChange != null) n.onChange(true);',
    replace: 'else if (n.onChange != null) n.onChange();',
    expect: 'RadioWidget.as'
  },
  {
    id: 'M5',
    why: 'AUTHOR SIDE: a docs handler drops its parameter, so the widget would call a 0-argument '
      + 'closure with 1 argument -- legal on AVM2 but it documents the wrong contract',
    file: 'ui-demo/demo/DocsControls.as',
    find: 'onChange: function (n:Number):void { m.put("sl.vol", n); }',
    replace: 'onChange: function ():void { m.put("sl.vol", 0); }',
    expect: 'DocsControls.as'
  },
  {
    id: 'M6',
    why: 'AUTHOR SIDE, the other direction: an onClick handler that expects an event -- onClick is '
      + 'invoked with NO arguments, so this declaration is a #1063 waiting for a click',
    file: 'ui-demo/demo/DocsStart.as',
    find: 'onClick: function ():void',
    replace: 'onClick: function (e:MouseEvent):void',
    expect: 'DocsStart.as'
  }
];

function runScan() {
  return spawnSync(process.execPath, ['tools/callback-arity.cjs'], { cwd: UI, encoding: 'utf8' });
}

const log = [];
const line = (s) => { console.log(s); log.push(s); };
let caught = 0;
let broken = 0;

const base = runScan();
const baseOut = (base.stdout || '') + (base.stderr || '');
line('baseline (unmutated): exit ' + base.status);
if (base.status !== 0) {
  line('the baseline is not green; a mutation run would be meaningless. Aborting.');
  for (const l of baseOut.split(/\r?\n/).slice(-20)) line('  ' + l);
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
    const r = runScan();
    const out = (r.stdout || '') + (r.stderr || '');
    const saidIt = out.indexOf(m.expect) >= 0;
    const ok = r.status === 1 && saidIt;
    if (ok) caught++; else broken++;
    line(m.id + '  ' + (ok ? 'CAUGHT' : 'MISSED (THIS IS BAD)') + '  ' + m.why);
    line('     exit ' + r.status + (saidIt ? '' : '  MISSING the expected line "' + m.expect + '"'));
    for (const l of out.split(/\r?\n/).filter((l) => /^  \S+\.as:/.test(l)).slice(0, 3)) line('     ' + l.trim());
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
line('MUTATION callback-arity: ' + caught + '/' + MUTATIONS.length + ' caught, ' + broken + ' problem(s)');
line(broken === 0 && caught === MUTATIONS.length ? 'RESULT: PASS' : 'RESULT: FAIL');
fs.mkdirSync(path.dirname(RESULTS), { recursive: true });
fs.writeFileSync(RESULTS, log.join('\n') + '\n');
process.exit(broken === 0 && caught === MUTATIONS.length ? 0 : 1);
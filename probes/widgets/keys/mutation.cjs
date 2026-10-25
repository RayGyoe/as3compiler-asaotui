// probes/widgets/keys/mutation.cjs -- proves probes/widgets/keys CAN go red on the
// batch that gave `list`, `table` and `tabs` a keyboard.
//
// Every mutation is one CONTRACT, not one bug: each removes exactly the mechanism whose
// absence the probe is supposed to see, so a green run after a mutation would mean the
// probe is measuring nothing.
//
//   K1 list CLAMPS at the end              -> Down on the last row wraps to the first
//   K2 tabs WRAP at the ends               -> Left on the first segment sticks at 0
//   K3 the virtual table REVEALS the row   -> a selection outside the mounted window is
//                                             never scrolled into view (unhighlightable)
//   K4 the Binding is the ONE write path   -> the selection is written to the widget
//                                             private slot, so the author model never
//                                             hears about it
//
// K1/K2 are the same code with opposite answers ON PURPOSE: a probe that only checked
// "the arrow moves" would pass with either one, so each direction is pinned twice (list
// Down-at-end, tabs Left-at-start) and each mutation breaks exactly one of them.
//
// Each mutated file is restored in `finally` and its sha256 compared byte-for-byte with
// the pre-mutation hash: a mutation run can never leave the kit subtly altered.
//
// USAGE (from asaotui/):   node probes/widgets/keys/mutation.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const DIR = __dirname;
const UI = path.resolve(DIR, '..', '..', '..');   // probes/widgets/keys -> asaotui
const PROBE = 'probes/widgets/keys';
const RESULTS = path.join(DIR, 'keys-mutation.txt');

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const MUTATIONS = [
  {
    id: 'K1',
    file: 'kit/asaot/ui/kind/ListWidget.as',
    why: 'LIST WRAPS INSTEAD OF CLAMPING: a listbox is a SEQUENCE (ARIA listbox: the ends are walls), so'
      + 'Down on the last row must stay there. Sliding to 0 is the tab-strip answer, and the probe asserts'
      + 'the pixel AND the model, so both would move.',
    find: '            if (next >= count) next = count - 1;',
    replace: '            if (next >= count) next = 0;',
    expect: 'list Down at the end',
  },
  {
    id: 'K2',
    file: 'kit/asaot/ui/kind/TabsWidget.as',
    why: 'TABS CLAMP INSTEAD OF WRAPPING: a strip is a RING, so Left on the first segment goes to the last.'
      + 'This is the exact inversion of K1 -- same code shape, different structure -- which is why the two'
      + 'widgets are mutated separately rather than trusted to share a rule.',
    find: '            else next = (cur - 1 + count) % count;',
    replace: '            else next = cur > 0 ? cur - 1 : 0;',
    expect: 'tabs Left from 0',
  },
  {
    id: 'K3',
    file: 'kit/asaot/ui/kind/TableWidget.as',
    why: 'THE VIRTUAL TABLE DOES NOT REVEAL THE ROW IT SELECTED: the index is valid and the model moves,'
      + 'but the row is outside the mounted window, so nothing on screen shows the selection. Invisible to'
      + 'every property assertion -- the probe reads TableNode.firstRow and the author offset.',
    find: '            if (t.virtual) this.reveal(n, t, next, fit);',
    replace: '            if (t.virtual && false) this.reveal(n, t, next, fit);',
    expect: 'virtual table firstRow',
  },
  {
    id: 'K4',
    file: 'kit/asaot/ui/kind/ListWidget.as',
    why: 'THE KEY WRITES THE WIDGET PRIVATE SLOT INSTEAD OF THE BINDING: the picture would still move'
      + '(payload reads extra[sel]), so only the author model shows it -- and the second write path is the'
      + 'one that later makes payload stop repainting, because it can no longer SEE the change.',
    // The anchor is the four-line body of select() and NOTHING AFTER IT: that method
    // is last in the class, so a tail comment from a neighbouring method is an anchor
    // that cannot match (this cost one SKIPPED run).
    find: '            if (n.binding != null) n.binding.set(idx);\n            n.app.markPaint(n);\n            if (n.onChange != null) n.onChange(idx);\n            n.app.invalidate(Dirty.VALUE);',
    replace: '            n.extra[SEL_KEY] = idx;\n            n.app.markPaint(n);\n            if (n.onChange != null) n.onChange(idx);\n            n.app.invalidate(Dirty.VALUE);',
    expect: 'list End',
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
  // THE ANCHOR'S LINE ENDINGS MUST MATCH THE FILE'S. This kit is mixed: the repo
  // pins only *.bat in .gitattributes, so a file rewritten by an editor with the
  // other convention silently stopped matching a multi-line `find` written with
  // \n -- and the runner then reported SKIPPED, which reads like "nothing to do"
  // instead of "this mutation no longer exists". Resolve to whatever the file uses.
  const nl = before.indexOf('\r\n') >= 0 ? '\r\n' : '\n';
  const find = m.find.replace(/\r?\n/g, nl);
  const repl = m.replace.replace(/\r?\n/g, nl);
  if (before.indexOf(find) < 0) {
    line(m.id + '  SKIPPED -- anchor text not found in ' + m.file
      + ' (the file drifted; fix the mutation, do not ignore it)');
    broken++;
    continue;
  }
  try {
    fs.writeFileSync(file, before.split(find).join(repl));
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
line('MUTATION keys: ' + caught + '/' + MUTATIONS.length + ' caught, ' + broken + ' problem(s)');
line(broken === 0 && caught === MUTATIONS.length ? 'RESULT: PASS' : 'RESULT: FAIL');
fs.writeFileSync(RESULTS, log.join('\n') + '\n');
process.exit(broken === 0 && caught === MUTATIONS.length ? 0 : 1);

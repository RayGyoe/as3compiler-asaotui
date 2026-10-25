// probes/widgets/accordion/mutation.cjs -- proves probes/widgets/accordion CAN go red on
// the batch that added `mode: "multi"`.
//
// Every mutation is one CONTRACT, not one bug:
//
//   A1 the header fill ignores the SET        -> only one header is highlighted, whatever
//                                                the open set says (paint has to walk the
//                                                same predicate the factory used)
//   A2 the factory mounts ONE panel only      -> a section is "open" in the state and has
//                                                nothing on screen
//   A3 a toggle REPLACES the set              -> clicking one header closes the others,
//                                                i.e. single mode wearing a multi name
//   A4 the exclusive-option guard is gone     -> `mode:"multi"` + `activeIndex` is silently
//                                                accepted and one of the two is ignored
//
// Each mutated file is restored in `finally` and its sha256 compared byte-for-byte with
// the pre-mutation hash: a mutation run can never leave the kit subtly altered.
//
// USAGE (from asaotui/):   node probes/widgets/accordion/mutation.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const DIR = __dirname;
const UI = path.resolve(DIR, '..', '..', '..');   // probes/widgets/accordion -> asaotui
const PROBE = 'probes/widgets/accordion';
const RESULTS = path.join(DIR, 'accordion-mutation.txt');

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const MUTATIONS = [
  {
    id: 'A1',
    file: 'kit/asaot/ui/kind/AccordionWidget.as',
    why: 'THE HEADER FILL IGNORES THE SET: paint highlights "the first section" instead of every open one,'
      + 'so with [0,2] open the picture shows one highlight. This is the classic "state is right, the paint'
      + 'reads something else" split -- invisible to a model assertion.',
    find: '                var isOpen:Boolean = multi ? AccordionNode.isOpen(openSet, k) : (k == act);',
    replace: '                var isOpen:Boolean = multi ? (k == 0) : (k == act);',
    expect: 'header 2 fill',
  },
  {
    id: 'A2',
    file: 'kit/asaot/ui/accordion.as',
    why: 'THE FACTORY MOUNTS ONLY THE FIRST OPEN PANEL: `openIndices` is accepted and even painted, but a'
      + 'section can be "open" with no content on screen -- the exact half-implementation a mode flag is'
      + 'supposed to rule out.',
    find: '                ? AccordionNode.isOpen(n.openIndices, i) : (i == n.activeIndex);',
    replace: '                ? (AccordionNode.isOpen(n.openIndices, i) && i == 0) : (i == n.activeIndex);',
    expect: 'section 2 of the open set',
  },
  {
    id: 'A3',
    file: 'kit/asaot/ui/kind/AccordionWidget.as',
    why: 'A TOGGLE REPLACES THE SET WITH THE CLICKED INDEX: this is single mode wearing a multi name --'
      + 'clicking B closes A and C. Every model assertion about "the set changed" would still pass, which is'
      + 'why the probe asserts the three members by name.',
    find: '            if (n.binding != null) n.binding.set(next);\n            n.app.markPaint(n);\n            if (n.onChange != null) n.onChange(target);',
    replace: '            if (n.binding != null) n.binding.set([target]);\n            n.app.markPaint(n);\n            if (n.onChange != null) n.onChange(target);',
    expect: 'not three members',
  },
  {
    id: 'A4',
    file: 'kit/asaot/ui/accordion.as',
    why: 'THE EXCLUSIVE-OPTION GUARD IS GONE: `mode:"multi"` + `activeIndex` is accepted, and one of the two'
      + 'states is silently ignored -- AGENTS.md 2.5 exactly. Nothing on screen changes, so only the THROW'
      + 'assertion can see it.',
    // The anchor stops at `Error(`: the throw's argument holds AS3-escaped quotes (\")
    // and a JS single-quoted literal turns a lone \" into a plain quote, so spanning it
    // is an anchor that can never match. Everything up to `Error(` is literal text.
    // The anchor stops at `Error(`: the throw holds AS3-escaped quotes (\"multi\"
    // in the source), and a JS single-quoted literal turns a lone \" into a plain
    // quote -- so spanning it gives an anchor that can never match, and the runner
    // reported SKIPPED ("the file drifted") for a file that had not changed.
    find: '                if (opts.activeIndex != null)\n                {\n                    throw new Error(',
    replace: '                if (false)\n                {\n                    throw new Error(',
    expect: 'mode multi + activeIndex did NOT throw',
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
line('MUTATION accordion: ' + caught + '/' + MUTATIONS.length + ' caught, ' + broken + ' problem(s)');
line(broken === 0 && caught === MUTATIONS.length ? 'RESULT: PASS' : 'RESULT: FAIL');
fs.writeFileSync(RESULTS, log.join('\n') + '\n');
process.exit(broken === 0 && caught === MUTATIONS.length ? 0 : 1);

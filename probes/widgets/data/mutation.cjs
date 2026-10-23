// probes/widgets/data/mutation.cjs -- proves tools/probe.cjs CAN go red on this probe.
//
// A probe that cannot fail is decoration. Each mutation below is a deliberate
// one-token change to the thing the probe measures (a palette constant, the slot
// arithmetic, the accordion's structure, the exact layering bug the probe found
// while it was being written, and M5 -- the text-measure defect the catalog page
// exposed: an auto-width text node that forgets its own padding). After each
// mutation the probe MUST fail, and it must fail with the SPECIFIC message named in
// `expect`, so that "it went
// red" is never confused with "it failed to build".
//
// Every file is restored in `finally` and its sha256 compared byte-for-byte with the
// pre-mutation hash: a mutation run can never leave the kit subtly altered.
//
// USAGE (from asaotui/):   node probes/widgets/data/mutation.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const DIR = __dirname;
const UI = path.resolve(DIR, '..', '..', '..');   // probes/widgets/data -> asaotui
const PROBE = 'probes/widgets/data';
const RESULTS = path.join(DIR, 'data-mutation.txt');

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const MUTATIONS = [
  {
    id: 'M1',
    why: 'the selection colour moves to magenta -> BOTH the hand-written pixel in expect.json and the '
      + 'program-side sample must name the wrong colour',
    file: 'kit/asaot/ui/TableNode.as',
    find: 'public static const SEL_BG:uint = 0xDBEAFE;',
    replace: 'public static const SEL_BG:uint = 0xFF00FF;',
    expect: 'row 1 selection',
  },
  {
    id: 'M2',
    why: 'the slot window widens by one (inner = w-1) -> page 3 now renders 1..7 with no ellipsis, so '
      + 'pg7 must be reported as mounted when it should not be',
    file: 'kit/asaot/ui/kind/PaginationWidget.as',
    find: 'var inner:int = w - 2;',
    replace: 'var inner:int = w - 1;',
    expect: 'pg7 is mounted',
  },
  {
    id: 'M3',
    why: 'the accordion mounts EVERY panel -> a collapsed panel must be reported as mounted',
    file: 'kit/asaot/ui/accordion.as',
    find: 'if (i == n.activeIndex && sec.content != null)',
    replace: 'if (sec.content != null)',
    expect: 'p1 (a closed panel) is mounted',
  },
  {
    id: 'M4',
    why: 'THE LAYERING BUG THIS PROBE FOUND, re-introduced: give the header its own background again '
      + '(a child paints in front of the container shape) -> the open header highlight goes invisible, '
      + 'which is exactly what the probe caught on its first run',
    file: 'kit/asaot/ui/accordion.as',
    find: '        var headRef:StyleRefinement = StyleRefinement.from({\n            padding: [AccordionNode.HEADER_PAD_H, AccordionNode.HEADER_PAD_V],',
    replace: '        var headRef:StyleRefinement = StyleRefinement.from({\n            background: AccordionNode.HEADER_BG,\n            padding: [AccordionNode.HEADER_PAD_H, AccordionNode.HEADER_PAD_V],',
    expect: 'open header fill',
  },
  {
    id: 'M5',
    why: 'the text measure publishes its BARE glyph width again, dropping its own padding -> the separator\'s '
      + 'box shrinks below its content and the run overflows into the next crumb (the defect this pin exists for)',
    file: 'kit/asaot/ui/kind/TextWidget.as',
    find: '                    n.state.measuredW + PaintKit.padH(s.padding) + PaintKit.borderH(s.borderWidths));',
    replace: '                    n.state.measuredW);',
    expect: 'must include its insets',
  },
];

function runProbe() {
  return spawnSync(process.execPath, ['tools/probe.cjs', PROBE], { cwd: UI, encoding: 'utf8' });
}

const log = [];
const line = (s) => { console.log(s); log.push(s); };
let caught = 0;
let broken = 0;

// Baseline: the unmutated probe must PASS, otherwise a mutation "failing" proves
// nothing (it was already red).
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
line('MUTATION data: ' + caught + '/' + MUTATIONS.length + ' caught, ' + broken + ' problem(s)');
line(broken === 0 && caught === MUTATIONS.length ? 'RESULT: PASS' : 'RESULT: FAIL');
fs.writeFileSync(RESULTS, log.join('\n') + '\n');
process.exit(broken === 0 && caught === MUTATIONS.length ? 0 : 1);
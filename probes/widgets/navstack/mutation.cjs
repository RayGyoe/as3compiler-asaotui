// probes/widgets/navstack/mutation.cjs -- proves the navStack probe CAN go red.
//
// The probe asserts seven separable things (every page is mounted at the stack's box,
// only the top one is visible and pickable, `activeIndex` picks the top, the page's
// own nodes survive a push/pop, BACK -- with no focus anywhere -- is the only key that
// pops, a HIDDEN stack ignores that key, and an empty `pages` array is legal). Each
// mutation breaks exactly one and must fail with the SPECIFIC message named in
// `expect`, so "it went red" is never confused with "it failed to build".
//
// Every file is restored in `finally` and its sha256 compared with the pre-mutation
// hash: a mutation run can never leave the kit altered.
//
// USAGE (from asaotui/):   node probes/widgets/navstack/mutation.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const DIR = __dirname;
const UI = path.resolve(DIR, '..', '..', '..');   // probes/widgets/navstack -> asaotui
const PROBE = 'probes/widgets/navstack';
const RESULTS = path.join(DIR, 'navstack-mutation.txt');

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const MUTATIONS = [
  {
    id: 'M1',
    why: 'the pages stop being absolute -> a stack lays them out as a COLUMN, so every page is a '
      + 'third of the box and the visible one is at the wrong offset',
    file: 'kit/asaot/ui/navStack.as',
    find: '            position: "absolute", inset: 0, size: [pct(1), pct(1)] });',
    replace: '            inset: 0, size: [pct(1), pct(1)] });',
    expect: 'not 20,20,240,160',
  },
  {
    id: 'M2',
    why: 'every page stays visible -> the hidden pages paint over each other (the pixel shows the '
      + 'FIRST page, not the top one) and a click reaches a page nobody can see',
    file: 'kit/asaot/ui/navStack.as',
    find: '            e.visible = (i == top);',
    replace: '            e.visible = true;',
    expect: 'page A is visible while C is on top',
  },
  {
    id: 'M3',
    why: '`activeIndex` is ignored (the FIRST page is always "top") -> the stack shows the home '
      + 'page no matter what the model says',
    file: 'kit/asaot/ui/NavStackNode.as',
    find: '            return want;',
    replace: '            return 0;',
    expect: 'the top page C is not visible',
  },
  {
    id: 'M4',
    why: 'the page style is REPLACED instead of patched -> every page loses its own background and '
      + 'text, which is the difference between a container and a container that eats your node',
    file: 'kit/asaot/ui/navStack.as',
    find: '            p.style = own == null ? fill : own.withPatch(fill);',
    replace: '            p.style = fill;',
    expect: 'after the pop the stack shows',
  },
  {
    id: 'M5',
    why: 'only the top page is mounted -> the stack looks perfect until you go back and find the '
      + 'page below it gone (this is the "fake stack" the probe exists to reject)',
    file: 'kit/asaot/ui/navStack.as',
    find: '            n.addChild(p);',
    replace: '            if (i == top) n.addChild(p);',
    expect: 'is missing',
  },
  {
    id: 'M6',
    why: 'the BACK filter is dropped -> any key (the probe sends \'A\') pops the stack, so a desktop '
      + 'user typing in a field navigates away',
    file: 'kit/asaot/ui/kind/NavStackWidget.as',
    find: '            if (e.keyCode != Keyboard.BACK) return;',
    replace: '            if (false) return;',
    expect: 'a non-BACK key raised onBack',
  },
  {
    id: 'M7',
    why: 'the author\'s onBack is never called -> BACK is consumed and nothing happens, the worst '
      + 'of both worlds (the platform gesture is spent, the app does not move)',
    file: 'kit/asaot/ui/kind/NavStackWidget.as',
    find: '            if (cb != null) cb();',
    replace: '            // (mutation) the author is never told',
    expect: 'the BACK key raised onBack 0 times',
  },
  {
    id: 'M8',
    why: 'the on-screen check is dropped -> the stage listener answers in EVERY mounted stack, so one '
      + 'BACK gesture pops the tab the user is on AND every tab they cannot see (the probe keeps a '
      + 'second stack in a hidden tab and counts its callbacks)',
    file: 'kit/asaot/ui/kind/NavStackWidget.as',
    find: '            if (!visibleChain(n)) return;',
    replace: '            // (mutation) no on-screen check',
    expect: 'a HIDDEN stack',
  },
  {
    id: 'M9',
    why: 'an empty stack gets a blank PLACEHOLDER page mounted -> "no pages" becomes "one empty page", '
      + 'which is a different value from the author\'s (`pages: []` must mount nothing and still report '
      + 'depth 0)',
    file: 'kit/asaot/ui/navStack.as',
    find: '        var top:int = NavStackNode.topIndex(n.pages.length, n.activeIndex);',
    replace: '        var top:int = NavStackNode.topIndex(n.pages.length, n.activeIndex);\n'
      + '        if (n.pages.length == 0) n.addChild(box({ key: "emptyPage" }));',
    expect: 'children',
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
    for (const f of fails.slice(0, 4)) line('     ' + f.trim().slice(0, 300));
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
line('MUTATION navstack: ' + caught + '/' + MUTATIONS.length + ' caught, ' + broken + ' problem(s)');
line(broken === 0 && caught === MUTATIONS.length ? 'RESULT: PASS' : 'RESULT: FAIL');
fs.writeFileSync(RESULTS, log.join('\n') + '\n');
process.exit(broken === 0 && caught === MUTATIONS.length ? 0 : 1);

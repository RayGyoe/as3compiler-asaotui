// probes/widgets/appbar/mutation.cjs -- proves the appBar probe CAN go red.
//
// The probe asserts seven separable things (the three slots are LAYOUT, a slot may
// be a LIST, `collapse` is one number at every step, the collapsing area is CLIPPED,
// a compact bar ignores `collapse`, a String title is wrapped into a text node, and
// a safe-area inset is PADDING that can go back to zero). Each mutation breaks
// exactly one and must fail with the SPECIFIC message named in `expect`, so "it went
// red" is never confused with "it failed to build".
//
// Every file is restored in `finally` and its sha256 compared with the pre-mutation
// hash: a mutation run can never leave the kit altered.
//
// USAGE (from asaotui/):   node probes/widgets/appbar/mutation.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const DIR = __dirname;
const UI = path.resolve(DIR, '..', '..', '..');   // probes/widgets/appbar -> asaotui
const PROBE = 'probes/widgets/appbar';
const RESULTS = path.join(DIR, 'appbar-mutation.txt');

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const MUTATIONS = [
  {
    id: 'M1',
    why: 'the bar row is a BOX instead of a `row(...)` -- a box takes its axis from `BoxNode.direction`, '
      + 'which defaults to column, so the three slots stack and every rect in the probe is wrong '
      + '(this is the measured trap: `flexDirection: "row"` in a box style is simply ignored)',
    file: 'kit/asaot/ui/appBar.as',
    find: '        var bar:Node = row({ style: StyleRefinement.from({',
    replace: '        var bar:Node = box({ style: StyleRefinement.from({',
    expect: 'not 12,16,40,24',
  },
  {
    id: 'M2',
    why: 'the bar padding tuple is written [vertical, horizontal] instead of [horizontal, vertical] -- '
      + 'the leading slot loses its 12px left edge and the row loses 12px of height on both sides',
    file: 'kit/asaot/ui/appBar.as',
    find: '            height: rowH, padding: [12, 0] }) });',
    replace: '            height: rowH, padding: [0, 12] }) });',
    expect: 'not 12,16,40,24',
  },
  {
    id: 'M3',
    why: 'the large area ignores `collapse` -- the bar stays at its open height while the author '
      + 'scrolls, which is the whole difference between a header and a large header',
    file: 'kit/asaot/ui/appBar.as',
    find: '                height: extra - coll, padding: [12, 0] }) }, [tBig]));',
    replace: '                height: extra, padding: [12, 0] }) }, [tBig]));',
    expect: 'want 84',
  },
  {
    id: 'M4',
    why: 'a fully collapsed large bar keeps the extra row mounted (height 0) and drops the compact '
      + 'title -- the bar is the right height but shows no title at all',
    file: 'kit/asaot/ui/appBar.as',
    find: '        var closed:Boolean = !n.large || coll >= extra;',
    replace: '        var closed:Boolean = !n.large;',
    expect: 'the collapsed large bar mounted no title',
  },
  {
    id: 'M5',
    why: 'the bar stops clipping itself -- the collapsing title is 32px tall in an 8px row and hangs '
      + 'over whatever is below the bar for the whole gesture (the sampled pixel turns green)',
    file: 'kit/asaot/ui/kind/AppBarWidget.as',
    find: '            n.backing.scrollRect = r;',
    replace: '            // (mutation) no clip',
    expect: "want the root's #FFFFFF",
  },
  {
    id: 'M6',
    why: 'the compact title is mounted even while the large area is open -- the same Node is placed in '
      + 'two slots, so the title leaves the place the probe hand-computed for it',
    file: 'kit/asaot/ui/appBar.as',
    find: '        if (closed && tSmall != null) mid.addChild(tSmall);',
    replace: '        if (tSmall != null) mid.addChild(tSmall);',
    expect: 'the title top-left is',
  },
  {
    id: 'M7',
    why: 'the centre slot always centres -- a LARGE bar must keep its title left-aligned when it '
      + 'collapses, otherwise the title jumps sideways at the end of the scroll',
    file: 'kit/asaot/ui/appBar.as',
    find: '            justifyContent: n.large ? "flex-start" : "center" }) });',
    replace: '            justifyContent: "center" }) });',
    expect: 'want 95',
  },
  {
    id: 'M8',
    why: 'a String title is not wrapped -- the factory hands a String to `as Node` (null) and the bar '
      + 'renders with no title at all',
    file: 'kit/asaot/ui/appBar.as',
    find: '            if (opts.title is Node)',
    replace: '            if (true)',
    expect: 'a String title mounted no text node',
  },
  {
    id: 'M9',
    why: 'a slot is taken with `as Node` again -- `trailing: [a, b]` (the shape the gallery documents, '
      + 'and the reason this mutation exists) is not a Node, so the actions vanish silently',
    file: 'kit/asaot/ui/appBar.as',
    find: '            n.trailing = slot(opts.trailing, "trailing");',
    replace: '            n.trailing = opts.trailing as Node;',
    expect: 'used to be dropped entirely',
  },
  {
    id: 'M10',
    why: 'a claimed safe-area edge with a zero inset keeps the value UNSET -- the engine is only '
      + 'given padding when it is non-null, so the last inset stays in the engine and the bar stays 103',
    file: 'kit/asaot/ui/UiNode.as',
    find: '            if ((mask & bit) == 0) return v;',
    replace: '            if ((mask & bit) == 0 || inset == 0) return v;',
    expect: 'not 0,0,320,56',
  },
  {
    id: 'M11',
    why: 'an inset change only re-resolves -- `keepPrevious` leaves the diff baseline, so folding the '
      + 'inset back to zero raises no measure bit and the old geometry survives until another reflow',
    file: 'kit/asaot/ui/UiNode.as',
    find: '            this.dirty |= Dirty.M_PAINT;\n            this.markLayoutDirty();',
    replace: '            // (mutation) no layout mark',
    expect: 'not 0,0,320,56',
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
line('MUTATION appbar: ' + caught + '/' + MUTATIONS.length + ' caught, ' + broken + ' problem(s)');
line(broken === 0 && caught === MUTATIONS.length ? 'RESULT: PASS' : 'RESULT: FAIL');
fs.writeFileSync(RESULTS, log.join('\n') + '\n');
process.exit(broken === 0 && caught === MUTATIONS.length ? 0 : 1);

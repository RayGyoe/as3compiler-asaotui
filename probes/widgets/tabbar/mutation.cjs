// probes/widgets/tabbar/mutation.cjs -- proves the tabBar probe CAN go red.
//
// The probe asserts eight separable things (the cells are equal and fill the bar, the
// selected state is the tint, a tap reports its OWN index, a re-tap is still
// reported, barHeight moves the bar, a shrinking `items` drops the stale cell, a
// Node icon keeps the author's colour, and the home indicator is padding). Each
// mutation breaks exactly one and must fail with the SPECIFIC message named in
// `expect`, so "it went red" is never confused with "it failed to build".
//
// Every file is restored in `finally` and its sha256 compared with the pre-mutation
// hash: a mutation run can never leave the kit altered.
//
// USAGE (from asaotui/):   node probes/widgets/tabbar/mutation.cjs
'use strict';
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const DIR = __dirname;
const UI = path.resolve(DIR, '..', '..', '..');   // probes/widgets/tabbar -> asaotui
const PROBE = 'probes/widgets/tabbar';
const RESULTS = path.join(DIR, 'tabbar-mutation.txt');

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const MUTATIONS = [
  {
    id: 'M1',
    why: 'the handler reports the LAST index instead of its own -- this is the AS3 loop-closure trap the '
      + 'factory exists to avoid: every cell of a `for (var i ...)` loop shares one binding, so three '
      + 'different taps all report "the last tab"',
    file: 'kit/asaot/ui/tabBar.as',
    find: '                onClick: OptionSupport.tapIndex(cb, i),',
    replace: '                onClick: OptionSupport.tapIndex(cb, list.length - 1),',
    expect: 'want [0]',
  },
  {
    id: 'M2',
    why: 'the cells stop growing -- three cells size to their own content, so the strip no longer fills '
      + 'the bar and a tap near the right edge can land on nothing',
    file: 'kit/asaot/ui/tabBar.as',
    find: '                flexGrow: 1, alignItems: "center", justifyContent: "center", gap: 2',
    replace: '                alignItems: "center", justifyContent: "center", gap: 2',
    expect: 'cell t0 is',
  },
  {
    id: 'M3',
    why: 'the tint is applied to every cell EXCEPT the current one -- the bar highlights the tabs you '
      + 'are not on',
    file: 'kit/asaot/ui/tabBar.as',
    find: '            var on:Boolean = (i == sel);',
    replace: '            var on:Boolean = (i != sel);',
    expect: 'the selected label is',
  },
  {
    id: 'M4',
    why: 'the ICON is built with the muted tint -- the label still highlights, so the bar looks like it '
      + 'half-works (the icon never follows the selection)',
    file: 'kit/asaot/ui/tabBar.as',
    find: '                    size: [24, 24], color: on ? t.accent : t.textMuted }));',
    replace: '                    size: [24, 24], color: t.textMuted }));',
    expect: 'the selected icon is',
  },
  {
    id: 'M5',
    why: 'the bar never paints its surface -- the cells still tint correctly, so nothing looks wrong '
      + 'until you point it at a dark page and the bar disappears',
    file: 'kit/asaot/ui/kind/TabBarWidget.as',
    find: '            PaintKit.paintBox(n, s, PaintKit.w1(n), PaintKit.h1(n));',
    replace: '            // (mutation) no surface',
    expect: 'the pixel inside the bar is',
  },
  {
    id: 'M6',
    why: '`barHeight` is ignored -- the strip is always 56, so a bar the author made taller to clear '
      + 'the home indicator floats away from the bottom edge',
    file: 'kit/asaot/ui/tabBar.as',
    find: '            height: rowH, alignItems: "stretch" }) });',
    replace: '            height: 56, alignItems: "stretch" }) });',
    expect: 'a 72px bar is',
  },
  {
    id: 'M7',
    why: 'the LABEL keeps its own untinted style -- the cell is tinted but the text is patched back to '
      + 'the muted colour, so the selected tab looks exactly like the others',
    file: 'kit/asaot/ui/tabBar.as',
    find: '                .withPatch(on ? selTint : offTint) }));',
    replace: '                .withPatch(offTint) }));',
    expect: 'the selected label is',
  },
  {
    id: 'M8',
    why: 'a NODE icon is re-built through the string path -- the author\'s own node is thrown away '
      + '(it is not a path string), so a custom badge/avatar in a cell silently disappears',
    file: 'kit/asaot/ui/tabBar.as',
    find: '                if (ic is Node) kids.push(ic as Node);   // the author\'s own colour wins',
    replace: '                if (false) kids.push(ic as Node);',
    expect: 'the Node icon was not mounted',
  },
  {
    id: 'M9',
    why: 'the `safeArea:` opt is not mirrored onto the descriptor -- no bar claims the bottom inset, so '
      + 'the cells sit on the very bottom edge under the home indicator and the bar is 56 tall, not 90',
    file: 'kit/asaot/ui/OptionSupport.as',
    find: '            if (opts.safeArea != null) n.safeArea = opts.safeArea;',
    replace: '            // (mutation) the safeArea opt is dropped',
    expect: 'not 0,170,320,90',
  },
  {
    id: 'M10',
    why: 'the label sizes to its TEXT instead of to the cell -- an over-long label is laid out at its '
      + 'intrinsic width (164px in a 160px cell) and paints across the boundary into the next tab, '
      + 'because a cell does not clip',
    file: 'kit/asaot/ui/tabBar.as',
    find: '                size: [pct(1), auto()],\n',
    replace: '',
    expect: 'want x=0 w=160',
  },
  {
    id: 'M11',
    why: 'the label is pinned to the cell but told nothing about overflow -- the field clips mid-glyph '
      + 'with no ellipsis, so the run ends in a half letter instead of a "…"',
    file: 'kit/asaot/ui/tabBar.as',
    find: 'text: { fontSize: 11, textAlign: "center", textOverflow: "ellipsis" } })',
    replace: 'text: { fontSize: 11, textAlign: "center" } })',
    expect: 'was not truncated at all',
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
line('MUTATION tabbar: ' + caught + '/' + MUTATIONS.length + ' caught, ' + broken + ' problem(s)');
line(broken === 0 && caught === MUTATIONS.length ? 'RESULT: PASS' : 'RESULT: FAIL');
fs.writeFileSync(RESULTS, log.join('\n') + '\n');
process.exit(broken === 0 && caught === MUTATIONS.length ? 0 : 1);

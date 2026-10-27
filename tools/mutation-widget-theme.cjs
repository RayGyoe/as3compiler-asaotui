// tools/mutation-widget-theme.cjs -- proves probes/widgets/theme CAN go red.
//
// The theme layer is exactly the kind of thing that looks wired up and is not: the
// palette can be swapped without anything repainting, without the defaults being
// rebuilt, without the overlay chrome being rebuilt, and the resting bitmap can still
// come out "plausibly themed" if the probe only took one screenshot. So every mutation
// below removes ONE of the four pathways and the run must fail with THAT pathway's
// assertion named in `expect` -- "it went red" is never enough (a build failure is red
// too), and every mutation is also checked to still COMPILE.
//
// Every file is restored in `finally` and its sha256 compared byte for byte with the
// pre-mutation hash, so a botched restore can never be left behind silently.
//
// USAGE (from asaotui/):   node tools/mutation-widget-theme.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const UI = path.resolve(__dirname, '..');
const RESULTS = path.join(UI, 'reviews', 'mutation-widget-theme.txt');
const PROBE = 'probes/widgets/theme';

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const MUTATIONS = [
  {
    id: 'M1',
    why: 'the swap does not bump the epoch -> nothing downstream learns a theme switch happened',
    file: 'kit/asaot/ui/Theme.as',
    find: '            _epoch = _epoch + 1;',
    replace: '            _epoch = _epoch + 0;   // MUTATED',
    expect: 'the epoch is 0 not 1',
  },
  {
    id: 'M2',
    why: 'markThemeDirty stops marking styles stale -> nodes whose style POINTER did not move keep the old baseline',
    file: 'kit/asaot/ui/UiApp.as',
    find: '            n.lastStyleStale = true;\n            n.dirty |= Dirty.M_PAINT;',
    replace: '            n.dirty |= Dirty.M_PAINT;   // MUTATED: lastStyleStale',
    expect: 'after the switch the button text colour is',
  },
  {
    id: 'M3',
    why: 'the overlay chrome is not rebuilt -> every baked overlay colour stays light',
    file: 'kit/asaot/ui/Theme.as',
    find: '            OverlayChrome.rebuild();',
    replace: '            // MUTATED: OverlayChrome.rebuild();',
    expect: 'hover band did not follow',
  },
  {
    id: 'M4',
    why: 'setTheme aliases the caller palette instead of copying -> the caller can repaint half the tree',
    file: 'kit/asaot/ui/Theme.as',
    find: '            _palette.copyFrom(t);',
    replace: '            _palette = t;   // MUTATED',
    expect: 'setTheme aliased the caller',
  },
  {
    id: 'M5',
    why: 'the override layer is no longer consulted -> an author customisation silently disappears',
    file: 'kit/asaot/ui/Theme.as',
    find: '            var o:Style = _overrides[kind];',
    replace: '            var o:Style = null;   // MUTATED',
    expect: 'override is not in force after the swap',
  },
  {
    id: 'M6',
    why: 'a widget still paints a LIGHT LITERAL -> the dark pass catches the one that did not migrate',
    file: 'kit/asaot/ui/kind/SwitchWidget.as',
    find: 'on ? pal.success : pal.trackOff',
    // No trailing comment: it would swallow the rest of the call on the same line.
    replace: 'on ? pal.success : 0xD1D5DB',
    expect: 'dark: switch at (48,68)',
  },
  {
    id: 'M7',
    why: 'no DESCRIBE is requested -> factory-baked refinements never get the new palette (geometry is fine, paint-time reads look fine)',
    file: 'kit/asaot/ui/UiApp.as',
    find: '                this.invalidate(Dirty.THEME);',
    replace: '                this.invalidate(0);   // MUTATED: Dirty.THEME',
    expect: 'dark: page at (400,340)',
  },
  {
    id: 'M8',
    why: 'the kind defaults are not rebuilt -> every baseline-driven colour (text, borders) stays light',
    file: 'kit/asaot/ui/Theme.as',
    find: '            buildDefaults();\n            // The one class that bakes colours',
    replace: '            // MUTATED: buildDefaults();\n            // The one class that bakes colours',
    expect: 'after the switch the button text colour is',
  },
];

function runProbe() {
  return spawnSync(process.execPath, ['tools/probe.cjs', PROBE], { cwd: UI, encoding: 'utf8', maxBuffer: 1 << 28 });
}

const log = [];
const line = (s) => { console.log(s); log.push(s); };
let caught = 0;
let broken = 0;

// Baseline: the probe must be green unmutated, or "it went red" proves nothing.
{
  const r = runProbe();
  const out = (r.stdout || '') + (r.stderr || '');
  const v = /RESULT: (PASS|FAIL)/.exec(out);
  const m = /PROBE \S+: (\d+) checks, (\d+) failures/.exec(out);
  line('baseline ' + PROBE + ': ' + (v ? v[0] : 'NO VERDICT -- build failure?') + (m ? '  (' + m[1] + ' checks)' : ''));
  if (!v || v[1] !== 'PASS') {
    line('  the baseline is not green; a mutation run would be meaningless. Aborting.');
    fs.writeFileSync(RESULTS, log.join('\n') + '\n');
    process.exit(1);
  }
  line('');
}

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
    for (const f of fails.slice(0, 3)) line('     ' + f.trim());
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
line('MUTATION theme: ' + caught + '/' + MUTATIONS.length + ' caught, ' + broken + ' problem(s)');
line(broken === 0 && caught === MUTATIONS.length ? 'RESULT: PASS' : 'RESULT: FAIL');
fs.writeFileSync(RESULTS, log.join('\n') + '\n');
process.exit(broken === 0 && caught === MUTATIONS.length ? 0 : 1);
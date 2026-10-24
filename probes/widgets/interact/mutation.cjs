// probes/widgets/interact/mutation.cjs -- proves tools/probe.cjs CAN go red on the
// interaction probe.
//
// A probe that cannot fail is decoration: this one exercises four features that all
// work by ABSENCE as much as by presence (a hover that is not derived, a disabled
// control that still runs its handler, a ring that is not drawn, a field that only
// mirrors the model), so without these it would be very easy to "fix" the probe by
// breaking the feature.
//
// Each mutation is a one-token change to something the probe actually measures, and
// each names the SPECIFIC failure line it must produce -- so "it went red" is never
// confused with "it failed to build".
//
// Every file is restored in `finally` and its sha256 compared byte-for-byte with the
// pre-mutation hash: a mutation run can never leave the kit subtly altered.
//
// USAGE (from asaotui/):   node probes/widgets/interact/mutation.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const DIR = __dirname;
const UI = path.resolve(DIR, '..', '..', '..');   // probes/widgets/interact -> asaotui
const PROBE = 'probes/widgets/interact';
const RESULTS = path.join(DIR, 'interact-mutation.txt');

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const MUTATIONS = [
  {
    id: 'M1',
    why: 'nothing reads `state.hover` again -- the pre-audit state, where the flag was maintained and '
      + 'the surface ignored it',
    file: 'kit/asaot/ui/PaintKit.as',
    find: 'public static const HOVER_LIFT:int = 8;',
    replace: 'public static const HOVER_LIFT:int = 0;',
    expect: 'the hovered button\'s fill (8% toward white)',
  },
  {
    id: 'M2',
    why: 'the press no longer sinks the surface -> a pressed button is indistinguishable from an idle one',
    file: 'kit/asaot/ui/PaintKit.as',
    find: 'public static const PRESS_SINK:int = 12;',
    replace: 'public static const PRESS_SINK:int = 0;',
    expect: 'the pressed button\'s fill (12% toward black)',
  },
  {
    id: 'M3',
    why: 'the disabled dimming is dropped from the BACKING (UiNode), which is the only place that can '
      + 'dim the label, the border and the fill together',
    file: 'kit/asaot/ui/UiNode.as',
    find: '            if (this.state.disabled != 0) this.backing.alpha = this.backing.alpha * PaintKit.DISABLED_ALPHA;',
    replace: '            if (false) this.backing.alpha = this.backing.alpha * PaintKit.DISABLED_ALPHA;',
    expect: "a disabled node's backing alpha is 1 not 0.45",
  },
  {
    id: 'M4',
    why: 'DISABLED STOPS BEING INERT: the guard in handleClick is removed, so a direct dispatch (a test, '
      + 'a programmatic click on a child) runs the handler of a disabled control',
    file: 'kit/asaot/ui/UiNode.as',
    find: '            if (this.inert()) return;\n            this.setPressed(0);',
    replace: '            this.setPressed(0);',
    expect: 'a disabled button ran its onClick',
  },
  {
    id: 'M5',
    why: 'the focus ring is not drawn -> the ring pixel stays the fill colour (the four-bar draw is the '
      + 'only thing that can put FOCUS_RING on the border while the fill stays put)',
    file: 'kit/asaot/ui/PaintKit.as',
    find: '            if (n.state.focused != 0 && n.tabEnabled && n.state.disabled == 0',
    replace: '            if (false && n.state.focused != 0 && n.tabEnabled && n.state.disabled == 0',
    expect: "the focus ring's left bar",
  },
  {
    id: 'M6',
    why: 'the tab ring stops excluding inert subtrees -> Tab lands on the disabled button',
    file: 'kit/asaot/ui/UiApp.as',
    find: '            if (n.tabEnabled && !n.inert()) out.push(n);',
    replace: '            if (n.tabEnabled) out.push(n);',
    expect: 'Tab from btnA landed on btnA not inp',
  },
  {
    id: 'M7',
    why: 'THE ORIGINAL DEFECT, re-introduced: the field only MIRRORS the model. Event.CHANGE no longer '
      + 'writes back, so the user types and the model never hears about it',
    file: 'kit/asaot/ui/kind/InputWidget.as',
    find: '            var t:String = n.tf.text;\n            if (t == n.value) return;\n            n.value = t;',
    replace: '            var t:String = n.tf.text;\n            if (t == n.value) return;',
    expect: "the retained node's value is '' not 'Ada'",
  },
  {
    id: 'M8',
    why: 'Enter no longer commits -> the model updates but onCommit never fires (a form cannot ever be '
      + 'submitted)',
    file: 'kit/asaot/ui/kind/InputWidget.as',
    find: '            if (n.onCommit != null) n.onCommit(n.value);',
    replace: '            if (false && n.onCommit != null) n.onCommit(n.value);',
    expect: 'Enter did not commit',
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
line('MUTATION interact: ' + caught + '/' + MUTATIONS.length + ' caught, ' + broken + ' problem(s)');
line(broken === 0 && caught === MUTATIONS.length ? 'RESULT: PASS' : 'RESULT: FAIL');
fs.writeFileSync(RESULTS, log.join('\n') + '\n');
process.exit(broken === 0 && caught === MUTATIONS.length ? 0 : 1);
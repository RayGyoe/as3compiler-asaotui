// tools/mutation-widget-actions.cjs -- proves probes/widgets/actions CAN go red.
//
// The probe covers four additions at once (right click + point-anchored menu, double
// click, splitPane, and the keymap: ActionRegistry + Control.action + tabIndex), and
// every one of them can be broken WITHOUT the resting bitmap changing: a menu that
// ignores its anchor still draws a menu, a splitter that ignores minSize still draws
// two panes, a keymap that ignores its context still fires the action the probe asks
// for first. So each mutation below changes the exact thing one assertion measures,
// and the run must fail with THAT assertion's line named in `expect` -- "it went red"
// is never enough (a build failure is red too).
//
// Every file is restored in `finally` and its sha256 compared byte for byte with the
// pre-mutation hash, so a botched restore can never be left behind silently.
//
// USAGE (from asaotui/):   node tools/mutation-widget-actions.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const UI = path.resolve(__dirname, '..');
const RESULTS = path.join(UI, 'reviews', 'mutation-widget-actions.txt');
const PROBE = 'probes/widgets/actions';

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const MUTATIONS = [
  {
    id: 'M1',
    why: 'the keymap is never consulted -> a bound key does nothing (the built-ins still work)',
    file: 'kit/asaot/ui/UiApp.as',
    find: '            if (hit != null)\n            {\n                e.preventDefault();\n                ActionRegistry.dispatch(String(hit.id), hit.payload as Object);',
    replace: '            if (false)\n            {\n                e.preventDefault();\n                ActionRegistry.dispatch(String(hit.id), hit.payload as Object);',
    expect: 'Escape inside `probe > modal` did not fire the action',
  },
  {
    id: 'M2',
    why: 'Control.action is never consumed -> Enter on a focused button falls back to onClick',
    file: 'kit/asaot/ui/UiApp.as',
    find: '                if (f.action != null)\n                {\n                    ActionRegistry.dispatch(f.action, null);',
    replace: '                if (false)\n                {\n                    ActionRegistry.dispatch(f.action, null);',
    expect: 'Enter on a control with an action did not dispatch it',
  },
  {
    id: 'M3',
    why: 'the ring is left in document order -> tabIndex has no consumer again',
    file: 'kit/asaot/ui/UiApp.as',
    find: '            if (!any) return ring;',
    replace: '            return ring;   // MUTATED',
    expect: 'Tab went to',
  },
  {
    id: 'M4',
    why: 'doubleClickEnabled is never switched on -> the runtime never produces a doubleClick',
    file: 'kit/asaot/ui/UiNode.as',
    find: '                this.backing.doubleClickEnabled = this.onDoubleClick != null;',
    replace: '                this.backing.doubleClickEnabled = false;   // MUTATED',
    expect: 'a node with onDoubleClick has doubleClickEnabled off',
  },
  {
    id: 'M5',
    why: 'the right-click handler is never copied to the retained node -> the popup never opens',
    file: 'kit/asaot/ui/UiNode.as',
    find: '            this.onRightClick = Element(desc).onRightClick;',
    replace: '            this.onRightClick = null;   // MUTATED',
    expect: 'onRightClick got',
  },
  {
    id: 'M6',
    why: 'the point anchor ignores its own x -> the panel lands 4pt away from the pointer',
    file: 'kit/asaot/ui/kind/MenuWidget.as',
    find: '            eng.setPosition(e, LayoutConstants.EDGE_LEFT, x - ox, LayoutConstants.UNIT_POINT);',
    replace: '            eng.setPosition(e, LayoutConstants.EDGE_LEFT, x - ox + 4, LayoutConstants.UNIT_POINT);   // MUTATED',
    expect: 'the menu is at',
  },
  {
    id: 'M7',
    why: 'measure() stops honouring minSize -> an authored ratio of 0.02 yields a 6pt pane',
    file: 'kit/asaot/ui/kind/SplitPaneWidget.as',
    find: '            if (w1 < minS) w1 = minS;',
    replace: '            if (false) w1 = minS;   // MUTATED',
    expect: 'after the clamp pane A is',
  },
  {
    id: 'M8',
    why: 'the DRAG stops honouring minSize -> it reports 0.0136 instead of clamping to 0.13605',
    file: 'kit/asaot/ui/kind/SplitPaneWidget.as',
    find: '            if (r < lo) r = lo;',
    replace: '            if (false) r = lo;   // MUTATED',
    expect: 'the clamped share is',
  },
  {
    id: 'M9',
    why: 'lookup() ignores the context predicate -> a binding fires everywhere in the app',
    file: 'kit/asaot/ui/ActionRegistry.as',
    find: '                if (!ContextExpr(e.ctx).matches(contexts)) continue;',
    replace: '                if (false) continue;   // MUTATED',
    expect: 'Escape fired outside its context',
  },
  {
    id: 'M10',
    why: 'the keystroke stops checking SHIFT -> ctrl-shift-s also matches a plain ctrl-s press',
    file: 'kit/asaot/ui/KeyStroke.as',
    // No `// MUTATED` here on purpose: a line comment would swallow the `&& this.meta`
    // term on the NEXT line and leave the predicate unchanged (a no-op mutation).
    find: '                && this.shift == kShift',
    replace: '                && this.shift == this.shift',
    expect: 'ctrl-shift-s matched a press without shift',
  },
  {
    id: 'M11',
    why: '`a > b` is read as "b is an ancestor of a" -> every nested binding inverts',
    file: 'kit/asaot/ui/ContextExpr.as',
    find: '                    for (var j:int = 0; j < i; j++)',
    replace: '                    for (var j:int = i + 1; j < m; j++)   // MUTATED',
    expect: 'matched the REVERSED list',
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
line('MUTATION actions: ' + caught + '/' + MUTATIONS.length + ' caught, ' + broken + ' problem(s)');
line(broken === 0 && caught === MUTATIONS.length ? 'RESULT: PASS' : 'RESULT: FAIL');
fs.writeFileSync(RESULTS, log.join('\n') + '\n');
process.exit(broken === 0 && caught === MUTATIONS.length ? 0 : 1);
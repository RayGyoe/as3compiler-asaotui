// tools/mutation-widget-inputs.cjs -- proves probes/widgets/inputs CAN go red.
//
// The probe covers five additions at once (numberInput, rangeSlider, multiSelect and
// `virtual: true` on list + tree), and every one of them can be broken WITHOUT the
// resting bitmap changing: a window that mounts one row too few still looks like a
// list, a click that reports a window-relative index still paints the same band, a
// clamp that does not clamp still draws a number. So each mutation below changes the
// exact thing one assertion measures, and the run must fail with THAT assertion's
// line named in `expect` -- "it went red" is never enough (a build failure is red).
//
// Every file is restored in `finally` and its sha256 compared byte for byte with the
// pre-mutation hash, so a botched restore can never be left behind silently.
//
// USAGE (from asaotui/):   node tools/mutation-widget-inputs.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const UI = path.resolve(__dirname, '..');
const RESULTS = path.join(UI, 'reviews', 'mutation-widget-inputs.txt');
const PROBE = 'probes/widgets/inputs';

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const MUTATIONS = [
  {
    id: 'M1',
    why: 'the window drops its +1 partial row -> six mounted rows become five, and the probe counts them',
    file: 'kit/asaot/ui/ListNode.as',
    find: '            var last:int = first + fit;      // +1: the partial row',
    replace: '            var last:int = first + fit - 1;  // MUTATED: no partial row',
    expect: 'the virtual list mounts',
  },
  {
    id: 'M2',
    why: 'the list stops clipping to the viewport -> the mounted-but-offscreen row 5 paints (#606060)',
    file: 'kit/asaot/ui/kind/ListWidget.as',
    find: '            n.backing.scrollRect = new Rectangle(0, 0, w, h);',
    replace: '            // MUTATED: no clip',
    expect: '(30,216) is',
  },
  {
    id: 'M3',
    why: 'a click reports its WINDOW-relative row instead of the absolute index -> row 3 becomes row 0',
    file: 'kit/asaot/ui/kind/ListWidget.as',
    find: '            if (Number(n.extra[VIRT_KEY]) != 0) target = target + int(Number(n.extra[FIRST_KEY]));',
    replace: '            if (Number(n.extra[VIRT_KEY]) != 0) target = target;   // MUTATED',
    expect: 'the click selected',
  },
  {
    id: 'M4',
    why: 'a row click stops claiming focus -> the End key after a click never reaches the list',
    file: 'kit/asaot/ui/kind/ListWidget.as',
    find: '            n.app.focusNode(n);\n            this.select(n, target);',
    replace: '            this.select(n, target);',
    expect: 'End selected',
  },
  {
    id: 'M5',
    why: 'reveal() becomes a no-op -> End moves the selection but leaves the window where it was',
    file: 'kit/asaot/ui/kind/ListWidget.as',
    find: '            if (sel >= first && sel < first + fit) return;',
    replace: '            return;   // MUTATED: never scroll',
    expect: 'End left the window at',
  },
  {
    id: 'M6',
    why: 'clamp() forgets the upper bound -> PageUp takes the value to 25 instead of stopping at max 10',
    file: 'kit/asaot/ui/NumberInputNode.as',
    find: '            if (!isNaN(max) && out > max) out = max;',
    replace: '            if (false && !isNaN(max) && out > max) out = max;   // MUTATED',
    expect: 'PageUp reported',
  },
  {
    id: 'M7',
    why: 'the stepper strip shrinks from 32pt to 2pt -> a press on the visible `+` lands in the text field',
    file: 'kit/asaot/ui/kind/NumberInputWidget.as',
    find: '        private static const STEP_W:Number = 32;',
    replace: '        private static const STEP_W:Number = 2;   // MUTATED',
    expect: 'the + stepper reported',
  },
  {
    id: 'M8',
    why: 'the stepper loses its transparent hit surface -> only the +/- strokes are clickable, not the column',
    file: 'kit/asaot/ui/kind/NumberInputWidget.as',
    find: '            g.beginFill(0x000000, 0);\n            g.drawRect(x0, 0, STEP_W, h);\n            g.endFill();',
    replace: '            // MUTATED: no stepper hit surface',
    expect: 'the + stepper reported',
  },
  {
    id: 'M9',
    why: 'a multi-select toggle closes the menu -> the gesture becomes a single-select',
    file: 'kit/asaot/ui/kind/MultiSelectWidget.as',
    find: '            var f:Function = n.extra[TOGGLE_FN];\n            if (f != null) f(row);\n            n.app.markPaint(n);',
    replace: '            var f:Function = n.extra[TOGGLE_FN];\n            if (f != null) f(row);\n            n.app.markPaint(n);\n            this.close(n, false);   // MUTATED',
    expect: 'onOpenChange fired',
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
line('MUTATION inputs: ' + caught + '/' + MUTATIONS.length + ' caught, ' + broken + ' problem(s)');
line(broken === 0 && caught === MUTATIONS.length ? 'RESULT: PASS' : 'RESULT: FAIL');
fs.writeFileSync(RESULTS, log.join('\n') + '\n');
process.exit(broken === 0 && caught === MUTATIONS.length ? 0 : 1);
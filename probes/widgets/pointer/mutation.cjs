// probes/widgets/pointer/mutation.cjs -- proves probes/widgets/pointer CAN go red on the
// batch that moved hover from per-object mouseOver/mouseOut (which our AOT never
// dispatches, G25) onto one stage MOUSE_MOVE plus a backing -> node registry.
//
// Every mutation is one CONTRACT, not one bug: each removes exactly the mechanism whose
// absence the probe is supposed to see, so a green run after a mutation would mean the
// probe is measuring nothing.
//
//   M1 ancestors do not get the hover      -> a card with a hover background never
//                                             lights while the pointer is on its children
//   M2 the old chain is never cleared      -> two nodes hovered at once, and the one the
//                                             pointer left stays lit forever
//   M3 no fallback to "auto"               -> Mouse.cursor is process-wide, so the shape
//                                             of the last cursor-declaring node sticks to
//                                             the whole window
//   M4 the derived shape is never written  -> Style.cursor is parsed, inherited, resolved
//                                             and then not applied: opt-in that does
//                                             nothing is worse than absent
//   M5 a destroyed node stays the target   -> the next mouse move paints a node whose app
//                                             is null (#1009 inside a mouse event, i.e.
//                                             one console line thanks to the frame guard)
//
// Each mutated file is restored in `finally` and its sha256 compared byte-for-byte with
// the pre-mutation hash: a mutation run can never leave the kit subtly altered.
//
// USAGE (from asaotui/):   node probes/widgets/pointer/mutation.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const DIR = __dirname;
const UI = path.resolve(DIR, '..', '..', '..');   // probes/widgets/pointer -> asaotui
const PROBE = 'probes/widgets/pointer';
const RESULTS = path.join(DIR, 'pointer-mutation.txt');

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const MUTATIONS = [
  {
    id: 'M1',
    file: 'kit/asaot/ui/UiApp.as',
    why: 'ANCESTORS DO NOT GET THE HOVER: only the hit node lights, so a card whose background must react '
      + 'to its children stays flat -- AIR bubbles mouseOver, and every hover-on-container design depends on it',
    find: '            p = n;\n            while (p != null)\n            {\n                p.setHover(1);\n                p = p.parent;\n            }\n            this.applyCursor();',
    // NOTE: `if (n != null)` is not decoration -- setHoverTarget(null) is the "pointer
    // left" path and also the destroyed-node path, so an unguarded n.setHover(1) turns
    // this mutation into a #1009 inside a mouse event, the probe stops on its
    // setTimeout chain and the run reads TIMEOUT instead of a named failure (measured).
    replace: '            if (n != null) n.setHover(1);\n            this.applyCursor();',
    expect: 'did not get the bubbled hover',
  },
  {
    id: 'M2',
    file: 'kit/asaot/ui/UiApp.as',
    why: 'THE OLD CHAIN IS NEVER CLEARED: the node the pointer just left keeps its hover, so two controls are '
      + 'lit at once and the stale one never goes dark again',
    find: '                if (!this.onChain(n, p)) p.setHover(0);',
    replace: '                if (false && !this.onChain(n, p)) p.setHover(0);',
    expect: 'stayed hovered after the pointer left it',
  },
  {
    id: 'M3',
    file: 'kit/asaot/ui/UiApp.as',
    why: 'NO FALLBACK TO "auto": Mouse.cursor is process-wide, so leaving a node that asked for an I-beam '
      + 'leaves the I-beam on the whole window -- the shape never comes back on its own',
    find: '            if (want == null) want = MouseCursor.AUTO;',
    replace: '            if (want == null) want = Mouse.cursor;',
    expect: 'cursor-declaring node left',
  },
  {
    id: 'M4',
    file: 'kit/asaot/ui/UiApp.as',
    why: 'THE DERIVED SHAPE IS NEVER WRITTEN: cursor is parsed, inherited and resolved on every move, and the '
      + 'result is dropped -- an opt-in that does nothing at all',
    find: '            if (Mouse.cursor != want) Mouse.cursor = want;',
    replace: '            if (false && Mouse.cursor != want) Mouse.cursor = want;',
    expect: 'did not reach Mouse.cursor',
  },
  {
    id: 'M5',
    file: 'kit/asaot/ui/UiApp.as',
    why: 'A DESTROYED NODE STAYS THE HOVER TARGET: the registry drops it, but the chain keeps a node whose '
      + '`app` is null, and the next move calls markPaint on it',
    find: '            if (this._hover != null && this.onChain(this._hover, n)) this.setHoverTarget(null);',
    replace: '            if (false && this._hover != null && this.onChain(this._hover, n)) this.setHoverTarget(null);',
    expect: "still the app's hover target",
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
    const timedOut = /TIMEOUT/.test(out);
    const ok = verdict != null && verdict[1] === 'FAIL' && saidIt && !buildFailed;
    if (ok) caught++; else broken++;
    line(m.id + '  ' + (ok ? 'CAUGHT' : 'MISSED (THIS IS BAD)') + '  ' + m.why);
    line('     verdict: ' + (verdict ? verdict[0] : 'none')
      + (buildFailed ? '  BUILD FAILED -- a mutation that does not compile proves nothing' : '')
      + (timedOut ? '  TIMEOUT -- the program never reached its verdict' : '')
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
line('MUTATION pointer: ' + caught + '/' + MUTATIONS.length + ' caught, ' + broken + ' problem(s)');
line(broken === 0 && caught === MUTATIONS.length ? 'RESULT: PASS' : 'RESULT: FAIL');
fs.writeFileSync(RESULTS, log.join('\n') + '\n');
process.exit(broken === 0 && caught === MUTATIONS.length ? 0 : 1);
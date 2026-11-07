// probes/widgets/popover-scroll/mutation.cjs -- proves tools/probe.cjs CAN go red on
// the "floating panel anchored inside a scrolling pane" probe.
//
// The defect is one root cause with two links, and the mutations are aimed at each
// link rather than at the pixels:
//
//   M1 the anchor is read in LAYOUT coordinates again -- the reported bug verbatim
//      (the panel lands where the trigger would be without the scroll);
//   M2 the panel is positioned right the first time and never re-solved after the
//      main tree: a nested surface reads its parent row a frame stale and keeps that
//      placement forever;
//   M3 the viewport renders the slide but never BUMPS the epoch, so a wheel that
//      raises no describe leaves the panel where the pane used to be (M2 with the
//      signal missing instead of the reaction).
//
// Every file is restored in `finally` and its sha256 compared byte-for-byte with the
// pre-mutation hash: a mutation run can never leave the kit subtly altered.
//
// USAGE (from asaotui/):   node probes/widgets/popover-scroll/mutation.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const DIR = __dirname;
const UI = path.resolve(DIR, '..', '..', '..');   // probes/widgets/popover-scroll -> asaotui
const PROBE = 'probes/widgets/popover-scroll';
const RESULTS = path.join(DIR, 'popover-scroll-mutation.txt');
const POPOVER = 'kit/asaot/ui/kind/PopoverWidget.as';
const WIDGET = 'kit/asaot/ui/kind/ScrollViewWidget.as';
const APP = 'kit/asaot/ui/UiApp.as';

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const MUTATIONS = [
  {
    id: 'M1',
    file: POPOVER,
    why: 'THE ANCHOR IS READ IN LAYOUT COORDINATES: the panel is placed where the '
      + 'trigger would be WITHOUT the scroll -- the reported defect, at the one line '
      + 'that decides where an anchored panel goes',
    find: '            var ay:Number = a.visualY();',
    replace: '            var ay:Number = a.absY;',
    expect: 'the panel is at y 92 after scrolling 40',
  },
  {
    id: 'M2',
    file: APP,
    why: 'THE PANEL IS NEVER RE-SOLVED WHEN A PANE SLIDES: a scroll raises no layout '
      + 'dirty bit, so the frame that moves the pane leaves the panel at the height the '
      + 'trigger had before it',
    find: '            if (this.overlayRoot != null\n'
      + '                && (reconciledOverlay || this.scrollEpoch != this._overlayEpoch))',
    replace: '            if (false && this.overlayRoot != null\n'
      + '                && (reconciledOverlay || this.scrollEpoch != this._overlayEpoch))',
    expect: 'the panel is at y 92 after scrolling 40',
  },
  {
    id: 'M3',
    file: WIDGET,
    why: 'THE VIEWPORT NEVER BUMPS THE EPOCH: the slide reaches visualX/Y correctly, but '
      + 'nothing tells UiApp that the floating layer has to be solved again',
    find: '                if (n.app != null) n.app.scrollEpoch = n.app.scrollEpoch + 1;',
    replace: '                if (false) n.app.scrollEpoch = n.app.scrollEpoch + 1;',
    expect: 'the panel is at y 92 after scrolling 40',
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
line('MUTATION popover-scroll: ' + caught + '/' + MUTATIONS.length + ' caught, ' + broken + ' problem(s)');
line(broken === 0 && caught === MUTATIONS.length ? 'RESULT: PASS' : 'RESULT: FAIL');
fs.writeFileSync(RESULTS, log.join('\n') + '\n');
process.exit(broken === 0 && caught === MUTATIONS.length ? 0 : 1);
// probes/widgets/flip/mutation.cjs -- proves tools/probe.cjs CAN go red on the
// overflow-flip probe.
//
// The flip is invisible when it is missing: a panel that stays put instead of moving
// out of the window is still a panel with a valid rect and a painted surface, so every
// "does it render" assertion in the world passes. What must move is a NUMBER, and
// these five mutations are the five ways that number can go wrong -- no vertical flip,
// a flip that forgets the panel's own height, no HORIZONTAL flip, a placement that
// ignores the parent's origin, and a flip that forgets to clamp itself back inside.
//
// Every file is restored in `finally` and its sha256 compared byte-for-byte with the
// pre-mutation hash: a mutation run can never leave the kit subtly altered.
//
// USAGE (from asaotui/):   node probes/widgets/flip/mutation.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const DIR = __dirname;
const UI = path.resolve(DIR, '..', '..', '..');   // probes/widgets/flip -> asaotui
const PROBE = 'probes/widgets/flip';
const FILE = 'kit/asaot/ui/kind/PopoverWidget.as';
const RESULTS = path.join(DIR, 'flip-mutation.txt');

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const MUTATIONS = [
  {
    id: 'M1',
    why: 'NO VERTICAL FLIP: the overflow test is short-circuited, so the panel stays below its anchor '
      + 'and hangs 6px out of a 260px window (y=200, bottom edge 266)',
    find: '            if (pw > 0 && ph > 0)',
    replace: '            if (false && pw > 0 && ph > 0)',
    expect: 'the overflowing popover is at y=200 not 90',
  },
  {
    id: 'M2',
    why: 'THE PANEL\'S OWN HEIGHT IS DROPPED from the flipped placement, so it lands exactly where the '
      + 'anchor is (y=156) instead of ending there -- the bottom edge is off by its own height',
    find: 'eng.setPosition(e, LayoutConstants.EDGE_TOP, a.absY - off - ph - oy,',
    replace: 'eng.setPosition(e, LayoutConstants.EDGE_TOP, a.absY - off - oy,',
    expect: 'the overflowing popover is at y=156 not 90',
  },
  {
    id: 'M3',
    why: 'NO SIDEWAYS FLIP: only the vertical branch is kept, so the right-anchored panel stays where '
      + 'it was asked to go (x=386) and hangs 106px out of a 400px window',
    find: '                else if (want == "right" && a.absX + a.absW + off + pw > winW\n'
      + '                    && a.absX - off - pw >= 0) place = "left";',
    replace: '                else if (false) place = "left";',
    expect: 'the right-anchored popover is at x=386 not 134',
  },
  {
    id: 'M4',
    why: 'THE PARENT-LOCAL CONVERSION IS DROPPED from the horizontal inset (the `- ox` of a padded '
      + 'parent), so an anchored panel is offset by 40px -- x=-20 here',
    find: '                eng.setPosition(e, LayoutConstants.EDGE_LEFT, clampX(a.absX, pw, winW) - ox,\n'
      + '                                LayoutConstants.UNIT_POINT);\n'
      + '                eng.setPosition(e, LayoutConstants.EDGE_TOP, a.absY - off - ph - oy,',
    replace: '                eng.setPosition(e, LayoutConstants.EDGE_LEFT, clampX(a.absX, pw, winW) - ox - 40,\n'
      + '                                LayoutConstants.UNIT_POINT);\n'
      + '                eng.setPosition(e, LayoutConstants.EDGE_TOP, a.absY - off - ph - oy,',
    expect: 'the flipped popover is at x=-20 not 20',
  },
  {
    id: 'M5',
    why: 'THE CLAMP IS DROPPED on the flipped-side branch: the panel is on the correct axis but its '
      + 'bottom hangs 10px out of the window (y=204 instead of 190)',
    find: '                eng.setPosition(e, LayoutConstants.EDGE_LEFT, a.absX - off - pw - ox,\n'
      + '                                LayoutConstants.UNIT_POINT);\n'
      + '                eng.setPosition(e, LayoutConstants.EDGE_TOP, clampY(a.absY, ph, winH) - oy,',
    replace: '                eng.setPosition(e, LayoutConstants.EDGE_LEFT, a.absX - off - pw - ox,\n'
      + '                                LayoutConstants.UNIT_POINT);\n'
      + '                eng.setPosition(e, LayoutConstants.EDGE_TOP, a.absY - oy,',
    expect: 'the sideways-flipped popover is at y=204 not 190',
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
  const file = path.join(UI, FILE);
  const before = fs.readFileSync(file, 'utf8');
  const beforeHash = sha(file);
  if (before.indexOf(m.find) < 0) {
    line(m.id + '  SKIPPED -- anchor text not found in ' + FILE
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
line('MUTATION flip: ' + caught + '/' + MUTATIONS.length + ' caught, ' + broken + ' problem(s)');
line(broken === 0 && caught === MUTATIONS.length ? 'RESULT: PASS' : 'RESULT: FAIL');
fs.writeFileSync(RESULTS, log.join('\n') + '\n');
process.exit(broken === 0 && caught === MUTATIONS.length ? 0 : 1);
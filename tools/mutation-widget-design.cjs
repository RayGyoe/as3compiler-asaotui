// tools/mutation-widget-design.cjs -- proves probes/widgets/design CAN go red.
//
// The design discipline has four seams, each breakable while the app still looks fine:
//   1. innerRadius honours the gap      (concentric corners, not two unrelated numbers)
//   2. grid4 stays on the 4pt grid      (a skin that drifts off-grid is not the grid skin)
//   3. OverlayMotion reads the table    (a hardcoded 250 in the widget is a visible diff)
//   4. the table holds the shipped value(140/120 are the calibrated numbers, not guesses)
//
// Each mutation removes exactly one, must still COMPILE, and must fail with THAT line
// named in `expect`. Files restored in `finally`, compared byte for byte by sha256.
//
// USAGE (from asaotui/):   node tools/mutation-widget-design.cjs   (honours ASC_COMPILER)
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const UI = path.resolve(__dirname, '..');
const RESULTS = path.join(UI, 'reviews', 'mutation-widget-design.txt');
const PROBE = 'probes/widgets/design';

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const MUTATIONS = [
  {
    id: 'M1',
    why: 'innerRadius ignores the gap -> an inner control can out-round its container (the concentric rule is gone)',
    file: 'kit/asaot/ui/ThemeMetrics.as',
    find: 'var r:int = outer - gap;',
    replace: 'var r:int = outer;   // MUTATED: gap ignored',
    expect: 'innerRadius(14,8) != 6',
  },
  {
    id: 'M2',
    why: 'grid4 drifts off the 4pt grid -> the "grid" skin is no longer on the grid',
    file: 'kit/asaot/ui/ThemeMetrics.as',
    find: 'm.buttonPadY = 8;',
    replace: 'm.buttonPadY = 9;   // MUTATED: off grid',
    expect: 'grid4 padding off the grid',
  },
  {
    id: 'M3',
    why: 'OverlayMotion.enterMs hardcodes 250 instead of reading the Motion table -> a widget invents its own duration',
    file: 'kit/asaot/ui/OverlayMotion.as',
    find: 'public static function enterMs():int { return Motion.OVERLAY_ENTER_MS; }',
    replace: 'public static function enterMs():int { return 250; }   // MUTATED: bypass table',
    expect: 'does not read the Motion table',
  },
  {
    id: 'M4',
    why: 'the Motion table entrance value is retuned to 250 -> the shipped, calibrated 140 is lost',
    file: 'kit/asaot/ui/anim/Motion.as',
    find: 'public static const OVERLAY_ENTER_MS:int = 140;',
    replace: 'public static const OVERLAY_ENTER_MS:int = 250;   // MUTATED: retuned',
    expect: 'not 140 in the Motion table',
  },
];

function runProbe() {
  return spawnSync(process.execPath, ['tools/probe.cjs', PROBE], { windowsHide: true, cwd: UI, encoding: 'utf8', maxBuffer: 1 << 28 });
}

const log = [];
const line = (s) => { console.log(s); log.push(s); };
let caught = 0;
let broken = 0;

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
    for (const f of fails.slice(0, 2)) line('     ' + f.trim().slice(0, 300));
    if (fails.length > 2) line('     ... and ' + (fails.length - 2) + ' more');
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
line('MUTATION design: ' + caught + '/' + MUTATIONS.length + ' caught, ' + broken + ' problem(s)');
line(broken === 0 && caught === MUTATIONS.length ? 'RESULT: PASS' : 'RESULT: FAIL');
fs.writeFileSync(RESULTS, log.join('\n') + '\n');
process.exit(broken === 0 && caught === MUTATIONS.length ? 0 : 1);
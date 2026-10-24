// probes/widgets/imaging/mutation.cjs -- proves probes/widgets/imaging CAN go red on
// the batch that gave `image()` a Loader.
//
// Every mutation is one CONTRACT, not one bug: each removes exactly the mechanism whose
// absence the probe is supposed to see, so a green run after a mutation would mean the
// probe is measuring nothing.
//
//   M1 COMPLETE does not re-measure                 -> an auto-sized image keeps the
//                                                      64x64 placeholder box
//   M2 "fit" contains with max() instead of min()   -> the picture overflows its box
//   M3 a failed load never reaches UiNode.loadError -> the error is silent (onError is
//                                                      the only trace, and that is what
//                                                      the author cannot test against)
//   M4 the loaded Bitmap is not adopted             -> the bytes arrived and nothing is
//                                                      displayed
//   M5 "stretch" is ignored                         -> the picture keeps its 1:1 size
//                                                      inside a box it was told to fill
//
// Each mutated file is restored in `finally` and its sha256 compared byte-for-byte with
// the pre-mutation hash: a mutation run can never leave the kit subtly altered.
//
// USAGE (from asaotui/):   node probes/widgets/imaging/mutation.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const DIR = __dirname;
const UI = path.resolve(DIR, '..', '..', '..');   // probes/widgets/imaging -> asaotui
const PROBE = 'probes/widgets/imaging';
const RESULTS = path.join(DIR, 'imaging-mutation.txt');

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const MUTATIONS = [
  {
    id: 'M1',
    file: 'kit/asaot/ui/kind/ImageWidget.as',
    why: 'COMPLETE DOES NOT RE-MEASURE: the paint bit alone never re-solves a box, so an image with no '
      + '`size` keeps the 64x64 placeholder it measured before the bytes landed -- the exact failure that '
      + 'makes async images look broken while every property is correct',
    find: '            n.markLayoutDirty();\n            n.dirty = n.dirty | Dirty.M_PAINT;',
    replace: '            n.dirty = n.dirty | Dirty.M_PAINT;',
    expect: 'not the loaded 16x16',
  },
  {
    id: 'M2',
    file: 'kit/asaot/ui/kind/ImageWidget.as',
    why: '"fit" CONTAINS WITH max(): 16x16 into an 80x20 box becomes 80x80 and spills out of the box on the '
      + 'short axis, so the pixel just left of the contained area is painted instead of showing the '
      + 'background',
    find: '                var k:Number = Math.min(w / sw, h / sh);',
    replace: '                var k:Number = Math.max(w / sw, h / sh);',
    expect: 'fit painted outside the contained image',
  },
  {
    id: 'M3',
    file: 'kit/asaot/ui/kind/ImageWidget.as',
    why: 'A FAILED LOAD NEVER REACHES UiNode.loadError: the author callback still fires, but nothing on the '
      + 'node says the image is broken, so a re-describe repaints a silent blank box forever',
    find: '            n.loadError = msg;',
    replace: '            var swallowed:String = msg;',
    expect: 'UiNode.loadError did not receive the message',
  },
  {
    id: 'M4',
    file: 'kit/asaot/ui/kind/ImageWidget.as',
    why: 'THE LOADED BITMAP IS NOT ADOPTED: the job succeeds, the callbacks run, and the widget keeps '
      + 'measuring the placeholder -- "bytes arrived, nothing displayed"',
    find: '            n.extra[BMP_KEY] = b;',
    replace: '            n.extra["unused"] = b;',
    expect: 'auto (no size) is',
  },
  {
    id: 'M5',
    file: 'kit/asaot/ui/kind/ImageWidget.as',
    why: '"stretch" IS IGNORED: the picture is contained instead of filled, so the 40x40 box shows a 20x20 '
      + 'image in its middle -- a scale mode that is parsed, accepted and not applied',
    find: '            if (mode == "stretch")',
    replace: '            if (false && mode == "stretch")',
    expect: "pic's left half is not red",
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
line('MUTATION imaging: ' + caught + '/' + MUTATIONS.length + ' caught, ' + broken + ' problem(s)');
line(broken === 0 && caught === MUTATIONS.length ? 'RESULT: PASS' : 'RESULT: FAIL');
fs.writeFileSync(RESULTS, log.join('\n') + '\n');
process.exit(broken === 0 && caught === MUTATIONS.length ? 0 : 1);
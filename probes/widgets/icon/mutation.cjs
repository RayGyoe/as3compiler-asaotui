// probes/widgets/icon/mutation.cjs -- proves probes/widgets/icon CAN go red.
//
// Every mutation is one CONTRACT, not one bug: each removes exactly the mechanism whose
// absence the probe is supposed to see, so a green run after a mutation would mean the
// probe is measuring nothing.
//
//   I1 the cubic is never subdivided -> one quadratic standing in for the whole cubic,
//                                       i.e. a chord: the curve's own midpoint empties
//   I2 the stroke width is not scaled -> a VIEWBOX width used as a device width, so an
//                                       icon drawn at 2x has a half-thickness outline
//   I3 the viewBox is ignored in fit  -> the glyph is laid out in a 24-unit box whatever
//                                       space its data was authored in
//   I4 an arc becomes a chord         -> the silent approximation the class refuses:
//                                       the data parses and paints, and is wrong
//   I5 a relative command is absolute -> every offset in an "m/l/h/v" path is lost
//   I6 the node's colour is ignored   -> the glyph takes the theme colour, so an icon
//                                       cannot be the colour the author asked for
//
// Each mutated file is restored in `finally` and its sha256 compared byte-for-byte with
// the pre-mutation hash: a mutation run can never leave the kit subtly altered.
//
// USAGE (from asaotui/):   node probes/widgets/icon/mutation.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const DIR = __dirname;
const UI = path.resolve(DIR, '..', '..', '..');   // probes/widgets/icon -> asaotui
const PROBE = 'probes/widgets/icon';
const RESULTS = path.join(DIR, 'icon-mutation.txt');

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const MUTATIONS = [
  {
    id: 'I1',
    file: 'kit/asaot/ui/PathData.as',
    why: 'THE CUBIC IS NEVER SUBDIVIDED: one quadratic stands in for the whole cubic, so the curve the icon '
      + 'data describes is drawn as a chord through it',
    find: '            if (err <= this.tol || depth >= MAX_DEPTH)',
    replace: '            if (true)',
    expect: 'want a subdivided run',
  },
  {
    id: 'I2',
    file: 'kit/asaot/ui/kind/IconWidget.as',
    why: 'THE STROKE WIDTH IS NOT SCALED: a viewBox width is used as a device width, so the same glyph has half '
      + 'the outline it asked for at 2x',
    find: 'g.lineStyle(sw * scale, col, 1.0, false, "normal", "round", "round", 3);',
    replace: 'g.lineStyle(sw, col, 1.0, false, "normal", "round", "round", 3);',
    expect: 'pixel (36,90) want #2563EB',
  },
  {
    id: 'I3',
    file: 'kit/asaot/ui/kind/IconWidget.as',
    why: 'THE VIEWBOX IS IGNORED IN THE FIT: the glyph is laid out as if its data were always authored in a '
      + '24-unit box, so a 12-viewBox icon lands at the wrong scale',
    find: 'var scale:Number = Math.min(w / vb, h / vb);',
    replace: 'var scale:Number = Math.min(w / 24, h / 24);',
    // (96,92) and not (96,96): the glyph is CENTRED, so a wrong scale still puts the path
    // on y=96 -- only the band's THICKNESS moves. This mutation was MISSED on the first
    // sweep for exactly that reason.
    expect: 'pixel (96,92) want #2563EB',
  },
  {
    id: 'I4',
    file: 'kit/asaot/ui/PathData.as',
    why: 'AN ARC BECOMES A CHORD: the silent approximation the class exists to refuse -- the data parses, '
      + 'paints, and is not the shape it says it is',
    find: '                else if (c == "A")\n'
      + '                {\n'
      + '                    throw this.fail("the \'A\' (elliptical arc) command is not supported -- see compiler-gaps.md G26. "\n'
      + '                        + "An arc has to go arc -> cubic -> quadratic, and the engine has no cubic; "\n'
      + '                        + "drawing a chord instead would be a silent approximation. Use Q/T, or an arc-free icon set.");\n'
      + '                }',
    replace: '                else if (c == "A")\n'
      + '                {\n'
      + '                    this.num(); this.num(); this.num(); this.num(); this.num();\n'
      + '                    x = this.num(); y = this.num();\n'
      + '                    if (rel) { x += this.cx; y += this.cy; }\n'
      + '                    this.lineTo(x, y);\n'
      + '                    this.prevCmd = c;\n'
      + '                }',
    expect: 'did not throw naming G26',
  },
  {
    id: 'I5',
    file: 'kit/asaot/ui/PathData.as',
    why: 'A RELATIVE COMMAND IS TREATED AS ABSOLUTE: every offset in an "m/l/h/v" path is lost and the glyph '
      + 'collapses toward the origin',
    find: '                    x = this.num(); y = this.num();\n'
      + '                    if (rel) { x += this.cx; y += this.cy; }\n'
      + '                    this.lineTo(x, y);',
    replace: '                    x = this.num(); y = this.num();\n'
      + '                    this.lineTo(x, y);',
    expect: 'the relative lineto is',
  },
  {
    id: 'I6',
    file: 'kit/asaot/ui/kind/IconWidget.as',
    why: "THE NODE'S COLOUR IS IGNORED: the glyph takes the theme colour, so an icon cannot be the colour the "
      + 'author asked for',
    find: 'if (!isNaN(own)) col = uint(own) & 0xFFFFFF;',
    replace: 'if (false) col = uint(own) & 0xFFFFFF;',
    expect: 'pixel (156,96) want #DC2626',
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
line('MUTATION icon: ' + caught + '/' + MUTATIONS.length + ' caught, ' + broken + ' problem(s)');
line(broken === 0 && caught === MUTATIONS.length ? 'RESULT: PASS' : 'RESULT: FAIL');
fs.writeFileSync(RESULTS, log.join('\n') + '\n');
process.exit(broken === 0 && caught === MUTATIONS.length ? 0 : 1);
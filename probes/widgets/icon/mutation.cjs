// probes/widgets/icon/mutation.cjs -- proves probes/widgets/icon CAN go red.
//
// Every mutation is one CONTRACT, not one bug: each removes exactly the mechanism whose
// absence the probe is supposed to see, so a green run after a mutation would mean the
// probe is measuring nothing.
//
//   I1 the cubic is emitted as ONE QUADRATIC -> the best quadratic through the same ends
//                                       still passes through t=0.5, so only the
//                                       maximum-deviation sample and the command kind
//                                       can see it (this is the approximation the class
//                                       used to do on purpose, before G26)
//   I2 the stroke width is not scaled -> a VIEWBOX width used as a device width, so an
//                                       icon drawn at 2x has a half-thickness outline
//   I3 the viewBox is ignored in fit  -> the glyph is laid out in a 24-unit box whatever
//                                       space its data was authored in
//   I4 an arc becomes a chord         -> the silent approximation the class refuses:
//                                       the data parses and paints, and is wrong
//   I5 a relative command is absolute -> every offset in an "m/l/h/v" path is lost
//   I6 the node's colour is ignored   -> the glyph takes the theme colour, so an icon
//                                       cannot be the colour the author asked for
//   I7 an arc flag is read as a number -> the compact form ("011 1", no separators) misreads
//                                       its flags and then runs out of data
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
    why: 'THE CUBIC IS EMITTED AS ONE QUADRATIC: the shape still passes through t=0.5, so only the '
      + 'command kind and the maximum-deviation sample can see that the curve was approximated',
    find: '                    this.cubicTo(c1x, c1y, c22x, c22y, x, y);',
    replace: '                    this.quadTo((3 * (c1x + c22x) - (this.cx + x)) / 4, (3 * (c1y + c22y) - (this.cy + y)) / 4, x, y);',
    expect: 'pixel (111,35)',
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
    find: '                    this.arcTo(arx, ary, arot, alarge, asweep, x, y);',
    replace: '                    this.lineTo(x, y);',
    expect: 'pixel (236,96)',
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
  {
    id: 'I7',
    file: 'kit/asaot/ui/PathData.as',
    why: 'AN ARC FLAG IS READ AS A NUMBER: the separated form still parses, but the compact form '
      + '("a10 10 0 011 1") reads "011" as eleven and then has no numbers left',
    find: '            if (ch == "1") { this.i++; return true; }',
    replace: '            var fv:Number = this.num(); return fv > 0;',
    expect: 'compact-flag arc did not parse',
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
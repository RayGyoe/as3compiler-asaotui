// probes/widgets/textfx/mutation.cjs -- proves tools/probe.cjs CAN go red on the
// batch that added boxShadow, gradients, wrap, ellipsis and the multi-line field.
//
// Every mutation is one CONTRACT, not one bug: each removes exactly the mechanism
// whose absence the probe is supposed to see, so a green run after a mutation would
// mean the probe is measuring nothing.
//
//   M1 the shadow is never handed to the display object  -> no shadow under the box
//   M2 a gradient paints its FIRST STOP as a solid fill  -> no ramp (this is the
//                                                           silent fallback the
//                                                           kit refuses by throwing
//                                                           on radial instead)
//   M3 the wrap width is dropped at measure time         -> a long text stays one line
//   M4 truncation is skipped at paint time               -> the run keeps all 90 chars
//   M5 the text area CONSUMES Return (the single-line    -> Enter commits/reverts
//      contract leaked into the multi-line one)             instead of inserting
//
// Each mutated file is restored in `finally` and its sha256 compared byte-for-byte
// with the pre-mutation hash: a mutation run can never leave the kit subtly altered.
//
// USAGE (from asaotui/):   node probes/widgets/textfx/mutation.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const DIR = __dirname;
const UI = path.resolve(DIR, '..', '..', '..');   // probes/widgets/textfx -> asaotui
const PROBE = 'probes/widgets/textfx';
const RESULTS = path.join(DIR, 'textfx-mutation.txt');

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const NL = String.fromCharCode(10);   // a real newline, built rather than typed

const MUTATIONS = [
  {
    id: 'M1',
    file: 'kit/asaot/ui/UiNode.as',
    why: 'THE SHADOW IS NEVER HANDED TO THE DISPLAY OBJECT: the filter list is built and then thrown away, '
      + 'so the box looks exactly as it did before this batch -- the failure mode of "boxShadow parsed but '
      + 'never painted", which no property assertion would catch',
    find: '            target.filters = list;',
    replace: '            var dropped:Array = list;',
    expect: 'no shadow below the box',
  },
  {
    id: 'M2',
    file: 'kit/asaot/ui/PaintKit.as',
    why: 'A GRADIENT PAINTS ITS FIRST STOP AS A SOLID: the exact silent fallback the kit refuses for radial '
      + '(it throws) would then happen for linear too -- left edge still dark, so only the RAMP assertion '
      + 'can see it',
    find: '                m.createGradientBox(w, h, f.angle * Math.PI / 180.0, 0, 0);',
    replace: '                m.createGradientBox(w, h, f.angle * Math.PI / 180.0, 0, 0);'
      + ' g.beginFill(uint(Number(f.colors[0])) & 0xFFFFFF, 1.0); return;',
    expect: 'the gradient is not a ramp',
  },
  {
    id: 'M3',
    file: 'kit/asaot/ui/kind/TextWidget.as',
    why: 'THE WRAP WIDTH IS DROPPED AT MEASURE TIME: whiteSpace "normal" is accepted and then measured as '
      + 'one line, so the node publishes a single-line height and the text overflows its box',
    find: '            PaintKit.measureField(n, n.tf, n.textContent, s, wrapW);',
    replace: '            PaintKit.measureField(n, n.tf, n.textContent, s, NaN);',
    expect: 'did not wrap',
  },
  {
    id: 'M4',
    file: 'kit/asaot/ui/kind/TextWidget.as',
    why: 'TRUNCATION IS SKIPPED AT PAINT TIME: textOverflow "ellipsis" is parsed, accepted and then not '
      + 'applied, so a 90-character run is drawn into a 120px box',
    find: '                if (contentW > 0 && n.tf.textWidth > contentW)',
    replace: '                if (false)',
    expect: 'the ellipsis node still holds all',
  },
  {
    id: 'M5',
    file: 'kit/asaot/ui/kind/TextAreaWidget.as',
    why: 'THE TEXT AREA CONSUMES RETURN: the single-line contract (Enter commits) leaks into the multi-line '
      + 'one, which both suppresses the newline the runtime would insert and reverts the field to the last '
      + 'committed value -- the exact inversion TextAreaNode documents',
    find: '            if (keyCode == 27)',
    replace: '            if (keyCode == 27 || keyCode == 13)',
    expect: 'the field holds',
  },
  {
    id: 'M6',
    file: 'kit/asaot/ui/kind/TextWidget.as',
    why: 'THE DECORATION IS NEVER DRAWN: textDecoration is parsed, cascaded and then never reaches the '
      + 'shape, so an underline run looks exactly like a plain one -- a property assertion would still pass',
    find: '            PaintKit.decorate(n);',
    replace: '            // PaintKit.decorate(n);',
    expect: 'no underline at',
  },
  {
    id: 'M7',
    file: 'kit/asaot/ui/PaintKit.as',
    why: 'LINE-THROUGH IS DRAWN WHERE THE UNDERLINE GOES: the strike rule collapses into the underline rule, '
      + 'so the one line it does draw is in the wrong place -- and the probe\'s accent-insensitive text '
      + 'still has a line, which is why it samples the STRIKE node separately',
    find: '                else ly = top + acc + asc - asc * STRIKE_RATIO;',
    replace: '                else ly = top + acc + asc + 1;',
    expect: 'no line-through at',
  },
  {
    id: 'M8',
    file: 'kit/asaot/ui/PaintKit.as',
    why: 'THE RULE IGNORES THE LINE\'S LEFT EDGE: the decoration is drawn from the field\'s origin instead '
      + 'of from the line box\'s `lm.x`, so a centred or inset run gets a rule that starts too early -- a '
      + 'line that is still "an underline" to any assertion that only counts ink',
    find: '                g.drawRect(Math.round(tf.x + lm.x), Math.round(ly), Math.max(1, Math.round(lm.width)), 1);',
    replace: '                g.drawRect(Math.round(tf.x), Math.round(ly), Math.max(1, Math.round(lm.width)), 1);',
    expect: 'starts before the line',
  },
  {
    id: 'M9',
    file: 'kit/asaot/ui/kind/TextWidget.as',
    why: 'A TEXT NODE OWNS NO PAINT BOX: the shape that PaintKit.paintBox draws into is never created, so the '
      + 'node keeps its geometry and its glyphs while its background / borderColor paint NOTHING -- the silent '
      + 'drop the docs audit found (three tinted alignment lines came out untinted). Every property assertion '
      + 'still passes; only a pixel inside the box can see it',
    find: ['            n.shapeA = new Shape();', '            n.backing.addChild(n.shapeA);', '            n.tf = PaintKit.makeText(false);'].join(NL),
    replace: '            n.tf = PaintKit.makeText(false);',
    expect: 'the text node paints no background',
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
  // THE ANCHOR'S LINE ENDINGS MUST MATCH THE FILE'S. This kit is mixed: the repo
  // pins only *.bat in .gitattributes, so a file rewritten by an editor with the
  // other convention silently stopped matching a multi-line `find` written with
  // \n -- and the runner then reported SKIPPED, which reads like "nothing to do"
  // instead of "this mutation no longer exists". Resolve to whatever the file uses.
  const nl = before.indexOf('\r\n') >= 0 ? '\r\n' : '\n';
  const find = m.find.replace(/\r?\n/g, nl);
  const repl = m.replace.replace(/\r?\n/g, nl);
  if (before.indexOf(find) < 0) {
    line(m.id + '  SKIPPED -- anchor text not found in ' + m.file
      + ' (the file drifted; fix the mutation, do not ignore it)');
    broken++;
    continue;
  }
  try {
    fs.writeFileSync(file, before.split(find).join(repl));
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
line('MUTATION textfx: ' + caught + '/' + MUTATIONS.length + ' caught, ' + broken + ' problem(s)');
line(broken === 0 && caught === MUTATIONS.length ? 'RESULT: PASS' : 'RESULT: FAIL');
fs.writeFileSync(RESULTS, log.join('\n') + '\n');
process.exit(broken === 0 && caught === MUTATIONS.length ? 0 : 1);
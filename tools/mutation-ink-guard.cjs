// tools/mutation-ink-guard.cjs -- prove tools/ink-guard.cjs can go RED.
//
// A nail that cannot fail certifies nothing (the style-scan gate in gates.cjs spent
// three rounds counting a marker its tool never printed). The ink guard is a static
// scan, so the honest demonstration is: plant ONE defect of each class in a copy of a
// real widget file, run the guard, and require a non-zero exit that NAMES the file.
//
// THREE MUTATIONS, one per failure mode that actually shipped or nearly did:
//   M1 measure-only ink     -- delete the applyInk call from TextWidget: the ink a
//                              palette swap cannot refresh (G48's mechanism).
//   M2 the NaN guard        -- put `if (s.text.color >= 0) applyInk(...)` back: the
//                              shape that left the switch label black on the dark
//                              track (found by probes/widgets/theme).
//   M3 a second ink writer  -- add `setTextFormat` to a widget: a run assembled
//                              outside the kit's only ink writer.
//
// Every mutation is applied to a TEMPORARY COPY (`kit/.../_mut_ink_*.as`), never to
// the real file, and the copy is removed in `finally` with its absence verified.
// Each case also checks the guard's BASELINE first: the unmutated kit must PASS, or a
// green mutation run proves nothing.
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const UI = path.resolve(__dirname, '..');
const GUARD = path.join(__dirname, 'ink-guard.cjs');
const KIND = path.join(UI, 'kit', 'asaot', 'ui', 'kind');
const results = [];
function record(name, ok, detail) { results.push({ name, ok, detail }); }

const src = (f) => fs.readFileSync(path.join(KIND, f), 'utf8');
const sha = (s) => crypto.createHash('sha256').update(s).digest('hex').slice(0, 12);

function runGuard() {
  const r = spawnSync(process.execPath, [GUARD], { cwd: UI, encoding: 'utf8' });
  const out = (r.stdout || '') + (r.stderr || '');
  return { status: r.status, out };
}

// ---- baseline: the real kit must be clean ------------------------------------
const base = runGuard();
record('baseline: the unmutated kit passes', base.status === 0 && /RESULT: PASS/.test(base.out),
  'exit ' + base.status);

// A copy keeps the class/package shape (the guard is textual), so the mutations are
// made in-file on a copy under the kind/ directory the guard walks.
const CASES = [
  {
    id: 'M1',
    name: 'measure-only ink (applyInk removed)',
    file: 'TextWidget.as',
    mutate: (s) => s.replace(/\s*PaintKit\.applyInk\(n, n\.tf, PaintKit\.inkOf\(n\)\);/, '\n'),
    want: /R2 measure without applyInk/,
  },
  {
    id: 'M2',
    name: 'the NaN guard (`text.color >= 0`) is back',
    file: 'SwitchWidget.as',
    mutate: (s) => s.replace('PaintKit.applyInk(n, n.tf, PaintKit.inkOf(n));',
      'if (s.text.color >= 0) PaintKit.applyInk(n, n.tf, uint(s.text.color));'),
    want: /R3 `text\.color >= 0`|R6 applyInk with uint/,
  },
  {
    id: 'M3',
    name: 'a second ink writer appears',
    file: 'ChipWidget.as',
    mutate: (s) => s.replace('PaintKit.applyInk(n, n.tf, fg);',
      'n.tf.setTextFormat(PaintKit.formatFor(n.resolved));\n                PaintKit.applyInk(n, n.tf, fg);'),
    want: /R1 setTextFormat outside PaintKit/,
  },
];

for (const c of CASES) {
  const original = src(c.file);
  const mutated = c.mutate(original);
  const copy = path.join(KIND, '_mut_ink_' + c.id + '_' + c.file);
  try {
    if (mutated === original) { record(c.id + ' ' + c.name, false, 'the mutation did not change the source'); continue; }
    fs.writeFileSync(copy, mutated);
    const r = runGuard();
    record(c.id + ' ' + c.name + ' -> guard exits non-zero', r.status !== 0, 'exit ' + r.status);
    record(c.id + ' ' + c.name + ' -> the risk is named', c.want.test(r.out),
      (r.out.split(/\r?\n/).filter((l) => /INK-RISK/.test(l)).slice(0, 2).join(' | ') || '(no INK-RISK line)'));
  } finally {
    if (fs.existsSync(copy)) fs.unlinkSync(copy);
    if (sha(src(c.file)) !== sha(original)) record(c.id + ' restored ' + c.file, false, 'the real file changed!');
  }
}

// ---- the real files are byte-identical, and no copy is left behind -----------
record('no mutation file left in kit/', fs.readdirSync(KIND).every((f) => f.indexOf('_mut_ink_') !== 0),
  fs.readdirSync(KIND).filter((f) => f.indexOf('_mut_ink_') === 0).join(', ') || 'clean');

console.log('');
for (const r of results) console.log((r.ok ? 'MUTATION PASS  ' : 'MUTATION FAIL  ') + r.name + '   [' + r.detail + ']');
const bad = results.filter((r) => !r.ok).length;
console.log('');
console.log('MUTATION: ' + (bad === 0 ? 'PASS (' + results.length + '/' + results.length + ')' : 'FAIL (' + bad + ' problem(s))'));
process.exit(bad === 0 ? 0 : 1);
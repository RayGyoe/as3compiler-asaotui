// mutation-checkui-array-bg.cjs -- prove the new array-`background` checks in
// CheckUi.as can FAIL, i.e. that they are not decoration.
//
// Two independent mutations, each undoing ONE half of the fix:
//
//   M1  put StyleRefinement.from back to the unconditional
//       `r.background = Fill.fromAny(o.background);` -- the pre-2026-10-23 shape.
//       Prediction: the Array goes into an Object-typed parameter, `is Fill` reads
//       the array header as a vtable, the process dies with 0xC0000005, so
//       CheckUi exits non-zero. If this mutation does NOT go red, the new
//       `is Array` branch is not what is saving us.
//
//   M2  make Fill.fromAny return null for everything (`if (o is Number)` ->
//       `if (false)`). This one checks the OTHER side: that the "scalar background
//       still yields an opaque solid fill" assertion is a real assertion and not a
//       tautology that would pass for any implementation.
//
// Both mutations are undone in `finally` and the restoration is verified by hash --
// a mutation that leaves the tree dirty is worse than no mutation at all.
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const HERE = __dirname;
const UI = path.resolve(HERE, '..');
const COMPILER = path.resolve(UI, '..', 'as3compiler');

const REFINE = path.join(UI, 'kit', 'asaot', 'ui', 'style', 'StyleRefinement.as');
const FILL = path.join(UI, 'kit', 'asaot', 'ui', 'style', 'Fill.as');

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const before = { refine: sha(REFINE), fill: sha(FILL) };

function runCheck() {
  const r = spawnSync(process.execPath, [path.join(HERE, 'run-check.cjs')],
    { cwd: HERE, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  return { code: r.status === null ? 'signal ' + r.signal : r.status, out: (r.stdout || '') + (r.stderr || '') };
}

const results = [];
const record = (name, ok, detail) => results.push({ name, ok, detail });

function withPatched(file, from, to, body) {
  const orig = fs.readFileSync(file, 'utf8');
  if (!orig.includes(from)) throw new Error('mutation anchor not found in ' + file + ':\n' + from);
  try {
    fs.writeFileSync(file, orig.replace(from, to));
    return body();
  } finally { fs.writeFileSync(file, orig); }
}

// ---- M1: undo the call-site branch ------------------------------------------
withPatched(REFINE,
  '                r.background = o.background is Array\n                    ? Fill.fromArray(o.background as Array)\n                    : Fill.fromAny(o.background);',
  '                r.background = Fill.fromAny(o.background);',
  () => {
    const r = runCheck();
    const crashed = /3221225477|0xC0000005|STATUS_ACCESS_VIOLATION/.test(r.out) || r.code !== 0;
    record('M1 unconditional Fill.fromAny -> red (crash)', crashed,
      'exit=' + r.code + (String(r.code) === '0' ? ' (WANTED non-zero: the branch is not what saves us)' : ''));
  });

// ---- M2: make the scalar path vacuous ---------------------------------------
withPatched(FILL,
  'if (o is Number) return solid(Number(o));',
  'if (false) return solid(Number(o));',
  () => {
    const r = runCheck();
    const named = /FAIL\s+scalar background still yields an opaque solid fill/.test(r.out);
    record('M2 Fill.fromAny never solid -> red (the scalar check is real)', r.code !== 0 && named,
      'exit=' + r.code + (named ? ' + the scalar assertion FAILED' : ' but the scalar assertion did not name the failure'));
  });

// ---- restore verification ---------------------------------------------------
const restored = before.refine === sha(REFINE) && before.fill === sha(FILL);
console.log('');
for (const r of results) console.log((r.ok ? 'MUTATION PASS  ' : 'MUTATION FAIL  ') + r.name + '   [' + r.detail + ']');
console.log('restore: ' + (restored ? 'StyleRefinement.as + Fill.as byte-identical' : 'TAMPERED'));
const bad = results.filter((r) => !r.ok).length + (restored ? 0 : 1);
console.log('');
console.log('MUTATION: ' + (bad === 0 ? 'PASS (' + results.length + '/' + results.length + ')' : 'FAIL (' + bad + ' problem(s))'));
process.exit(bad === 0 ? 0 : 1);
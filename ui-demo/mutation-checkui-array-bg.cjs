// mutation-checkui-array-bg.cjs -- prove the new array-`background` checks in
// CheckUi.as can FAIL, i.e. that they are not decoration.
//
// Two independent mutations, each undoing ONE half of the nail:
//
//   M1  make Fill.fromAny treat an ARRAY as a solid BLACK fill -- i.e. break the
//       branch that now lives INSIDE fromAny. Until 2026-10-23 that branch lived at
//       the StyleRefinement call site and the same undo killed the process
//       (0xC0000005), so a non-zero exit was enough evidence. The revert moved the
//       dispatch into fromAny and G14 is fixed (compiler 阶段二百五十三), so the
//       observable is now a VALUE, not a crash: this mutation must be caught by
//       NAME ('array background yields no fill' + 'Fill.fromAny(Array) itself
//       yields no fill'), not merely by an exit code. If it is not named, the
//       assertions are decoration.
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
// REFINE is intentionally NOT mutated any more: the call site no longer branches
// (the revert moved the dispatch into fromAny), so mutating it could only re-test
// fromAny from a distance. It is kept as a path so the header above can point at
// where the branch used to be.

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const before = { fill: sha(FILL) };

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

// ---- M1: break the array branch inside fromAny --------------------------------
withPatched(FILL,
  '            if (o is Array) return fromArray(o as Array);',
  '            if (o is Array) return solid(0x000000);',
  () => {
    const r = runCheck();
    const named = /FAIL\s+array background yields no fill/.test(r.out)
      && /FAIL\s+Fill\.fromAny\(Array\) itself yields no fill/.test(r.out);
    record('M1 an Array treated as a solid fill -> named red', r.code !== 0 && named,
      'exit=' + r.code + (named ? ' + both array assertions FAILED by name' : ' but the array assertions did not name the failure'));
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
const restored = before.fill === sha(FILL);
console.log('');
for (const r of results) console.log((r.ok ? 'MUTATION PASS  ' : 'MUTATION FAIL  ') + r.name + '   [' + r.detail + ']');
console.log('restore: ' + (restored ? 'Fill.as byte-identical' : 'TAMPERED'));
const bad = results.filter((r) => !r.ok).length + (restored ? 0 : 1);
console.log('');
console.log('MUTATION: ' + (bad === 0 ? 'PASS (' + results.length + '/' + results.length + ')' : 'FAIL (' + bad + ' problem(s))'));
process.exit(bad === 0 ? 0 : 1);
// mutation.cjs -- proves run.cjs has TEETH: it re-introduces the G13 defect in the
// COMPILER and checks that the probe goes red.
//
// Post-fix the defect can no longer be produced from the input side: the earlier
// version of this file added `var leftover:Leaf;` to Main.as to drag Leaf into the
// main loop, which only worked BECAUSE the forced-file pass never expanded it.
// Now the fix has to be undone directly. Two mutations, because the fix has two
// load-bearing halves:
//
//   M1  "mark without expanding" -- in the forced files' non-class pass, put back
//       `reachable.add(n)` where the fix uses `enqueue(n)`. Leaf is then reached
//       and emitted, but its `extends Base` and `new Helper()` are never followed.
//   M2  "expand before seeding" -- move the two forced-file passes back AFTER the
//       fixed-point loop, i.e. the original order. What they enqueue is never
//       drained. Same observable failure, different half of the fix.
//
// Each mutation is reverted in a `finally` and the revert is verified by hash: a
// harness that silently leaves a mutant behind would poison every later run.
//
// Usage:  node probes/reach-freefn/mutation.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const UI = path.resolve(__dirname, '..', '..');
const REACH = path.resolve(UI, '..', 'as3compiler', 'src', 'reach.ts');
const original = fs.readFileSync(REACH, 'utf8');
const hash = (s) => crypto.createHash('sha256').update(s).digest('hex').slice(0, 16);

// Anchors. Both are asserted to exist before mutating, so a reshaped reach.ts
// fails loudly here instead of silently mutating nothing.
const SEED_MARK = '  // Every seed must be in the queue BEFORE';
const LOOP_MARK = '  while (queue.length > 0) {';
const FORCED_NONCLASS_MARK = '  // The forced files\' non-class code too:';
const KEPT_MARK = '  const kept =';

function requireAnchors(text) {
  for (const m of [SEED_MARK, LOOP_MARK, FORCED_NONCLASS_MARK, KEPT_MARK]) {
    if (text.indexOf(m) < 0) throw new Error('anchor not found: ' + JSON.stringify(m));
  }
}

const mutations = [
  {
    id: 'M1',
    label: 'forced pass marks reachable instead of enqueueing',
    apply(text) {
      const at = text.indexOf(FORCED_NONCLASS_MARK);
      const head = text.slice(0, at);
      const body = text.slice(at);
      if (body.indexOf('      enqueue(n);') < 0) throw new Error('M1 anchor `enqueue(n)` not found in the forced pass');
      return head + body.replace('      enqueue(n);', '      reachable.add(n);');
    },
  },
  {
    id: 'M2',
    label: 'forced passes moved back after the fixed-point loop',
    apply(text) {
      const start = text.indexOf(SEED_MARK);
      const end = text.indexOf(LOOP_MARK);
      if (start < 0 || end < 0 || end <= start) throw new Error('M2 block boundaries not found');
      const block = text.slice(start, end);
      const without = text.slice(0, start) + text.slice(end);
      const keptAt = without.indexOf(KEPT_MARK);
      return without.slice(0, keptAt) + block + without.slice(keptAt);
    },
  },
];

let code = 1;
try {
  requireAnchors(original);
  let failed = 0;
  for (const m of mutations) {
    const mutant = m.apply(original);
    if (mutant === original) throw new Error(m.id + ': mutation did not change the file');
    fs.writeFileSync(REACH, mutant);
    console.log('mutator: ' + m.id + ' -- ' + m.label);
    console.log('mutator: reach.ts  ' + hash(original) + ' -> ' + hash(mutant));
    console.log('');
    try {
      const r = spawnSync(process.execPath, [path.join(__dirname, 'run.cjs')], {
        cwd: UI, encoding: 'utf8', maxBuffer: 1 << 28,
      });
      const out = (r.stdout || '') + (r.stderr || '');
      console.log(out);
      const red = r.status !== 0;
      if (!red) { failed++; console.log('mutator: ' + m.id + ' *** run.cjs stayed GREEN -- probe has no teeth here ***'); }
      else console.log('mutator: ' + m.id + ' -> run.cjs went RED (as required)');
    } finally {
      fs.writeFileSync(REACH, original);
      const back = fs.readFileSync(REACH, 'utf8');
      console.log('mutator: reach.ts restored  ' + hash(back) + (back === original ? '  (identical)' : '  *** MISMATCH ***'));
      if (back !== original) { failed++; }
      console.log('');
    }
  }
  code = failed === 0 ? 0 : 1;
  console.log(code === 0
    ? '==== MUTATION: PASS -- both mutants make the probe go red (' + mutations.length + '/' + mutations.length + ') ===='
    : '==== MUTATION: FAIL -- ' + failed + ' mutant(s) left the probe green ====');
} catch (e) {
  console.error('mutator error: ' + e.message);
  code = 1;
} finally {
  // Belt and braces: the per-mutation finally above already restored it, but a
  // throw before the loop would otherwise leave the mutant on disk.
  if (fs.readFileSync(REACH, 'utf8') !== original) {
    fs.writeFileSync(REACH, original);
    console.log('mutator: reach.ts force-restored  ' + hash(original));
  }
}
process.exit(code);
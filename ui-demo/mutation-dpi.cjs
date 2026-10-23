// mutation-dpi.cjs -- proves check-dpi.cjs has TEETH.
//
// check-dpi.cjs claims: "<requestedDisplayResolution>high is what makes this demo
// render at the display's real resolution". The cheapest way to attack that claim is
// to make the two descriptors IDENTICAL -- flip the control arm from `standard` to
// `high` -- and see whether the assertions notice. If check-dpi still reported PASS,
// its A/B would be decoration: two builds that agree because nothing distinguishes
// them, not because the descriptor is causal.
//
// Only the workflow is reversed here, never the checker: the mutation edits
// air-gallery-standard/app.xml (the input), runs check-dpi.cjs unmodified, and
// requires it to go RED. The descriptor is restored in a `finally` and the restore is
// verified by hash -- a mutation harness that leaves the mutant behind would poison
// every later run, and this one leaves a COMMITTED descriptor, not a scratch file.
//
// Usage:  node mutation-dpi.cjs      (~3 min: both arms are rebuilt)
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const { initialWindowBlock } = require('./air-run.cjs');

const TARGET = path.join(__dirname, 'air-gallery-standard', 'app.xml');
const original = fs.readFileSync(TARGET, 'utf8');
const hash = (s) => crypto.createHash('sha256').update(s).digest('hex').slice(0, 16);

// The one setting that separates the two arms. Flipping it makes the control arm the
// same experiment as the treatment arm.
//
// The splice uses the offsets from the shared initialWindowBlock() reader, which
// blanks XML comments first: the descriptor QUOTES markup inside its own comment
// ("...except ONE line -- requestedDisplayResolution ..."), and a plain replace() hits
// the prose. The first version of this file did exactly that -- the comment flipped,
// the real tag did not, and the probe went red for a reason other than the intended
// one. A mutation that does not mutate what it names is worse than no mutation: it
// certifies the wrong thing.
const win = initialWindowBlock(TARGET);
if (!win) throw new Error('no <initialWindow> in ' + TARGET);
const mutantBlock = win.block.replace('>standard<', '>high<');
const mutant = original.slice(0, win.start) + mutantBlock + original.slice(win.end);

let code = 1;
try {
  if (mutantBlock === win.block) throw new Error('mutation did not apply (no >standard< inside <initialWindow>)');
  if (mutant === original) throw new Error('mutation did not change the file');
  if (!/^\s*<requestedDisplayResolution>high<\/requestedDisplayResolution>\s*$/m.test(mutantBlock)) {
    throw new Error('the mutated block does not say high - refusing to run an ambiguous mutation');
  }
  if (!/^\s*<requestedDisplayResolution>standard<\/requestedDisplayResolution>\s*$/m.test(win.block)) {
    throw new Error('the unmutated block does not say standard - refusing to run an ambiguous mutation');
  }
  fs.writeFileSync(TARGET, mutant);
  console.log('mutator: air-gallery-standard/app.xml  ' + hash(original) + ' -> ' + hash(mutant));
  console.log('mutator: control arm is now requestedDisplayResolution=high (both arms identical)');
  console.log('');

  const r = spawnSync(process.execPath, [path.join(__dirname, 'check-dpi.cjs')], {
    cwd: __dirname, encoding: 'utf8', maxBuffer: 1 << 28,
  });
  const out = (r.stdout || '') + (r.stderr || '');
  // Print only the A/B table and the verdict; the two builds' logs are noise here.
  console.log(out.split(/\r?\n/).filter((l) => /tour text|^(  (HIGH|STANDARD)|RESULT|  )|\bFAIL\b/.test(l)).join('\n'));
  code = r.status === 0 ? 1 : 0;   // RED is the point: exit 0 here would be a broken mutator
  console.log('');
  console.log(code === 0
    ? '==== MUTATION: PASS -- the mutant makes check-dpi go red (check-dpi has teeth) ===='
    : '==== MUTATION: FAIL -- check-dpi stayed green with both arms identical ====');
} catch (e) {
  console.error('mutator error: ' + e.message);
  code = 1;
} finally {
  fs.writeFileSync(TARGET, original);
  const back = fs.readFileSync(TARGET, 'utf8');
  console.log('mutator: air-gallery-standard/app.xml restored  ' + hash(back) + (back === original ? '  (identical)' : '  *** MISMATCH ***'));
  if (back !== original) code = 1;
}
process.exit(code);
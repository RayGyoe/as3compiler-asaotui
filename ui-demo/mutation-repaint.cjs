// mutation-repaint.cjs -- proves run-repaint-diff.cjs has TEETH.
//
// The gate claims: "a decoration-only frame paints exactly what a full repaint of the
// same state would paint". A differential like that can be green for two worthless
// reasons -- the change never reaches the screen (so there is nothing to compare), or
// the incremental pass repaints everything anyway (so the two pictures agree by
// construction). Each mutation below breaks ONE of those links and the gate must go
// RED; every file is restored in a `finally` and the restore is verified by sha256.
//
// Only the KIT is mutated, never the gate: the gate runs unmodified, and what has to
// change is its verdict.
//
// Usage:  node mutation-repaint.cjs           (all three, ~4 min: three rebuilds)
//         node mutation-repaint.cjs m2        (just one)
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const UI = __dirname;
const ROOT = path.resolve(UI, '..');
const KIT = path.join(ROOT, 'kit', 'asaot', 'ui');
const BAK = path.join(ROOT, 'temp', 'mut-backup');

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const MUTATIONS = {
  // m1 -- THE DIRTY CLASSIFICATION. Drop `opacity` from the paint-only bucket in
  // Style.diffFlags: an opacity change then raises NO dirty bit, so nothing repaints.
  // Both pictures are still "valid", it is the comparison that sees it.
  m1: {
    file: path.join(KIT, 'style', 'Style.as'),
    old: '|| !cornersEq(prev.cornerRadii, cur.cornerRadii) || !numEq(prev.opacity, cur.opacity)',
    new: '|| !cornersEq(prev.cornerRadii, cur.cornerRadii)',
    expect: 'FAIL 18/20 -- scenarios 3 and 4 diverge (opacity never repaints)',
  },
  // m2 -- THE WALK. paintDirty stops descending into children, so only a node that
  // carries M_PAINT at the ROOT is ever repainted. Child-only changes go stale, and
  // the leftover-bit assertion fires with them.
  m2: {
    file: path.join(KIT, 'UiApp.as'),
    old: '            for (var i:int = 0; i < n.children.length; i++) paintDirty(n.children[i]);',
    new: '            // MUTATION: no descent into children.',
    expect: 'FAIL 14/20 -- scenarios 2/3/4 diverge; scenario 1 survives (root change)',
  },
  // m3 -- THE HISTORIC BUG, VERBATIM. The decoration-only branch paints nothing at
  // all: the M_PAINT bits are never consumed and the change never reaches the screen
  // (the state UiApp.as documents around the `else if (wantsPaint || reconciled)`
  // branch). The frame still COUNTS a paint pass, so only the pictures can catch it.
  m3: {
    file: path.join(KIT, 'UiApp.as'),
    old: `                if (this.root != null) paintDirty(this.root);
                if (this.overlayRoot != null) paintDirty(this.overlayRoot);`,
    new: '                // MUTATION: paint nothing.',
    expect: 'FAIL 12/20 -- ALL four scenarios diverge (the screen stays stale)',
  },
};

// The kit sources are a mix of LF and CRLF (UiApp.as is LF, Style.as is too), so a
// multi-line anchor is re-encoded to whichever the file uses. An anchor written with
// the wrong line ending matches 0 times, and "0 times" must never be silently
// tolerated: the first version of this file reported a mutation as "survived" when
// the patch had simply not applied.
function patch(p, oldText, newText) {
  const src = fs.readFileSync(p, 'utf8');
  const crlf = src.includes('\r\n');
  const oldT = crlf ? oldText.replace(/\r?\n/g, '\r\n') : oldText;
  const newT = crlf ? newText.replace(/\r?\n/g, '\r\n') : newText;
  const hits = src.split(oldT).length - 1;
  if (hits !== 1) throw new Error('mutation anchor matched ' + hits + ' times in ' + p);
  fs.writeFileSync(p, src.split(oldT).join(newT), 'utf8');
}

function run(id) {
  const m = MUTATIONS[id];
  fs.mkdirSync(BAK, { recursive: true });
  const before = sha(m.file);
  const backup = path.join(BAK, id + '-' + path.basename(m.file));
  fs.copyFileSync(m.file, backup);
  console.log('== ' + id + ': ' + path.relative(ROOT, m.file) + ' ' + before.slice(0, 12));
  console.log('   expects: ' + m.expect);

  let out = '';
  try {
    patch(m.file, m.old, m.new);
    const r = spawnSync(process.execPath, ['run-repaint-diff.cjs'], {
      cwd: UI, encoding: 'utf8', timeout: 600000,
      env: { ...process.env, ASC_CC: process.env.ASC_CC || 'clang' },
    });
    out = (r.stdout || '') + (r.stderr || '');
  } finally {
    fs.copyFileSync(backup, m.file);
    const after = sha(m.file);
    if (after !== before) throw new Error('RESTORE FAILED for ' + m.file);
    console.log('   restored: IDENTICAL ' + after.slice(0, 12));
  }

  const verdict = (out.match(/REPAINT-DIFF: .*/, ) || ['<no verdict>'])[0];
  console.log('   ' + verdict);
  for (const line of out.split(/\r?\n/)) if (/^\s+FAIL /.test(line)) console.log('   ' + line.trim());
  const caught = /GATE FAIL/.test(out);
  console.log('   => ' + (caught ? 'MUTATION CAUGHT' : '*** MUTATION SURVIVED ***'));
  return caught ? 0 : 1;
}

const arg = process.argv[2];
const ids = arg ? [arg] : Object.keys(MUTATIONS);
let bad = 0;
for (const id of ids) {
  if (!MUTATIONS[id]) { console.error('unknown mutation: ' + id); process.exit(2); }
  bad += run(id);
}
console.log(bad === 0 ? '\nALL MUTATIONS CAUGHT' : '\n' + bad + ' MUTATION(S) SURVIVED');
process.exit(bad === 0 ? 0 : 1);

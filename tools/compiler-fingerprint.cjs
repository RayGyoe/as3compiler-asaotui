// compiler-fingerprint.cjs -- prove the compiler tree did not change under us.
//
// WHY: this workspace builds a UI toolkit WITHOUT touching the compiler repo.
// "I did not change it" is not evidence; a hash per file is. `--capture` records
// HEAD + every path git reports as dirty, with size + sha256/16; running it again
// later compares against that snapshot and fails loudly on any drift.
//
// Usage:
//   node tools/compiler-fingerprint.cjs --capture     # (re)write reviews/compiler-tree-fingerprint.json
//   node tools/compiler-fingerprint.cjs               # verify against it (exit 1 on drift)
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { execFileSync } = require('child_process');

const UI = path.resolve(__dirname, '..');
const REPO = path.resolve(UI, '..', 'as3compiler');
const SNAP = path.join(UI, 'reviews', 'compiler-tree-fingerprint.json');

// NOTE: the raw git output is NOT trimmed here. Trimming the whole buffer eats the
// leading space of a first line like " M src/reach.ts" (XY = " M" = modified in the
// worktree), which shifts every field by one and makes the path parse as
// "rc/reach.ts" -- a file that does not exist, so the entry was silently DROPPED.
// That is how this tool under-reported today: `M src/reach.ts` (the file the whole
// exercise is about) was invisible while `test/unit/reach.ts` was listed.
const git = (...args) => execFileSync('git', ['-C', REPO, ...args], { encoding: 'utf8' });
const sha16 = (f) => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex').slice(0, 16);

// Parse `git status --porcelain -z`. NUL-separated means git never quotes or escapes
// a path, so `XY SP <path>` can be sliced at fixed offsets -- which is the property
// the old line-based + trimmed form quietly lacked. A record that does not look like
// that shape is a rename source (a bare path); `-z` is NUL-separated, so those are
// skipped safely -- but anything else is reported as an ERROR rather than dropped.
// Under-reporting an instrument is worse than no instrument: it certifies the wrong
// thing, and today it certified a tree state that was not the one on disk.
function parsePorcelainZ(out) {
  const entries = [];
  const bad = [];
  for (const rec of out.split('\u0000')) {
    if (rec === '') continue;
    if (rec.length < 4 || rec[2] !== ' ') { bad.push(rec); continue; }
    entries.push({ code: rec.slice(0, 2), f: rec.slice(3) });
  }
  return { entries, bad };
}

function snapshot() {
  const head = git('log', '-1', '--format=%H %cd').trim();
  const { entries, bad } = parsePorcelainZ(git('status', '--porcelain', '-z'));
  const files = [];
  const skipped = [];
  for (const { code, f } of entries) {
    const abs = path.join(REPO, f);
    if (!fs.existsSync(abs) || fs.statSync(abs).isDirectory()) { skipped.push(code + f); continue; }
    files.push({ code, f, size: fs.statSync(abs).size, sha256_16: sha16(abs), mtime: fs.statSync(abs).mtime.toISOString() });
  }
  const treeFingerprint = crypto.createHash('sha256')
    .update(head + '\n' + files.map((x) => x.code + x.f + x.size + x.sha256_16).join('\n'))
    .digest('hex').slice(0, 20);
  return { capturedAt: new Date().toISOString(), head, files, treeFingerprint, bad, skipped };
}

module.exports = { parsePorcelainZ };

if (require.main !== module) return;

const now = snapshot();
// Loud, not silent: an unparsable porcelain record used to be dropped on the floor.
if (now.bad.length) {
  console.log('UNPARSABLE git status records (' + now.bad.length + ') -- refusing to report on a tree I cannot read:');
  for (const b of now.bad) console.log('  ' + JSON.stringify(b));
  process.exit(2);
}
if (now.skipped.length) {
  // These are REAL working-tree changes (deleted/renamed paths) that cannot be hashed.
  // Printing them as a bare note while the summary said "N files" once made a tree with
  // 352 deletions read as "1 file dirty" -- so they are counted in the summary too.
  console.log('note: ' + now.skipped.length + ' dirty entry/entries point at paths that are gone (deleted/renamed);'
    + ' they cannot be hashed and are NOT in the file list below. First 5: '
    + now.skipped.slice(0, 5).join(', ') + (now.skipped.length > 5 ? ' ...' : ''));
}
if (process.argv.includes('--capture')) {
  fs.writeFileSync(SNAP, JSON.stringify(now, null, 2) + '\n');
  console.log('captured ' + now.files.length + ' dirty files, head ' + now.head.split(' ')[0]);
  console.log('  ' + now.files.map((x) => x.code + ' ' + x.f).join('\n  '));
  console.log('treeFingerprint ' + now.treeFingerprint);
  process.exit(0);
}

if (!fs.existsSync(SNAP)) { console.log('no snapshot at ' + SNAP + ' -- run --capture first'); process.exit(2); }
const was = JSON.parse(fs.readFileSync(SNAP, 'utf8'));
const problems = [];
if (was.head !== now.head) problems.push('HEAD moved: ' + was.head + ' -> ' + now.head);
if (was.treeFingerprint !== now.treeFingerprint) {
  problems.push('treeFingerprint ' + was.treeFingerprint + ' -> ' + now.treeFingerprint);
  const a = new Map(was.files.map((x) => [x.f, x]));
  const b = new Map(now.files.map((x) => [x.f, x]));
  for (const [f, x] of b) if (!a.has(f)) problems.push('  NEW dirty file: ' + f);
  for (const [f, x] of a) if (!b.has(f)) problems.push('  file no longer dirty: ' + f);
  for (const [f, x] of a) {
    const y = b.get(f);
    if (!y) continue;
    if (x.sha256_16 !== y.sha256_16) problems.push('  content changed: ' + f + '  ' + x.sha256_16 + ' -> ' + y.sha256_16);
    else if (x.code !== y.code) problems.push('  status changed: ' + f + '  "' + x.code + '" -> "' + y.code + '"');
  }
}
console.log('snapshot ' + was.capturedAt + '  head ' + was.head.split(' ')[0] + '  ' + was.files.length + ' files'
  + (was.skipped && was.skipped.length ? ' + ' + was.skipped.length + ' deleted/renamed' : ''));
console.log('now      ' + now.capturedAt + '  head ' + now.head.split(' ')[0] + '  ' + now.files.length + ' files'
  + (now.skipped.length ? ' + ' + now.skipped.length + ' deleted/renamed' : ''));
if (problems.length) {
  console.log('COMPILER TREE CHANGED SINCE THE SNAPSHOT:');
  for (const p of problems) console.log('  ' + p);
  // This tool answers "did the compiler tree move", NOT "did we move it". On this
  // machine another session edits -- and commits to -- the compiler repo, so a bare
  // 'DRIFTED' reads like an accusation. Split it into the two things it actually
  // distinguishes, because they mean very different things for this workspace.
  const newDirty = problems.filter((p) => /NEW dirty file/.test(p));
  const dirtyNow = now.files.length > 0 || now.skipped.length > 0;
  const clean = !dirtyNow;
  if (clean) {
    console.log('');
    console.log('  -> the working tree is CLEAN right now (0 modified/untracked/deleted files), so');
    console.log('     the difference is entirely in HEAD -- i.e. someone COMMITTED (expected: the');
    console.log('     concurrent session upstream). A clean tree is the strongest form of "this');
    console.log('     workspace wrote nothing here"; see the log line above for what moved.');
  } else {
    console.log('');
    console.log('  -> the working tree is DIRTY (' + now.files.length + ' modified/untracked'
      + (now.skipped.length ? ' + ' + now.skipped.length + ' deleted/renamed' : '') + '): read the list above.');
    console.log('     If none of them is a file this workspace\'s tools write, it is the concurrent');
    console.log('     session\'s uncommitted work, not ours.' + (newDirty.length ? ' Includes NEW dirty file(s).' : ''));
  }
  process.exit(1);
}
console.log('compiler tree UNCHANGED -- ' + was.files.length + ' dirty files, byte-for-byte');
process.exit(0);

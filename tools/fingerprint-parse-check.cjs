// fingerprint-parse-check.cjs -- pins the one thing that made
// tools/compiler-fingerprint.cjs lie: parsing `git status --porcelain`.
//
// THE BUG (found 2026-10-23, by hand): the tool ran
//     execFileSync('git', [...]).trim()
// and then sliced each line at fixed offsets (XY at 0..1, path at 3..). `.trim()`
// strips whitespace from the WHOLE buffer, and the first line of a worktree-only
// modification is " M src/reach.ts" -- one leading space. Trim removed it, every
// field shifted one left, the path parsed as "rc/reach.ts", `existsSync` said no,
// and the entry was dropped WITHOUT A WORD. `src/reach.ts` -- the file the whole
// G13 exercise is about -- was invisible while its sibling was listed.
//
// An instrument that under-reports is worse than no instrument: it certifies the
// wrong thing. So this check pins the parser against every porcelain shape a
// shared worktree produces, including the two-space form that git emits for a
// STAGED change (`M  x`), which is the very shape the broken version hallucinated.
//
// Usage:  node tools/fingerprint-parse-check.cjs      # exit 0 iff all checks pass

'use strict';

const { parsePorcelainZ } = require('./compiler-fingerprint.cjs');

const fails = [];
function check(ok, label, detail) {
  console.log((ok ? '  ok   ' : '  FAIL ') + label);
  if (!ok) fails.push(label + (detail ? ' -- ' + detail : ''));
}

const z = (...paths) => paths.join('\u0000');

// Every one of these must survive with its path intact. The first entry of each
// case is the one that used to be eaten.
const cases = [
  ['worktree-modified first (the one that was dropped)', z(' M src/reach.ts', ' M test/unit/reach.ts', '?? icudtl.dat'),
    [' M|src/reach.ts', ' M|test/unit/reach.ts', '??|icudtl.dat']],
  ['staged-modified first (two spaces = the real `M  x` shape)', z('M  src/reach.ts', '?? icudtl.dat'),
    ['M |src/reach.ts', '??|icudtl.dat']],
  ['both staged and worktree (MM)', z('MM src/a.ts', 'A  src/b.ts'),
    ['MM|src/a.ts', 'A |src/b.ts']],
  ['deleted + untracked (deleted path is gone, so it is skipped -- but must be SEEN)', z(' D src/gone.ts', '?? new.txt'),
    [' D|src/gone.ts', '??|new.txt']],
  ['path with an interior space', z('M  src/two words.as'),
    ['M |src/two words.as']],
];

for (const [label, out, want] of cases) {
  const { entries, bad } = parsePorcelainZ(out);
  const got = entries.map((e) => e.code + '|' + e.f);
  check(got.length === want.length, label + ': every record survives', 'got ' + JSON.stringify(got));
  check(got.every((g, i) => g === want[i]), label + ': paths are not shifted',
    'want ' + JSON.stringify(want) + ' got ' + JSON.stringify(got));
  check(bad.length === 0, label + ': nothing reported as unparsable', JSON.stringify(bad));
}

// The empty status (a clean tree) must produce zero entries, not one blank one.
{
  const { entries, bad } = parsePorcelainZ('');
  check(entries.length === 0 && bad.length === 0, 'clean tree: no entries, no complaints',
    JSON.stringify({ entries, bad }));
}

// A rename emits the NEW path as a normal record and the OLD path as a bare record.
// The bare one has no `XY ` prefix, so it must land in `bad` (reported), never be
// silently sliced into a nonsense path.
{
  const { entries, bad } = parsePorcelainZ(z('R  src/new.as', 'src/old.as'));
  check(entries.length === 1 && entries[0].f === 'src/new.as', 'rename: new path parsed',
    JSON.stringify(entries));
  check(bad.length === 1 && bad[0] === 'src/old.as', 'rename: old path reported, not invented',
    JSON.stringify(bad));
}

// Guard against a regression to the exact old shape: a leading space must never be
// lost. This is the assertion that would have caught the bug the day it was written.
{
  const { entries } = parsePorcelainZ(z(' M src/reach.ts'));
  check(entries.length === 1 && entries[0].f === 'src/reach.ts',
    'regression guard: leading-space record keeps its full path', JSON.stringify(entries));
  check(entries[0] && entries[0].code === ' M', 'regression guard: XY keeps BOTH characters',
    JSON.stringify(entries));
}

console.log('');
if (fails.length) {
  console.log('==== FINGERPRINT PARSE: FAIL (' + fails.length + ') ====');
  for (const f of fails) console.log('  ' + f);
  process.exit(1);
}
console.log('==== FINGERPRINT PARSE: PASS -- porcelain parsing keeps every record, paths unshifted ====');

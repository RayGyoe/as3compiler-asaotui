// air-sdk.cjs -- the ONE place that answers "where is the AIR SDK on this box".
//
// WHY ONE PLACE: four tools asked this question and each had its own answer
// (`sdkFromPath()` twice, `airSdkRoot()` in gates.cjs, and a bash copy in
// ui-demo/air-gallery/build.sh). All four asked the ENVIRONMENT -- AIRSDK_HOME,
// then PATH -- and none of them looked at where an SDK is actually installed. On
// the dev box the SDK sat in ~/Documents/Software/AIRSDK/AIRSDK_51.4.1 with a
// STALE `.../AIRSDK_51.2.1/bin` on PATH, so every one of them answered "no SDK"
// and nine gates reported SKIP while the reference runtime was two `ls` calls
// away. "Not on PATH" is not "not installed".
//
// THE RULE (the same one bin-aot/build-aot.sh uses to find the compiler): ask the
// environment first, then SEARCH A BOUNDED LIST OF INSTALL LOCATIONS, and accept a
// hit only after VERIFYING it structurally -- a directory is an SDK root when it
// has bin/ holding a launcher THIS HOST CAN RUN. A name match is a hint, never a
// proof: the Harman SDK ships `adl`, `adl.exe`, `adl_linux64` and
// `adl_linux_arm64` in the same bin/, so `fs.existsSync(bin/adl)` on Windows and
// `-x bin/adl` on POSIX are different questions and the first one answers "yes"
// on the wrong machine.
//
// USAGE (from asaotui/, or programmatically):
//   node tools/air-sdk.cjs            print the root, exit 0 (3 if none)
//   node tools/air-sdk.cjs --print    same, for shell callers
//   node tools/air-sdk.cjs --json     {root,mxmlc,adl,source,notes}
//   node tools/air-sdk.cjs --why      every location tried, in order, and why it lost
//
// Env: AIRSDK_HOME (explicit root), ASC_NO_AIR_SCAN=1 (env+PATH only, no search).
'use strict';

const fs = require('fs');
const path = require('path');

const WIN = process.platform === 'win32';
const HOME = process.env.HOME || process.env.USERPROFILE || '';
const UI = path.resolve(__dirname, '..');

// POSIX: bin/mxmlc is a shell script and must be EXECUTABLE. Windows: bin/mxmlc.bat.
// The lists are DISJOINT on purpose. The SDK is one zip for every platform, so a
// mixed list ("mxmlc, else mxmlc.bat") looks harmless and is not: a Windows-only
// tree unzipped on macOS has bin/mxmlc.bat, and a 0755 .bat passes `access(X_OK)`
// even though no POSIX shell can run it. Measured: that is exactly how the fixture
// "a directory named AIRSDK_60.0 holding only adl.exe + mxmlc.bat" was reported as
// a usable SDK. The HOST decides the spelling, never the found filename.
const LAUNCHERS = WIN ? { mxmlc: ['mxmlc.bat', 'mxmlc.exe'], adl: ['adl.exe'] }
  : { mxmlc: ['mxmlc'], adl: ['adl'] };

function isLauncher(p) {
  try {
    if (!fs.statSync(p).isFile()) return false;
    if (WIN) return true;
    fs.accessSync(p, fs.constants.X_OK);
    return true;
  } catch (e) {
    return false;
  }
}

// A path that cannot exist here is the most common shape of "found an SDK": a
// Windows root inherited from a shell profile or a committed default. Say it,
// instead of letting it fall through as a plain miss.
function foreignPath(p) {
  if (WIN) return /^\/[A-Za-z](\/|$)/.test(p) || /^\/mnt\//.test(p);
  return /^[A-Za-z]:[\\/]/.test(p);
}

function inspect(root) {
  const bin = path.join(root, 'bin');
  const pick = (names) => names.map((n) => path.join(bin, n)).find(isLauncher) || null;
  const mxmlc = pick(LAUNCHERS.mxmlc);
  const adl = pick(LAUNCHERS.adl);
  return { root, bin, mxmlc, adl, usable: mxmlc !== null, complete: mxmlc !== null && adl !== null };
}

// Version rank of a directory NAME, so `AIRSDK_51.4.1` beats `AIRSDK_51.2.1` and a
// stale install never wins over the current one. Non-numeric names rank lowest.
function versionOf(p) {
  const nums = (path.basename(p).match(/\d+/g) || []).map(Number);
  return nums;
}
function newer(a, b) {
  const va = versionOf(a); const vb = versionOf(b);
  for (let i = 0; i < Math.max(va.length, vb.length); i++) {
    const d = (va[i] === undefined ? -1 : va[i]) - (vb[i] === undefined ? -1 : vb[i]);
    if (d !== 0) return d;
  }
  return 0;
}

// Where an SDK actually gets installed. ONE level deep per parent, plus one more
// level inside a name that matches -- `~/Documents/Software/AIRSDK/AIRSDK_51.4.1`
// is the layout on the dev box, and `~/AIRSDK_51.4.1` is the flat one. Deliberately
// a short list of parents rather than a walk of $HOME: a filesystem walk that finds
// the SDK by accident also finds it in a backup, an unzip under Downloads, and a
// half-extracted zip whose bin/ is missing -- and "found something named AIRSDK" is
// exactly the false positive the structural check exists to reject.
//
// ASC_AIR_SDK_SEARCH_DIRS (path-delimiter separated) goes FIRST, so an SDK installed
// somewhere unusual is named rather than hunted for. It is also the seam the resolver's
// own gate uses: a fixture tree in temp/ can be graded without mocking the filesystem.
function parents() {
  const extra = (process.env.ASC_AIR_SDK_SEARCH_DIRS || '').split(path.delimiter).filter(Boolean);
  const list = [
    ...extra,
    HOME,
    path.join(HOME, 'Documents'),
    path.join(HOME, 'Documents', 'Software'),   // the dev box: .../Software/AIRSDK/AIRSDK_51.4.1
    path.join(HOME, 'Documents', 'AIRSDK'),
    path.join(HOME, 'Software'),
    path.join(HOME, 'Tools'),
    path.join(HOME, 'dev'),
    path.join(HOME, 'Desktop'),
    path.join(HOME, 'Downloads'),
    path.join(HOME, 'Applications'),
    '/Applications',
    '/opt',
    '/usr/local',
    '/usr/local/share',
    UI,                     // a vendored SDK inside the workspace
    path.dirname(UI),
  ];
  const out = [];
  for (const p of list) if (p && fs.existsSync(p) && !out.includes(p)) out.push(p);
  return out;
}

const SDK_NAME = /air[._ -]?sdk/i;

function scan() {
  const found = [];
  const notes = [];
  for (const parent of parents()) {
    let entries;
    try { entries = fs.readdirSync(parent, { withFileTypes: true }); } catch (e) { continue; }
    for (const e of entries) {
      if (!e.isDirectory() || !SDK_NAME.test(e.name)) continue;
      const p = path.join(parent, e.name);
      // `AIRSDK/AIRSDK_51.4.1`: the matching directory is a CONTAINER of versions,
      // so its children are the roots -- and the container itself may also be one.
      let children = [];
      try { children = fs.readdirSync(p, { withFileTypes: true }); } catch (err) { children = []; }
      const inner = children.filter((c) => c.isDirectory() && SDK_NAME.test(c.name))
        .map((c) => path.join(p, c.name));
      if (!inner.length) found.push(p);
      else found.push(...inner);
    }
  }
  // Dedupe on the real path, then prefer the newest and the complete ones.
  const seen = new Set();
  const uniq = [];
  for (const p of found) {
    let real; try { real = fs.realpathSync(p); } catch (e) { continue; }
    if (seen.has(real)) continue;
    seen.add(real);
    uniq.push(real);
  }
  // NOT sorted here: `resolveAirSdk` is the ONE place that ranks (complete first, then
  // newest), and a second sort that agrees with it makes the ranking unmutatable --
  // reversing either one alone would change nothing (measured: M2 stayed green).
  notes.push('scanned ' + parents().length + ' parent dir' + (parents().length === 1 ? '' : 's')
    + ', ' + uniq.length + ' candidate(s)');
  return { roots: uniq, notes };
}

function fromPath() {
  const notes = [];
  const dirs = (process.env.PATH || '').split(path.delimiter).filter(Boolean);
  for (let d of dirs) {
    // WSL spells a Windows drive as /mnt/c/... ; only the Windows form is visible
    // to a Windows node, so translate before looking.
    const m = /^\/mnt\/([A-Za-z])\/(.*)$/.exec(d);
    if (m && WIN) d = m[1].toUpperCase() + ':/' + m[2];
    const root = /[\\/]bin[\\/]?$/.test(d) ? path.dirname(d) : d;
    if (LAUNCHERS.mxmlc.some((n) => isLauncher(path.join(root, 'bin', n)))) {
      notes.push('PATH entry ' + d);
      return { root, notes };
    }
  }
  return { root: null, notes: ['no PATH entry holds bin/' + LAUNCHERS.mxmlc[0]] };
}

// The resolution order, and every step is reported: an explicit root is taken as
// given (and REJECTED loudly if it does not verify, rather than silently replaced
// by something else the search found -- "I asked for THIS SDK" is a different
// intent from "find me one").
function resolveAirSdk(explicit) {
  const tried = [];
  const notes = [];
  const candidates = [];

  if (explicit) {
    const c = inspect(explicit);
    tried.push({ source: '--sdk', root: explicit, ok: c.usable });
    if (!c.usable) {
      return { root: null, mxmlc: null, adl: null, source: '--sdk',
        notes: ['--sdk ' + explicit + ': no runnable bin/' + LAUNCHERS.mxmlc[0]], tried };
    }
    return { ...c, source: '--sdk', notes, tried };
  }

  if (process.env.AIRSDK_HOME) {
    const home = process.env.AIRSDK_HOME;
    const c = inspect(home);
    tried.push({ source: 'AIRSDK_HOME', root: home, ok: c.usable,
      why: foreignPath(home) ? 'this path belongs to another OS' : undefined });
    if (c.usable) return { ...c, source: 'AIRSDK_HOME', notes, tried };
    notes.push('AIRSDK_HOME=' + home + ' does not verify' + (foreignPath(home) ? ' (path for another OS)' : ''));
  }

  const p = fromPath();
  tried.push({ source: 'PATH', root: p.root, ok: p.root !== null });
  notes.push(...p.notes);
  if (p.root) return { ...inspect(p.root), source: 'PATH', notes, tried };

  if (process.env.ASC_NO_AIR_SCAN === '1') {
    notes.push('ASC_NO_AIR_SCAN=1, so the install-location search was skipped');
    return { root: null, mxmlc: null, adl: null, source: 'none', notes, tried };
  }

  const s = scan();
  notes.push(...s.notes);
  for (const root of s.roots) {
    const c = inspect(root);
    tried.push({ source: 'scan', root, ok: c.usable, why: c.usable ? undefined : 'no runnable bin/' + LAUNCHERS.mxmlc[0] });
    if (c.usable) { candidates.push(c); }
  }
  if (candidates.length) {
    // Sorted newest-first already; a complete install (mxmlc AND adl) wins over a
    // half one, because every gate that needs the SDK needs both.
    candidates.sort((a, b) => (b.complete - a.complete) || newer(b.root, a.root));
    const best = candidates[0];
    if (!best.complete) notes.push(best.root + ' has no runnable bin/' + LAUNCHERS.adl[0] + ' (mxmlc only)');
    return { ...best, source: 'scan', notes, tried };
  }
  return { root: null, mxmlc: null, adl: null, source: 'none', notes, tried };
}

function describe(r) {
  if (!r.root) {
    return '[air-sdk] no AIR SDK found. Set AIRSDK_HOME to the SDK root (adl and mxmlc live in'
      + ' <root>/bin), or install one where this search looks: ' + parents().slice(0, 4).join(', ')
      + ', ... (run `node tools/air-sdk.cjs --why` for every location tried).\n'
      + r.notes.map((n) => '         ' + n).join('\n');
  }
  return '[air-sdk] ' + r.root + '  (found via ' + r.source + ')'
    + (r.complete ? '' : '  -- WARNING: mxmlc only, no runnable adl');
}

module.exports = { resolveAirSdk, inspect, describe, parents, LAUNCHERS };

if (require.main === module) {
  const argv = process.argv.slice(2);
  let sdkArg = null;
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--sdk') sdkArg = argv[++i];
    else if (argv[i] === '--print') { /* the default */ }
    else if (argv[i] === '--json' || argv[i] === '--why') { /* handled below */ }
    else { console.error('[air-sdk] unknown argument ' + argv[i]); process.exit(2); }
  }
  const r = resolveAirSdk(sdkArg);
  if (argv.includes('--why')) {
    console.log('[air-sdk] resolution order: --sdk, AIRSDK_HOME, PATH, install-location scan');
    for (const t of r.tried) {
      console.log('  ' + (t.ok ? 'HIT ' : 'miss') + '  ' + (t.source + ' ' + (t.root || '')).trim()
        + (t.why ? '   (' + t.why + ')' : ''));
    }
    for (const n of r.notes) console.log('  note: ' + n);
  }
  if (argv.includes('--json')) console.log(JSON.stringify(r, null, 2));
  else {
    // ALWAYS state the answer on stderr -- a hit says WHERE it came from, a miss says
    // what was tried. `--print` still owns stdout (build.sh does `$(...)` on it).
    console.error(describe(r));
    if (r.root) console.log(r.root);
  }
  process.exit(r.root ? 0 : 3);
}
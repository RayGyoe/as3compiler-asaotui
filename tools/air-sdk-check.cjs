// tools/air-sdk-check.cjs -- the gate on the SDK RESOLVER itself.
//
// WHY: for three rounds nine gates reported SKIP "the AIR reference runtime is not
// installed" while mxmlc compiled the docs app in 1.8 s, because the detection asked
// only AIRSDK_HOME and PATH. A resolver that says "no SDK" is indistinguishable from a
// machine that has none -- so its answer has to be graded like any other instrument,
// on a fixture tree where the right answer is known, and it has to be able to go RED
// (tools/mutation-air-sdk.cjs plants each of the five defects and this must fail).
//
// HERMETIC ON PURPOSE: every case runs in a CHILD process with HOME pointed at the
// fixture and PATH emptied, so the machine's own SDK cannot satisfy a case that the
// fixture was supposed to fail. Grading against the real box would make the gate pass
// for the wrong reason here and red on a machine that has no SDK at all.
//
// The fixture (temp/airsdk-check/, never in the repo tree):
//   a/AIRSDK_51.2.1, a/AIRSDK_51.4.1   two COMPLETE installs, both spellings
//   b/AIRSDK_99.0                      newest NAME, empty bin/ -> not an SDK anywhere
//   c/AIRSDK_60.0                      Windows-only tree (adl.exe + mxmlc.bat)
//   d/AIRSDK_51.3.0                    mxmlc but no adl -> usable, NOT complete
//
// USAGE (from asaotui/):  node tools/air-sdk-check.cjs
// Exit: 0 every case holds; 1 a case failed (the failing line names the case).
'use strict';

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const UI = path.resolve(__dirname, '..');
const ROOT = path.join(UI, 'temp', 'airsdk-check');
const RESOLVER = path.join(__dirname, 'air-sdk.cjs');
const WIN = process.platform === 'win32';
const POSIX = !WIN;

const fails = [];
let n = 0;
function check(name, cond, detail) {
  n++;
  if (cond) { console.log('  ok   ' + name); return; }
  fails.push(name);
  console.log('  FAIL ' + name + (detail ? '\n         ' + detail : ''));
}

// ---- the fixture ------------------------------------------------------------
function launcher(p) {
  fs.writeFileSync(p, WIN ? '@echo off\r\n' : '#!/bin/sh\nexit 0\n');
  if (POSIX) fs.chmodSync(p, 0o755);
}
function sdkRoot(dir, names) {
  const bin = path.join(dir, 'bin');
  fs.mkdirSync(bin, { recursive: true });
  for (const nm of names) launcher(path.join(bin, nm));
  return dir;
}

fs.rmSync(ROOT, { recursive: true, force: true });
fs.mkdirSync(ROOT, { recursive: true });

const A = path.join(ROOT, 'a');
const B = path.join(ROOT, 'b');
const C = path.join(ROOT, 'c');
const D = path.join(ROOT, 'd');
const BOTH = ['mxmlc', 'mxmlc.bat', 'adl', 'adl.exe'];
const OLD = sdkRoot(path.join(A, 'AIRSDK_51.2.1'), BOTH);
const NEW = sdkRoot(path.join(A, 'AIRSDK_51.4.1'), BOTH);
const BROKEN = path.join(B, 'AIRSDK_99.0');
fs.mkdirSync(path.join(BROKEN, 'bin'), { recursive: true });   // newest name, empty bin/
fs.writeFileSync(path.join(BROKEN, 'bin', 'README.txt'), 'half-extracted zip\n');
const WINSH = sdkRoot(path.join(C, 'AIRSDK_60.0'), ['mxmlc.bat', 'adl.exe']);
const HALF = sdkRoot(path.join(D, 'AIRSDK_51.3.0'), WIN ? ['mxmlc.bat'] : ['mxmlc']);

// One case = one child process, running the resolver under a controlled environment
// and printing its result as JSON. No monkey-patching of the module in-process.
function resolve(env, explicit) {
  const code = 'const {resolveAirSdk}=require(' + JSON.stringify(RESOLVER) + ');'
    + 'process.stdout.write(JSON.stringify(resolveAirSdk(process.argv[1] || null)))';
  const e = { HOME: ROOT, PATH: '', ...env };
  const r = spawnSync(process.execPath, ['-e', code, explicit || ''], { encoding: 'utf8', env: e });
  if (r.status !== 0) throw new Error('resolver child failed: ' + (r.stderr || '').trim());
  return JSON.parse(r.stdout);
}
const real = (p) => { try { return fs.realpathSync(p); } catch (e) { return p; } };

console.log('[air-sdk-check] fixture: ' + ROOT);

// 1. The newest COMPLETE install wins over an older complete one. Both are candidates,
//    so this grades the ranking and nothing else.
{
  const r = resolve({ ASC_AIR_SDK_SEARCH_DIRS: A });
  check('scan picks the newest complete install (' + path.basename(NEW) + ' over ' + path.basename(OLD) + ')',
    r.root === real(NEW), 'got ' + r.root);
}

// 2. A name that LOOKS newest is not an SDK: the structural check decides, not the name.
{
  const r = resolve({ ASC_AIR_SDK_SEARCH_DIRS: B });
  check('a directory named ' + path.basename(BROKEN) + ' with an empty bin/ is not an SDK',
    r.root === null, 'got ' + r.root);
}

// 3. The HOST decides the launcher spelling: adl.exe + mxmlc.bat is a Windows SDK.
{
  const r = resolve({ ASC_AIR_SDK_SEARCH_DIRS: C });
  const want = WIN ? real(WINSH) : null;
  check('host launcher rule: a Windows-only tree is ' + (WIN ? 'usable on Windows' : 'rejected on POSIX'),
    r.root === want, 'got ' + r.root + ', wanted ' + want);
}

// 4. mxmlc without adl resolves, but says complete=false -- a gate that needs adl must
//    not be told "the SDK is fine".
{
  const r = resolve({ ASC_AIR_SDK_SEARCH_DIRS: D });
  check('mxmlc without adl resolves with complete=false',
    r.root === real(HALF) && r.complete === false, 'got ' + r.root + ' complete=' + r.complete);
}

// 5. An explicit --sdk that does not verify is REJECTED, never silently replaced by
//    something the search found: "I asked for THIS SDK" is a different request.
{
  const r = resolve({ ASC_AIR_SDK_SEARCH_DIRS: A }, BROKEN);
  check('--sdk <unrunnable> fails instead of falling back to the scan',
    r.root === null && r.source === '--sdk', 'got ' + r.root + ' via ' + r.source);
}

// 6. AIRSDK_HOME wins over the scan when it verifies...
{
  const r = resolve({ AIRSDK_HOME: OLD, ASC_AIR_SDK_SEARCH_DIRS: A });
  check('a verifying AIRSDK_HOME wins over the scan',
    r.root === real(OLD) && r.source === 'AIRSDK_HOME', 'got ' + r.root + ' via ' + r.source);
}

// 7. ...and when it does not (a path from another OS), the resolver KEEPS LOOKING
//    instead of answering "no SDK". This is the exact dev-box failure: AIRSDK_HOME
//    held D:/Adobe/... and the SDK was in ~/Documents/Software/.
{
  const r = resolve({ AIRSDK_HOME: 'D:/Adobe/Flex_Sdk/AIRSDK_51.4.1', ASC_AIR_SDK_SEARCH_DIRS: A });
  const recorded = (r.tried || []).some((t) => t.source === 'AIRSDK_HOME' && t.ok === false);
  check('a foreign-OS AIRSDK_HOME is recorded as a miss and the search still runs',
    r.root === real(NEW) && r.source === 'scan' && recorded, 'got ' + r.root + ' via ' + r.source);
}

// 8. A PATH that points at a stale bin/ is a MISS, not an answer -- the second half of
//    the same dev-box failure (PATH held .../AIRSDK_51.2.1/bin, which no longer exists).
{
  const gone = path.join(ROOT, 'uninstalled', 'AIRSDK_10.0', 'bin');
  fs.mkdirSync(gone, { recursive: true });
  const r = resolve({ PATH: gone, ASC_AIR_SDK_SEARCH_DIRS: A });
  check('a PATH entry without a runnable mxmlc falls through to the search',
    r.root === real(NEW) && r.source === 'scan', 'got ' + r.root + ' via ' + r.source);
}

// 9. ASC_NO_AIR_SCAN=1 means env+PATH only: the escape hatch has to actually stop the
//    search, or "the scan is off" is a claim nobody can rely on.
{
  const r = resolve({ ASC_NO_AIR_SCAN: '1', ASC_AIR_SDK_SEARCH_DIRS: A });
  check('ASC_NO_AIR_SCAN=1 does not scan', r.root === null, 'got ' + r.root);
}

// 10. The CLI is the module: build.sh consumes `--print`, the tools consume the module,
//     so they must not be able to disagree.
{
  const e = { HOME: ROOT, PATH: '', ASC_AIR_SDK_SEARCH_DIRS: A };
  const cli = spawnSync(process.execPath, [RESOLVER, '--print'], { encoding: 'utf8', env: e });
  const mod = resolve({ ASC_AIR_SDK_SEARCH_DIRS: A });
  check('the CLI --print agrees with the module',
    cli.status === 0 && cli.stdout.trim() === mod.root, 'cli=' + JSON.stringify(cli.stdout) + ' module=' + mod.root);
}

// 11. The failure message says WHERE it looked: "not installed" with no locations is
//     the sentence that cost three rounds.
{
  const e = { HOME: ROOT, PATH: '', ASC_NO_AIR_SCAN: '0', ASC_AIR_SDK_SEARCH_DIRS: path.join(ROOT, 'none') };
  const r = spawnSync(process.execPath, [RESOLVER, '--why'], { encoding: 'utf8', env: e });
  const out = (r.stdout || '') + (r.stderr || '');
  check('a miss reports exit 3 and names the locations it searched',
    r.status === 3 && /install-location scan/.test(out) && /no AIR SDK found/.test(out),
    'status=' + r.status + '\n         ' + out.trim().split('\n').slice(0, 4).join('\n         '));
}

console.log('RESULT: ' + (fails.length ? 'FAIL ' + fails.length + '/' + n : 'PASS')
  + ' (' + (n - fails.length) + '/' + n + ' cases)');
process.exit(fails.length ? 1 : 0);
// asaotui/tools/mxmlc-check.cjs -- compile an AS3 source tree with the REAL AIR
// reference compiler and report the result.
//
// WHY THIS IS A SEPARATE CHECK FROM "it runs under our AOT": our AOT accepts a
// superset of what mxmlc accepts -- it tolerates top-level-script .as files
// (mxmlc demands a class named after the file), it resolves some types without an
// explicit import, and it never rejects a construct with mxmlc's wording. So
// "our compiler accepted it" is NOT evidence that a library is portable AS3.
// Running mxmlc is. This is how "the toolkit is pure AS3" gets to be a measured
// claim instead of an intention.
//
// Usage:
//   node mxmlc-check.cjs --root <file.as> [--root <file2.as> ...] --src <dir> [--src <dir2>] [--out <x.swf>] [--sdk <AIR SDK root>]
//   node mxmlc-check.cjs --root kit/asaot/ui/KitCheck.as --src kit
//
// Env: AIRSDK_HOME points at the AIR SDK root (never a hardcoded machine path);
//      --sdk overrides it, for callers running from a shell that mangles the
//      environment of native children.
// Exit: 0 compiled, 1 compile errors, 2 usage/SDK problem.
const { mxmlcRun } = require('./mxmlc-run.cjs');
const { spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const argv = process.argv.slice(2);
const roots = [];
const srcs = [];
let out = null;
let sdkArg = null;
for (let i = 0; i < argv.length; i++) {
  if (argv[i] === '--root') roots.push(argv[++i]);
  else if (argv[i] === '--src') srcs.push(argv[++i]);
  else if (argv[i] === '--out') out = argv[++i];
  else if (argv[i] === '--sdk') sdkArg = argv[++i];
  else { console.error('mxmlc-check.cjs: unknown argument ' + argv[i]); process.exit(2); }
}
if (!roots.length) {
  console.error('usage: node mxmlc-check.cjs --root a.as [--root b.as] [--src dir] [--out x.swf] [--sdk dir]');
  process.exit(2);
}
for (const r of roots) if (!fs.existsSync(r)) { console.error('no such root file: ' + r); process.exit(2); }

// --sdk exists because AIRSDK_HOME is an ENVIRONMENT variable, and the shells this
// workspace is driven from do not all deliver one to a native child (measured: the
// value was set by the calling script and arrived empty here). An argument never
// gets that wrong, so a caller that already knows the root passes it explicitly;
// the variable stays supported for everyone else.
//
// The fallback is the workspace's ONE resolver (tools/air-sdk.cjs), not a PATH scan:
// "not on PATH" is not "not installed" -- this box had the SDK in
// ~/Documents/Software/AIRSDK/AIRSDK_51.4.1 with a stale 51.2.1/bin on PATH, and the
// old PATH-only fallback answered "no AIR SDK" while mxmlc compiled in 1.8 s.
const { resolveAirSdk, describe } = require('./air-sdk.cjs');
const resolved = resolveAirSdk(sdkArg);
const sdk = resolved.root;
if (!sdk) {
  console.error('mxmlc-check.cjs: no AIR SDK -- ' + describe(resolved).replace(/^\[air-sdk\] /, ''));
  process.exit(2);
}
// mxmlc is a .bat on Windows, a shell script elsewhere -- the resolver already
// picked the host's own launcher, so this line cannot get the platform wrong.
const mxmlc = resolved.mxmlc;
if (!fs.existsSync(mxmlc)) { console.error('mxmlc-check.cjs: no mxmlc at ' + mxmlc); process.exit(2); }

const outSwf = out || path.join(path.dirname(roots[0]), '.mxmlc-check.swf');
const cmdArgs = ['-output=' + outSwf, ...srcs.flatMap((s) => ['-source-path=' + s]), ...roots];

console.log('mxmlc: ' + roots.join(' ') + '   (source-path: ' + (srcs.join(', ') || none()) + ')');
const r = mxmlcRun(mxmlc, cmdArgs, { encoding: 'buffer', timeout: 300000 });
// mxmlc writes its diagnostics in the console codepage on Windows, not UTF-8.
const decode = (b) => { try { return new TextDecoder('gbk').decode(b); } catch (e) { return String(b); } };
const text = decode(r.stdout || Buffer.alloc(0)) + decode(r.stderr || Buffer.alloc(0));

const errors = text.split('\n').filter((l) => /^\s*错误|^\s*Error|error:/.test(l));
if (r.status === 0) {
  console.log('MRC_EXIT 0');
  console.log('OK: compiled by AIR -- ' + (fs.existsSync(outSwf) ? fs.statSync(outSwf).size + ' bytes at ' + outSwf : 'no output?'));
  process.exit(0);
}
console.log('MRC_EXIT ' + (r.status === null ? 'KILLED-TIMEOUT' : r.status));
console.log(text.split('\n').slice(0, 80).join('\n'));
console.log('\n' + errors.length + ' error line(s)');
process.exit(1);

function none() { return '(none)'; }
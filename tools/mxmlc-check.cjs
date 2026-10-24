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
const sdk = sdkArg || process.env.AIRSDK_HOME || sdkFromPath();
if (!sdk) {
  console.error('mxmlc-check.cjs: no AIR SDK -- pass --sdk <root>, or set AIRSDK_HOME, or put its bin/ on PATH');
  process.exit(2);
}

// Last resort so a caller does not have to restate the SDK: walk PATH looking for
// the SDK's own bin/ tools. PATH entries arrive in three spellings in this
// workspace (D:\x, D:/x, and WSL's /mnt/d/x), and only the first two are visible to
// a Windows node, so the POSIX form is translated before the lookup.
function sdkFromPath() {
  const dirs = (process.env.PATH || '').split(path.delimiter);
  for (let d of dirs) {
    if (!d) continue;
    const m = /^\/mnt\/([A-Za-z])\/(.*)$/.exec(d);
    if (m) d = m[1].toUpperCase() + ':/' + m[2];
    for (const n of ['adl.exe', 'adl', 'mxmlc.bat', 'mxmlc']) {
      if (fs.existsSync(path.join(d, n))) return path.resolve(d, '..');
    }
  }
  return null;
}
// mxmlc is a .bat on Windows, a shell script elsewhere.
const mxmlc = path.join(sdk, 'bin', process.platform === 'win32' ? 'mxmlc.bat' : 'mxmlc');
if (!fs.existsSync(mxmlc)) { console.error('mxmlc-check.cjs: no mxmlc at ' + mxmlc); process.exit(2); }

const outSwf = out || path.join(path.dirname(roots[0]), '.mxmlc-check.swf');
const cmdArgs = [mxmlc, '-output=' + outSwf, ...srcs.flatMap((s) => ['-source-path=' + s]), ...roots];

console.log('mxmlc: ' + roots.join(' ') + '   (source-path: ' + (srcs.join(', ') || none()) + ')');
const r = spawnSync('cmd', ['/c', ...cmdArgs], { encoding: 'buffer', timeout: 300000 });
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
// Run the AIR reference compiler (mxmlc) and the AIR runtime (adl) from a Node
// harness, on any host.
//
// WHY THIS FILE EXISTS: mxmlc is `mxmlc.bat` on Windows and a shell script on
// macOS/Linux, and Windows cannot execute a .bat directly -- it has to go through
// `cmd /c`. Every probe runner in this repo used to spell that Windows shape
// inline (`spawnSync('cmd', ['/c', mxmlc, ...])`), which is why the whole
// AOT-vs-AIR arm was unreachable off Windows: the runner died at "mxmlc FAILED
// (exit null)" before a single comparison row was printed.
const { spawnSync } = require('child_process');

const WIN = process.platform === 'win32';

// mxmlcRun(mxmlcPath, mxmlcArgs, spawnOpts) -> spawnSync result
function mxmlcRun(mxmlc, args, opts) {
  return WIN ? spawnSync('cmd', ['/c', mxmlc, ...args], opts) : spawnSync(mxmlc, args, opts);
}

// The AIR SDK's own binary for a tool name: `.bat` / `.exe` on Windows, bare
// elsewhere. `bin` is the SDK root's `bin` directory.
function sdkBin(sdk, name) {
  return require('path').join(sdk, 'bin', WIN ? name + '.bat' : name);
}

module.exports = { mxmlcRun, sdkBin, WIN };

// ui-demo/run-adl.cjs -- run the AIR demo under adl with a hard timeout.
//
// Copied in spirit from ../air-check/run-adl.cjs (read-only there). WHY IT IS
// NEEDED: an AIR app that does not call NativeApplication.exit() keeps its event
// loop alive, so `adl app.xml` never returns; and this host has no coreutils, so
// there is no `timeout` command. child_process's own `timeout` option is the
// portable substitute. The demo DOES call exit(), so the timeout is a safety net.
//
// Usage:  node run-adl.cjs [descriptor.xml] [timeoutMs]
// Reads AIRSDK_HOME for the SDK root -- never a hardcoded machine path.
const { execFile } = require('child_process');
const fs = require('fs');
const path = require('path');

const sdk = process.env.AIRSDK_HOME;
if (!sdk) {
  console.error('run-adl.cjs: AIRSDK_HOME is not set (point it at the AIR SDK root)');
  process.exit(2);
}
const descriptor = process.argv[2] || 'app-ui-demo.xml';
const timeoutMs = Number(process.argv[3] || 120000);
const adl = path.join(sdk, 'bin', process.platform === 'win32' ? 'adl.exe' : 'adl');
if (!fs.existsSync(adl)) {
  console.error('run-adl.cjs: no adl at ' + adl);
  process.exit(2);
}

execFile(adl, [descriptor], { timeout: timeoutMs, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 },
  (err, stdout, stderr) => {
    let code = 0;
    if (err) code = err.killed ? 'KILLED-TIMEOUT' : (err.code === undefined ? 'ERR' : err.code);
    console.log('ADL_EXIT ' + code);
    console.log('--- stdout ---');
    process.stdout.write(stdout || '');
    console.log('--- stderr ---');
    process.stdout.write(stderr || '');
    process.exit(err ? 1 : 0);
  });

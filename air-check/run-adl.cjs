// air-check/run-adl.cjs -- run an AIR app under adl with a hard timeout.
//
// WHY THIS EXISTS: an AIR app that does not call NativeApplication.exit()
// keeps its event loop alive, so `adl app.xml` never returns (measured: 900 s
// before the caller gave up). This host also has no coreutils, so there is no
// `timeout` command to lean on. child_process's own `timeout` option kills the
// child and reports it, which is what the harness needs.
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
const descriptor = process.argv[2] || 'app.xml';
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
    // A killed child means the app never asked to exit -- treat it as failure.
    process.exit(err ? 1 : 0);
  });
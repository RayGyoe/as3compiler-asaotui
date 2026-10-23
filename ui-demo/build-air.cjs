// ui-demo/build-air.cjs -- compile the demo with mxmlc (the AIR reference
// compiler) so the SAME view code runs on AIR, proving the toolkit is portable.
//
// Usage:  node build-air.cjs          (needs AIRSDK_HOME set to the SDK root)
//
// WHY cmd.exe: mxmlc is a .bat, and Node cannot spawn a .bat directly on Windows
// (spawnSync returns status null). Routing through `cmd /c` is the portable fix.
'use strict';

const { spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const here = __dirname;
const sdk = process.env.AIRSDK_HOME;
if (!sdk) {
  console.error('build-air.cjs: AIRSDK_HOME is not set (point it at the AIR SDK root)');
  process.exit(2);
}
const mxmlc = path.join(sdk, 'bin', process.platform === 'win32' ? 'mxmlc.bat' : 'mxmlc');
if (!fs.existsSync(mxmlc)) {
  console.error('build-air.cjs: no mxmlc at ' + mxmlc);
  process.exit(2);
}

// -source-path lists the ROOT of each package tree: `.` has demo/ + the document
// class, ../kit has asaot/ui/*, ../seam has the pure-AS3 layout engine.
const cmd = '"' + mxmlc + '" -output=UiDemoAir.swf' +
  ' -source-path=. -source-path=../kit -source-path=../seam' +
  ' UiDemoAir.as';

console.log('[build-air] ' + cmd);
const r = spawnSync(cmd, { cwd: here, encoding: 'utf8', shell: true, maxBuffer: 64 * 1024 * 1024 });
const out = (r.stdout || '') + (r.stderr || '');
const errs = out.split('\n').filter(function (l) { return /Error|error:/.test(l); });
if (errs.length) {
  console.error(errs.slice(0, 30).join('\n'));
  process.exit(1);
}
const swf = path.join(here, 'UiDemoAir.swf');
if (!fs.existsSync(swf)) {
  console.error('[build-air] BUILD FAILED: no UiDemoAir.swf\n' + out.slice(-2000));
  process.exit(1);
}
console.log('[build-air] ok: UiDemoAir.swf ' + fs.statSync(swf).size + ' bytes');

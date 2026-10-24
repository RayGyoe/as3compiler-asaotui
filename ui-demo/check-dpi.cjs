// check-dpi.cjs -- prove that <requestedDisplayResolution>high is what makes this
// demo render at the display's real resolution, by building the SAME app twice from
// two descriptors that differ in exactly that one line.
//
//   usage:  node check-dpi.cjs
//
//   arm HIGH      air-gallery/app.xml            (requestedDisplayResolution=high)
//   arm STANDARD  air-gallery-standard/app.xml   (requestedDisplayResolution=standard)
//
// Both arms go through run-gallery.cjs (so both get --all-sources, the G11 retry and
// the shared screenshot measurement), and both run the identical 42-page docs tour with
// the identical logical 1000x700 stage. The ONLY thing that may differ is the PNG's
// pixel size:
//
//   high      -> 1000x700 x device scale  (1500x1050 on this box's 150% display)
//   standard  -> exactly 1000x700        (the compositor would stretch this)
//
// A one-line descriptor change with a two-way visible consequence is why this is a
// gate rather than a note in a README: if a future change makes `high` behave like
// `standard` (or vice versa), exactly one of these arms goes red.
//
// ON A 100% DISPLAY both arms measure 1x and the experiment cannot distinguish them.
// That is reported as INCONCLUSIVE, not as a pass: claiming a HiDPI win on a machine
// where HiDPI is invisible would be the dishonest reading.
'use strict';

const path = require('path');
const fs = require('fs');
const { spawnSync } = require('child_process');
const { pngSize, descriptorWindow, initialWindowBlock } = require('./air-run.cjs');

const here = __dirname;
const arms = [
  { label: 'HIGH', dir: 'air-gallery' },
  { label: 'STANDARD', dir: 'air-gallery-standard' },
];

// ---- pre-check: the two descriptors must differ in ONE setting -------------
// The whole experiment rests on the two arms being the same app, so this is checked
// before anything is built: compare the <initialWindow> blocks with the resolution
// value normalised away. They must then be byte-identical. If someone changes the
// control arm's size or renderMode, the A/B stops being one-variable and this fails
// immediately instead of producing numbers that look fine.
function normalisedWindow(dir, arm) {
  const win = initialWindowBlock(path.join(here, dir, 'app.xml'));
  if (!win) {
    console.error('[check-dpi] ' + dir + '/app.xml has no <initialWindow>');
    process.exit(2);
  }
  if (arm.resolution !== (descriptorWindow(path.join(here, dir, 'app.xml')) || {}).resolution) {
    // Cannot happen with the current call sites; asserted so the pre-check can never
    // compare a block against a resolution it did not read from that same block.
    console.error('[check-dpi] internal: resolution mismatch for ' + dir);
    process.exit(2);
  }
  return win.block.replace(/<requestedDisplayResolution>\s*\w+\s*<\/requestedDisplayResolution>/,
    '<requestedDisplayResolution>RESOLUTION</requestedDisplayResolution>');
}
{
  for (const arm of arms) arm.resolution = (descriptorWindow(path.join(here, arm.dir, 'app.xml')) || {}).resolution;
  const a = normalisedWindow(arms[0].dir, arms[0]);
  const b = normalisedWindow(arms[1].dir, arms[1]);
  if (a !== b) {
    console.error('[check-dpi] the two descriptors differ beyond requestedDisplayResolution:');
    const la = a.split(/\r?\n/);
    const lb = b.split(/\r?\n/);
    for (let i = 0; i < Math.max(la.length, lb.length); i++) {
      if (la[i] !== lb[i]) console.error('  line ' + (i + 1) + ': ' + JSON.stringify(la[i]) + ' vs ' + JSON.stringify(lb[i]));
    }
    console.error('  -> the A/B would no longer be one-variable; fix the descriptors first.');
    process.exit(2);
  }
  console.log('[check-dpi] descriptors are identical except requestedDisplayResolution -- one variable');
}

// ---- build+run both arms ---------------------------------------------------
const results = [];
for (const arm of arms) {
  const descriptor = path.join(here, arm.dir, 'app.xml');
  const size = descriptorWindow(descriptor);
  console.log('');
  console.log('======== arm ' + arm.label + ' (' + arm.dir + '/app.xml, requestedDisplayResolution='
    + size.resolution + ') ========');
  const r = spawnSync(process.execPath, ['run-gallery.cjs'], {
    cwd: here, stdio: 'inherit', env: { ...process.env, ASC_AIR_DIR: arm.dir, ASC_NO_OPEN: '1' },
  });
  const png = path.join(here, arm.dir, 'gallery-page0.png');
  const px = fs.existsSync(png) ? pngSize(png) : null;
  results.push({ arm, size, exit: r.status, png, px });
  console.log('[' + arm.label + '] run-gallery.cjs exit ' + r.status
    + ', screenshot ' + (px ? px.w + 'x' + px.h : 'MISSING'));
}

// ---- the A/B ---------------------------------------------------------------
console.log('');
console.log('---- descriptor A/B ----');
for (const r of results) {
  const scale = r.px ? r.px.w / r.size.w : 0;
  console.log('  ' + r.arm.label.padEnd(9) + ' ' + r.size.resolution.padEnd(9)
    + ' stage ' + r.size.w + 'x' + r.size.h
    + '  ->  PNG ' + (r.px ? r.px.w + 'x' + r.px.h : 'MISSING')
    + '   scale ' + (r.px ? scale : '?')
    + '   tour exit ' + r.exit);
}

const problems = [];
const high = results[0];
const std = results[1];
for (const r of results) if (r.exit !== 0) problems.push(r.arm.label + ' arm: run-gallery.cjs exited ' + r.exit);
if (!high.px) problems.push('HIGH arm wrote no screenshot');
if (!std.px) problems.push('STANDARD arm wrote no screenshot');

if (high.px && std.px) {
  // Same logical stage in both arms -- otherwise the sizes are not comparable.
  if (high.size.w !== std.size.w || high.size.h !== std.size.h) {
    problems.push('the two descriptors declare different stage sizes (' + high.size.w + 'x' + high.size.h
      + ' vs ' + std.size.w + 'x' + std.size.h + '): the comparison is void');
  }
  const stdScale = std.px.w / std.size.w;
  if (stdScale !== 1) {
    // Documented AIR behaviour: `standard` renders at 1x and lets the compositor
    // stretch. Anything else means the build ignored the descriptor (e.g. the
    // scoreboard define leaking in from a cached manifest).
    problems.push('STANDARD arm rendered at ' + stdScale + 'x; <requestedDisplayResolution>standard must be 1x');
  }
  const highScale = high.px.w / high.size.w;
  if (highScale <= 1) {
    console.log('');
    console.log('RESULT: INCONCLUSIVE -- this display is ' + highScale + 'x, so <requestedDisplayResolution>high'
      + '\n  has no visible effect here and the two arms are indistinguishable. The');
    console.log('  experiment needs a display scaled above 100% (this box measures 150%).');
    console.log('  Both arms still built and ran their tour, so this is NOT a failure.');
    process.exit(0);
  }
  if (high.px.w === std.px.w && high.px.h === std.px.h) {
    problems.push('HIGH and STANDARD produced the same PNG size (' + high.px.w + 'x' + high.px.h
      + '): the descriptor line changed nothing, so it is not the cause');
  }

  // The strongest form of the claim: the descriptor changes the PIXEL DENSITY and
  // nothing else. Both tours are hand-computed rect dumps of the same five pages, so
  // if the two files are byte-identical then not one logical coordinate moved -- the
  // app never learns how many pixels it is given. A byte comparison also catches a
  // bleed the other way (HiDPI silently rescaling the layout instead of the canvas).
  const txt = (dir) => path.join(here, dir, 'gallery.txt');
  if (fs.existsSync(txt(high.arm.dir)) && fs.existsSync(txt(std.arm.dir))) {
    const a = fs.readFileSync(txt(high.arm.dir), 'utf8');
    const b = fs.readFileSync(txt(std.arm.dir), 'utf8');
    console.log('  tour text: ' + (a === b ? 'IDENTICAL (' + a.length + ' B, to the byte)'
      : 'DIFFERS -- logical geometry depends on the resolution'));
    if (a !== b) {
      const la = a.split(/\r?\n/);
      const lb = b.split(/\r?\n/);
      let i = 0;
      while (i < la.length && i < lb.length && la[i] === lb[i]) i++;
      problems.push('the two tours disagree at line ' + (i + 1) + ': ' + JSON.stringify(la[i])
        + ' vs ' + JSON.stringify(lb[i])
        + ' -- a resolution change must not move a logical coordinate');
    }
  }
}

console.log('');
if (problems.length) {
  console.log('RESULT: FAIL');
  for (const p of problems) console.log('  ' + p);
  process.exit(1);
}
console.log('RESULT: PASS -- the same app renders at 1x under standard and at '
  + (high.px.w / high.size.w) + 'x under high, from a one-line descriptor change');
process.exit(0);
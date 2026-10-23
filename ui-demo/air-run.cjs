// air-run.cjs -- the small shared plumbing of the two `--air-app` demo runners
// (run-gallery.cjs and build-and-run.cjs). Both do the same four things around a
// descriptor-driven build, and doing them twice would mean two implementations of
// "measure the screenshot" -- exactly the kind of drift this workspace measures
// instead of trusting.
//
// Not a framework: four functions, no state, no I/O policy. Everything specific to
// a demo (what to assert, how many screenshots, how to print the verdict) stays in
// that demo's runner.
'use strict';

const fs = require('fs');
const { execFileSync } = require('child_process');

// PNG pixel size, straight from the IHDR chunk (8-byte signature, then the chunk
// length/type, then width and height as big-endian uint32 at byte offsets 16/20).
// No image decoder needed for two integers.
function pngSize(file) {
  const b = fs.readFileSync(file);
  if (b.length < 24 || b.readUInt32BE(0) !== 0x89504e47) return null;
  return { w: b.readUInt32BE(16), h: b.readUInt32BE(20) };
}

// XML comments are blanked out before any tag is looked for, and blanked with SPACES
// of the same length so every byte offset still refers to the original file. Both
// descriptors in this directory quote markup inside their own comments ("...except
// ONE line -- requestedDisplayResolution ..."), and a naive first-match regex happily
// matches the prose: that misled a runner once and a mutation once. Offsets are
// preserved so a caller can find a span, edit it and splice it back.
function blankComments(xml) {
  return xml.replace(/<!--[\s\S]*?-->/g, (m) => m.replace(/[^\n]/g, ' '));
}

// The window's logical size and requested resolution, read from the descriptor --
// the descriptor is the source of truth, so a runner must not restate any of it.
function descriptorWindow(descriptor) {
  const win = initialWindowBlock(descriptor);
  if (!win) return null;
  const body = win.block;
  const w = /<width>\s*(\d+)\s*<\/width>/.exec(body);
  const h = /<height>\s*(\d+)\s*<\/height>/.exec(body);
  const r = /<requestedDisplayResolution>\s*(\w+)\s*<\/requestedDisplayResolution>/.exec(body);
  if (!w || !h) return null;
  return { w: Number(w[1]), h: Number(h[1]), resolution: r ? r[1].toLowerCase() : 'standard' };
}

// The raw <initialWindow>...</initialWindow> span, comments ignored, with offsets
// into the ORIGINAL text so an editor can splice a modified block back in.
function initialWindowBlock(descriptor) {
  const xml = fs.readFileSync(descriptor, 'utf8');
  const stripped = blankComments(xml);
  const m = /<initialWindow>[\s\S]*?<\/initialWindow>/.exec(stripped);
  if (!m) return null;
  return { block: xml.slice(m.index, m.index + m[0].length), start: m.index, end: m.index + m[0].length };
}

// Windows holds the image file of a running process, so a leftover window makes the
// next build fail with "permission denied" -- kill it first, and treat "not running"
// as the normal case rather than an error.
function killImage(exeName) {
  try {
    execFileSync('taskkill', ['/F', '/IM', exeName], { stdio: 'ignore' });
  } catch (e) {
    // Not running: that is the normal case.
  }
}

// A real synchronous sleep. `Atomics.wait` on a throwaway SharedArrayBuffer is the
// only way to block the main thread for a moment without spawning a helper process
// (this box has no coreutils, so no `sleep`).
function sleepMs(ms) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

// Poll for a file a demo writes as its result channel, up to timeoutMs. Returns its
// trimmed contents, or null on timeout. Polling (not a watch) because the file is
// written once, atomically, at the very end of the run.
function waitForFile(file, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (fs.existsSync(file)) return fs.readFileSync(file, 'utf8').trim();
    sleepMs(150);
  }
  return null;
}

// Measure one screenshot against the logical stage it came from, returning the
// problems found (empty = ok) plus the numbers for the log.
//
// WHAT THIS IS FOR: <requestedDisplayResolution>high makes the render surface
// physical-pixel sized, so the PNG of an LxH stage comes out L*s x H*s where s is
// the display's device scale. A 1x PNG means the descriptor never reached the build
// -- a blurry window that every rect assertion in a demo would still call perfect.
//
// The scale is NOT assumed to be an integer: at 150% a 500x375 stage yields
// 750x563 (375 * 1.5 = 562.5, rounded up). So the two axes are allowed to disagree
// by at most one physical pixel, and each axis must be the device scale rounded to
// whole pixels -- which is what a windowing system does.
function checkShot(file, logical, label) {
  const problems = [];
  if (!fs.existsSync(file)) {
    problems.push(label + ' was not written');
    return { problems, size: null, scale: 0 };
  }
  const s = pngSize(file);
  if (!s) {
    problems.push(label + ' is not a PNG');
    return { problems, size: null, scale: 0 };
  }
  const scale = s.w / logical.w;
  const sy = s.h / logical.h;
  if (Math.abs(scale - sy) > 1 / Math.min(logical.w, logical.h)) {
    problems.push(label + ' has two device scales: ' + s.w + 'x' + s.h + ' for a '
      + logical.w + 'x' + logical.h + ' stage (' + scale + ' vs ' + sy + ')');
  }
  if (s.w !== Math.round(logical.w * scale) || s.h !== Math.round(logical.h * scale)) {
    problems.push(label + ' is not the logical stage times the device scale, rounded: '
      + s.w + 'x' + s.h + ' vs ' + Math.round(logical.w * scale) + 'x' + Math.round(logical.h * scale));
  }
  if (logical.resolution === 'high' && scale <= 1) {
    problems.push(label + ' is ' + scale + 'x (1x): <requestedDisplayResolution>'
      + logical.resolution + '</requestedDisplayResolution> produced no physical pixels');
  }
  return { problems, size: s, scale };
}

// The state of the compiler repo we are about to build with. WHY THIS EXISTS, and
// why it replaced a retry loop:
//
// compiler-gaps.md G11 used to read "the same source built twice can produce
// different C, retry the build". The measured cause is duller and far more useful:
// on this machine ANOTHER SESSION EDITS THE COMPILER while we build, so "the same
// source, two builds, different C" means the compiler changed in between. A retry
// loop hides that, and -- worse -- hides a real defect behind "succeeded on attempt
// 2". Printing the tree state names the condition instead, and a build failure can
// then be read correctly: a dirty tree means retry later, a clean tree means the
// failure is ours.
function compilerTree(compilerDir) {
  const git = (...a) => execFileSync('git', ['-C', compilerDir, ...a], { encoding: 'utf8' });
  const head = git('rev-parse', '--short', 'HEAD').trim();
  const tracked = [];
  const untracked = [];
  for (const rec of git('status', '--porcelain', '-z').split('\u0000')) {
    if (rec === '') continue;
    // `XY SP <path>`; anything else (a rename source) is reported rather than dropped.
    if (rec.length < 4 || rec[2] !== ' ') { tracked.push('UNPARSED:' + JSON.stringify(rec)); continue; }
    const code = rec.slice(0, 2);
    (code[0] === '?' ? untracked : tracked).push(code + ' ' + rec.slice(3));
  }
  return { head, tracked, untracked };
}

module.exports = { pngSize, descriptorWindow, initialWindowBlock, blankComments, killImage, sleepMs, waitForFile, checkShot, compilerTree };

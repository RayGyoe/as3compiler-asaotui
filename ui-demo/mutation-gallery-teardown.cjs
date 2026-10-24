// mutation-gallery-teardown.cjs -- prove the two TEARDOWN pins in the gallery tour
// have teeth.
//
// Page 5 of the gallery is the only program that builds the overlay tree and then
// TEARS IT DOWN while the app keeps running, and that is what found two defects
// nothing else could see:
//
//   * the anchored overlays (menu / popover / select) subscribe to the STAGE's
//     CLICK to close on an outside press, and nothing removed that listener when
//     the node was destroyed. The next click anywhere in the window then ran
//     `onAnyClick` on a node whose scratch bag (`n.extra`) had been nulled by
//     `UiNode.destroySubtree` -- #1009, one frame after page 5 went away. The
//     gallery's tab click is exactly that click, so the tour died mid-way and the
//     runner reported TIMEOUT (no `gallery.done`).
//   * the overlay ROOT has no parent NODE, so `destroySubtree`'s "remove me from
//     my parent's backing" step could never detach it: the empty host Sprite
//     stayed on the stage, above the main tree, for the rest of the session. The
//     tour compares `stage.numChildren` against the baseline it recorded on page 0.
//
// M1 reverts the teardown hook, M2 reverts the root detach. Each must make the
// gallery go red with the SPECIFIC message, not merely exit non-zero (a broken
// build also exits non-zero, which proves nothing).
//
// The mutated run rewrites the seven tracked `air-gallery/gallery-page{0..6}.png`
// screenshots, so they are snapshotted first and restored byte-for-byte, verified
// by hash -- same discipline as the source file.
//
// USAGE (from asaotui/ui-demo/, AIRSDK_HOME set):   node mutation-gallery-teardown.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const HERE = __dirname;
const UINODE = path.join(HERE, '..', 'kit', 'asaot', 'ui', 'UiNode.as');
const RECON = path.join(HERE, '..', 'kit', 'asaot', 'ui', 'Reconciler.as');
const SHOTS = [0, 1, 2, 3, 4, 5, 6, 7].map((i) => path.join(HERE, 'air-gallery', 'gallery-page' + i + '.png'));

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

function runGallery() {
  const r = spawnSync(process.execPath, [path.join(HERE, 'run-gallery.cjs')], {
    cwd: HERE,
    encoding: 'utf8',
    maxBuffer: 64 * 1024 * 1024,
    timeout: 900000,
    env: { ...process.env, ASC_NO_OPEN: '1' },
  });
  return {
    code: r.status === null ? 'signal/timeout ' + (r.signal || '') : r.status,
    out: (r.stdout || '') + (r.stderr || ''),
  };
}

const rows = [];
const record = (name, ok, detail) => rows.push({ name, ok, detail });

// ---- baseline ---------------------------------------------------------------
{
  const r = runGallery();
  const pass = /\[gallery\] RESULT: PASS/.test(r.out);
  record('baseline (unmutated) gallery tour', r.code === 0 && pass,
    'exit=' + r.code + (pass ? ' + RESULT: PASS' : ' but the tour was not green -- a mutation run would prove nothing'));
  if (!pass) {
    console.log(r.out.split(/\r?\n/).slice(-15).join('\n'));
    for (const row of rows) console.log((row.ok ? 'MUTATION PASS  ' : 'MUTATION FAIL  ') + row.name + '   [' + row.detail + ']');
    process.exit(1);
  }
}

const shots = SHOTS.map((p) => ({ p, bytes: fs.readFileSync(p), hash: sha(p) }));
const shotsHash = shots.map((s) => s.hash).join(',');
const restoreShots = () => shots.every((s) => {
  fs.writeFileSync(s.p, s.bytes);
  return sha(s.p) === s.hash;
});

const MUTATIONS = [
  {
    id: 'M1',
    why: 'the teardown hook is dropped: a destroyed anchored overlay keeps its STAGE click '
      + 'listener, which dereferences the nulled scratch bag on the next click -> #1009 and the '
      + 'tour never writes gallery.done',
    file: UINODE,
    find: '            if (this.widget is WidgetTeardown) WidgetTeardown(this.widget).teardown(this);',
    replace: '            // MUTATION M1: teardown hook removed',
    verdict: (out) => /TIMEOUT|Uncaught exception/.test(out) && !/\[gallery\] RESULT: PASS/.test(out),
    detail: (out) => (/Uncaught exception/.test(out) ? 'uncaught #1009 (the listener outlived the node)'
      : /TIMEOUT/.test(out) ? 'TIMEOUT (the tour died before writing gallery.done)' : 'neither symptom appeared'),
  },
  {
    id: 'M2',
    why: 'the overlay root is never detached from the stage container: the empty host Sprite stays '
      + 'stacked above the main tree, and the tour\'s stage.numChildren check must say so by name',
    file: RECON,
    find: '            if (b != null && b.parent != null) b.parent.removeChild(b);',
    replace: '            // MUTATION M2: root detach removed',
    verdict: (out) => /the stage holds \d+ display objects after the overlay was torn down/.test(out)
      && !/\[gallery\] RESULT: PASS/.test(out),
    detail: (out) => (/the stage holds \d+ display objects/
      ? 'the count verdict named the leak' : 'the count verdict did not appear'),
  },
];

let allRestored = true;
for (const m of MUTATIONS) {
  const before = fs.readFileSync(m.file, 'utf8');
  const beforeHash = sha(m.file);
  if (!before.includes(m.find)) {
    record(m.id + ' anchor present', false, 'the mutation anchor is not in ' + path.basename(m.file)
      + ' -- the pin has lost its teeth');
    continue;
  }
  try {
    fs.writeFileSync(m.file, before.replace(m.find, m.replace));
    const r = runGallery();
    record(m.id + ' ' + m.why.slice(0, 60) + '...', m.verdict(r.out),
      'exit=' + r.code + ' + ' + m.detail(r.out));
  } finally {
    fs.writeFileSync(m.file, before);
    const ok = sha(m.file) === beforeHash;
    if (!ok) allRestored = false;
    record(m.id + ' source restored byte-identical', ok, ok ? 'same sha256 as before the mutation' : 'TAMPERED');
  }
}

const shotsOk = restoreShots();
record('screenshots restored byte-identical', shotsOk,
  shotsOk ? SHOTS.length + ' PNG(s), same bytes as before the mutations'
          : 'the mutated screenshots could not be put back -- do not trust the tree');

console.log('');
for (const row of rows) console.log((row.ok ? 'MUTATION PASS  ' : 'MUTATION FAIL  ') + row.name + '   [' + row.detail + ']');
const bad = rows.filter((r) => !r.ok).length;
console.log('');
console.log('MUTATION gallery-teardown: ' + (bad === 0 ? 'PASS (' + MUTATIONS.length + '/' + MUTATIONS.length + ' + 3 pins)'
  : 'FAIL (' + bad + ' problem(s))'));
console.log('screenshot baseline: ' + shotsHash.slice(0, 12) + '...');
process.exit(bad === 0 && allRestored ? 0 : 1);
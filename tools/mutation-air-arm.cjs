// mutation-air-arm.cjs -- prove the "AIR arm compiles under mxmlc" gate has teeth.
//
// Both mutations break COMPILATION of the docs app for the AIR runtime, which is the
// only thing the gate claims. They are the two portability defects this arm was
// actually born with, not invented noise:
//
//   M1 an unimported package-level `box()` call in a demo page. OUR compiler resolves
//      it (same-package free functions, no import needed), mxmlc does not -- this is
//      verbatim the state the docs tree was in before the AIR arm existed.
//   M2 the AIR entry class touching `Stage.render`, an AOT-only test hook. mxmlc has
//      no such member and rejects the file -- which is why `DocsAir.as` exists
//      separately from the touring `DocsMain.as`.
//
// Each file is restored byte-for-byte (sha256 checked afterwards).
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const CASES = [
  {
    id: 'M1',
    name: 'DocsStart.as calls box() without importing it',
    file: path.join(ROOT, 'ui-demo', 'demo', 'DocsStart.as'),
    from: '    import asaot.ui.box;\n',
    to: '',
    expect: /box/,
  },
  {
    id: 'M2',
    name: 'DocsAir.as touches the AOT-only Stage.render hook',
    file: path.join(ROOT, 'ui-demo', 'demo', 'DocsAir.as'),
    from: '            this.app.reflow();\n',
    to: '            this.app.reflow();\n            this.stage.render(0, 0, "x.png");\n',
    expect: /render/,
  },
];

const gate = () => spawnSync(process.execPath, ['tools/mxmlc-check.cjs',
  '--root', 'ui-demo/demo/DocsAir.as',
  '--src', 'ui-demo', '--src', 'kit', '--src', 'seam',
  '--out', 'ui-demo/air-gallery/GalleryApp.swf'], { cwd: ROOT, encoding: 'utf8' });

let bad = 0;
for (const c of CASES) {
  const before = sha(c.file);
  const src = fs.readFileSync(c.file, 'utf8');
  const hits = src.split(c.from).length - 1;
  if (hits !== 1) {
    console.log(c.id + ': SKIPPED -- the anchor occurs ' + hits + ' times in ' + path.basename(c.file));
    bad++;
    continue;
  }
  fs.writeFileSync(c.file, src.replace(c.from, c.to));
  let r;
  try {
    r = gate();
  } finally {
    fs.writeFileSync(c.file, src);
  }
  const out = (r.stdout || '') + (r.stderr || '');
  const caught = r.status !== 0 && c.expect.test(out) && /MRC_EXIT [1-9]/.test(out);
  if (!caught) bad++;
  console.log('---- ' + c.id + ': ' + c.name);
  console.log('   exit ' + r.status + ' -> ' + (caught ? 'CAUGHT' : 'MISSED'));
  const err = out.split(/\r?\n/).find((l) => /^\s*错误|^\s*Error/.test(l));
  if (err) console.log('   | ' + err.trim());
  console.log('   restore: ' + (sha(c.file) === before ? 'byte-identical ' + before.slice(0, 16) : 'DIFFERS!!'));
  if (sha(c.file) !== before) bad++;
}

// The healthy tree must still compile after the restores -- otherwise the file was
// not really put back and the two CAUGHT lines above would mean nothing.
{
  const r = gate();
  const ok = r.status === 0 && /OK: compiled by AIR/.test((r.stdout || '') + (r.stderr || ''));
  if (!ok) bad++;
  console.log('---- baseline after restores: ' + (ok ? 'compiles' : 'DOES NOT COMPILE'));
}

console.log(bad === 0 ? 'MUTATION: 2/2 CAUGHT' : 'MUTATION: ' + bad + ' problem(s)');
process.exit(bad === 0 ? 0 : 1);
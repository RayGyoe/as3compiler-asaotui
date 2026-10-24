// mutation-docs-tour.cjs -- prove the docs tour's CLICK and CHROME assertions bite.
//
// The tour (ui-demo/demo/DocsMain.as) is the only test that drives real input, so it
// is the only place a whole class of defect can be caught: the one the user reported
// was a demo asking toast() for a CHIP tone, which threw while the overlay tree was
// being built -- the frame guard recovered, so 41 rendered screenshots all looked
// fine and the symptom was a console stream. Stage 6d clicks that button and names
// the throw, and it also checks that a scroll view's bars end up ABOVE its content
// (the base index used to count the bar layer, so every content child was ordered
// over it and the bars only returned when some later repaint happened to raise
// them again -- page 0's screenshot showed a thumb behind the code block).
//
// Each case: patch one unit -> rebuild+run the tour -> read the verdict -> restore
// -> sha256 must be byte-identical.
//
//   M1  ui-demo/demo/DocsView.as   tone: "default" -> "info"   (THE BUG THE USER HIT)
//   M2  kit/asaot/ui/OverlayChrome.as   TOAST_LAYER gap 8 -> 0  (geometry only: nothing
//       throws, the toasts simply stop being 8 apart)
//   M3  kit/asaot/ui/kind/ScrollViewWidget.as   drop `n.aboveContent = n.shapeB`
//       (structure only: the bars are painted, then buried)
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const DEMO = path.join(ROOT, 'ui-demo');

function sha(p) { return crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex'); }

function runTour() {
  const r = spawnSync(process.execPath, ['run-gallery.cjs'], {
    cwd: DEMO,
    env: { ...process.env, AIRSDK_HOME: process.env.AIRSDK_HOME || 'D:/Adobe/Flex_Sdk/AIRSDK_51.4.1', ASC_CC: process.env.ASC_CC || 'clang', ASC_NO_OPEN: '1' },
    encoding: 'utf8',
    timeout: 900000,
    maxBuffer: 1 << 28
  });
  const donePath = path.join(DEMO, 'air-gallery', 'gallery.done');
  const txtPath = path.join(DEMO, 'air-gallery', 'gallery.txt');
  const done = fs.existsSync(donePath) ? fs.readFileSync(donePath, 'utf8').trim() : '(no gallery.done)';
  const txt = fs.existsSync(txtPath) ? fs.readFileSync(txtPath, 'utf8') : '';
  return { status: r.status, done, txt, log: (r.stdout || '') + (r.stderr || '') };
}

const CASES = [
  {
    id: 'M1',
    name: 'toastHost demo asks for tone "info" (the reported bug)',
    file: path.join(DEMO, 'demo', 'DocsView.as'),
    from: 'tone: "default", duration: 4000,',
    to: 'tone: "info", duration: 4000,',
    want: /opening the toastHost demo threw: .*unknown tone 'info'/
  },
  {
    id: 'M2',
    name: 'TOAST_LAYER gap 8 -> 0',
    file: path.join(ROOT, 'kit', 'asaot', 'ui', 'OverlayChrome.as'),
    from: 'padding: 16, gap: 8',
    to: 'padding: 16, gap: 0',
    want: /the toast gap is not 8/
  },
  {
    id: 'M3',
    name: 'the bar layer is counted as content base again (bars buried)',
    file: path.join(ROOT, 'kit', 'asaot', 'ui', 'kind', 'ScrollViewWidget.as'),
    from: '            n.aboveContent = n.shapeB;',
    to: '            // M3: the bars are left in the child base index',
    want: /bars sit at display index \d+ of \d+, so the content below them paints over the bars/
  }
];

let caught = 0;
let missed = 0;
for (const c of CASES) {
  const before = sha(c.file);
  const src = fs.readFileSync(c.file, 'utf8');
  const hits = src.split(c.from).length - 1;
  if (hits !== 1) {
    console.log(c.id + ': ANCHOR PROBLEM -- "' + c.from.trim() + '" occurs ' + hits + ' times in '
      + path.basename(c.file) + ' (expected 1)');
    missed++;
    continue;
  }
  fs.writeFileSync(c.file, src.replace(c.from, c.to));
  let res;
  try {
    res = runTour();
  } finally {
    fs.writeFileSync(c.file, src);
  }
  const after = sha(c.file);
  // The named failure lands in gallery.done ('FAIL <problems>'); gallery.txt is the
  // report the tour writes for humans, and carries only the measurements.
  const red = res.done.startsWith('FAIL') && c.want.test(res.done);
  if (red) caught++; else missed++;
  console.log('---- ' + c.id + ': ' + c.name);
  const named = res.done.split(/\r?\n/).filter((l) => c.want.test(l));
  for (const l of named) console.log('   | ' + l.trim());
  console.log('   caught : ' + (red ? 'CAUGHT' : 'MISSED') + '   (verdict: ' + res.done.slice(0, 120) + ')');
  console.log('   restore: ' + (after === before ? 'byte-identical ' + before.slice(0, 16) : 'DIFFERS!! ' + before + ' vs ' + after));
  if (after !== before) missed++;
}
console.log('\n' + caught + '/' + (caught + missed) + ' mutations changed the verdict');
process.exit(missed === 0 ? 0 : 1);
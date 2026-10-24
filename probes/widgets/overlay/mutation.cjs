// probes/widgets/overlay/mutation.cjs -- proves tools/probe.cjs CAN go red on the
// overlay probe.
//
// A probe that cannot fail is decoration. Each mutation below is a deliberate
// one-token change to something the probe actually measures, and each names the
// SPECIFIC failure line it must produce, so that "it went red" is never confused
// with "it failed to build".
//
// Five of the nine are the REAL DEFECTS this probe found while it was being
// written -- the overlay tree solved against the pre-window fallback size, the
// panel surfaces that painted nothing at all, the layer that shrank when the
// control's own `width`/`size` option leaked into a style shorthand, the row
// routing that read a target-relative localY, and the visibility flip that never
// reached the display object. Keeping them as mutations means the pins stay
// honest: fix one of them wrongly (or re-introduce it later) and this file says so.
//
// Every file is restored in `finally` and its sha256 compared byte-for-byte with
// the pre-mutation hash: a mutation run can never leave the kit subtly altered.
//
// USAGE (from asaotui/):   node probes/widgets/overlay/mutation.cjs
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const DIR = __dirname;
const UI = path.resolve(DIR, '..', '..', '..');   // probes/widgets/overlay -> asaotui
const PROBE = 'probes/widgets/overlay';
const RESULTS = path.join(DIR, 'overlay-mutation.txt');

const sha = (p) => crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');

const MUTATIONS = [
  {
    id: 'M1',
    why: 'the dialog LAYER keeps the explicit `size.width` that the control\'s own `width` option '
      + 'leaks into a style shorthand -> an explicit size BEATS `inset` in a flex solve, the layer '
      + 'shrinks to the panel width and the centring collapses',
    file: 'kit/asaot/ui/dialog.as',
    find: '        n.style.size = null;',
    replace: '        n.style.size = n.style.size;',
    expect: 'dialog panel is 0,300',
  },
  {
    id: 'M2',
    why: 'the scrim goes from 0.4 to 0.6 alpha -> the hand-computed composite over white (255*0.6) '
      + 'no longer matches, on BOTH sampled points',
    file: 'kit/asaot/ui/OverlayChrome.as',
    find: 'public static const SCRIM:Fill = Fill.fromArgb(0x66, 0x00, 0x00, 0x00);',
    replace: 'public static const SCRIM:Fill = Fill.fromArgb(0x99, 0x00, 0x00, 0x00);',
    expect: 'the scrim over white is not #999999',
  },
  {
    id: 'M3',
    why: 'rowAt stops using the row\'s own solved rect and matches every row from the top -> a click '
      + 'reported as row 0, so the band never moves',
    file: 'kit/asaot/ui/OverlayList.as',
    find: '                if (ly >= top && ly < top + c.absH) return i;',
    replace: '                if (i == 0 || ly >= top && ly < top + c.absH) return i;',
    expect: 'the select reported row 0 not 2',
  },
  {
    id: 'M4',
    why: 'THE FIRST DEFECT THIS PROBE FOUND, re-introduced: the overlay tree is solved once against '
      + 'the 560x460 pre-window fallback and never re-solved when the stage reports 760x560',
    file: 'kit/asaot/ui/UiApp.as',
    find: '            if (availW != this._solvedW || availH != this._solvedH)\n            {\n                if (this.root != null)',
    replace: '            if (false)\n            {\n                if (this.root != null)',
    expect: 'dialog is not vertically centred',
  },
  {
    id: 'M5',
    why: 'THE SECOND DEFECT THIS PROBE FOUND, re-introduced: the panel surface is not created, so '
      + 'paintBox (and OverlayList.band) null-guard out of their work -- the surface has a correct '
      + 'solved rect and paints nothing',
    file: 'kit/asaot/ui/kind/PopoverWidget.as',
    find: '            n.shapeA = new Shape();\n            n.backing.addChild(n.shapeA);\n',
    replace: '',
    expect: "the popover panel's padding is not white",
  },
  {
    id: 'M6',
    why: 'the stack gap drops from 8 to 0 -> the toasts touch, and the probe\'s exact stack arithmetic '
      + '(gap 8, last bottom 544) no longer holds',
    file: 'kit/asaot/ui/OverlayChrome.as',
    find: '            padding: 16, gap: 8',
    replace: '            padding: 16, gap: 0',
    expect: 'the toast gap is not 8',
  },
  {
    id: 'M7',
    why: 'THE FOURTH DEFECT THIS PROBE FOUND, re-introduced: a visibility flip writes the field but '
      + 'raises no arrange bit, so the display object keeps the old visibility -- the dropdown '
      + 'reopens in the tree and stays invisible on screen',
    file: 'kit/asaot/ui/UiNode.as',
    find: '            if (vis != this.visible)\n            {\n                this.visible = vis;\n                this.dirty |= Dirty.M_ARRANGE | Dirty.M_PAINT;\n                this.markLayoutDirty();\n            }',
    replace: '            this.visible = vis;',
    expect: 'the band did not move to row 2 after the click',
  },
  {
    id: 'M8',
    why: 'THE PARENT-LOCAL CONVERSION IS DROPPED for the submenu (its parent is the MENU, not the '
      + 'overlay root at the origin), so the nested panel lands 20px to the right of its row',
    file: 'kit/asaot/ui/kind/PopoverWidget.as',
    find: '                eng.setPosition(e, LayoutConstants.EDGE_LEFT, a.absX + a.absW + off - ox,',
    replace: '                eng.setPosition(e, LayoutConstants.EDGE_LEFT, a.absX + a.absW + off - ox + 20,',
    expect: 'the submenu is at x=199 not 179',
  },
  {
    id: 'M9',
    why: 'THE SUBMENU COLLISION GUARD IS REMOVED: a click inside the submenu is also read as a click on '
      + 'the parent row at the same height (they overlap), so the parent selection moves too',
    file: 'kit/asaot/ui/kind/MenuWidget.as',
    find: '                if (OverlayList.isInside(c.backing, e.target)) return;',
    replace: '',
    expect: 'a click inside the submenu also activated parent row',
  },
];

function runProbe() {
  return spawnSync(process.execPath, ['tools/probe.cjs', PROBE], { cwd: UI, encoding: 'utf8' });
}

const log = [];
const line = (s) => { console.log(s); log.push(s); };
let caught = 0;
let broken = 0;

// Baseline: the unmutated probe must PASS, otherwise a mutation "failing" proves
// nothing (it was already red).
const base = runProbe();
const baseOut = (base.stdout || '') + (base.stderr || '');
const baseVerdict = /RESULT: (PASS|FAIL)/.exec(baseOut);
line('baseline (unmutated): ' + (baseVerdict ? baseVerdict[0] : 'NO VERDICT -- build failure?'));

if (!baseVerdict || baseVerdict[1] !== 'PASS') {
  line('the baseline is not green; a mutation run would be meaningless. Aborting.');
  line('--- baseline output (tail) ---');
  for (const l of baseOut.split(/\r?\n/).slice(-25)) line('  ' + l);
  fs.writeFileSync(RESULTS, log.join('\n') + '\n');
  process.exit(1);
}
line('');

for (const m of MUTATIONS) {
  const file = path.join(UI, m.file);
  const before = fs.readFileSync(file, 'utf8');
  const beforeHash = sha(file);
  if (before.indexOf(m.find) < 0) {
    line(m.id + '  SKIPPED -- anchor text not found in ' + m.file
      + ' (the file drifted; fix the mutation, do not ignore it)');
    broken++;
    continue;
  }
  try {
    fs.writeFileSync(file, before.split(m.find).join(m.replace));
    const r = runProbe();
    const out = (r.stdout || '') + (r.stderr || '');
    const verdict = /RESULT: (PASS|FAIL)/.exec(out);
    const saidIt = out.indexOf(m.expect) >= 0;
    const buildFailed = /BUILD FAILED/.test(out);
    const ok = verdict != null && verdict[1] === 'FAIL' && saidIt && !buildFailed;
    if (ok) caught++; else broken++;
    line(m.id + '  ' + (ok ? 'CAUGHT' : 'MISSED (THIS IS BAD)') + '  ' + m.why);
    line('     verdict: ' + (verdict ? verdict[0] : 'none')
      + (buildFailed ? '  BUILD FAILED -- a mutation that does not compile proves nothing' : '')
      + (saidIt ? '' : '  MISSING the expected failure line "' + m.expect + '"'));
    const fails = out.split(/\r?\n/).filter((l) => /  FAIL  /.test(l));
    for (const f of fails.slice(0, 4)) line('     ' + f.trim());
    if (fails.length > 4) line('     ... and ' + (fails.length - 4) + ' more');
  } finally {
    fs.writeFileSync(file, before);
  }
  const afterHash = sha(file);
  line('     restore: ' + (afterHash === beforeHash
    ? 'byte-identical (' + afterHash.slice(0, 16) + ')'
    : 'MISMATCH ' + beforeHash.slice(0, 16) + ' -> ' + afterHash.slice(0, 16) + '  THIS IS BAD'));
  if (afterHash !== beforeHash) broken++;
}

line('');
line('MUTATION overlay: ' + caught + '/' + MUTATIONS.length + ' caught, ' + broken + ' problem(s)');
line(broken === 0 && caught === MUTATIONS.length ? 'RESULT: PASS' : 'RESULT: FAIL');
fs.writeFileSync(RESULTS, log.join('\n') + '\n');
process.exit(broken === 0 && caught === MUTATIONS.length ? 0 : 1);
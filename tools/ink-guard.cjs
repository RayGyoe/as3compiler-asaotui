// tools/ink-guard.cjs -- the static half of the FIFTH colour channel.
//
// WHAT THE FOUR KNOWN CHANNELS ARE (see probes/widgets/theme, README, STATUS):
//   paint-time read   Theme.tokens().x read inside a widget's paint
//   factory-baked     a StyleRefinement built by a factory at describe time
//   baseline          Theme.controlDefault(kind), rebuilt by setTheme
//   overlay chrome    OverlayChrome's baked StyleRefinements, rebuilt by setTheme
//
// The fifth is the INK INSIDE A TextField, and it fails differently from all of
// them: it is not a fill and not a stroke, it is a RUN FORMAT written when the
// string was measured, and a run OUTRANKS `TextField.textColor` (compiler-gaps.md
// G48; src/emit.ts: `unsigned fcol = (tf->textColor != 0u && frn == 0) ? tf->textColor
// : run->color`). Two consequences make this class of defect invisible to the other
// four channels and to a pixel sample:
//
//   1. `textColor` alone is dead on any field that ever went through
//      `setTextFormat` -- which is every measured field.
//   2. a colour-only style change raises M_PAINT and NOT M_MEASURE
//      (Style.diffFlags splits the text fields for exactly that reason), so ink that
//      was written by `measureField` is NEVER refreshed by a palette swap.
//
// The hymn demo shipped with 86/86 text nodes stale for this reason; the theme
// probe then found two more instances in the kit itself (ButtonWidget never called
// applyInk at all; eight widgets left an unset `text.color` to measure's run, so the
// switch label stayed #000000 on the dark track). Both are fixed. This tool is what
// keeps the next widget from re-opening them.
//
// RULES (each has teeth; each names the file and line)
//   R1 `setTextFormat(` outside PaintKit.as            -- a second ink writer.
//   R2 `measureField` without any `applyInk` in a file -- ink that only measure writes.
//   R3 `text.color >= 0` as a guard                    -- "no colour" leaves measure's run.
//   R4 `.textColor =` outside PaintKit                 -- only the run-free trio may.
//   R5 `defaultTextFormat =` without `textColor =`     -- the run-free contract needs both.
//   R6 `applyInk(..., uint(s.text.color))`             -- use inkOf(n): the colour may be unset.
//
// The run-free trio (Input / TextArea / NumberInput) is the ONE legitimate exception:
// those widgets never call setTextFormat (InputWidget's header, defect b), so their
// field has no runs and `textColor` IS the ink. R2 asserts they really are run-free.
//
// USAGE: node tools/ink-guard.cjs [--verbose]      exit 0 = clean, 1 = risk found.
'use strict';

const fs = require('fs');
const path = require('path');

const UI = path.resolve(__dirname, '..');
const KIT = path.join(UI, 'kit');
const PAINTKIT = path.join('kit', 'asaot', 'ui', 'PaintKit.as');
// The documented run-free widgets: defaultTextFormat + textColor, never a run.
const RUN_FREE = ['InputWidget.as', 'TextAreaWidget.as', 'NumberInputWidget.as'];
const verbose = process.argv.includes('--verbose');

function walk(d, out) {
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.as')) out.push(p);
  }
  return out;
}

const files = walk(KIT, []).sort();
const risks = [];
function risk(file, line, text, why) {
  risks.push({ file: path.relative(UI, file).split(path.sep).join('/'), line, text, why });
}

let scanned = 0;
let applyInkCalls = 0;

for (const file of files) {
  const rel = path.relative(UI, file).split(path.sep).join('/');
  const isPaintKit = rel === PAINTKIT.split(path.sep).join('/');
  const base = path.basename(file);
  const isRunFree = RUN_FREE.indexOf(base) >= 0;
  const src = fs.readFileSync(file, 'utf8');
  const lines = src.split(/\r?\n/);
  scanned++;

  const hasMeasureField = /PaintKit\.measureField\s*\(/.test(src);
  const hasApplyInk = /PaintKit\.applyInk\s*\(/.test(src);
  const hasSetTextFormat = /\.setTextFormat\s*\(/.test(src);
  const hasDtfAssign = /defaultTextFormat\s*=/.test(src);
  const hasTextColorAssign = /\.textColor\s*=(?!=)/.test(src);
  const applyInkCount = (src.match(/PaintKit\.applyInk\s*\(/g) || []).length;
  applyInkCalls += applyInkCount;

  lines.forEach((text, i) => {
    const n = i + 1;
    const trimmed = text.trim();
    if (trimmed.startsWith('//')) return;   // comments describe these rules on purpose

    // R1 -------------------------------------------------------------------
    if (hasSetTextFormat && !isPaintKit && /\.setTextFormat\s*\(/.test(trimmed)) {
      risk(file, n, trimmed, 'R1 setTextFormat outside PaintKit: a run format outranks textColor (G48)');
    }
    // R2 -------------------------------------------------------------------
    // Checked per file, then reported on the measureField line.
    // R3 -------------------------------------------------------------------
    if (/text\.color\s*>=\s*0/.test(trimmed)) {
      risk(file, n, trimmed, 'R3 `text.color >= 0` leaves an unset ink to measure\'s run; use PaintKit.inkOf(n)');
    }
    // R4 -------------------------------------------------------------------
    if (!isPaintKit && !isRunFree && /\.textColor\s*=(?!=)/.test(trimmed)) {
      risk(file, n, trimmed, 'R4 .textColor outside PaintKit and outside the run-free trio');
    }
    // R5 -------------------------------------------------------------------
    if (!isPaintKit && !isRunFree && /defaultTextFormat\s*=/.test(trimmed)) {
      risk(file, n, trimmed, 'R5 defaultTextFormat outside the run-free trio');
    }
    // R6 -------------------------------------------------------------------
    if (/PaintKit\.applyInk\s*\(/.test(trimmed) && /uint\(\s*s\.text\.color\s*\)/.test(trimmed)) {
      risk(file, n, trimmed, 'R6 applyInk with uint(s.text.color): may be NaN; use PaintKit.inkOf(n)');
    }
  });

  // R2: a measured field's ink must not be measure-only.
  if (hasMeasureField && !hasApplyInk && !isPaintKit) {
    const at = lines.findIndex((l) => /PaintKit\.measureField\s*\(/.test(l)) + 1;
    risk(file, at || 1, 'PaintKit.measureField(...)',
      'R2 measure without applyInk: the run keeps the colour it had when measured, and a '
      + 'palette swap raises M_PAINT only -- the ink never refreshes');
  }
  // R5b: the run-free contract is only honest if the file has no runs at all.
  if (isRunFree && hasSetTextFormat) {
    const at = lines.findIndex((l) => /\.setTextFormat\s*\(/.test(l)) + 1;
    risk(file, at || 1, '.setTextFormat(...)',
      'run-free widget that calls setTextFormat: its textColor is now dead (G48)');
  }
  if (isRunFree && !hasTextColorAssign && hasDtfAssign) {
    const at = lines.findIndex((l) => /defaultTextFormat\s*=/.test(l)) + 1;
    risk(file, at || 1, 'defaultTextFormat = ...',
      'run-free widget sets defaultTextFormat but never textColor: the ink is whatever the '
      + 'format happened to carry');
  }
  if (verbose && (hasMeasureField || hasApplyInk)) {
    console.log('  ' + rel.padEnd(44) + ' measure=' + (hasMeasureField ? 'y' : 'n')
      + ' applyInk=' + applyInkCount);
  }
}

const measureFiles = files.filter((f) => /PaintKit\.measureField\s*\(/.test(fs.readFileSync(f, 'utf8')))
  .filter((f) => path.basename(f) !== 'PaintKit.as').length;

console.log('ink guard: ' + scanned + ' kit files, ' + measureFiles + ' measure their own field, '
  + applyInkCalls + ' applyInk call sites');
for (const r of risks) {
  console.log('INK-RISK ' + r.file + ':' + r.line + '  (' + r.why + ')\n         ' + r.text);
}
if (risks.length === 0) {
  console.log('RESULT: PASS (every measured field writes its ink on every paint)');
  process.exit(0);
}
console.log('RESULT: FAIL (' + risks.length + ' ink risk' + (risks.length === 1 ? '' : 's') + ')');
process.exit(1);
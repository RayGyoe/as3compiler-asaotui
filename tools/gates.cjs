// gates.cjs -- every acceptance gate for the asaotui workspace, in one command.
//
// WHY ONE COMMAND: each gate is an independent build+run of a real program, so
// "it passed" is only defensible if it is reproducible by a single invocation
// with a single exit code. Anything less and a green claim can quietly be a
// stale artifact or a gate that was never actually run.
//
// Every gate below has been MUTATION-TESTED (a one-unit change to the
// implementation or to the input makes it go red with a non-zero exit code):
//   chip 19     -- tone colour 1/255; layout gap 8->9
//   form 41     -- RadioWidget `*`->`Object` (the G9 regression); progress fill 1/255
//   display 48  -- badge danger colour 1/255; root padding 20->21
//   nav 41      -- TabsWidget SEL_BG 1/255; ListWidget SEL_BG 1/255
//   anim 14     -- A_HOT transitionMs 400->0 (the value must then JUMP, not
//                  interpolate); A_HOT background 1/255 (the landed pixel)
//   redraw 14   -- drop the `reconciled` term from UiApp's paint condition: a
//                  paint-only change then never reaches the screen (3 failures)
//   CheckMain 133 -- see layout-check/README.md
//   gallery   -- the multi-page demo: mutating UiNode.markLayoutDirty (the
//                ancestor walk) leaves the swapped-in page's subtree at 0x0, and
//                reverting the `resolveStyle(true)` call in applyPayload leaves the
//                reused body slot laying out in the PREVIOUS page's direction.
//                Both are structural, so the tour's hand-computed rects go red.
//   G13       -- probes/reach-freefn/mutation.cjs: two compiler mutations (mark
//                without expanding; seeds drained after the loop) re-create the
//                defect and the assertions go red (2/2, each restoring reach.ts
//                by hash). Fixed in 阶段二百四十九 -- this is now a tripwire on the
//                fix, not on a known defect.
//   dpi A/B   -- ui-demo/mutation-dpi.cjs: flipping the control descriptor to `high`
//                makes both arms render 1.5x and the assertions fire (2 failures).
//   fp parse  -- tools/mutation-parse.cjs: restoring the old per-record trim() makes 4
//                assertions go red (the path is sliced into `rc/reach.ts`).
//   G11       -- probes/g11-nondeterminism/mutation.cjs: six mutation groups (inject the
//                naming break into the HEALTHY artifact / point a props entry at a
//                field that does not exist / change one string literal in the source
//                (the hash must move) / flip the gate's own expectation / a generator
//                that MOVED mid-run must be INCONCLUSIVE / a move confined to ONE build
//                must be blamed on the move, not called nondeterminism) go red when
//                they should (10/10, restoring every file by hash). The gap itself is
//                closed -- this gate is the instrument that replaced "just retry".
//   style scan-- tools/mutation-bound-truthy.cjs: one planted `:Object` local used
//                as a condition in kit/ makes the tool exit 1. This gate used to
//                count a marker string the tool has never printed, so it could not
//                go red at all; it now delegates to the tool's exit code.
//   G14       -- probes/obj-array-identity/mutation.cjs: 4/4 (flip an AS3 rule /
//                drop a documented deviation / invent one / truncate the case list),
//                every file restored byte-for-byte.
//   vec vs arr-- probes/vec-vs-arr/mutation.cjs: 2/2, the strong one being "make the
//                Vector.<int> row actually RUN ON AN ARRAY", which collapses the
//                measured ratio and fires the >= 2x claim.
'use strict';
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const UI = path.resolve(__dirname, '..');
const COMPILER = path.resolve(UI, '..', 'as3compiler');
const clang = process.env.ASC_CC || 'clang';
const kit = require(path.join(UI, 'ui-demo', 'kit-list.cjs'));

const sh = (cmd, args, cwd, env) => spawnSync(cmd, args, { cwd, encoding: 'utf8', maxBuffer: 1 << 28, env: env ? { ...process.env, ...env } : process.env });
const tail = (s, n) => (s || '').split(/\r?\n/).filter((l) => l.trim() !== '').slice(-n).join('\n');

const gates = [];
const skipped = [];
function record(name, code, detail) {
  // Exit 3 is the one "could not measure" code any gate may return (only the G11
  // determinism gate does today): every assertion inside it was green, but the tree
  // it measured on was being edited by another session. It is reported as SKIP and
  // counted separately -- a green would certify an unknown tree, and a red would
  // blame this workspace for someone else's uncommitted edit. It is LOUD, never
  // silent, and the summary always states how many gates were skipped.
  if (code === 3) {
    skipped.push({ name, detail });
    console.log('[SKIP] ' + name + '  (exit 3: nothing violated, the compiler source MOVED mid-run)');
    const why = /blocked by: .*/.exec(detail || '');
    if (why) console.log('       ' + why[0]);
    return;
  }
  gates.push({ name, code, detail });
  console.log('[' + (code === 0 ? 'PASS' : 'FAIL') + '] ' + name + '  (exit ' + code + ')');
  if (code !== 0) console.log(tail(detail, 12));
}

// ---- 1..3: pure-AS3 probes (windowed; probe.cjs owns build+run+assert) -------
for (const p of ['widgets/chip', 'widgets/form', 'widgets/display', 'widgets/nav', 'widgets/anim', 'redraw']) {
  const r = sh(process.execPath, ['tools/probe.cjs', 'probes/' + p], UI);
  const out = (r.stdout || '') + (r.stderr || '');
  const m = /PROBE \S+: (\d+) checks, (\d+) failures/.exec(out);
  record('probe ' + p + (m ? ' (' + m[1] + ' checks, ' + m[2] + ' failures)' : ''), r.status, out);
}

// ---- 3b: the animator and the paint-sweep regression ------------------------
// `widgets/anim` is the animator's acceptance; `redraw` is the pin for the
// UiApp.reflow() fix (a reconciled frame must get a paint sweep). The animator
// HID that defect, because it calls markPaint on every frame of a tween, so an
// animating app repainted continuously and looked correct.
//
// ---- 4: layout text half -- the raw seam, no kit involved -------------------
{
  const seam = [
    '../asaotui/seam/asaot/ui/LayoutConstants.as',
    '../asaotui/seam/asaot/ui/LayoutEngine.as',
    '../asaotui/seam/asaot/ui/as3/As3LayoutNode.as',
    '../asaotui/seam/asaot/ui/as3/As3LayoutEngine.as'
  ];
  const r = sh(process.execPath,
    ['src/index.ts', '../asaotui/layout-check/CheckMain.as', ...seam,
     '--run', '--cc', clang,
     '-I', './vendor/curl/include', '-L', './vendor/curl/lib/windows-x64', '-l', 'zlib'], COMPILER);
  const out = (r.stdout || '') + (r.stderr || '');
  const m = /---- (\d+) checks, (\d+) failures ----/.exec(out);
  record('layout-check text half' + (m ? ' (' + m[1] + ' checks, ' + m[2] + ' failures)' : ''), r.status, out);
}

// ---- 5: kit behaviour / regression -----------------------------------------
{
  const r = sh(process.execPath, ['run-check.cjs'], path.join(UI, 'ui-demo'));
  const out = (r.stdout || '') + (r.stderr || '');
  const m = /CHECKUI: (\d+) checks, (\d+) failures/.exec(out);
  record('ui-demo CheckUi' + (m ? ' (' + m[1] + ' checks, ' + m[2] + ' failures)' : ''), r.status, out);
}

// ---- 6: layout visual half --窗口 + 帧缓冲读回 ---------------------------------
{
  const r = sh(process.execPath, ['layout-check/visual-check.cjs'], UI);
  const out = (r.stdout || '') + (r.stderr || '');
  const m = /(\d+) checks, (\d+) failures/.exec(out);
  record('layout-check visual half' + (m ? ' (' + m[1] + ' checks, ' + m[2] + ' failures)' : ''), r.status, out);
}

// ---- 6b: the multi-page demo tour -------------------------------------------
// This is the only gate that exercises a WHOLE app: four pages sharing one body
// slot, a widget-driven page switch, and rects that were hand-computed before the
// run (see ui-demo/demo/GalleryMain.as). It is the pin for the two layout fixes in
// UiNode (markLayoutDirty propagation out of a subtree, and re-resolving when a
// widget override changes the direction) -- neither is visible to a single-page
// probe, because a single-page app never swaps a subtree under an unchanged style.
{
  const r = sh(process.execPath, ['run-gallery.cjs'], path.join(UI, 'ui-demo'), { ASC_NO_OPEN: '1' });
  const out = (r.stdout || '') + (r.stderr || '');
  const m = /\[gallery\] RESULT: (\S+)/.exec(out);
  record('gallery tour: 4 pages, widget-driven switch, hand-computed rects' + (m ? ' (' + m[1] + ')' : ''), r.status, out);
}

// ---- 6c: the --air-app reachability probe (G13, fixed 阶段二百四十九) ----------
// Three measurements in one command: the closure MUST keep 5/5, and BOTH arms
// (plain `--air-app`, and `--all-sources`) MUST build+run the same source. The
// second arm is the control that says the two faces must agree -- a "fix" that
// disabled pruning would look fine on arm A alone. mutation.cjs re-introduces the
// defect in two independent ways to prove the probe has teeth.
{
  const r = sh(process.execPath, ['probes/reach-freefn/run.cjs'], UI);
  const out = (r.stdout || '') + (r.stderr || '');
  const m = /G13 PROBE: (\S+)/.exec(out);
  record('G13 air-app reach: closure keeps 5/5, both faces build+run' + (m ? ' (' + m[1] + ')' : ''), r.status, out);
}

// ---- 6d: the login demo, built with --air-app ----------------------------
{
  const r = sh(process.execPath, ['build-and-run.cjs'], path.join(UI, 'ui-demo'), { ASC_NO_OPEN: '1' });
  const out = (r.stdout || '') + (r.stderr || '');
  const m = /\[uidemo\] RESULT: (\S+)/.exec(out);
  record('login demo: --air-app descriptor, hand-derived rects, HiDPI PNG' + (m ? ' (' + m[1] + ')' : ''), r.status, out);
}

// ---- 6e: the descriptor is the CAUSE of the high-resolution pixels ----------
// Two builds of the same app from two descriptors that differ in exactly
// requestedDisplayResolution. The gate is the A/B itself: high MUST render above 1x
// and standard MUST render at exactly 1x, and both tours' logical rects must stay
// byte-identical. ~2.5 min, because it is two full builds -- and it is the only
// measurement that turns "the descriptor enables HiDPI" into a fact rather than a
// claim. Its teeth are shown by ui-demo/mutation-dpi.cjs (both arms high => the
// assertions fire).
{
  const r = sh(process.execPath, ['check-dpi.cjs'], path.join(UI, 'ui-demo'));
  const out = (r.stdout || '') + (r.stderr || '');
  const m = /RESULT: (\S+)/.exec(out);
  record('descriptor DPI A/B: standard 1x vs high >1x, same logical rects' + (m ? ' (' + m[1] + ')' : ''), r.status, out);
}

// ---- 7: style scan -- a value read from a binding / dynamic source must not be
// parked in an `Object`-typed local. -----------------------------------------
// HISTORY: this gate was written for G9, when `Boolean(<Object-typed local>)` was
// LOWERED WRONG (a plain pointer test, so a boxed `false` read as TRUE). G9 is
// fixed (阶段二百四十八) -- the pattern is no longer a correctness bug, and the gate
// is kept for the two reasons that survive:
//   (a) `var x:Object = binding.get()` BOXES the value (`as_value_to_obj`) -> one
//       GC allocation per read; `var x:*` does not.
//   (b) an ARRAY in an `Object` slot loses its identity and can even SIGSEGV the
//       process (G14) -- so `*` is the safe default for anything that may hold an
//       Array.
// DEFECT FIXED HERE: the gate used to count lines matching the string
// `Boolean-CALL`, which this tool has NEVER printed -- so `bad` was always empty
// and the gate could not go red whatever the kit contained. A nail that cannot
// fail certifies nothing. It now delegates to the tool's own exit code, with the
// printed marker as a second, independent signal.
//   mutation: tools/mutation-bound-truthy.cjs (one planted risky local -> red).
{
  const r = sh(process.execPath, ['tools/find-bound-truthy.cjs', 'kit', 'seam'], UI);
  const out = (r.stdout || '') + (r.stderr || '');
  const hits = out.split(/\r?\n/).filter((l) => /G9-RISK/.test(l)).length;
  const code = (r.status !== 0 || hits > 0) ? 1 : 0;
  record('style scan: no Object-typed local is used as a condition (' + hits + ' found)', code,
    out + (code ? '\nDeclare the local `*` instead of `Object`: no boxing allocation per read,\nand no Array-identity hazard (compiler-gaps.md G14).' : ''));
}

// ---- 8b: G11 is closed -- the generator IS deterministic, and here is why it
// looked otherwise. Five builds of one program must produce ONE generated C (with
// the input hashes recorded too), the three built-in field spellings must agree in
// the struct, the props table AND the hand-written body literal, and the three
// surviving artifacts from the window in which the naming was being rewritten must
// decay 20 -> 1 -> 0 clang errors. ~40 s (five builds). The tree-state line is part
// of the gate on purpose: a MODIFIED compiler tree means nothing could be certified,
// so this gate reports SKIP (exit 3) rather than a fake red -- nothing was violated,
// but nothing was measured either.
{
  const r = sh(process.execPath, ['probes/g11-nondeterminism/run.cjs'], UI);
  const out = (r.stdout || '') + (r.stderr || '');
  const m = /distinct hashes: (\d+) of (\d+)/.exec(out);
  record('G11 determinism: 5 builds -> 1 C, spellings agree, artifacts decay'
    + (m ? ' (' + m[1] + '/' + m[2] + ' hashes)' : ''), r.status, out);
}

// ---- 9: G14 -- does an Array in an `Object`-typed slot keep its identity? ----
// 26 cases, run on BOTH runtimes: our AOT (one process PER CASE, because several
// of them SIGSEGV) and real AIR (mxmlc + adl). The AIR arm is checked against a
// HAND-WRITTEN AS3 rule, so "AIR is the reference" is itself a measured claim.
// The gate is green while the AOT deviation set is EXACTLY the documented set
// (7 ids): a new deviation, a deviation that quietly vanishes, or a case that
// stops being run all go red. A vanishing deviation is the interesting one -- it
// is what a real compiler-side fix looks like, and the message says so.
//   mutation: probes/obj-array-identity/mutation.cjs (4/4, restoring by hash).
{
  const r = sh(process.execPath, ['probes/obj-array-identity/run.cjs'], UI);
  const out = (r.stdout || '') + (r.stderr || '');
  const m = /AOT deviations from AIR: (.*)/.exec(out);
  record('G14 array-in-Object-slot identity (26 cases, AOT vs AIR)'
    + (m ? ' -- deviations ' + m[1].trim() : ''), r.status, out);
}

// ---- 10: Vector.<T> is really faster than Array in OUR AOT -------------------
// The same benchmark body compiled by BOTH toolchains (so the only difference is
// the runtime). The claim: our AOT lowers `Vector.<T>` to a MONOMORPHIZED C struct
// (`int* data` / `double* data`) rather than an array of boxed `as_value` cells,
// so `Vector.<int>` is >= 2x faster than `Array` on fill+sum. If that lowering is
// ever lost -- a Vector silently lowered to `as_array`, an extra copy, a call per
// read -- the ratio collapses towards 1 and this gate fires.
// AIR is the reference arm and is deliberately NOT asserted: on AVM2 the JIT
// already specialises Array, so the two are within noise there. That contrast IS
// the finding (see probes/vec-vs-arr/README.md).
//   mutation: probes/vec-vs-arr/mutation.cjs (2/2, incl. making the Vector row
//   actually run on an Array, which collapses the ratio).
{
  const r = sh(process.execPath, ['probes/vec-vs-arr/run.cjs'], UI);
  const out = (r.stdout || '') + (r.stderr || '');
  const m = /AOT Vector\.<int> \/ Array = ([\d.]+)x/.exec(out);
  record('Vector vs Array throughput, both runtimes' + (m ? ' (AOT ratio ' + m[1] + 'x)' : ''), r.status, out);
}

// ---- 8: the instrument that certifies "we did not touch the compiler" -------// Instant (pure string parsing, no build). It is a gate because every
// "as3compiler/ is unchanged" claim in this workspace rests on this one tool, and
// it silently under-reported once: it trimmed the whole `git status` buffer, which
// ate the leading space of the common " M path" first line and dropped that entry.
// An instrument that under-reports certifies the wrong thing.
//   mutation: tools/mutation-parse.cjs (re-introduces the trim bug; 4 checks go red).
{
  const r = sh(process.execPath, ['tools/fingerprint-parse-check.cjs'], UI);
  const out = (r.stdout || '') + (r.stderr || '');
  const m = /FINGERPRINT PARSE: (\S+)/.exec(out);
  record('fingerprint porcelain parsing: no dropped records' + (m ? ' (' + m[1] + ')' : ''), r.status, out);
}

const failed = gates.filter((g) => g.code !== 0);
const total = gates.length + skipped.length;
console.log('');
console.log('==== ' + (gates.length - failed.length) + '/' + total + ' gates PASS'
  + (skipped.length ? ', ' + skipped.length + ' SKIPPED' : '') + ' ====');
if (failed.length) {
  console.log('FAILED: ' + failed.map((f) => f.name).join(' | '));
  process.exit(1);
}
if (skipped.length) console.log('SKIPPED: ' + skipped.map((s) => s.name).join(' | '));
console.log('RESULT: PASS' + (skipped.length ? ' (with ' + skipped.length + ' skipped)' : ''));
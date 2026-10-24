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
//   feedback 43 -- tools/mutation-widget-probes.cjs M1/M2/M5/M6: the skeleton plate
//                colour and the spinner arc colour each moved 1/255 (both are
//                hand-written pixels, so the failure names the exact coordinate); and
//                the two halves of the paint-scheduling contract a spinner depends on
//                -- M5 restores "clear M_PAINT after painting", which erases the very
//                request a paint pass raises for its own next frame ("repainted only
//                2 time(s) in 10 frames"), and M6 makes the spin ask for a LAYOUT bit
//                instead of paint ("spinning re-solved layout 9 time(s)").
//   media 43  -- tools/mutation-widget-probes.cjs M3/M4: the "fit" factor becomes
//                max instead of min (the 8x8 source grows to 80x80 and the letterbox
//                pixel that proves containment turns solid -- this is the DEFAULT
//                scale mode, added to the probe after the mutation sweep showed the
//                default was never exercised), and the scroll clamp forgets the
//                viewport height (the overscroll no longer stops at 60).
//   data 77   -- probes/widgets/data/mutation.cjs: 4/4 (SEL_BG 1/255; the slot
//                window inner w-2 -> w-1; the accordion mounting EVERY panel; and
//                the layering bug the probe found, re-introduced by giving a header
//                its own background again), every file restored byte-for-byte.
//   G16       -- probes/g16-ternary-null/mutation.cjs: 4/4 (patch the shape the
//                probe measures / claim a passing case is NULL / break a passing
//                case / make the AIR arm die by returning a bare null from both
//                branches, which the runner must report instead of silently
//                comparing against missing lines).
//   G14       -- probes/obj-array-identity/mutation.cjs: 4/4 (flip an AS3 rule /
//                drop a documented deviation / invent one / truncate the case list),
//                every file restored byte-for-byte.
//   vec vs arr-- probes/vec-vs-arr/mutation.cjs: 2/2, the strong one being "make the
//                Vector.<int> row actually RUN ON AN ARRAY", which collapses the
//                measured ratio and fires the >= 2x claim.
//   style fromAny -- probes/style-fromany/mutation.cjs: 4/4 (drop an array branch /
//                swap an [h,v] pair / hard-code `is Array` on an Object param to
//                false), every file restored byte-for-byte. This is the gate on the
//                REVERT of the workaround G14 had forced on the style layer.
//   overlay 65 -- probes/widgets/overlay/mutation.cjs: 9/9. Five of the nine are the
//                REAL DEFECTS the probe found while it was written (overlay tree
//                solved once against the pre-window fallback and never re-solved; a
//                panel surface that was never created, so its rect was right and it
//                painted nothing; the control's own `width` option leaking into a
//                style shorthand and shrinking the layer; row routing that read a
//                target-relative localY; a visibility flip that raised no arrange
//                bit and never reached the display object; and a click inside a SUBMENU
//                that was also read as a click on the parent row underneath it). The
//                other four move a hand-computed pixel/geometry by one unit (incl. the
//                submenu's parent-local conversion and the flip's clamp).
//   interact 25 -- probes/widgets/interact/mutation.cjs: 8/8. Every mutation is one of
//                the four features the phase added, turned OFF: nothing reads
//                state.hover / the press sink / the disabled dimming / the focus ring /
//                the inert skip in the tab ring / Event.CHANGE write-back / the Enter
//                commit. Two of them are also the defects this probe found (a
//                read-only field and an onChange the node never carried).
//   flip 54   -- probes/widgets/flip/mutation.cjs: 5/5, the five ways a placement can
//                go wrong (no vertical flip, the panel's own height dropped, no
//                sideways flip, the parent-local conversion dropped, the clamp
//                dropped). A flip is invisible when missing -- the panel is still a
//                panel with a valid rect -- so the probe asserts a NUMBER.
//   gallery teardown -- ui-demo/mutation-gallery-teardown.cjs: 2/2, and both are
//                defects the SIX-page tour found and no probe could (a probe never
//                destroys an overlay tree): dropping the WidgetTeardown hook leaves
//                a destroyed menu's stage listener running on a nulled scratch bag
//                (#1009 on the next click -> the tour never finishes), and dropping
//                the root detach leaves the empty host Sprite on the stage (the
//                tour's stage.numChildren verdict names it).
//   array(x)  -- probes/array-coerce/: `Array(arg)` must wrap a non-number in ONE
//                element on BOTH runtimes (SQL: Array([1,2]).length == 1 and [0] is
//                Array). Found when `Array(opts.items)` in the overlay factories
//                threw #1034 in the AOT; OptionSupport.list() is the replacement.
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
for (const p of ['widgets/chip', 'widgets/form', 'widgets/display', 'widgets/nav', 'widgets/anim',
                 'widgets/feedback', 'widgets/media', 'widgets/data', 'widgets/overlay',
                 'widgets/interact', 'widgets/flip', 'redraw']) {
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
// This is the only gate that exercises a WHOLE app: six pages sharing one body
// slot, a widget-driven page switch, a SECOND retained tree (page 5 floats a
// dialog + menu + toast on the overlay root and tears it down again), and rects
// that were hand-computed before the run (see ui-demo/demo/GalleryMain.as). It is
// the pin for the two layout fixes in UiNode (markLayoutDirty propagation out of a
// subtree, and re-resolving when a widget override changes the direction) --
// neither is visible to a single-page probe, because a single-page app never swaps
// a subtree under an unchanged style -- and for the two teardown fixes (a destroyed
// overlay's stage listener; the overlay root being left on the stage), which need a
// page switch to be visible at all.
{
  const r = sh(process.execPath, ['run-gallery.cjs'], path.join(UI, 'ui-demo'), { ASC_NO_OPEN: '1' });
  const out = (r.stdout || '') + (r.stderr || '');
  const m = /\[gallery\] RESULT: (\S+)/.exec(out);
  record('gallery tour: 6 pages (incl. the overlay tree), hand-computed rects' + (m ? ' (' + m[1] + ')' : ''), r.status, out);
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
//   (b) `*` is also the safe default for a value that may be an Array, which was a
//       CORRECTNESS reason while G14 lived. G14 is fixed now (阶段二百五十三), so only
//       (a) remains -- `*` is still the default because it is the cheaper correct
//       one, not because the other is broken.
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
// of them SIGSEGV'd before the fix) and real AIR (mxmlc + adl). The AIR arm is
// checked against a HAND-WRITTEN AS3 rule, so "AIR is the reference" is itself a
// measured claim.
// The gate is green while the AOT deviation set is EXACTLY the documented set: it
// is EMPTY since as3compiler 阶段二百五十三 (v0.4.217) and held 7 ids before that. A
// new deviation goes red; so does a case that stops being run. The interesting
// direction is the other one -- a deviation VANISHING without expect.json being
// updated also goes red, and the message says "if this is the fix, shrink the
// recorded set" -- because a silently shrinking set would let a regression hide
// behind a stale expectation.
//   mutation: probes/obj-array-identity/mutation.cjs (4/4, restoring by hash).
{
  const r = sh(process.execPath, ['probes/obj-array-identity/run.cjs'], UI);
  const out = (r.stdout || '') + (r.stderr || '');
  const m = /AOT deviations from AIR: (.*)/.exec(out);
  record('G14 array-in-Object-slot identity (26 cases, AOT vs AIR)'
    + (m ? ' -- deviations ' + m[1].trim() : ''), r.status, out);
}

// ---- 9b: G16 -- `cond ? null : X` collapses to a zero value -----------------
// A null LITERAL in the THEN slot makes unifyType fall through to "keep the
// then-branch type" (src/emit.ts:28936), so the whole conditional is typed `null`
// and `convert` emits it as a CONSTANT zero (0 / false / NULL) -- the branch that
// would actually run is thrown away. 17 cases, run on BOTH runtimes; the AIR arm is
// checked against a HAND-DERIVED rule, so "AIR is the reference" is itself measured.
// As with G14 before its fix, the gate is green while the AOT deviation set is
// EXACTLY the documented one. A new deviation goes red; so does a case that stops
// being run; and so does a deviation VANISHING without this list being updated --
// because a silently shrinking set would let a regression hide behind a stale
// expectation. The failure message says which direction to fix.
const G16_KNOWN = ['1', '3', '4', '5', '7', '8', '9', '10', '14', '15', '16', '17'];
{
  const r = sh(process.execPath, ['probes/g16-ternary-null/run.cjs'], UI);
  const out = (r.stdout || '') + (r.stderr || '');
  // Only "our AOT says X but AIR says Y" lines: an AIR-arm disagreement or a crash
  // must never be mistaken for the documented deviation set.
  const aotIds = [...new Set([...out.matchAll(/FAIL  id (\d+): our AOT says/g)].map((m) => m[1]))]
    .sort((a, b) => Number(a) - Number(b));
  const armBad = /the REFERENCE disagrees|arm wrote only/.test(out);
  const same = !armBad && aotIds.join(',') === G16_KNOWN.join(',');
  record('G16 ternary-null (17 cases, AOT vs AIR) -- AOT deviations: '
    + (aotIds.join(',') || 'none'), same ? 0 : 1,
    out + (same ? '' : '\nThe AOT deviation set is no longer the recorded one (' + G16_KNOWN.join(',') + ').'
      + '\nIf the compiler FIXED G16, that is good news: shrink the recorded set here AND in'
      + '\nprobes/g16-ternary-null/expect.json, and re-point its mutation M1 (its header says how).'
      + '\nAny other change is a regression.'));
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

// ---- 11: the style layer's `fromAny` is TOTAL -------------------------------
// The style layer used to split every entry point in two -- `fromAny(o:Object)` for
// scalars and `fromArray(a:Array)` for arrays -- because an Array put into an
// Object-typed parameter lost its identity in our AOT, and a following `is Fill`
// even SIGSEGV'd (G14). 阶段二百五十三 fixed G14, and the split was then REVERTED:
// `fromAny` now dispatches the array form itself, so no call site has to know the
// shape of the value it forwards. This gate makes that revert a measurement rather
// than a hope -- it asks the questions the library actually depends on (does
// `is Array` hold for an Object-typed parameter? does every documented shape still
// land where it should?) on BOTH runtimes, against answers HAND-DERIVED in
// expect.json (the AIR arm is checked against them too, so "AIR is the reference"
// is itself measured).
// A short line count from either arm is a CRASH, not a pass: the case that died
// stops the program, so the runner fails on the missing tail.
//   mutation: probes/style-fromany/mutation.cjs (4/4 -- drop an array branch, swap
//   an [h,v] pair in two different types, and hard-code the mechanism itself to
//   false; every file restored byte-for-byte by hash).
{
  const r = sh(process.execPath, ['probes/style-fromany/run.cjs'], UI);
  const out = (r.stdout || '') + (r.stderr || '');
  const m = /RESULT: (\S+.*)/.exec(out);
  record('style fromAny is total: 19 cases, AOT vs AIR' + (m ? ' (' + m[1].trim() + ')' : ''), r.status, out);
}

// ---- 7b: `Array(x)` wraps -- the runtime fact the overlay factories ran into ---
// Eight cases on BOTH runtimes: the AOT arm and the AIR arm must agree, case by
// case. This is not a compiler-gap probe (there is no gap -- AIR behaves the same);
// it exists because the library got this wrong once: `Array(opts.items)` was used
// to normalise "one item or a list" and threw #1034 in the AOT on a BoxNode, since
// `Array([a,b])` is a ONE-element array in AS3 and not a copy of the list. The fix
// is `OptionSupport.list()`, and this gate is the measurement that keeps anyone
// from "simplifying" it back. The AIR arm is what makes "this is AS3, not our bug"
// a measurement instead of an assertion.
{
  const r = sh(process.execPath, ['probes/array-coerce/run.cjs'], UI);
  const out = (r.stdout || '') + (r.stderr || '');
  const m = /RESULT: (\S+.*)/.exec(out);
  record('Array(x) wraps on both runtimes (8 cases, AOT vs AIR)' + (m ? ' (' + m[1].trim() + ')' : ''), r.status, out);
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
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
//                tools/mutation-docs-tour.cjs adds three more on the surfaces only a
//                CLICK and a CHROME ORDER can reach (3/3, each restoring its file by
//                hash): the toastHost demo asking toast() for the chip tone it
//                THROWS on (the bug the user reported -- the frame guard hid it, so
//                the page still rendered and 41 screenshots looked fine); the toast
//                layer's gap 8 -> 0 (geometry only, nothing throws); and the scroll
//                bar layer being counted as content base again, which buries the
//                bars under every content child on a page switch.
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
//   G16       -- probes/g16-ternary-null/mutation.cjs: 4/4. G16 is FIXED (stage 266),
//                so the mutations measure the HARNESS instead of the defect: the rule
//                is checked against AIR (not assumed), the AIR arm is rebuilt from the
//                source (not read off a stale file), an arm that dies mid-run is
//                reported, and a build failure is never mistaken for agreement. The
//                two mutations that used to measure the collapse itself went vacuous
//                the day it was fixed -- its header records why they were re-pointed
//                rather than deleted.
//   G19       -- probes/g19-roundrect/: the gate itself is the A/B (92 geometry rows x
//                40 lines each + 13 argument cases, AIR vs AOT). Its teeth are the
//                ANALYTIC check: every row must sit within 1 px of the exact corner
//                ellipse computed from the case table, so a renderer that silently
//                drops a radius (the old stub) or clamps the wrong axis fails the math,
//                not just a snapshot. Mutation: temp/g16g19g20 (the stub itself was the
//                "mutation" until stage 267 -- restoring `(void)ew; (void)eh;` makes
//                every rounded row go square and the geometry comparison fails).
//   G20       -- probes/g20-settextformat/mutation.cjs: 5/5 (3 mutations inside
//                src/emit.ts's TextField_setTextFormat -- stop dropping covered runs /
//                lose the right remainder of a split / drop the trailing insert -- plus
//                "the rule is checked against AIR" and "a build failure is never
//                agreement"), every file restored byte-for-byte by hash.
//   G21       -- probes/g21-gettextformat/: the gate is the 30-case range matrix run on
//                both runtimes (no run / inside one run / straddling / reversed / empty
//                span / equal neighbours / #2006 bounds / -1 meaning "not supplied"),
//                plus a source audit of the emitted getTextFormat. Teeth:
//                probes/g21-gettextformat/mutation.cjs 5/5.
//   G22       -- probes/g22-closure-statics/: 10 cases on both runtimes AND a source
//                audit of the emitted C -- every statically-initialised class read must
//                be spelled `(Owner_cinit(), Owner_FIELD)` and the forward declaration
//                must precede the first call. This is the gate on code that only reads
//                its constants from inside factory closures (which is how UI pages are
//                written). Teeth: probes/g22-closure-statics/mutation.cjs 4/4.
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
//   popup 26  -- probes/widgets/popup/mutation.cjs: 4/4. The first is the REPORTED
//                defect itself (a popup that never leaves its owner's child list is
//                painted under the next sibling -- it stays a real requirement of the
//                engine that painting order IS sibling order, so the node has to
//                re-parent to be on top); the other three are the ways a lift can be
//                half-done: keeping the parent-relative x (the popup jumps by the
//                owner's own offset), never re-attaching on close, and detaching only
//                when the display parent happens to be `parent.backing` (a lifted
//                node is NOT, so its sprite stays on screen forever).
//   typing 18 -- probes/widgets/typing/mutation.cjs: 4/4. The first report is here
//                verbatim: forcing the ghost visible (the placeholder that stays
//                while you type). The second was "the text doubles on repaint",
//                whose COMPILER half (G20: the setter appended a run per call) was
//                fixed in stage 268 -- so M3 was re-pointed, the way the G16
//                mutations were, at the assertion it was never really about: paint
//                now writes the string twice and the single-copy pin (live width vs
//                a fresh field, ink extent) has to catch it. The other two are the
//                focus gate on the ghost and a blur that never reports the commit.
//                NOTE the probe's onChange deliberately does NOT invalidate: the
//                field owes the screen its own repaint, and an author-side invalidate
//                would hide that.
//   textfx 18 -- probes/widgets/textfx/mutation.cjs: 9/9. Three of them are boxShadow,
//                gradient fills and the textArea/Return contract inversion: the filter
//                list is built and then NOT handed to the display object (every property
//                correct, screen unchanged); the radial fallback the kit refuses -- painting
//                the first stop as a solid keeps the left edge dark and only the ramp check
//                sees it; and a text area that CONSUMES Return still compiles, still renders,
//                and quietly reverts the field instead of inserting a line break.
//                The three new ones are textDecoration (G28's workaround: G28 itself is
//                fixed as of as-aot v0.4.303, so these pin the LIBRARY's own rule set --
//                all three kinds off one set of line metrics -- and not a compiler defect): PaintKit.decorate(n) never called
//                (the property is parsed, cascaded and never reaches the shape -- a model
//                assertion would still pass); line-through drawn where the underline goes
//                (one line, wrong place, which is why the probe samples the STRIKE node
//                separately); and the rule drawn from the field's origin instead of the
//                line box's `lm.x` (an inset or centred run gets a rule that starts too
//                early -- still "an underline" to any check that only counts ink).
//                The ninth is a text node with no PAINT BOX: `background` / `borderColor`
//                are style fields every kind is supposed to honour, but PaintKit.paintBox
//                bails on a null shapeA, so a text node accepted them and painted nothing --
//                geometry, glyphs and every property assertion unchanged, which is exactly
//                why a pixel inside the box had to ask the question (found by the docs audit:
//                three tinted 300px alignment lines came out untinted).
//   keys 36   -- probes/widgets/keys/mutation.cjs: 4/4, one per way a keyboard list can
//                be wrong while its model is right: list Down at the last row WRAPS
//                (it must clamp -- ARIA listbox is a sequence, a ring is for tree/tabs);
//                tabs Left from 0 CLAMPS (it must wrap -- a tab strip is a ring); the
//                virtual table selects a row it never scrolls into the mounted window
//                (index valid, model moved, nothing on screen); and the key writes the
//                widget's private `extra[SEL_KEY]` instead of the Binding (the picture
//                still moves, so only the author model sees it -- and it is the split
//                that later makes payload stop repainting, because it can no longer
//                observe the change).
//   accordion 18 -- probes/widgets/accordion/mutation.cjs: 4/4, all on the NEW multi mode
//                (`openIndices`), which single mode cannot exercise: the header fill
//                ignores the open SET and highlights "the first section"; the factory
//                mounts only the first open panel (a section listed as open with no
//                content on screen); a toggle REPLACES the set with the clicked index
//                (single mode wearing a multi name -- every "the set changed" assertion
//                still passes, which is why the probe names the members); and the
//                exclusive-option guard is gone, so `mode:"multi"` + `activeIndex` is
//                accepted and one of the two states is silently ignored (nothing on
//                screen changes -- only the THROW assertion can see it).
//                NOTE how two of these were found: the runner refuses to call a SKIPPED
//                anchor a pass, and both A4 and K4 were skipping because their anchors
//                spanned text that had moved or that held AS3-escaped quotes. A mutation
//                that never ran is a mutation that certified nothing.
//   imaging 31 -- probes/widgets/imaging/mutation.cjs: 8/8. The first five are the older
//                batch (the src/onLoad arm, the "fit" factor, the failure placeholder);
//                M6-M8 are the "cover" mode added on top: max() becomes min() so cover
//                CONTAINS instead of filling (the whole mode degrades to a no-op that
//                still looks like a picture); the scrollRect window is written in the
//                BOX's units instead of the bitmap's (the renderer clips through the
//                object's own matrix, so a 24-unit window on a 3x bitmap is 72 device
//                pixels and the picture is cropped to nothing -- measured, the first
//                version of this read #ffffff everywhere); and leaving "cover" never
//                clears the window, so the next scale mode inherits a crop it did not ask
//                for (exactly the stale-state failure the arrange comment warns about).
//   inputs 50  -- tools/mutation-widget-inputs.cjs: 8/8, one per assertion a resting
//                bitmap cannot see. The +1 partial row (six mounted rows become five and
//                the list still scrolls); the viewport clip (the mounted-but-offscreen row
//                paints #606060 under the edge); the ABSOLUTE click index (a scrolled list
//                reports row 0 for a click on row 3); the focus claim a row click makes
//                (End after a click never reaches the list -- found by WRITING the probe,
//                not by reading the code); reveal() as a no-op (End selects the last row
//                and leaves the window behind); clamp() without its upper bound (PageUp
//                to 25 when max is 10); the stepper strip (a press on the painted `+`
//                lands in the text field); and a multi-select toggle that closes the menu
//                (the gesture becomes a single-select and still LOOKS like a picker).
//   gallery teardown -- ui-demo/mutation-gallery-teardown.cjs: 2/2, and both are
//                defects the SIX-page tour found and no probe could (a probe never
//                destroys an overlay tree): dropping the WidgetTeardown hook leaves
//                a destroyed menu's stage listener running on a nulled scratch bag
//                (#1009 on the next click -> the tour never finishes), and dropping
//                the root detach leaves the empty host Sprite on the stage (the
//                tour's stage.numChildren verdict names it).
//   kind cov. -- tools/mutation-kind-coverage.cjs: 3/3 (the tree call renamed in the
//                demo; a NEW kind+factory that nothing calls -- the regression that
//                happened twice; and the call surviving only in a `//` comment, which
//                the scan's first version counted as code).
//   demo opts -- tools/mutation-demo-options.cjs: 3/3 (a bogus key on a REAL call;
//                progress() losing its `value` read, i.e. the kit moving out from
//                under correct docs; and one style shorthand deleted from
//                StyleRefinement.from, which proves the shorthand allowance is
//                DERIVED from the source rather than a blanket amnesty -- the first
//                version of that mutation only disabled the read behind `false &&`
//                and the scan stayed green, so the anchor is now the whole line).
//   cb arity  -- tools/mutation-callback-arity.cjs: 6/6, three per direction. Re-arming
//                each of the four zero-argument calls the REPORTED bug shipped, a
//                handler in ui-demo that loses its parameter, and an onClick that
//                declares a MouseEvent (the argument the glue never passes). This is
//                the static half: a #1063 from a call/declaration mismatch is invisible
//                in a screenshot -- the frame guard restores the frame, the handler
//                simply never runs -- so the docs' slider shipped a dead callback.
//   callback 24 -- probes/widgets/callback/mutation.cjs: 8/8. The behavioural half, on
//                UNBOUND controls (probes/widgets/form only ever clicks BOUND ones, and
//                that is exactly why the defect escaped): a handler that never runs, a
//                drag that does not follow, a mouseMove the widget ignores (a slider
//                that looks draggable and is not), a missing repaint request (sampled
//                MID-drag -- the release flips the pressed state and that repaint would
//                hide it), a release that ends nothing, and a de-duplication gate that
//                turns one gesture into two model writes.
//   array(x)  -- probes/array-coerce/: `Array(arg)` must wrap a non-number in ONE
//                element on BOTH runtimes (SQL: Array([1,2]).length == 1 and [0] is
//                Array). Found when `Array(opts.items)` in the overlay factories
//                threw #1034 in the AOT; OptionSupport.list() is the replacement.
//   air arm   -- tools/mutation-air-arm.cjs: 2/2, and both are ways the AIR arm of the
//                docs app stops COMPILING (AIR is the reference runtime, so "it does
//                not build on the reference compiler" is a portability defect, not a
//                wish): one demo page loses an `import` the AOT resolves for free
//                (the command this was found with -- `box` is a package-level
//                function, so an unimported call is legal to OUR compiler and
//                invisible to mxmlc), and `DocsAir` starts touching an AOT-ONLY test
//                hook (`Stage.render`), which is exactly why the AIR entry class is
//                separate from the touring `DocsMain` in the first place.
//   air sweep -- tools/mutation-air-sweep.cjs: 3/3. The one gate that RUNS adl over
//                all 42 pages with every popup open, because our AOT is more forgiving
//                than AIR: `setChildIndex` past the end throws #2006 there and clamps
//                here, so `fixDisplayOrder` throwing once per frame on the
//                select/combobox/datePicker pages was invisible to every AOT probe and
//                to a render-only 42-page screenshot sweep. The three mutations are the
//                defect itself (the display slot computed from the description index),
//                a sweep that stops OPENING the popups (42 pages, 0 errors, blind), and
//                a sweep that stops one page early (a dead window must not look green).
//   gpu mode  -- tools/mutation-buildsh-gpu.cjs: 5/5. `--gpu cpu|gpu|d3d12|gl|direct`
//                is unverifiable by eye -- all five modes draw the same 42 pages, and a
//                mode that is parsed and then dropped looks exactly as correct as one
//                that works. So the gate pins the two things that DO differ: the derived
//                descriptor (one line off app.xml) and the argv the AOT arm gets. The
//                five mutations are the five ways to get those wrong, including a
//                descriptor that drifts a second line -- which is precisely the HiDPI
//                A/B that `check-dpi.cjs` demands.
'use strict';
const fs = require('fs');
const path = require('path');
const { spawnSync, spawn } = require('child_process');

const UI = path.resolve(__dirname, '..');
const COMPILER = path.resolve(UI, '..', 'as3compiler');
const clang = process.env.ASC_CC || 'clang';
const kit = require(path.join(UI, 'ui-demo', 'kit-list.cjs'));

// ---------------------------------------------------------------------------
// HOW THE GATES RUN: IN PARALLEL, BOUNDED, AND FILTERABLE.
//
// Every gate here is an independent build + program: no gate reads another's
// output, and each probe owns its own directory. Running them one at a time made
// a full pass take 40+ minutes on a 12-core machine, which is the point where the
// suite stops being run at all -- and a suite nobody runs certifies nothing.
//
//   ASC_GATE_JOBS=6        how many PROBES may build/run at once (default 6)
//   --jobs N               the same, from the command line
//   --only <regex>         run only the gates whose name matches (case-insensitive).
//                          Unselected gates are STUBBED, not silently passed --
//                          see the `stubbed` counter in `record()`.
//   ASC_GATE_TIMEOUT_MS    per-gate ceiling (default 420s). A hung child is killed.
//   ASC_PROBE_DEADLINE_MS  per-probe ceiling inside the pool (default 360s).
//
// Only the PROBE block is concurrent (it is ~50 of the ~66 gates and ~90% of the
// wall clock). The rest are single builds that already finish in seconds, and
// leaving them serial keeps their shared `ui-demo/` outputs uncontended. The
// STOPWATCH probes are taken out of the pool on purpose: `perf` asserts a 15ms
// ceiling on a no-change describe, and a frame-counting probe (`anim`, `feedback`,
// `motion`) counts repaints across frames -- both would measure the pool's own load
// instead of the kit. They run alone, after the pool drains, and say so.
const ARGV = process.argv.slice(2);
const argVal = (flag) => {
  const i = ARGV.indexOf(flag);
  return i >= 0 && i + 1 < ARGV.length ? ARGV[i + 1] : null;
};
const ONLY = argVal('--only') || process.env.ASC_GATE_ONLY || '';
const ONLY_RE = ONLY ? new RegExp(ONLY, 'i') : null;
const JOBS = Math.max(1, Number(argVal('--jobs') || process.env.ASC_GATE_JOBS || 6));
const omitted = [];
const T0 = Date.now();
let lastRecordAt = Date.now();
const secs = (ms) => (ms / 1000).toFixed(1) + 's';

// STOPWATCH PROBES: correct only when nothing else is hogging the cores.
//   perf     -- asserts a 15ms ceiling on a no-change describe.
//   anim     -- a 400ms transition must INTERPOLATE, so it is sampled per frame.
//   feedback -- counts repaints across 10 frames (a spinner).
//   motion   -- same shape: a paint-sweep count, not a pixel.
//   touch-scroll -- the coast integrates WALL-CLOCK dt, so a starved window coasts
//               for fewer frames and "the third release did not coast (still at 20)"
//               fires. Measured: green alone, red inside a 6-wide build pool.
// Everything else asserts geometry and exact pixels, which do not care how busy the
// machine is.
const SOLO_PROBES = ['perf', 'widgets/anim', 'widgets/feedback', 'widgets/motion',
  'widgets/touch-scroll'];

// ---- the AIR reference runtime, resolved ONCE -------------------------------
// Nine gates run a second arm under real AIR (mxmlc + adl). Each of them builds
// the AOT arm FIRST, so a missing SDK used to cost minutes per gate and then
// report a RED that blames this workspace for the state of the machine. A missing
// reference runtime is "could not measure" -- exit 3, reported as SKIP, never as
// a pass, and the AOT arm is not built either (an arm with nothing to compare
// against proves nothing, and building it is what cost the minutes).
//
// THE SKIP ITSELF WAS WRONG FOR THREE ROUNDS. This function used to ask only
// AIRSDK_HOME and PATH; on the dev box the SDK lives in
// ~/Documents/Software/AIRSDK/AIRSDK_51.4.1 and the PATH entry
// (".../AIRSDK_51.2.1/bin") was a leftover from an uninstalled version, so nine
// gates reported "the AIR reference runtime is not installed" while mxmlc
// compiled the docs app in 1.8 s. "Not on PATH" is not "not installed": the
// resolution now goes through tools/air-sdk.cjs (env -> PATH -> install
// locations, each verified as a launcher THIS HOST can run), and the banner
// states which root was used, so a SKIP can no longer be mistaken for a fact.
const { resolveAirSdk, describe: describeAirSdk } = require('./air-sdk.cjs');
const SKIP_AIR = process.env.ASC_SKIP_AIR === '1';
const AIR_SDK = SKIP_AIR
  ? { root: null, complete: false, source: 'ASC_SKIP_AIR', notes: [], tried: [] }
  : resolveAirSdk();
const AIR_ROOT = AIR_SDK.complete ? AIR_SDK.root : null;
// State the answer ONCE, before any gate runs. Nine gates depend on it, so "why did those
// nine skip" must be answerable from the top of the transcript, not by re-deriving it.
if (AIR_ROOT) console.log('[air] reference runtime: ' + AIR_ROOT + '  (via ' + AIR_SDK.source + ')');
else if (SKIP_AIR) console.log('[air] reference runtime: SKIPPED ON PURPOSE (ASC_SKIP_AIR=1)');
else console.log('[air] ' + describeAirSdk(AIR_SDK).replace(/^\[air-sdk\] /, '[air] '));
// Only when there IS a root: `--sdk null` would be printed in a [OMIT]/[skip] line and
// read as if a path had been chosen.
const AIR_SDK_ARGS = AIR_SDK.root ? ['--sdk', AIR_SDK.root] : [];
const AIR_RUNNER = /(obj-array-identity|g16-ternary-null|g19-roundrect|g20-settextformat|g21-gettextformat|g22-closure-statics|vec-vs-arr|style-fromany|array-coerce|mxmlc-check\.cjs|air-sweep\.cjs)/;

// EVERY CHILD IS BOUNDED, AND THAT IS NOT AN OPTIMISATION.
//
// These gates launch REAL WINDOWS (a probe, the gallery tour, an AIR app under adl).
// A program that errors on startup does not exit: it sits there with a window up and
// writes no verdict, and `spawnSync` without a `timeout` waits for ever -- so one bad
// build turns `node tools/gates.cjs` into a command that never returns. Measured: a
// full run that looked like "just slow" was a launch block, not a build.
//
// 15 minutes is a CEILING for the slowest legit gate (the web/emcc arm and the AIR
// sweep), not a budget anyone should need; `ASC_GATE_TIMEOUT_MS` lowers it. A killed
// child is reported as 124 with a `[TIMEOUT]` line naming the command, never as a
// silent `exit null`.
// 7 minutes, not 15: the ceiling exists for a CHILD THAT HANGS, and every gate
// that is legitimately slow (the two diorama tours, the web/emcc arm) is measured
// at well under two. A 15-minute ceiling meant one bad gate looked exactly like
// "the suite is just slow" for a quarter of an hour.
const GATE_TIMEOUT_MS = Number(process.env.ASC_GATE_TIMEOUT_MS || 420000);
// A gate whose commands were STUBBED by --only must never be reported as a pass:
// its "output" is empty and every assertion in it would trivially hold. `record()`
// drops any gate that issued a stubbed command since the previous record.
let stubbed = 0;
let lastStubCommand = '';
const sh = (cmd, args, cwd, env) => {
  const joined = [String(cmd), ...args].join(' ');
  if (ONLY_RE && !ONLY_RE.test(joined)) {
    stubbed++;
    lastStubCommand = joined;
    return { status: 0, stdout: '', stderr: '' };
  }
  if (!AIR_ROOT && AIR_RUNNER.test(joined)) {
    return {
      status: 3, stdout: '[skip] the AIR reference runtime is not installed: ' + describeAirSdk(AIR_SDK)
        + '\n         (ASC_SKIP_AIR=1 suppresses this search on purpose). The AOT arm was not'
        + ' built either -- a comparison arm with nothing to compare against proves nothing.\n',
      stderr: '',
    };
  }
  const t = Date.now();
  const r = spawnSync(cmd, args, {
    cwd, encoding: 'utf8', maxBuffer: 1 << 28,
    env: env ? { ...process.env, ...env } : process.env,
    timeout: GATE_TIMEOUT_MS,
    killSignal: 'SIGKILL',
  });
  r.ms = Date.now() - t;
  if (r.status === null && r.signal) {
    console.log('[TIMEOUT] ' + path.basename(String(cmd)) + ' ' + args.join(' ')
      + '  killed after ' + Math.round(GATE_TIMEOUT_MS / 1000) + 's'
      + ' (the window never published a verdict, or the build never finished);'
      + ' raise ASC_GATE_TIMEOUT_MS if this gate is legitimately slower');
    return { ...r, status: 124 };
  }
  return r;
};
const tail = (s, n) => (s || '').split(/\r?\n/).filter((l) => l.trim() !== '').slice(-n).join('\n');

const gates = [];
const skipped = [];
function record(name, code, detail, ms) {
  // --only: a gate this run did not execute. Reported in ONE line at the end, and
  // never counted either way -- an unselected gate is neither green nor red.
  if (ONLY_RE && !ONLY_RE.test(name)) { omitted.push(name); stubbed = 0; return; }
  // A stubbed gate (some command in it was skipped because --only filtered it) has
  // an empty transcript, so every assertion in it would trivially hold. Refuse it.
  // Reaching this point means the NAME matched (the check above runs first), so the
  // stub is the pattern's fault -- say so instead of reporting 0/0 in silence.
  if (stubbed > 0) {
    omitted.push(name);
    console.log('[OMIT] ' + name + '\n       --only "' + ONLY + '" matched this gate name but not its command:'
      + ' `' + lastStubCommand.slice(0, 90) + '`; widen the pattern');
    stubbed = 0;
    return;
  }
  const took = '   ' + secs(ms != null ? ms : Date.now() - lastRecordAt);
  lastRecordAt = Date.now();
  // Exit 3 is the one "could not measure" code any gate may return (only the G11
  // determinism gate does today): every assertion inside it was green, but the tree
  // it measured on was being edited by another session. It is reported as SKIP and
  // counted separately -- a green would certify an unknown tree, and a red would
  // blame this workspace for someone else's uncommitted edit. It is LOUD, never
  // silent, and the summary always states how many gates were skipped.
  if (code === 3) {
    skipped.push({ name, detail });
    const why = /\[skip\][^\n]*/.exec(detail || '')
      || /blocked by: .*/.exec(detail || '');
    console.log('[SKIP] ' + name + '  (exit 3: '
      + (why ? why[0].replace(/^\[skip\] /, '') : 'nothing violated, the compiler source MOVED mid-run') + ')' + took);
    return;
  }
  gates.push({ name, code, detail });
  console.log('[' + (code === 0 ? 'PASS' : 'FAIL') + '] ' + name + '  (exit ' + code + ')' + took);
  if (code !== 0) console.log(tail(detail, 12));
}

// ---- the probe pool ---------------------------------------------------------
// `probe.cjs` is ALREADY one bounded gate (build timeout, run timeout, kill by
// pid), so the pool only has to bound the batch's wall clock and keep the output
// attributed. It spawns children detached (each probe's window lands in its own
// process group, so the deadline kill takes the window with it) and polls for the
// `.gate-status` file the probe writes in its exit hook. Polling, not waiting:
// the pool's main thread is BLOCKED in `Atomics.wait`, and with the event loop
// parked no 'exit' event could ever be delivered -- while one `spawnSync` per
// probe is exactly the serial run this replaces.
const PROBE_DEADLINE_MS = Number(process.env.ASC_PROBE_DEADLINE_MS || 360000);
const sleepCell = new Int32Array(new SharedArrayBuffer(4));
const sleepSync = (ms) => { Atomics.wait(sleepCell, 0, 0, ms); };

function runProbes(list) {
  const picked = list.filter((p) => !ONLY_RE || ONLY_RE.test('probes/' + p));
  if (ONLY_RE) for (const p of list) if (picked.indexOf(p) < 0) omitted.push('probe ' + p);
  const solo = picked.filter((p) => SOLO_PROBES.indexOf(p) >= 0);
  const wide = picked.filter((p) => SOLO_PROBES.indexOf(p) < 0);
  const t = Date.now();
  runProbeBatch(wide, JOBS, 'parallel x' + JOBS);
  runProbeBatch(solo, 1, 'solo -- stopwatch probes: nothing else may be building');
  if (picked.length) console.log('[probes] ' + picked.length + ' probe(s) in ' + secs(Date.now() - t));
}

function runProbeBatch(names, width, mode) {
  if (!names.length) return;
  console.log('[probes] ' + names.length + ' probe(s), ' + mode);
  const queue = names.slice();
  const running = [];
  const results = [];   // reported in LIST order, not completion order
  while (queue.length || running.length) {
    while (running.length < width && queue.length) {
      const p = queue.shift();
      const dir = path.join(UI, 'probes', p);
      const base = path.basename(dir);
      const statusP = path.join(dir, base + '.gate-status');
      const logP = path.join(dir, base + '.gate.log');
      // Deleted BEFORE the spawn: the probe writes this file in its exit hook, so a
      // stale one from the previous run would be read as this run's verdict.
      try { fs.unlinkSync(statusP); } catch (e) { /* absent is the point */ }
      const fd = fs.openSync(logP, 'w');
      const child = spawn(process.execPath, ['tools/probe.cjs', 'probes/' + p], {
        cwd: UI, detached: true, stdio: ['ignore', fd, fd],
      });
      fs.closeSync(fd);
      running.push({ p, child, statusP, logP, t: Date.now(), deadline: Date.now() + PROBE_DEADLINE_MS });
    }
    sleepSync(120);
    for (let i = running.length - 1; i >= 0; i--) {
      const it = running[i];
      let code = null;
      if (fs.existsSync(it.statusP)) {
        code = Number(fs.readFileSync(it.statusP, 'utf8').trim());
      } else if (Date.now() > it.deadline) {
        console.log('[TIMEOUT] probe ' + it.p + ' killed after '
          + Math.round(PROBE_DEADLINE_MS / 1000) + 's (ASC_PROBE_DEADLINE_MS)');
        try { process.kill(-it.child.pid, 'SIGKILL'); } catch (e) { /* win32 / gone */ }
        try { process.kill(it.child.pid, 'SIGKILL'); } catch (e) { /* gone */ }
        code = 124;
      }
      if (code == null) continue;
      running.splice(i, 1);
      results.push({ p: it.p, code, logP: it.logP, ms: Date.now() - it.t });
      // A live line per probe: a batch that takes minutes must still look alive.
      console.log('   ... ' + it.p + (code === 0 ? ' pass ' : ' EXIT ' + code + ' ')
        + secs(Date.now() - it.t)
        + '  [' + (names.length - queue.length - running.length) + '/' + names.length + ']');
    }
  }
  // Attributed in LIST order: a log whose line order matches the list is one a
  // human can diff against the gate list. A FAILED probe keeps its transcript.
  for (const r of results) {
    const out = fs.existsSync(r.logP) ? fs.readFileSync(r.logP, 'utf8') : '';
    const m = /PROBE \S+: (\d+) checks, (\d+) failures/.exec(out);
    record('probe ' + r.p + (m ? ' (' + m[1] + ' checks, ' + m[2] + ' failures)' : ''), r.code, out, r.ms);
    if (r.code === 0) { try { fs.unlinkSync(r.logP); } catch (e) { /* fine */ } }
  }
}

// ---- 1..3: pure-AS3 probes (windowed; probe.cjs owns build+run+assert) -------
const PROBES = ['widgets/chip', 'widgets/form', 'widgets/display', 'widgets/nav', 'widgets/anim',
                 'widgets/feedback', 'widgets/media', 'widgets/data', 'widgets/overlay',
                 'widgets/interact', 'widgets/flip', 'widgets/motion', 'widgets/vlist',
                 'widgets/choice', 'redraw', 'widgets/popup', 'widgets/typing', 'widgets/scrollbar',
                 'widgets/callback', 'lifecycle', 'widgets/textfx',
                 // Added with their batches: a probe that is not in this list is a probe
                 // nobody runs. `pointer` (hover synthesised from one mouse move),
                 // `imaging` (ImageNode src/onLoad), `table2` (sort/resize/virtual) and
                 // `stick` (scroll that follows its own content) were each green by hand
                 // for a while before this line existed.
                 'widgets/pointer', 'widgets/imaging', 'widgets/table2', 'widgets/stick',
                 // `pointer-touch` is the MOBILE.md M0 pin: a SYNTHESIZED TouchEvent
                 // series (G5 means no backend produces one) goes through PointerRouter
                 // into the same press/click vocabulary the 41 kinds already speak, with
                 // the scroller press delay, the slop veto and hover arbitration
                 // (hasHover=false). It is also the only gate that checks a PICK against
                 // the engine's own hit test: four points, engine pointer vs
                 // UiApp.pickAt, so the touch path cannot invent a second definition of
                 // "under the finger". Teeth: probes/widgets/pointer-touch/mutation.cjs
                 // 6/6 -- including the one that removes the sub-step slop veto, which
                 // stayed green until the release path stopped re-deciding it.
                 'widgets/pointer-touch',
                 // `touch-scroll` is MOBILE.md M1 (S1/S2): a synthesized touch series
                 // DRAGS a viewport -- 1:1 follow, the press withdrawn without a click,
                 // the axis locked once, and a coast that integrates wall-clock dt.
                 // Deterministic half: the pixel offsets after a drag are hand arithmetic
                 // (20pt -> 20px, the slop does not scroll, a drag past the end clamps at
                 // 180, `momentum:false` stops at EXACTLY the release offset). Physics
                 // half: coarse on purpose (the glide moved further, stayed inside the
                 // content, and stopped) -- pinning the distance would pin the machine's
                 // frame clock. Teeth: probes/widgets/touch-scroll/mutation.cjs 9/9,
                 // including a programmatic scroll that must cancel a coast in flight.
                 'widgets/touch-scroll',
                 // `navstack` is the first MOBILE.md C-family gate (C1): a real stack
                 // -- every page mounted at the stack's box, only the top one visible
                 // AND pickable, and BACK delivered with no focus anywhere. The
                 // assertion it exists for is the one a fake stack cannot pass: after
                 // a push/pop the page below is at the offset the user left it, in the
                 // SAME nodes (identity), so page state is not rebuilt. It also keeps a
                 // stack in a HIDDEN tab and counts its callbacks, because the BACK key
                 // is a stage listener and must not unwind four tabs at once. Teeth:
                 // probes/widgets/navstack/mutation.cjs 9/9 -- including "only the top
                 // page is mounted", "every page stays visible" and the on-screen check.
                 'widgets/navstack',
                 // `appbar` is C2: the three slots as LAYOUT (leading/trailing pinned
                 // at the padding edges, the title centred in what is left), the large
                 // title collapsed by ONE author-driven number at four stops, and the
                 // clip that keeps a shrinking row's title off the content below. It is
                 // also the gate that measured "a box's style.flexDirection is ignored;
                 // only BoxNode.direction matters", the one that caught a `trailing: [a, b]`
                 // LIST being dropped by `as Node`, and the one that caught a safe-area
                 // inset NOT being undone when the env went back to zero (the bar stayed
                 // notched: `applyEngineStyle` only writes padding when it is non-null, and
                 // `setSafeInsets` re-resolved without raising a layout bit). Teeth:
                 // probes/widgets/appbar/mutation.cjs 11/11.
                 'widgets/appbar',
                 // `tabbar` is C3: equal cells that fill the bar, the selected state read
                 // back as `resolved.text.color` against Theme.tokens(), the three taps
                 // that prove each cell reports ITS OWN index (the AS3 loop-closure trap),
                 // a shrinking `items` dropping the stale cell, a Node icon keeping the
                 // author's colour, and the home indicator as 34px of bar PADDING. Teeth:
                 // probes/widgets/tabbar/mutation.cjs 9/9.
                 'widgets/tabbar',
                 // `icon` (SVG path data: cubic subdivision, stroke scaling, and the
                 // refusals an arc and a junk command must get) joined with the icons
                 // batch; it is the only probe in the kit that drives a PARSER.
                 'widgets/icon',
                 // `keys` (the three keyboard navigations: list/table CLAMP, tabs WRAP, and
                 // the virtual table's reveal) and `accordion` (single vs multi open state,
                 // the mutual-exclusion THROWs, and the header fill following the SET).
                 // Both exist because those behaviours have no pointer path at all: a click
                 // probe can only ever press row 0, and single-mode accordion can only
                 // ever have one panel open.
                 'widgets/keys', 'widgets/accordion',
                 // `inputs` is the batch probe for numberInput / rangeSlider / multiSelect
                 // plus `virtual: true` on list and tree. It is the only probe that drives a
                 // WINDOW (mounted rows are a COUNT, not a pixel), and its teeth are
                 // tools/mutation-widget-inputs.cjs (8/8).
                 'widgets/inputs',
                 // `actions` is the batch probe for the four input paths that are not a
                 // pointer: a right click (with its stage point), a double click (behind
                 // the runtime's doubleClickEnabled flag), a splitter drag (a ratio, not a
                 // width) and the keymap (ActionRegistry + Control.action + tabIndex). Its
                 // teeth are tools/mutation-widget-actions.cjs (11/11), which is how the
                 // two toothless assertions in it were found: a minSize clamp no drag can
                 // reach, and a shift-modifier vector that also held meta.
                 //
                 //  is the runtime theme switch: one tree painted twice (light,
                 // then dark), all 12 sample points asserted in BOTH passes, all 15 rects
                 // compared across the swap, plus the contract checks. Every style pointer
                 // in it is a const so the ONLY way a swap can reach a node is
                 // markThemeDirty -- its teeth are tools/mutation-widget-theme.cjs (8/8).
                 'widgets/theme',
                 'widgets/actions',
                 // `clip` is the pin for compiler-gaps G29, which the library closed by
                 // finally CONSUMING a style field nothing read: three 120x28 boxes with
                 // the same 200x28 strip inside, one `overflow: "hidden"`, one "scroll",
                 // one "visible" as the CONTROL. Teeth: deleting the one
                 // `applyOverflowClip()` call in UiNode.arrangeSelf leaves SIX assertions
                 // red -- the two 'past the box' pixels (the strip paints there again), both
                 // scrollRect checks, the cache-identity check and the click count (the
                 // spilling child takes the mouse again). Measured, then reverted.
                 'widgets/clip',
                 // `env` is MOBILE.md E1/E2: the platform facts arrive through ONE
                 // interface (`Env`, bound with `UiApp.bindEnv`) and the safe-area
                 // insets are consumed in ONE place (a container's own padding).
                 // It is the only probe that drives an ENV: the desktop answers are
                 // asserted as the floor every app gets, then a FakeEnv pulls the
                 // same window through a phone rotation (47 -> 0 -> bottom-only ->
                 // 47) and a hover-capable-pointer flip, because a desktop window
                 // can never show either. Teeth: probes/widgets/env/mutation.cjs 7/7,
                 // including one that makes every node claim every edge (the
                 // "scatter it everywhere" E2 forbids).
                 'widgets/env',
                 // probes/perf is not a pixel probe but a stopwatch: 300 keyed buttons,
                 // timed idle / describe / one-node-change / solve / paint phases.
                 // Its one assertion is a 15ms ceiling on a NO-CHANGE describe
                 // (39.3ms when the duplicate-key check was quadratic, 1.0ms now).
                 'perf'];

runProbes(PROBES);

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
     // The manifest is the ONE place that knows which include/link flags a host
     // needs; spelling them here by hand was Windows-only (`-L .../windows-x64`,
     // `-l zlib` -- on macOS clang reads that as "a file called libzlib.a" and the
     // link dies before a single check runs).
     '--manifest', 'examples/window.build.example.json'], COMPILER);
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

// ---- 6b: the component-docs tour -------------------------------------------
// This is the only gate that exercises a WHOLE app: 41 component pages rendered from
// one catalog into one content column, a widget-driven page switch (the sidebar),
// a SECOND retained tree (the overlay root carries a popover anchored by key and a
// window-centred dialog, both opened and torn down while the app keeps running), the
// toastHost demo's two-toast corner stack (which exists ONLY after a click -- see the
// tour's stage 6d), and rects that were hand-computed before the run (see
// ui-demo/demo/DocsMain.as). It is
// the pin for the two layout fixes in UiNode (markLayoutDirty propagation out of a
// subtree, and re-resolving when a widget override changes the direction) --
// neither is visible to a single-page probe, because a single-page app never swaps
// a subtree under an unchanged style -- and for the two teardown fixes (a destroyed
// overlay's stage listener; the overlay root being left on the stage), which need a
// page switch to be visible at all.
// Stage 6d also asserts the ORDER of the display list: a scroll view's bars must be
// the last child of its backing. That check has to run on a page switch -- a describe
// with no paint -- because that is the only frame where nothing else would put a bar
// back on top (see UiNode.aboveContent).
{
  const r = sh(process.execPath, ['run-gallery.cjs'], path.join(UI, 'ui-demo'), { ASC_NO_OPEN: '1' });
  const out = (r.stdout || '') + (r.stderr || '');
  const m = /\[gallery\] RESULT: (\S+)/.exec(out);
  const pg = /pages=(\d+)/.exec(out);
  record('gallery tour: ' + (pg ? pg[1] : '?') + ' component pages (incl. the overlay tree), hand-computed rects' + (m ? ' (' + m[1] + ')' : ''), r.status, out);
}

// ---- 6b2: every registered widget kind is SHOWN by the demo ------------------
// A source scan, not a run: tools/kind-coverage.cjs resolves each
// `register("<kind>", ...)` to its node class, then to the factory functions that
// construct that class, then asks whether the demo CALLS one of them. Why a gate:
// the gallery is the only place a widget can be looked at, and six kinds
// (virtualList, tree, combobox, datePicker, select, drawer, popover) had shipped
// without one -- STATUS.md meanwhile claimed "scrollView is the only kind not in
// the gallery". A checklist cannot stay true; a scan can.
// Its teeth: tools/mutation-kind-coverage.cjs 4/4 (the tree calls renamed; a new
// kind+factory that nothing shows -- the regression that actually happened; the
// calls surviving only in a `//` comment; and the calls surviving only inside a
// STRING, i.e. a page that prints the source of a widget it never renders. The last
// two are there because the tool's first version read both kinds of prose as code,
// and the second of them was still uncaught until the splitPane page made a demo
// with two real `tree(` calls -- a mutation that renames only the first match
// renamed a snippet and left both real calls in place).
{
  const r = sh(process.execPath, ['tools/kind-coverage.cjs'], UI);
  const out = (r.stdout || '') + (r.stderr || '');
  const m = /(\d+)\/(\d+) registered kinds/.exec(out);
  record('gallery kind coverage: all registered widgets are shown' + (m ? ' (' + m[1] + '/' + m[2] + ')' : ''), r.status, out);
}

// ---- 6b3: the docs demos only pass options the factories read --------------
// A source scan, like kind-coverage above, and for the same reason: the docs app
// prints the very literal that built the page, so a wrong key is a page teaching an
// API that does not exist. Three such pages had shipped by 2026-10-24 -- progress
// `tone` (progress() never read it), tooltip `tone: "info"` (a STRING where the
// bubble wants a fill COLOUR, so the fill went NaN) and toast `tone: "info"` (a chip
// tone the toast vocabulary does not have -- that one THREW, on every frame after the
// click, which is how it was found).
// What the scan accepts is what is really an option: the style shorthands
// StyleRefinement.from reads (so box({gap}) is fine), the shared set
// OptionSupport.applyOpts copies, and each factory's own `opts.x` reads.
// It cannot see VALUES (`tone: "info"` is a known key with a bad value); that class
// is covered behaviourally -- the tour's "6d toastHost" stage (gate 6b above) clicks
// the demo and names the throw.
//   mutation: tools/mutation-demo-options.cjs (3/3).
{
  const r = sh(process.execPath, ['tools/demo-options.cjs'], UI);
  const out = (r.stdout || '') + (r.stderr || '');
  const m = /unknown option key[s]?: (\d+)/.exec(out);
  record('docs demos pass only options the factories read' + (m ? ' (' + m[1] + ' unknown)' : ''), r.status, out);
}

// ---- 6b4: author callbacks carry the argument their contract promises -----
// A source scan in BOTH directions: the kit's INVOCATIONS (exactly one argument for
// a value callback, none for onClick) and the demo/probes DECLARATIONS (exactly one
// parameter for a value callback, none for onClick). Both directions are a #1063 on
// AVM2 -- a call with FEWER arguments than the closure declares throws, and the frame
// guard then hides it behind a console line.
//
// Why a gate: the docs' slider shipped calling `onChange()` while every page (and the
// whole point of the callback) declares `function (v:Number)`. Every click threw
// #1063, the handler never ran, the knob never moved -- and no gate saw it, because
// probes/widgets/form only ever clicks BOUND controls, so the onChange branch was
// never executed anywhere. The behavioural half is probes/widgets/callback (which
// clicks unbound controls and drags an unbound slider); this is the half that catches
// the NEXT widget doing it, in a scan that costs nothing.
//   mutation: tools/mutation-callback-arity.cjs (6/6, both directions).
{
  const r = sh(process.execPath, ['tools/callback-arity.cjs'], UI);
  const out = (r.stdout || '') + (r.stderr || '');
  const m = /(\d+) invocation\(s\) in kit\/, (\d+) handler declaration/.exec(out);
  const v = /(\d+) violations?/.exec(out);
  record('author callbacks carry their documented argument'
    + (m ? ' (' + m[1] + ' calls / ' + m[2] + ' handlers)' : '') + (v ? ' (' + v[1] + ' violations)' : ''),
    r.status, out);
}

// ---- 6b5: the AIR arm actually compiles under the reference compiler ----------
// `ui-demo/air-gallery/build.sh` runs the docs app on AIR by DEFAULT (mxmlc -> adl),
// and `aot` to run it on our AOT. The default arm is only worth having if the tree
// still builds on mxmlc, and "our compiler accepted it" is no evidence of that: the
// AOT resolves names mxmlc will not (an unimported package-level function, a
// definition whose .as file is not named after it) and accepts anything AIR does not
// even have. Both halves of that claim were measured today: `demo/DocsStart.as` used
// `box()` without importing it, and `kit/asaot/ui/combo.as` held a public function
// named `combobox` -- mxmlc rejects both, the AOT accepted both, and no gate ran the
// 81 KB compile that the default arm depends on.
//   mutation: tools/mutation-air-arm.cjs (2/2, restoring each file by hash).
{
  // --sdk passes the ALREADY RESOLVED root: an env var does not reliably reach a
  // native child in this workspace (measured), and the child would then have to
  // search the same locations again to arrive at the same answer.
  const r = sh(process.execPath, ['tools/mxmlc-check.cjs', ...AIR_SDK_ARGS,
    '--root', 'ui-demo/demo/DocsAir.as',
    '--src', 'ui-demo', '--src', 'kit', '--src', 'seam',
    '--out', 'ui-demo/air-gallery/GalleryApp.swf'], UI);
  const out = (r.stdout || '') + (r.stderr || '');
  const m = /OK: compiled by AIR -- (\d+) bytes/.exec(out);
  record('AIR arm (build.sh default) compiles under mxmlc' + (m ? ' (' + m[1] + ' B SWF)' : ''), r.status, out);
}

// ---- 6b5b: `--gpu <mode>` really selects the window's composition mode -------
// `build.sh --gpu cpu|gpu|d3d12|gl|direct` is the option a reader of the docs asks
// for first ("can I see it on the GPU?"), and it is unverifiable by looking: all five
// modes render the same 42 pages, because a GPU nobody asked for is still a correct
// picture. What IS observable is the descriptor (`app.<mode>.xml`, one line off
// app.xml, handed to both arms) and the argv the AOT arm receives. The gate drives
// the `desc` arm, which derives the descriptor and prints the argv through the same
// `aot_args()` the `aot` arm execs -- 2 seconds, no compiler, no window -- and both
// consumer arms were measured for real when the option landed (aot --gpu gl: manifest
// ASC_RENDER_GL=1 and 41/42 pages; aot --gpu gpu: ASC_RENDER_D3D=1; air --gpu gl: a
// window under adl). `run-gallery.cjs` keeps asserting that a gpu mode reached the
// manifest, so the runtime half cannot rot silently.
//   mutation: tools/mutation-buildsh-gpu.cjs (5/5: a named-but-unpassed backend, a mode
//             wired to the wrong <renderMode>, an unknown mode swallowed, a derived
//             descriptor described but not passed, and a descriptor that drifts a
//             SECOND line -- the last one is what would break 6d's one-line A/B).
{
  const r = sh(process.execPath, ['tools/buildsh-gpu.cjs'], UI);
  const out = (r.stdout || '') + (r.stderr || '');
  const m = /buildsh-gpu: (\d+) checks, (\d+) failures/.exec(out);
  record('build.sh --gpu selects renderMode + backend, app.xml untouched'
    + (m ? ' (' + m[1] + ' checks, ' + m[2] + ' failures)' : ''), r.status, out);
}

// ---- 6b5c: `build.sh web` builds the SAME app for a browser -----------------
// The third arm. A native build that goes wrong leaves no exe and is obvious; a web
// build that goes wrong leaves `GalleryApp.html/.js/.wasm` which load, paint something
// and look finished, so the arm needs an instrument rather than an eye. Two failures
// are specific to it: the toolchain cannot be started (on Windows the SDK's `emcc` is a
// POSIX wrapper -- compiler-gaps.md G27 -- which this workspace once stood a PE
// launcher in front of; as-aot v0.4.240 launches `emcc.bat` itself, so the launcher is
// gone and the question is put to the compiler rather than re-implemented here), and
// the argv is assembled wrong (`--target wasm` without `--package web`, or a native
// main class, each of which compiles and produces a page that never mounts).
// So the gate drives the arm's own decision path -- `bash build.sh web --check`: the
// compiler says whether it can start emcc (via `as-aot doctor`, i.e. the same
// `webToolchainError()` the build runs; a stub emcc that exits 1 must come back
// unusable), and the printed argv is the array the build EXECS (one definition, two
// consumers, not a description). ~5 s, no compiler, no window.
// What it deliberately does not do is compile: that is ~3 minutes, and the product was
// measured when the arm landed (48-point sample grid vs the native gallery-page0.png:
// 44 identical, the four differences inside a text run; the 8 most common colours agree
// within 0.3%). The half a fast gate cannot see is covered by that measurement, and the
// half it CAN see is what rots silently.
//   mutation: tools/mutation-buildsh-web.cjs (7/7: `--package web` dropped from the argv;
//             the entry class switched to DocsAir; `--check` believing any toolchain
//             status; the --gpu refusal losing its arm comparison; the generated app dir
//             losing its .gitignore rule; a wrong EMSDK_HOME falling back to the
//             workspace SDK; and the runner naming an emcc outside the SDK again --
//             the shape of the G27 shim).
{
  const r = sh(process.execPath, ['tools/buildsh-web.cjs'], UI);
  const out = (r.stdout || '') + (r.stderr || '');
  const m = /buildsh-web: (\d+) checks, (\d+) failures/.exec(out);
  record('build.sh web: toolchain spawned, argv pinned, refusals, staged dir untracked'
    + (m ? ' (' + m[1] + ' checks, ' + m[2] + ' failures)' : ''), r.status, out);
}

// ---- 6b6: the docs app RUNS on the reference runtime, every page, popups open ----
// The one gate that measures AIR at run time, and the reason it exists is the shape
// of the last three user reports: a runtime that is MORE FORGIVING than AIR lets a
// library mistake through that AIR rejects, and the AOT suite cannot see it. The case
// that forced this gate: `setChildIndex` with an index >= numChildren threw RangeError
// #2006 on AIR and CLAMPED on our runtime (G24), so `Reconciler.fixDisplayOrder`
// computing a display slot from a description index threw once per frame -- a frozen
// select/combobox/datePicker page and a console stream -- while every AOT probe and a
// 42-page screenshot sweep passed. G24 and G25 were both fixed in v0.4.239; the gate
// stays because "aligned once" is not "aligned", and AIR is also the reference for
// error text, event ordering and text metrics. The sweep visits all 42 pages of the
// catalog with every openable popup flipped open (the lifted state), and fails on any
// error AIR reports, on a short page list, and on a popup step that stopped taking
// effect. ~20 s, one window. Exit 3 (no AIR SDK on this box) is reported as SKIP.
//   mutation: tools/mutation-air-sweep.cjs (5/5: the #2006 defect itself; a sweep that
//             stops opening popups; a sweep that stops one page early; the #1009 defect
//             (a torn-down node keeps its listeners); a drill that hovers thousands of
//             nodes and delivers nothing -- each restoring its file by hash).
//
// THE POINTER DRILL (2026-10-24, the second report): AIR cannot be scripted to click,
// so until then the sweep had NO pointer -- and `TypeError #1009` out of
// `UiNode.setHover` walked straight through it: an event is delivered one beat AFTER
// the frame that removed the node, so a listener left on a dead node's backing ran into
// nulled fields. While G25 was open our AOT dispatched no roll events at all, so no AOT
// probe could see that class by construction (G25 was fixed in v0.4.239). `DocsAir` now
// captures every leaf of the page it is about to leave (3107 nodes over the catalog) and
// delivers CLICK + MOUSE_DOWN one tick after the switch to the ones that really died
// (348 on the first measured run), which is why this gate also grades `TEARDOWN` lines.
//
// (It graded `ROLL` lines until 2026-10-26, when the library stopped installing
// per-object roll listeners -- hover is synthesized from one stage MOUSE_MOVE, the only
// pointer event both arms deliver. CLICK and MOUSE_DOWN are still per-object, so the
// drill moved to those; the invariant is the same, and the `destroyed=` floor still
// proves the drill meets torn-down nodes instead of grading a blind test.)
{
  const r = sh(process.execPath, ['tools/air-sweep.cjs', ...AIR_SDK_ARGS], UI);
  const out = (r.stdout || '') + (r.stderr || '');
  const m = /\[air-sweep\] (\d+)\/(\d+) page\(s\) visited, (\S+)\/(\d+) popup\(s\) opened, (\d+) runtime error\(s\), (\d+) node\(s\) captured and (\d+) of them destroyed/.exec(out);
  record('docs app on AIR (adl): every page, popups open, pointer drill, no runtime error'
    + (m ? ' (' + m[1] + '/' + m[2] + ' pages, ' + m[3] + '/' + m[4] + ' popups, ' + m[5]
      + ' errors, ' + m[7] + '/' + m[6] + ' destroyed)' : ''),
    r.status, out);
}

// ---- 6b7: every listener the kit installs is a listener the kit can remove ----
// The structural half of 6b6's pointer drill, and the cheap half: a source scan, no
// window. A node that wires `backing.addEventListener(type, fn)` directly cannot
// release it when it dies, so AIR's one-beat-late `mouseOut` runs a closure over
// nulled fields -- `TypeError #1009`, once per dead node. `UiNode.listen()` records
// the triple and `destroySubtree` replays it through `releaseListeners()`.
// The scan is deliberately narrow (only `x.backing.` / `x.tf.` receives are graded,
// which is where the kit attaches 29 listeners); STAGE listeners are NOT graded,
// because they belong to a gesture, not to a node, and keep their explicit add/remove
// pair in the widget's own teardown.
// A scan that matches nothing would certify everything, so it also fails when it sees
// zero attachments.
//   mutation: tools/mutation-listener-wiring.cjs (3/3: a raw attach in MenuWidget; a
//             TextField bypass in InputWidget; releaseListeners dropped from
//             destroySubtree -- each restoring its file by hash).
{
  const r = sh(process.execPath, ['tools/listener-wiring.cjs'], UI);
  const out = (r.stdout || '') + (r.stderr || '');
  const m = /wired listeners: (\d+)\s+raw attach sites: (\d+)/.exec(out);
  record('kit listeners are all releasable (UiNode.listen + destroySubtree)'
    + (m ? ' (' + m[1] + ' wired, ' + m[2] + ' raw)' : ''), r.status, out);
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

// ---- 6d: the descriptor is the CAUSE of the high-resolution pixels ----------
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

// ---- 9b: G16 -- `cond ? null : X` collapses to a zero value -- FIXED, set is empty
// A null LITERAL in the THEN slot made unifyType fall through to "keep the
// then-branch type", so the whole conditional was typed `null` and `convert`
// emitted it as a CONSTANT zero (0 / false / NULL). FIXED in the compiler
// (stage 266, v0.4.230): unifyType now has a null-family rule -- pointer-shaped
// families keep the concrete type (NULL is their null), numbers/booleans/`*` box
// to `any` so BOTH arms survive. 20 cases, run on BOTH runtimes; the AIR arm is
// checked against a HAND-DERIVED rule, so "AIR is the reference" is itself measured.
// The recorded AOT deviation set is now EMPTY. The dangerous direction is no longer
// "a new deviation appeared" alone -- it is also a deviation quietly VANISHING from
// the AIR arm (an arm that stops running its cases would make the set look clean),
// which is why the runner's own "only N/M lines" and "REFERENCE disagrees" checks
// are part of the gate. A non-empty set means the fix was lost.
const G16_KNOWN = [];
{
  const r = sh(process.execPath, ['probes/g16-ternary-null/run.cjs'], UI);
  const out = (r.stdout || '') + (r.stderr || '');
  // Only "our AOT says X but AIR says Y" lines: an AIR-arm disagreement or a crash
  // must never be mistaken for the documented deviation set.
  const aotIds = [...new Set([...out.matchAll(/FAIL  id (\d+): our AOT says/g)].map((m) => m[1]))]
    .sort((a, b) => Number(a) - Number(b));
  const armBad = /the REFERENCE disagrees|arm wrote only/.test(out);
  // `r.status === 0` IS PART OF IT. With no AIR runtime the command is skipped and
  // the transcript is empty -- reading the deviation set out of an empty string
  // would report "AOT deviations: none" for a comparison that never ran.
  const same = r.status === 0 && !armBad && aotIds.join(',') === G16_KNOWN.join(',');
  // 3 ("could not measure") is propagated: a skipped AIR arm is not a red.
  record('G16 ternary-null (20 cases, AOT vs AIR) -- AOT deviations: '
    + (aotIds.join(',') || 'none'), r.status === 3 ? 3 : (same ? 0 : 1),
    out + (same ? '' : '\nThe AOT deviation set is no longer the recorded one ([' + G16_KNOWN.join(',') + ']).'
      + '\nG16 is FIXED (stage 266), so any deviation here is a REGRESSION: find the emitter change that'
      + '\nbrought the zero-value collapse back (unifyType null-family rule, src/emit.ts).'
      + '\nIf a case was added/changed on purpose, update expect.json AND this comment together.'));
}

// ---- 9c: G19 -- Graphics.drawRoundRect builds a real ROUND rect -------------
// The generated body used to be `{ (void)ew; (void)eh; Graphics_drawRect(...); }`:
// both radii consumed and dropped, so every rounded control in the kit drew square.
// FIXED in the compiler (stage 267, v0.4.231): the emitter maps the two radii onto
// SkRRect (half-ellipse per axis, negative -> 0, each clamped to half the box, NaN
// ellipseHeight -> ellipseWidth, NaN ellipseWidth -> #2004), and the Skia seam gained
// `sk_path_add_rrect` on BOTH arms.
// The gate is the comparison itself: 9 geometry cases x ~40 rows each, run on BOTH
// runtimes, plus the 13-case argument contract. Rows are judged against the ANALYTIC
// corner ellipse (an exact renderer is within 1 px of the math), so "AIR and AOT agree"
// is not the only claim -- the SHAPE has to be a round rect too. The one documented
// deviation (negative radii, where AIR's own cubic self-intersects and inks 1-2 px
// outside the box) is counted, never dropped.
{
  const r = sh(process.execPath, ['probes/g19-roundrect/run.cjs'], UI);
  const out = (r.stdout || '') + (r.stderr || '');
  const m = /geometry rows: ([^\n]+)/.exec(out);
  record('G19 drawRoundRect, AOT vs AIR' + (m ? ' -- ' + m[1].trim() : ''), r.status, out);
}

// ---- 9d: G20 -- setTextFormat REPLACES a range, it does not stack a run -----
// AIR replaces the formatting of the range; this build appended a run every call, and
// the layout side copies text[start..end) once PER run -- so a repaint path grew the
// field linearly ("the typed text got copied once more"). FIXED in the compiler
// (stage 268, v0.4.232): the run table is rebuilt with the covered part dropped and the
// straddling runs split in two, keeping it sorted by start.
// Every case is RELATIONAL (two fields in the same process, then compared), because
// AIR and this build use different text engines and their absolute widths legitimately
// differ. Cases 10/11 were the registered G21 deviation (getTextFormat ignored the run
// table); stage 270 fixed that, so they now assert the value instead of an exemption.
{
  const r = sh(process.execPath, ['probes/g20-settextformat/run.cjs'], UI);
  const out = (r.stdout || '') + (r.stderr || '');
  const m = /RESULT: (\S+.*)/.exec(out);
  record('G20 setTextFormat replaces the range (AOT vs AIR)' + (m ? ' (' + m[1].trim() + ')' : ''), r.status, out);
}

// ---- 9e: G21 -- getTextFormat() answers from the RUN TABLE -------------------
// The old one-liner (`return tf->defaultTextFormat;`) predated the run table, so a
// field formatted with `setTextFormat(fmt(30, 0x0000FF))` still read back
// `color=0 size=20` -- any "what I set is what I read" logic was silently wrong.
// FIXED in the compiler (stage 270, v0.4.234): walk the runs, fill the gaps with
// defaultTextFormat, compare with a STRICT as_v_eq, answer a CLONE of the format or an
// empty one; (TextFormat fields are boxed so "unset" is expressible as null.)
// The gate is the 30-case matrix on both runtimes; the interesting rows are not
// "inside one run" but straddling/reversed/empty spans and the #2006 bounds.
{
  const r = sh(process.execPath, ['probes/g21-gettextformat/run.cjs'], UI);
  const out = (r.stdout || '') + (r.stderr || '');
  const m = /RESULT: (\S+.*)/.exec(out);
  record('G21 getTextFormat reads the run table (AOT vs AIR)' + (m ? ' (' + m[1].trim() + ')' : ''), r.status, out);
}

// ---- 9f: G22 -- a static read inside a CLOSURE carries its _cinit() guard ----
// Static fields initialise lazily, gated by `(Owner_cinit(), Owner_FIELD)`. The set of
// classes needing that gate was collected AFTER the closure bodies were emitted, so a
// static read that only ever happened in a closure was emitted bare -- `NAMES` stayed
// NULL and `NAMES[0]` threw #1009. Because _cinit() initialises a WHOLE class, one
// ordinary-method read anywhere hid the bug; a page written entirely with factories
// (which is exactly how this UI library is written) hit it. FIXED in stage 269:
// collect first, then forward-declare every `<Cls>_cinit`, then emit closures.
// The gate is two-sided: the 10 cases must agree on both runtimes AND the emitted C
// must be audited (every guarded read spelled out, forward declaration first).
{
  const r = sh(process.execPath, ['probes/g22-closure-statics/run.cjs'], UI);
  const out = (r.stdout || '') + (r.stderr || '');
  const m = /RESULT: (\S+.*)/.exec(out);
  record('G22 closure statics initialise (AOT vs AIR, emitted C audited)' + (m ? ' (' + m[1].trim() + ')' : ''), r.status, out);
}

// ---- 10: Vector.<T> is really faster than Array in OUR AOT -------------------// The same benchmark body compiled by BOTH toolchains (so the only difference is
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

// ---- 7c: where the AIR SDK is ----------------------------------------------------
// This gate exists because of a SKIP that lied for three rounds: nine gates reported
// "the AIR reference runtime is not installed" while mxmlc compiled the docs app in
// 1.8 s. The detection asked only AIRSDK_HOME and PATH; the SDK was in
// ~/Documents/Software/AIRSDK/AIRSDK_51.4.1 and the PATH entry named an uninstalled
// 51.2.1. `tools/air-sdk.cjs` now asks env -> PATH -> install locations and accepts a
// hit only after verifying a launcher THIS HOST can run (the SDK is one zip for every
// platform, so `bin/adl.exe` existing says nothing about macOS).
//
// It runs on EVERY machine, including one with no SDK: that is exactly when its answer
// matters. The cases are hermetic (a fixture under temp/, HOME redirected, PATH
// emptied), so a machine's own SDK cannot make a case pass that the fixture was
// supposed to fail.
//   mutation: tools/mutation-air-sdk.cjs (5/5 -- structural check removed / version
//   ranking reversed / --sdk falls through / ASC_NO_AIR_SCAN ignored / complete from
//   mxmlc alone; the resolver is restored by hash and the baseline is checked first,
//   because a harness that mutates without a green baseline proves nothing).
{
  const r = sh(process.execPath, ['tools/air-sdk-check.cjs'], UI);
  const out = (r.stdout || '') + (r.stderr || '');
  const m = /RESULT: (\S+.*)/.exec(out);
  record('AIR SDK resolution: env -> PATH -> install locations, verified per host'
    + (m ? ' (' + m[1].trim() + ')' : ''), r.status, out);
}

// ---- 8: the instrument that certifies "we did not touch the compiler" -------
// Instant (pure string parsing, no build). It is a gate because every
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
  + (skipped.length ? ', ' + skipped.length + ' SKIPPED' : '')
  + (omitted.length ? ', ' + omitted.length + ' NOT SELECTED (--only ' + ONLY + ')' : '')
  + '  in ' + secs(Date.now() - T0) + ' ====');
if (failed.length) {
  console.log('FAILED: ' + failed.map((f) => f.name).join(' | '));
  process.exit(1);
}
if (skipped.length) console.log('SKIPPED: ' + skipped.map((s) => s.name).join(' | '));
if (omitted.length && (process.env.ASC_GATE_VERBOSE === '1')) {
  console.log('NOT SELECTED: ' + omitted.join(' | '));
}
console.log('RESULT: PASS' + (skipped.length ? ' (with ' + skipped.length + ' skipped)' : ''));
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
//                all 41 pages with every popup open, because our AOT is more forgiving
//                than AIR: `setChildIndex` past the end throws #2006 there and clamps
//                here, so `fixDisplayOrder` throwing once per frame on the
//                select/combobox/datePicker pages was invisible to every AOT probe and
//                to a render-only 41-page screenshot sweep. The three mutations are the
//                defect itself (the display slot computed from the description index),
//                a sweep that stops OPENING the popups (41 pages, 0 errors, blind), and
//                a sweep that stops one page early (a dead window must not look green).
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
                 'widgets/interact', 'widgets/flip', 'widgets/motion', 'widgets/vlist',
                 'widgets/choice', 'redraw', 'widgets/popup', 'widgets/typing', 'widgets/scrollbar',
                 'widgets/callback', 'lifecycle']) {
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
  record('gallery tour: 41 component pages (incl. the overlay tree), hand-computed rects' + (m ? ' (' + m[1] + ')' : ''), r.status, out);
}

// ---- 6b2: every registered widget kind is SHOWN by the demo ------------------
// A source scan, not a run: tools/kind-coverage.cjs resolves each
// `register("<kind>", ...)` to its node class, then to the factory functions that
// construct that class, then asks whether the demo CALLS one of them. Why a gate:
// the gallery is the only place a widget can be looked at, and six kinds
// (virtualList, tree, combobox, datePicker, select, drawer, popover) had shipped
// without one -- STATUS.md meanwhile claimed "scrollView is the only kind not in
// the gallery". A checklist cannot stay true; a scan can.
// Its teeth: tools/mutation-kind-coverage.cjs 3/3 (the tree call renamed; a new
// kind+factory that nothing shows -- the regression that actually happened; the
// call surviving only in a `//` comment, which the tool's first version counted as
// code and thereby certified prose).
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
  const r = sh(process.execPath, ['tools/mxmlc-check.cjs',
    '--root', 'ui-demo/demo/DocsAir.as',
    '--src', 'ui-demo', '--src', 'kit', '--src', 'seam',
    '--out', 'ui-demo/air-gallery/GalleryApp.swf'], UI);
  const out = (r.stdout || '') + (r.stderr || '');
  const m = /OK: compiled by AIR -- (\d+) bytes/.exec(out);
  record('AIR arm (build.sh default) compiles under mxmlc' + (m ? ' (' + m[1] + ' B SWF)' : ''), r.status, out);
}

// ---- 6b6: the docs app RUNS on the reference runtime, every page, popups open ----
// The one gate that measures AIR at run time, and the reason it exists is the shape
// of the last three user reports: our AOT is MORE FORGIVING than AIR, so a library
// mistake AIR rejects can be invisible to the entire AOT suite. The case that forced
// this gate: `setChildIndex` with an index >= numChildren throws RangeError #2006 on
// AIR and CLAMPS on our runtime (compiler-gaps.md G24), so `Reconciler.fixDisplayOrder`
// computing a display slot from a description index threw once per frame -- a frozen
// select/combobox/datePicker page and a console stream -- while every AOT probe and a
// 41-page screenshot sweep passed. The sweep visits all 41 pages of the catalog with
// every openable popup flipped open (the lifted state), and fails on any error AIR
// reports, on a short page list, and on a popup step that stopped taking effect.
// ~20 s, one window. Exit 3 (no AIR SDK on this box) is reported as SKIP.
//   mutation: tools/mutation-air-sweep.cjs (5/5: the #2006 defect itself; a sweep that
//             stops opening popups; a sweep that stops one page early; the #1009 defect
//             (a torn-down node keeps its listeners); a drill that hovers thousands of
//             nodes and delivers nothing -- each restoring its file by hash).
//
// THE POINTER DRILL (2026-10-24, the second report): AIR cannot be scripted to click,
// so until then the sweep had NO pointer -- and `TypeError #1009` out of
// `UiNode.setHover` walked straight through it: `mouseOut` is delivered one beat AFTER
// the frame that removed the node, so a listener left on a dead node's backing ran into
// nulled fields. Our AOT never dispatches roll-over/roll-out at all (compiler-gaps.md
// G25), so no AOT probe could see that class by construction. `DocsAir` now hovers every
// leaf of the page it is about to leave (3107 nodes over the catalog) and delivers the
// roll-out one tick after the switch (348 of them had really been destroyed), which is
// why this gate also grades `ROLL` lines.
{
  const r = sh(process.execPath, ['tools/air-sweep.cjs'], UI);
  const out = (r.stdout || '') + (r.stderr || '');
  const m = /\[air-sweep\] (\d+)\/(\d+) page\(s\) visited, (\S+)\/(\d+) popup\(s\) opened, (\d+) runtime error\(s\), (\d+) node\(s\) hovered and (\d+) of them destroyed/.exec(out);
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
  const same = !armBad && aotIds.join(',') === G16_KNOWN.join(',');
  record('G16 ternary-null (20 cases, AOT vs AIR) -- AOT deviations: '
    + (aotIds.join(',') || 'none'), same ? 0 : 1,
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
  + (skipped.length ? ', ' + skipped.length + ' SKIPPED' : '') + ' ====');
if (failed.length) {
  console.log('FAILED: ' + failed.map((f) => f.name).join(' | '));
  process.exit(1);
}
if (skipped.length) console.log('SKIPPED: ' + skipped.map((s) => s.name).join(' | '));
console.log('RESULT: PASS' + (skipped.length ? ' (with ' + skipped.length + ' skipped)' : ''));
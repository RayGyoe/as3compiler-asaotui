// asaot.ui.UiApp -- the scheduler that owns the retained tree and runs the three
// passes (design doc sections 3 and 5.2).
//
// ONE INVALIDATE ENTRY POINT. Everything that changes goes through
// `invalidate(dirty)` (a single int OR) and, at the frame boundary, ONE reflow:
//
//   notify -> invalidate -> _pending |= dirty
//   ENTER_FRAME -> if pending: describe -> reconcile -> [measure -> solve -> arrange] -> paint
//
// A steady frame (no notify, no structure change, no hover) does NOTHING: no
// describe, no reconcile, no measure, no engine.calculate, no paint. That is the
// property CheckUi.as pins with counters, and it is the honest version of the
// design doc's "zero redraw" goal -- the design doc (section 5.2 / 11.1) already
// records that the window backend marks every visible window dirty every frame,
// so literal zero-redraw needs a backend idle mode; what we CAN and DO guarantee
// is zero describe/reflow work.
//
// The reflow runs inside the stage's ENTER_FRAME broadcast, i.e. on the frame
// boundary, BEFORE the window is presented (Stage_dispatchFrame runs before the
// present in the compiler's frame pump), so a notify on frame N is visible in the
// same frame's present.
package asaot.ui
{
    import asaot.ui.anim.Anim;
    import asaot.ui.anim.Tween;
    import asaot.ui.as3.As3LayoutEngine;

    import flash.display.DisplayObject;
    import flash.display.DisplayObjectContainer;
    import flash.display.InteractiveObject;
    import flash.display.Stage;
    import flash.events.Event;
    import flash.events.FocusEvent;
    import flash.events.KeyboardEvent;
    import flash.events.MouseEvent;
    import flash.text.TextField;
    import flash.ui.Mouse;
    import flash.ui.MouseCursor;
    import flash.utils.Dictionary;
    import flash.utils.getTimer;

    public class UiApp
    {
        public var view:View;
        public var engine:LayoutEngine;
        public var cfg:Object;
        public var stage:Stage;
        public var stageContainer:DisplayObjectContainer;

        // Reused per-node scratch for layoutGet, so arrange allocates nothing.
        public var rectScratch:Array;

        // ---- pass counters (the CheckUi invariants read these) ----------
        public var describeCalls:int;
        public var reconcileVisits:int;
        public var layoutSolves:int;
        public var measurePasses:int;
        public var arrangePasses:int;
        public var paintPasses:int;
        public var invalidateCalls:int;
        public var enterFrameTicks:int;
        // Keyboard/focus diagnostics. `tabMoves` counts ring moves the LIBRARY
        // performed (not the runtime's own), `keyEvents` counts every KEY_DOWN the
        // stage handed us -- so a probe can tell "the key never arrived" from
        // "it arrived and nothing handled it".
        public var tabMoves:int;
        public var keyEvents:int;

        // Reused scratch for the two per-keypress walks (a keymap context set and the
        // ordered tab ring). Steady state allocates nothing: AGENTS.md's hot-path rule
        // applies to a key repeat exactly as it does to a frame.
        private var ctxScratch:Array = [];
        private var ringScratch:Vector.<UiNode> = new Vector.<UiNode>();

        private var root:UiNode;
        // The keyboard owner. Library state, not display-list state: see
        // UiNode.tabEnabled for why the tab ring is a walk of the retained tree
        // rather than the runtime's `as_tab_scan`.
        private var _focus:UiNode;
        // The SECOND retained root: everything that floats above the layout tree
        // (dialog / drawer / popover / menu / toast). Reconciled from
        // View.renderOverlay(). It is a separate display object attached after
        // the main root, so it is painted last and can cover the whole window;
        // it never participates in the main tree's flex layout.
        private var overlayRoot:UiNode;
        private var reconciler:Reconciler;
        private var _pending:int;
        private var _needsPaint:Boolean;
        private var _solvedW:Number;
        private var _solvedH:Number;
        private var _running:Boolean;
        // The palette generation this app has already applied. `Theme.themeEpoch()`
        // changes when `Theme.setTheme()` swaps the palette; the difference is the whole
        // signal that a theme switch happened, and it is checked once per frame.
        private var _themeEpoch:int;

        public function UiApp(view:View):void
        {
            this.view = view;
            // The pure-AS3 engine is the ONLY implementation: the native (Yoga)
            // path is shelved (seam/README.md section 2), so there is no
            // compile-time switch and no silent fallback.
            this.engine = new As3LayoutEngine();
            this.cfg = this.engine.createConfig(0, true);   // web defaults: row + stretch
            this.rectScratch = [0, 0, 0, 0];
            this.reconciler = new Reconciler(this);
            this.root = null;
            this._pending = 0;
            this._needsPaint = false;
            this._solvedW = -1;
            this._solvedH = -1;
            this._running = false;
            this._themeEpoch = Theme.themeEpoch();
            this.describeCalls = 0;
            this.reconcileVisits = 0;
            this.layoutSolves = 0;
            this.measurePasses = 0;
            this.arrangePasses = 0;
            this.paintPasses = 0;
            this.invalidateCalls = 0;
            this.enterFrameTicks = 0;
            this.tabMoves = 0;
            this.keyEvents = 0;
            this._focus = null;
            if (view != null) view.attachApp(this);
        }

        public function mount(stage:Stage):void
        {
            this.stage = stage;
            // NOTE: the root backing is NOT attached here, so the author keeps
            // the design doc's `stage.addChild(root)` idiom explicit (call
            // attachRoot()). This also lets `mount` build + lay out the tree
            // before the window exists.
            this.view.mount(stage);
            stage.addEventListener(Event.ENTER_FRAME, onEnterFrame);
            stage.addEventListener(Event.RESIZE, onResize);
            // Keyboard and runtime focus. KEY_DOWN bubbles from whatever the runtime
            // made the target (the focused object, else the stage), so ONE stage
            // listener sees every key in the window.
            stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
            // The runtime focuses a TextField on mouse-down by itself (measured on
            // adl: FOCUS_IN fires BEFORE the field's own mouseDown listener). We
            // mirror that into library focus so the ring, the tab anchor and the
            // input's commit-on-blur all agree with what the runtime did.
            stage.addEventListener(FocusEvent.FOCUS_IN, onStageFocusIn);
            stage.addEventListener(FocusEvent.FOCUS_OUT, onStageFocusOut);
            // Hover (see the block above). ONE listener, for the whole window, on
            // purpose -- and now that G25 is fixed the reason is no longer "roll events
            // do not exist" but "one listener, sharing the click's hit test".
            stage.addEventListener(MouseEvent.MOUSE_MOVE, onStageMouseMove);
            stage.addEventListener(Event.MOUSE_LEAVE, onStageMouseLeave);
            this._running = true;
            this.invalidate(Dirty.ALL);
            this.reflow();
        }

        // The author-facing `stage.addChild(root)` step: attach the retained
        // root display object to the container. Idempotent.
        public function attachRoot():void
        {
            this.stageContainer = this.stage;
            if (this.root != null && this.root.backing != null && this.root.backing.parent == null
                && this.stageContainer != null)
            {
                this.stageContainer.addChild(this.root.backing);
            }
        }

        public function rootDisplay():DisplayObject
        {
            return this.root != null ? this.root.backing : null;
        }

        // The overlay root (null until the view first returns a non-null
        // renderOverlay()). Exposed for tests and for widgets that need the
        // window-sized coordinate space.
        public function getOverlayRoot():UiNode
        {
            return this.overlayRoot;
        }

        public function overlayDisplay():DisplayObject
        {
            return this.overlayRoot != null ? this.overlayRoot.backing : null;
        }

        // ---- the single dirty entry point -------------------------------
        public function invalidate(dirty:int):void
        {
            this._pending = this._pending | dirty;
            this.invalidateCalls = this.invalidateCalls + 1;
        }

        // Hover / press: decoration only, never a reflow (section 3.3).
        public function markPaint(node:UiNode):void
        {
            node.dirty = node.dirty | Dirty.M_PAINT;
            this._needsPaint = true;
        }

        // ---- pointer: hover is DERIVED here, not received -----------------
        //
        // G25 IS FIXED (v0.4.239): the runtime dispatches rollOver/rollOut/mouseOver/
        // mouseOut per object, with AIR's ordering. This block is therefore NOT a
        // workaround any more, and it stays for two reasons that are about this library:
        //
        //   1. THE HIT TEST MUST BE THE CLICK'S. `as_pick_hit` is what routes a click;
        //      deriving hover from rectangles computed here would be a SECOND rule, and
        //      its failure mode -- a control that lights up but cannot be clicked -- is
        //      invisible in every screenshot.
        //   2. ONE LISTENER FOR THE WINDOW, NOT ONE PER NODE. The chain is recomputed
        //      from the hit object's ancestry, so no node owns a listener that could
        //      outlive it and run a closure over nulled fields.
        //
        // MOUSE_MOVE bubbles and, when nothing is hit, targets the stage. Hit target ->
        // nearest registered backing -> that node plus every ANCESTOR of it (ANCESTORS
        // because AIR's mouseOver bubbles: a card with a hover background must light
        // while the pointer is over its children).
        //
        // AND IT IS CHECKED AGAINST THE ENGINE. Since the fix, `probes/widgets/pointer`
        // catches the runtime's OWN mouseOver at the stage and asserts its target lies
        // inside the node this code hovers, and that rollOver reaches the entered node
        // and its ancestors but no sibling subtree. "Our hover is the engine's hover"
        // is a measurement there, not a claim here.
        private var _nodeOf:Dictionary;     // backing -> UiNode (identity lookup)
        private var _regCount:int;          // entries in _nodeOf (O(1) diagnostic)
        private var _hover:UiNode;          // deepest node under the pointer
        public var hoverMoves:int;          // every MOUSE_MOVE the stage sent

        // Called by UiNode.createBacking. The registry is how a hit target (which
        // may be a TextField or a child node's backing) finds its owner in O(depth)
        // instead of an O(tree) walk per mouse move.
        public function nodeBackingBuilt(n:UiNode):void
        {
            if (n == null || n.backing == null) return;
            if (this._nodeOf == null) this._nodeOf = new Dictionary();
            if (this._nodeOf[n.backing] == null) this._regCount = this._regCount + 1;
            this._nodeOf[n.backing] = n;
        }

        // Called by UiNode.destroySubtree BEFORE the node's fields are nulled.
        public function nodeBackingGone(n:UiNode):void
        {
            if (n == null) return;
            // A destroyed node must not survive in two places. The registry is a
            // GC root for both key and value (a leak), and the hover chain would
            // hold a node whose `app` is null -- the next mouse move would then
            // run `app.markPaint` on null, i.e. exactly the #1009 that the
            // listener teardown of 2026-10-24 removed.
            if (this._nodeOf != null && n.backing != null && this._nodeOf[n.backing] == n)
            {
                delete this._nodeOf[n.backing];
                this._regCount = this._regCount - 1;
            }
            if (this._hover != null && this.onChain(this._hover, n)) this.setHoverTarget(null);
        }

        // Diagnostics: how many backings are registered. Read only by probes -- a
        // leak here is invisible on screen (the stale entries draw nothing).
        public function hoverRegistryCount():int
        {
            return this._regCount;
        }

        public function getHover():UiNode
        {
            return this._hover;
        }

        // Is `n` on `x`'s ancestor chain (or `x` itself)?
        private function onChain(x:UiNode, n:UiNode):Boolean
        {
            var p:UiNode = x;
            while (p != null)
            {
                if (p == n) return true;
                p = p.parent;
            }
            return false;
        }

        // The node that owns a display object: walk UP from the hit target until a
        // registered backing appears. The runtime answers the pick with the
        // DEEPEST interactive object (a selectable TextField, a child node's
        // backing), and every one of those lives inside exactly one node's
        // backing, so the walk is bounded by the display depth.
        public function nodeAt(o:DisplayObject):UiNode
        {
            if (this._nodeOf == null) return null;
            var d:DisplayObject = o;
            while (d != null)
            {
                var n:UiNode = this._nodeOf[d] as UiNode;
                if (n != null) return n;
                d = d.parent;
            }
            return null;
        }

        public function setHoverTarget(n:UiNode):void
        {
            var old:UiNode = this._hover;
            if (old == n) return;
            this._hover = n;
            // Clear the old chain MINUS the ancestors the new one still has:
            // sliding from a label onto the button beside it must not blink the
            // parent's hover off for a frame.
            var p:UiNode = old;
            while (p != null)
            {
                if (!this.onChain(n, p)) p.setHover(0);
                p = p.parent;
            }
            p = n;
            while (p != null)
            {
                p.setHover(1);
                p = p.parent;
            }
            this.applyCursor();
        }

        // Mouse.cursor is PROCESS-WIDE and it OVERRIDES the runtime's own rule
        // (src/emit.ts ASC_window_update_cursor only computes ibeam/hand while
        // cursor == "auto"), so a stale "hand" would stick to the whole window and
        // a text field would lose its I-beam. Hence: re-derive from the hover
        // chain on every change, and hand the decision back with "auto" when
        // nothing on the chain asks for a shape.
        public function applyCursor():void
        {
            var want:String = null;
            var p:UiNode = this._hover;
            while (p != null)
            {
                var c:String = p.resolved != null ? p.resolved.cursor : null;
                if (c != null) { want = c; break; }
                p = p.parent;
            }
            if (want == null) want = MouseCursor.AUTO;
            if (Mouse.cursor != want) Mouse.cursor = want;
        }

        private function onStageMouseMove(e:MouseEvent):void
        {
            this.hoverMoves = this.hoverMoves + 1;
            this.setHoverTarget(this.nodeAt(e.target as DisplayObject));
        }

        private function onStageMouseLeave(e:Event):void
        {
            this.setHoverTarget(null);
        }

        // Mark a whole subtree's styles stale and ask for a repaint. Styles are NOT
        // rebuilt here: the next reconcile re-resolves each node against the new
        // palette, which is one pass instead of two and keeps the "one writer per bit"
        // rule that `markLayoutDirty` documents. Layout is deliberately NOT marked --
        // a palette swap never changes a number, and forcing a re-solve would repaint
        // the tree through the expensive door for nothing.
        private function markThemeDirty(n:UiNode):void
        {
            n.lastStyleStale = true;
            n.dirty |= Dirty.M_PAINT;
            for (var i:int = 0; i < n.children.length; i++) this.markThemeDirty(n.children[i]);
        }

        // ---- frame boundary ---------------------------------------------
        private function onEnterFrame(e:Event):void
        {
            this.enterFrameTicks = this.enterFrameTicks + 1;
            if (!this._running) return;
            // A THEME SWITCH IS A FRAME BOUNDARY EVENT, and it runs FIRST: everything
            // below (the author's tick, the reconcile, the paint) must already see the
            // new palette. Two things have to happen, and they are different things:
            //   * a DESCRIBE pass (`invalidate`), because the overlay chrome and every
            //     factory-baked refinement were rebuilt with new pointers -- only a
            //     re-describe hands those pointers to the resolver. `Dirty.THEME` was
            //     declared for years with no consumer; this is its consumer.
            //   * `lastStyleStale` + M_PAINT on every node, because a node whose
            //     refinement pointer did NOT move (the author's own style, or a widget
            //     that paints from `Theme.tokens()` directly) still has to re-resolve
            //     its baseline and repaint.
            if (Theme.themeEpoch() != this._themeEpoch)
            {
                this._themeEpoch = Theme.themeEpoch();
                if (this.root != null) this.markThemeDirty(this.root);
                if (this.overlayRoot != null) this.markThemeDirty(this.overlayRoot);
                this.invalidate(Dirty.THEME);
            }
            // The author tick runs FIRST, for the same reason the reflow runs in
            // ENTER_FRAME at all: an invalidation raised here must be visible in
            // THIS frame's present. The clock is getTimer() (monotonic ms since
            // start) -- see the comment on View.tick for why not frame count and
            // why not an epoch clock. The SAME value drives the animator, so the
            // clock is read exactly once per frame.
            var now:Number = getTimer();
            this.view.tick(now);
            // Advance wall-time tweens and keep their nodes repainting until they
            // land. `advance` returns true while anything is still animating (a
            // tween that just landed counts for one more frame, so its exact final
            // value gets painted). The active list is walked by reference, so this
            // allocates nothing.
            if (Anim.advance(now))
            {
                var tweens:Array = Anim.activeList();
                for (var ti:int = 0; ti < tweens.length; ti++)
                {
                    var tw:Tween = Tween(tweens[ti]);
                    if (tw.active && tw.node != null) this.markPaint(tw.node);
                }
            }
            // A window resize arrives as an Event too, but some backends report a
            // changed drawable size without one, so compare the stage size as a
            // cheap safety net (this is the section 3.3 "window size changed" row).
            if (this.stage != null && this.stage.stageWidth > 0
                && (this.stage.stageWidth != this._solvedW || this.stage.stageHeight != this._solvedH))
            {
                this.invalidate(Dirty.STRUCTURE);
            }
            if (this._pending != 0 || this._needsPaint) this.reflow();
        }

        private function onResize(e:Event):void
        {
            this.invalidate(Dirty.STRUCTURE);
        }

        // ---- the reflow --------------------------------------------------
        public function reflow():void
        {
            var availW:Number = (this.stage != null && this.stage.stageWidth > 0) ? this.stage.stageWidth : 560;
            var availH:Number = (this.stage != null && this.stage.stageHeight > 0) ? this.stage.stageHeight : 460;

            // CONSUME THE PAINT REQUEST AT THE TOP, not at the bottom. A paint pass
            // can RAISE the next one -- SpinnerWidget's spin does exactly that: it
            // derives its angle from the frame clock and ends with `markPaint(n)`.
            // Clearing `_needsPaint` at the END of reflow therefore erased the
            // request that the pass just made, and a spinning spinner repainted
            // ONCE and then froze. It only looked alive because of an unrelated
            // accident: `_solvedW` used to be written only by the main root's solve
            // branch, so the ENTER_FRAME size check saw a mismatch every frame and
            // re-described the view, which repainted as a side effect. Fixing the
            // percentage-root re-solve below removed that accident and exposed it.
            // Swapping the flag here is the honest form: this number is what THIS
            // frame asked for; anything marked during the pass belongs to the next.
            var wantsPaint:Boolean = this._needsPaint;
            this._needsPaint = false;

            // A WINDOW RESIZE MUST RE-SOLVE PERCENTAGE-SIZED ROOTS. `size: [100%,100%]`
            // is resolved against `avail` at SOLVE time, but nothing in the tree
            // changed -- the styles are the same pointers, so the reconciler's
            // pointer test skips resolveStyle and the roots keep the rect they were
            // solved with. The overlay host is exactly that shape: it was measured
            // at the 560x460 fallback (the first frame runs before the window
            // exists) and stayed there while the stage was already 760x560, so every
            // overlay surface was laid out in a 200px-too-narrow box.
            if (availW != this._solvedW || availH != this._solvedH)
            {
                if (this.root != null)
                {
                    this.root.dirty |= Dirty.M_MEASURE | Dirty.M_ARRANGE;
                    this.root.markLayoutDirty();
                }
                if (this.overlayRoot != null)
                {
                    this.overlayRoot.dirty |= Dirty.M_MEASURE | Dirty.M_ARRANGE;
                    this.overlayRoot.markLayoutDirty();
                }
            }

            var reconciled:Boolean = false;
            var reconciledOverlay:Boolean = false;
            if (this._pending != 0)
            {
                var desc:Node = this.view.render();
                this.describeCalls = this.describeCalls + 1;
                if (desc == null)
                {
                    throw new Error('asaot.ui: View.render() returned null (see api-design section 1.1)');
                }
                this.root = this.reconciler.reconcile(this.root, desc, null);
                if (this.root.backing != null && this.root.backing.parent == null && this.stageContainer != null)
                {
                    this.stageContainer.addChild(this.root.backing);
                }

                // The overlay tree (see View.renderOverlay). Reconciled in the
                // same describe phase, but SOLVED after the main tree so an
                // anchored overlay reads this frame's final anchor rect.
                var odesc:Node = this.view.renderOverlay();
                if (odesc != null)
                {
                    this.overlayRoot = this.reconciler.reconcile(this.overlayRoot, odesc, null);
                    if (this.overlayRoot.backing != null && this.overlayRoot.backing.parent == null
                        && this.stageContainer != null)
                    {
                        this.stageContainer.addChild(this.overlayRoot.backing);
                    }
                    reconciledOverlay = true;
                }
                else if (this.overlayRoot != null)
                {
                    this.reconciler.destroyRoot(this.overlayRoot);
                    this.overlayRoot = null;
                    reconciledOverlay = true;
                }
                reconciled = true;
            }

            // Keep the overlay on top of the display list. It is normally added
            // after the main root and therefore already on top; this only has to
            // repair the one case where the main root was re-attached later.
            if (reconciledOverlay && this.overlayRoot != null && this.overlayRoot.backing != null
                && this.overlayRoot.backing.parent != null && this.stageContainer != null)
            {
                var top:int = this.stageContainer.numChildren - 1;
                if (top >= 0 && this.stageContainer.getChildIndex(this.overlayRoot.backing) != top)
                {
                    this.stageContainer.setChildIndex(this.overlayRoot.backing, top);
                }
            }

            var layoutRan:Boolean = false;
            if (this.root != null && (this.root.dirty & (Dirty.M_MEASURE | Dirty.M_ARRANGE)) != 0)
            {
                this.solveRoot(this.root, availW, availH);
                layoutRan = true;
            }
            // MAIN FIRST, OVERLAY SECOND. An anchored overlay (popover / menu)
            // reads its anchor's solved rect during its own measure pass, so the
            // anchor has to be final by then -- that ordering is the whole reason
            // this is a second `solveRoot` call and not one merged tree.
            if (this.overlayRoot != null
                && (this.overlayRoot.dirty & (Dirty.M_MEASURE | Dirty.M_ARRANGE)) != 0)
            {
                this.solveRoot(this.overlayRoot, availW, availH);
                layoutRan = true;
            }

            if (layoutRan)
            {
                // A full sweep, and that is a MEASURED decision, not inertia:
                // replacing this with paintDirty cost probes/widgets/stick its
                // sticky bands (a widget whose paint publishes state the next
                // scroll step reads), while removing painting altogether moved
                // the layout phase by 0ms (temp/dissect2.cjs). Painting is not
                // where the frame time is; measurePass is. Do not "optimise"
                // this line again without re-running both.
                this.paintPasses = this.paintPasses + 1;
                if (this.root != null) paintAll(this.root);
                if (this.overlayRoot != null) paintAll(this.overlayRoot);
            }
            else if (wantsPaint || reconciled)            {
                // A reconciled frame MUST get a paint sweep even when nothing
                // reflowed. An author change that only affects decoration (a
                // background, a border colour) arrives as a re-describe plus
                // node-level M_PAINT bits and *no* measure/arrange dirty anywhere
                // -- `style/Style.diffFlags` classifies it as paint-only, exactly
                // like a widget payload that returns false. Without this branch
                // the paint pass was skipped entirely, the M_PAINT bits were
                // never consumed, and the change silently never reached the
                // screen until some unrelated reflow happened to repaint it.
                // (The animation path hid this: `Anim` calls `markPaint` every
                // frame of a tween, so an animating app repainted continuously.)
                // `paintDirty` paints only nodes whose M_PAINT bit is set, so the
                // extra work is one O(n) walk plus O(changed) painting.
                this.paintPasses = this.paintPasses + 1;
                if (this.root != null) paintDirty(this.root);
                if (this.overlayRoot != null) paintDirty(this.overlayRoot);
            }

            this._pending = 0;
            // The pointer shape is re-derived at the END of the pass, so a style
            // change under a stationary pointer still reaches the window (the
            // hover chain is unchanged, so no callback would otherwise fire).
            this.applyCursor();

        }

        // One root: intrinsic measure, engine solve, arrange. Shared by the main
        // tree and the overlay tree so the two can never drift apart in how they
        // are driven.
        private function solveRoot(r:UiNode, availW:Number, availH:Number):void
        {
            this.measurePasses = this.measurePasses + 1;
            measurePass(r);
            this.layoutSolves = this.layoutSolves + 1;
            this.engine.calculate(r.engineNode, availW, availH, LayoutConstants.DIR_LTR);
            this.arrangePasses = this.arrangePasses + 1;
            arrangePass(r, 0, 0);
            this._solvedW = availW;
            this._solvedH = availH;
        }

        private function measurePass(n:UiNode):void
        {
            n.measureSelf();
            n.dirty = n.dirty & ~Dirty.M_MEASURE;
            for (var i:int = 0; i < n.children.length; i++) measurePass(n.children[i]);
        }

        private function arrangePass(n:UiNode, px:Number, py:Number):void
        {
            n.arrangeSelf(px, py);
            n.dirty = n.dirty & ~Dirty.M_ARRANGE;
            for (var i:int = 0; i < n.children.length; i++)
            {
                arrangePass(n.children[i], n.absX, n.absY);
            }
        }

        private function paintAll(n:UiNode):void
        {
            // CONSUME THE BIT BEFORE PAINTING. A paint pass may raise its OWN next
            // frame (SpinnerWidget's spin ends with `markPaint`); clearing the bit
            // afterwards erased that request and the spinner repainted once. Same
            // rule as `wantsPaint` at the top of reflow: what this pass asked for is
            // being served now, what the pass raises belongs to the next one.
            n.dirty = n.dirty & ~Dirty.M_PAINT;
            n.paintSelf();
            for (var i:int = 0; i < n.children.length; i++) paintAll(n.children[i]);
        }

        private function paintDirty(n:UiNode):void
        {
            if ((n.dirty & Dirty.M_PAINT) != 0)
            {
                n.dirty = n.dirty & ~Dirty.M_PAINT;
                n.paintSelf();
            }
            for (var i:int = 0; i < n.children.length; i++) paintDirty(n.children[i]);
        }

        // ---- focus --------------------------------------------------------
        // Focus is ONE library pointer plus a per-node int (`state.focused`).
        // Moving it repaints two nodes and re-solves nothing: a ring is decoration,
        // exactly like hover (design doc 3.3).
        public function focusedNode():UiNode
        {
            return this._focus;
        }

        // Programmatic focus. `null` clears it. An inert or invisible node is
        // refused rather than silently half-focused.
        public function focusNode(n:UiNode):void
        {
            if (n != null && (n.inert() || !n.visible || n.app != this)) return;
            if (n == this._focus)
            {
                this.applyStageFocus();
                return;
            }
            if (this._focus != null) this._focus.setFocused(0);
            this._focus = n;
            if (n != null) n.setFocused(1);
            this.applyStageFocus();
        }

        // Called by a node that became inert while focused.
        public function dropFocus(n:UiNode):void
        {
            if (this._focus == n) this.focusNode(null);
        }

        // Put the runtime's `stage.focus` where the focused node wants it. Only an
        // editable kind claims it (WidgetFocus); everything else clears it, which
        // is what makes clicking a button blur a text field -- the AIR-measured
        // behaviour for a non-TextField target.
        private function applyStageFocus():void
        {
            if (this.stage == null) return;
            var want:DisplayObject = this._focus == null ? null : this._focus.focusTarget();
            if (want == this.stage.focus) return;
            if (want is TextField) this.stage.focus = InteractiveObject(want);
            else if (this.stage.focus != null) this.stage.focus = null;
        }

        // ---- the tab ring -------------------------------------------------
        // Pre-order over the RETAINED tree, main tree first and the floating layer
        // second (it is drawn on top, so it comes last in reading order too). A node
        // is a stop iff it is tabEnabled, visible, and nothing above it is disabled.
        //
        // TRAP: once focus is INSIDE the floating layer, Tab stays there. That is
        // the one rule that gives a modal dialog a focus trap without UiApp having
        // to know what a dialog is -- and it cannot trap the page behind a MENU,
        // because opening a menu never moves the focus into it.
        private function focusNext(dir:int):void
        {
            var ring:Vector.<UiNode> = new Vector.<UiNode>();
            if (this._focus != null && inTree(this.overlayRoot, this._focus))
            {
                collectFocus(this.overlayRoot, ring);
            }
            else
            {
                collectFocus(this.root, ring);
                collectFocus(this.overlayRoot, ring);
            }
            ring = this.orderRing(ring);
            var m:int = ring.length;
            if (m == 0) return;
            var at:int = -1;
            for (var i:int = 0; i < m; i++) { if (ring[i] == this._focus) { at = i; break; } }
            var next:int;
            if (at >= 0) next = (at + dir + m) % m;
            else next = dir > 0 ? 0 : m - 1;
            this.tabMoves = this.tabMoves + 1;
            this.focusNode(ring[next]);
        }

        // `tabIndex` ORDERS THE RING, HTML-style: every explicit index first (ascending,
        // ties in document order), then everything that left it at -1, in document
        // order. The field had no consumer at all until now, so the ring was purely
        // document order and an author could not put a "Skip to content" button first.
        //
        // NO SORT AND NO VISITED-SET: the output vector IS the visited set, so this
        // needs one reusable buffer (a Tab press allocates nothing) and picks the
        // smallest index not yet emitted. n is the number of focus stops -- tens, not
        // thousands -- so the quadratic scan is invisible.
        private function orderRing(ring:Vector.<UiNode>):Vector.<UiNode>
        {
            var n:int = ring.length;
            var any:Boolean = false;
            for (var i0:int = 0; i0 < n; i0++) { if (ring[i0].tabIndex >= 0) { any = true; break; } }
            if (!any) return ring;

            var out:Vector.<UiNode> = this.ringScratch;
            out.length = 0;
            var guard:int = 0;
            while (guard <= n)
            {
                guard++;
                var bestV:int = -1;
                var found:Boolean = false;
                for (var j:int = 0; j < n; j++)
                {
                    var ti:int = ring[j].tabIndex;
                    if (ti < 0) continue;
                    if (emitted(out, ti)) continue;
                    if (!found || ti < bestV) { found = true; bestV = ti; }
                }
                if (!found) break;
                // Every node sharing that index, in DOCUMENT order -- which is what makes
                // the ties stable without carrying their positions around.
                for (var k0:int = 0; k0 < n; k0++)
                {
                    if (ring[k0].tabIndex == bestV) out.push(ring[k0]);
                }
            }
            for (var m0:int = 0; m0 < n; m0++)
            {
                if (ring[m0].tabIndex < 0) out.push(ring[m0]);
            }
            return out;
        }

        private static function emitted(out:Vector.<UiNode>, index:int):Boolean
        {
            for (var i:int = 0; i < out.length; i++)
            {
                if (out[i].tabIndex == index) return true;
            }
            return false;
        }

        private function collectFocus(n:UiNode, out:Vector.<UiNode>):void
        {
            if (n == null) return;
            // A hidden subtree has no stops. `visible` is the Element flag, which is
            // what a closed dialog sets -- the runtime's own ring walk does not check
            // it, and would happily put the caret inside a closed dialog.
            if (!n.visible) return;
            if (n.tabEnabled && !n.inert()) out.push(n);
            for (var i:int = 0; i < n.children.length; i++) collectFocus(n.children[i], out);
        }

        private function inTree(root:UiNode, n:UiNode):Boolean
        {
            var p:UiNode = n;
            while (p != null)
            {
                if (p == root) return root != null;
                p = p.parent;
            }
            return false;
        }

        // The retained node that owns this display object (or one of its internal
        // objects, e.g. an input field). Identity walk, no map, no hashing.
        private function findNodeFor(o:DisplayObject):UiNode
        {
            var hit:UiNode = findIn(this.overlayRoot, o);
            if (hit != null) return hit;
            return findIn(this.root, o);
        }

        private function findIn(n:UiNode, o:DisplayObject):UiNode
        {
            if (n == null) return null;
            if (n.backing == o || n.tf == o) return n;
            for (var i:int = 0; i < n.children.length; i++)
            {
                var hit:UiNode = findIn(n.children[i], o);
                if (hit != null) return hit;
            }
            return null;
        }

        private function onStageFocusIn(e:FocusEvent):void
        {
            var n:UiNode = findNodeFor(e.target as DisplayObject);
            if (n == null || n == this._focus) return;
            // Do NOT call focusNode(): the runtime already moved stage.focus, and
            // re-assigning it here would re-enter as_set_focus.
            if (this._focus != null) this._focus.setFocused(0);
            this._focus = n;
            n.setFocused(1);
        }

        private function onStageFocusOut(e:FocusEvent):void
        {
            var n:UiNode = findNodeFor(e.target as DisplayObject);
            if (n == null || n != this._focus) return;
            // A focus move within the library is already handled by focusNode (it
            // sets the new node after clearing the old). This branch is the runtime
            // blurring us -- focus became null -- so the pointer must go too.
            var rel:UiNode = e.relatedObject == null ? null : findNodeFor(e.relatedObject as DisplayObject);
            if (rel == null)
            {
                n.setFocused(0);
                this._focus = null;
            }
        }

        // ---- keys ---------------------------------------------------------
        private function onKeyDown(e:KeyboardEvent):void
        {
            this.keyEvents = this.keyEvents + 1;
            var kc:int = e.keyCode;

            // KEYMAP FIRST -- ahead of Tab. A binding the author installed is the
            // MOST specific statement about what a key means in their app, so it
            // wins over every built-in, including Tab (a user may legitimately want
            // Tab to do something else in an editor). An UNBOUND key falls through
            // untouched, which is what keeps plain typing inside a text field.
            var ctx:Array = this.contextsOf(this._focus);
            var hit:Object = ActionRegistry.lookup(kc, e.ctrlKey, e.altKey, e.shiftKey,
                                                   e.commandKey, ctx);
            if (hit != null)
            {
                e.preventDefault();
                ActionRegistry.dispatch(String(hit.id), hit.payload as Object);
                return;
            }

            // TAB. The runtime ALSO moves focus on Tab (as_focus_tab over the display
            // list) after the event is dispatched, unless the event was cancelled --
            // so preventing the default is not optional here, it is the difference
            // between one ring and two.
            if (kc == 9)
            {
                this.focusNext(e.shiftKey ? -1 : 1);
                e.preventDefault();
                return;
            }

            var f:UiNode = this._focus;
            if (f == null) return;
            // A kind that knows the key consumes it first (menu arrows, dialog Esc,
            // input Enter). `is` on an optional interface -- see WidgetKeys.
            if (f.widget is WidgetKeys)
            {
                if (WidgetKeys(f.widget).onKey(f, kc, e.shiftKey))
                {
                    e.preventDefault();
                    return;
                }
            }
            // Default activation: Enter / Space press the focused control. Skipped
            // when the focus target is an editable field -- there, Enter is the
            // field's commit and Space is a character, and swallowing either would
            // break typing.
            if (kc == 13 || kc == 32)
            {
                if (f.focusTarget() is TextField) return;
                e.preventDefault();
                // `Control.action` -- declared since the first commit, dispatched now.
                // A control that names an action is activated by that action; a
                // control without one keeps the plain click handler.
                if (f.action != null)
                {
                    ActionRegistry.dispatch(f.action, null);
                    return;
                }
                f.handleClick();
            }
        }

        // The key contexts of the focused node, INNERMOST FIRST (design doc 6.2).
        // Built into a reused array: this runs on every key repeat.
        private function contextsOf(n:UiNode):Array
        {
            var out:Array = this.ctxScratch;
            out.length = 0;
            var p:UiNode = n;
            while (p != null)
            {
                if (p.keyContext != null && p.keyContext != "") out.push(p.keyContext);
                p = p.parent;
            }
            return out;
        }

        // ---- introspection for tests / a11y ----------------------------
        public function getRoot():UiNode
        {
            return this.root;
        }

        public function findByKey(k:Object):UiNode
        {
            var hit:UiNode = findScoped(this.root, k);
            if (hit != null) return hit;
            // The overlay tree is a second root; a key is unique across BOTH trees
            // (the main tree wins a collision, which is also what a test author
            // expects: content over chrome).
            return findScoped(this.overlayRoot, k);
        }

        private function findScoped(n:UiNode, k:Object):UiNode
        {
            if (n == null) return null;
            if (n.key != null && String(n.key) == String(k)) return n;
            for (var i:int = 0; i < n.children.length; i++)
            {
                var hit:UiNode = findScoped(n.children[i], k);
                if (hit != null) return hit;
            }
            return null;
        }

        public function isRunning():Boolean
        {
            return this._running;
        }
    }
}
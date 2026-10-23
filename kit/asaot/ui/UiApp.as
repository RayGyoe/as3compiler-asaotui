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
    import asaot.ui.as3.As3LayoutEngine;
    import asaot.ui.anim.Anim;
    import asaot.ui.anim.Tween;

    import flash.display.DisplayObject;
    import flash.display.DisplayObjectContainer;
    import flash.display.Stage;
    import flash.events.Event;
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

        private var root:UiNode;
        private var reconciler:Reconciler;
        private var _pending:int;
        private var _needsPaint:Boolean;
        private var _solvedW:Number;
        private var _solvedH:Number;
        private var _running:Boolean;

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
            this.describeCalls = 0;
            this.reconcileVisits = 0;
            this.layoutSolves = 0;
            this.measurePasses = 0;
            this.arrangePasses = 0;
            this.paintPasses = 0;
            this.invalidateCalls = 0;
            this.enterFrameTicks = 0;
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

        // ---- frame boundary ---------------------------------------------
        private function onEnterFrame(e:Event):void
        {
            this.enterFrameTicks = this.enterFrameTicks + 1;
            if (!this._running) return;
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

            var reconciled:Boolean = false;
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
                reconciled = true;
            }

            var layoutRan:Boolean = false;
            if (this.root != null && (this.root.dirty & (Dirty.M_MEASURE | Dirty.M_ARRANGE)) != 0)
            {
                this.measurePasses = this.measurePasses + 1;
                measurePass(this.root);
                this.layoutSolves = this.layoutSolves + 1;
                this.engine.calculate(this.root.engineNode, availW, availH, LayoutConstants.DIR_LTR);
                this.arrangePasses = this.arrangePasses + 1;
                arrangePass(this.root, 0, 0);
                this._solvedW = availW;
                this._solvedH = availH;
                layoutRan = true;
            }

            if (layoutRan)
            {
                this.paintPasses = this.paintPasses + 1;
                paintAll(this.root);
            }
            else if (this.root != null && (this._needsPaint || reconciled))
            {
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
                paintDirty(this.root);
            }

            this._pending = 0;
            this._needsPaint = false;
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
            n.paintSelf();
            n.dirty = n.dirty & ~Dirty.M_PAINT;
            for (var i:int = 0; i < n.children.length; i++) paintAll(n.children[i]);
        }

        private function paintDirty(n:UiNode):void
        {
            if ((n.dirty & Dirty.M_PAINT) != 0)
            {
                n.paintSelf();
                n.dirty = n.dirty & ~Dirty.M_PAINT;
            }
            for (var i:int = 0; i < n.children.length; i++) paintDirty(n.children[i]);
        }

        // ---- introspection for tests / a11y ----------------------------
        public function getRoot():UiNode
        {
            return this.root;
        }

        public function findByKey(k:Object):UiNode
        {
            return findScoped(this.root, k);
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
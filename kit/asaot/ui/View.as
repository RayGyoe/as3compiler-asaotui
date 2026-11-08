// asaot.ui.View -- the root of a description tree (design doc section 1.1).
//
// `render()` is the ONLY method an author must implement, and its contract is
// GPUI's `Render::render` (asaotui/gpui-src/crates/gpui/src/element.rs:164-166):
// pure description, no side effects, no addChild, no reliance on evaluation
// order, and the return value must not be stored BY AUTHOR CODE. `memo()` below
// is the explicit framework-owned exception for immutable description subtrees.
// The difference from GPUI is the FREQUENCY: GPUI drops and rebuilds the whole element tree every frame
// (element.rs:10-14), while we call `render()` only on a dirty frame and then
// diff the description against the retained UiNode tree.
package asaot.ui
{
    import flash.display.Stage;
    import flash.utils.Dictionary;

    public class View extends Observable
    {
        protected var app:UiApp;
        private var _memo:Dictionary;

        public function View():void
        {
            super();
            this.app = null;
            this._memo = new Dictionary();
        }

        // Reuse an immutable description subtree until one of its inputs changes.
        // The factory runs ONLY on a miss; this is what avoids allocating the whole
        // subtree, not a deep-equality check after it has already been allocated.
        // `key` names the slot in this View; `version` must capture every input read
        // by the factory (strict === semantics, so use a scalar string/number/bool).
        // The returned Node and its descendants must never be mutated after the
        // factory returns. Reconciliation still applies theme/inherited changes to
        // the retained tree, so a palette switch does not need a cache-version bump.
        protected function memo(key:String, version:*, build:Function):Node
        {
            var entry:Array = this._memo[key] as Array;
            if (entry != null && entry[0] === version) return entry[1] as Node;
            var n:Node = build();
            // Only this explicit immutable-cache contract licenses Reconciler's
            // same-object subtree skip. Legacy views may retain and mutate an
            // ordinary Node, which must continue to reconcile on every render.
            n.memoRoot = true;
            this._memo[key] = [version, n];
            return n;
        }

        public function render():Node
        {
            return null;
        }

        // The OVERLAY tree (see UiApp.overlayRoot). A SECOND, independent
        // description root reconciled against the stage on top of `render()`'s
        // tree -- it is how dialog / drawer / popover / menu / toast escape the
        // flex flow and the parent's box. Returns null when nothing floats
        // (the default), and null tears any existing overlay tree down.
        //
        // WHY A SECOND ROOT AND NOT A CHILD OF render(): an overlay must be able
        // to cover the WHOLE window and be painted last no matter where in the
        // tree its trigger sits. A child would be laid out inside its parent's
        // box and drawn in child order, so a dialog declared in a form row would
        // be clipped to that row's rectangle and painted under every later
        // sibling. Being a separate retained root gives both properties for free
        // and keeps the main tree's layout numbers untouched.
        //
        // The tree is laid out AFTER the main one, so `absX/absY/absW/absH` read
        // from `app.findByKey(anchor)` during an overlay node's measure are THIS
        // frame's final anchor rect, not last frame's.
        public function renderOverlay():Node
        {
            return null;
        }

        // Per-frame author hook, called once per frame BEFORE the dirty check, so
        // a tick that invalidates is serviced in THIS frame's present rather than
        // the next one.
        //
        // `nowMs` is `getTimer()`: monotonic milliseconds since the program
        // started. It is NOT seconds and NOT an epoch timestamp, and both of
        // those matter -- animation must advance on wall time, because a
        // frame-counted tween runs at a different speed on a 60Hz and a 120Hz
        // machine. (Measured: `new Date().getTime()` works and gives epoch ms;
        // `getTimer()` works and gives ms since start; `Date.now()` does not
        // compile -- see compiler-gaps.md G10.)
        //
        // This is GPUI's prepaint step in spirit (see gpui-borrow-map.md): the
        // place to advance transient state before the frame is described. It is
        // deliberately OPT-IN -- the default does nothing, which is what keeps
        // the "a settled frame does zero describe/reflow work" invariant that
        // CheckUi pins.
        public function tick(nowMs:Number):void
        {
            // Author hook; nothing required.
        }

        public function mount(stage:Stage):void
        {
            // Author hook; nothing required.
        }

        public function attachApp(a:UiApp):void
        {
            this.app = a;
        }

        public function getApp():UiApp
        {
            return this.app;
        }

        // The data-flow seam (section 5.1): a view does NOT redraw here, it only
        // raises a dirty bit with the scheduler.
        public function invalidate(dirty:int):void
        {
            if (this.app != null) this.app.invalidate(dirty);
        }

        public function invalidateAll():void
        {
            this.invalidate(Dirty.ALL);
        }
    }
}
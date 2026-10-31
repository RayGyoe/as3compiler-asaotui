// asaot.ui.kind.NavStackWidget -- the BACK key for NavStackNode.
//
// The stack draws nothing of its own: the factory has already mounted one
// absolute inset-0 wrapper per page, and `visible` on those wrappers is the whole
// "which page is on top" mechanism. So this widget's job is the ONE thing a
// description cannot express -- INTENT from outside the tree -- and it is short on
// purpose.
//
// WHY A STAGE LISTENER AND NOT WidgetKeys: `WidgetKeys.onKey` is delivered to the
// FOCUSED node only (see that interface's contract). Back is not a property of the
// focused control -- it must work whether the focus is in a text field, on a button,
// or nowhere at all, because on a phone it is a system gesture. UiApp keeps the
// stage-level listener list, so this widget listens there too and filters by
// `keyCode == Keyboard.BACK`. It is registered lazily from `payload` (the first
// pass in which `n.app` exists) and removed in `teardown`: a destroyed stack must
// not keep the frame's stage pointing at it.
//
// HONEST LIMIT: Windows/macOS key events cannot produce 0x01000016, so on a
// desktop this listener is dead code until a backend maps a real back gesture onto
// it (MOBILE.md B13 / compiler-gaps G5). The probe dispatches the synthetic
// KEY_DOWN itself, which is the same thing the touch probes do.
//
// ONLY THE VISIBLE STACK ANSWERS. The listener is on the stage, so EVERY mounted
// stack hears the key -- and an app composed as "one navStack per tab, all mounted,
// only the active one visible" (which is how a phone app keeps each tab's history)
// would pop in all of them at once, including the tabs the user cannot see. The key
// is only delivered to a node whose whole ancestor chain is visible, i.e. the stack
// that is actually on screen. Two VISIBLE stacks still both answer: at that point
// the composition has two live screens and the author must decide (a dialog stack
// is not this widget's job).
package asaot.ui.kind
{
    import asaot.ui.NavStackNode;
    import asaot.ui.Node;
    import asaot.ui.UiNode;
    import asaot.ui.Widget;
    import asaot.ui.WidgetTeardown;

    import flash.events.KeyboardEvent;
    import flash.ui.Keyboard;

    public class NavStackWidget implements Widget, WidgetTeardown
    {
        private static const BACK_FN:String = "backfn";   // the stage listener closure
        private static const BACK_CB:String = "backcb";   // the author's onBack
        private static const BACK_ON:String = "backon";   // the listener is live

        public function build(n:UiNode):void
        {
        }

        public function payload(n:UiNode, desc:Node):Boolean
        {
            var d:NavStackNode = NavStackNode(desc);
            n.extra[BACK_CB] = d.onBack;
            this.listen(n);
            return false;   // pages are children; this node's own box never changes
        }

        private function listen(n:UiNode):void
        {
            if (n.extra[BACK_ON] != null) return;
            if (n.app == null || n.app.stage == null) return;   // retried next pass
            var self:NavStackWidget = this;
            var fn:Function = function (e:KeyboardEvent):void { self.onBackKey(n, e); };
            n.extra[BACK_FN] = fn;
            n.extra[BACK_ON] = true;
            n.app.stage.addEventListener(KeyboardEvent.KEY_DOWN, fn);
        }

        private function onBackKey(n:UiNode, e:KeyboardEvent):void
        {
            // The media/TV block is the only place Keyboard.BACK exists; a desktop
            // key can never carry it, and any other code belongs to somebody else.
            if (e.keyCode != Keyboard.BACK) return;
            if (!visibleChain(n)) return;
            var cb:Function = n.extra[BACK_CB] as Function;
            if (cb != null) cb();
        }

        // "Is this stack on screen" -- its own `visible` AND every ancestor's, the
        // same rule UiApp.pickAt applies to a pixel. Walked here rather than asked
        // of the app because the answer has to be current AT THE KEY EVENT, and the
        // picker is for coordinates, not for nodes.
        private function visibleChain(n:UiNode):Boolean
        {
            var p:UiNode = n;
            while (p != null)
            {
                if (!p.visible) return false;
                p = p.parent;
            }
            return true;
        }

        public function wantsPress():Boolean { return false; }

        public function measure(n:UiNode):void
        {
            // The wrappers are the layout: absolute inset 0 makes them exactly this
            // node's box, so the stack itself contributes no intrinsic size at all.
        }

        public function arrange(n:UiNode):void
        {
        }

        public function paint(n:UiNode):void
        {
            // No surface of its own. A page paints its own background; a stack that
            // painted one too would show through every rounded page corner.
        }

        public function click(n:UiNode):Boolean
        {
            return false;
        }

        public function teardown(n:UiNode):void
        {
            var fn:Function = n.extra[BACK_FN] as Function;
            if (fn != null && n.app != null && n.app.stage != null)
            {
                n.app.stage.removeEventListener(KeyboardEvent.KEY_DOWN, fn);
            }
            n.extra[BACK_FN] = null;
            n.extra[BACK_ON] = null;
            n.extra[BACK_CB] = null;
        }
    }
}

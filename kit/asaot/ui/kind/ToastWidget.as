// asaot.ui.kind.ToastWidget -- paints the bubble and owns its dismiss timer.
//
// THE ONLY TIMER IN THE LIBRARY, and it is armed from `payload` when `open` flips,
// not from `build`: a toast that starts ATOMICALLY at open:dismiss 800ms later
// would fire during whatever frame is running, which is untestable. Arming on the
// transition keeps the timer's origin at a frame boundary the author caused.
//
// THE TIMER ONLY CALLS `onClose`. It never writes `open` itself: the author's model
// owns that (same rule as dialog/drawer/popover), so a re-render that keeps `open`
// true after the deadline simply re-arms -- which is correct, because the author
// re-opened it.
//
// `clearTimeout` is called whenever the toast closes, so a toast whose author closes
// it early does not leave a pending callback that would fire `onClose` twice.
package asaot.ui.kind
{
    import asaot.ui.Node;
    import asaot.ui.OverlayMotion;
    import asaot.ui.PaintKit;
    import asaot.ui.ToastNode;
    import asaot.ui.UiNode;
    import flash.display.Shape;
    import asaot.ui.Widget;
    import asaot.ui.WidgetTeardown;

    import flash.utils.setTimeout;
    import flash.utils.clearTimeout;

    public class ToastWidget implements Widget, WidgetTeardown
    {
        private static const OPEN_KEY:String = "open";
        private static const DUR_KEY:String = "dur";
        private static const TMR_KEY:String = "tmr";
        private static const FN_KEY:String = "onClose";

        public function build(n:UiNode):void
        {
            // One Shape at child INDEX 0 holds the panel/trigger background;
            // PaintKit.paintBox draws nothing without it, so the surface used to
            // have a correct solved rect and paint nothing at all. Same layout as
            // BoxWidget: the shape is added in build(), before the reconciler
            // appends this node's children, so the children keep a stable base
            // index for display-order repair.
            n.shapeA = new Shape();
            n.backing.addChild(n.shapeA);
            n.extra[OPEN_KEY] = false;
            n.extra[DUR_KEY] = 0;
            n.extra[TMR_KEY] = -1;
            n.extra[FN_KEY] = null;
        }

        // A pending setTimeout holds this node just like the popover stage listener
        // does: the callback would fire onClose on a torn-down toast (#1009).
        public function teardown(n:UiNode):void
        {
            if (n.extra == null) return;
            var tmr:Object = n.extra[TMR_KEY];
            if (tmr != null && int(Number(tmr)) >= 0) clearTimeout(int(Number(tmr)));
            n.extra[TMR_KEY] = -1;
        }

        public function payload(n:UiNode, desc:Node):Boolean
        {
            var t:ToastNode = ToastNode(desc);
            n.extra[FN_KEY] = t.onClose;
            n.extra[DUR_KEY] = t.duration;

            var was:Boolean = Boolean(n.extra[OPEN_KEY]);
            if (was == t.open) return false;
            n.extra[OPEN_KEY] = t.open;
            if (t.open) OverlayMotion.start(n);
            n.visible = t.open;
            if (n.backing != null) n.backing.visible = t.open;

            var tmr:Object = n.extra[TMR_KEY];
            if (tmr != null && int(Number(tmr)) >= 0) { clearTimeout(int(Number(tmr))); n.extra[TMR_KEY] = -1; }

            if (t.open && t.duration > 0)
            {
                n.extra[TMR_KEY] = setTimeout(function ():void { ToastWidget.fire(n); }, t.duration);
            }
            // A visibility flip needs the arrange sweep to re-apply backing.visible.
            return true;
        }

        public function wantsPress():Boolean { return false; }

        public function measure(n:UiNode):void { }

        public function arrange(n:UiNode):void { }

        public function paint(n:UiNode):void
        {
            PaintKit.paintBox(n, n.resolved, PaintKit.w1(n), PaintKit.h1(n));
            // A toast rises into its slot (the stack grows upward, so a rise reads
            // as "this one just arrived").
            OverlayMotion.apply(n, n, n, 0, 8);
        }

        public function click(n:UiNode):Boolean { return false; }

        private static function fire(n:UiNode):void
        {
            n.extra[TMR_KEY] = -1;
            if (!Boolean(n.extra[OPEN_KEY])) return;
            var f:Function = n.extra[FN_KEY];
            if (f != null) f();
        }
    }
}
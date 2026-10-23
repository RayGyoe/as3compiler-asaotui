// asaot.ui.kind.TextWidget -- a static, single-line text run.
//
// Its intrinsic size is measured through a REAL TextField (see Widget.measure),
// and that field doubles as the on-screen display object -- we never draw a
// second text pipeline (design doc section 4.4).
package asaot.ui.kind
{
    import asaot.ui.PaintKit;
    import asaot.ui.TextNode;
    import asaot.ui.UiNode;
    import asaot.ui.Widget;
    import asaot.ui.Node;
    import asaot.ui.style.Style;

    import asaot.ui.LayoutConstants;

    public class TextWidget implements Widget
    {
        public function build(n:UiNode):void
        {
            n.tf = PaintKit.makeText(false);
            n.backing.addChild(n.tf);
        }

        public function payload(n:UiNode, desc:Node):Boolean
        {
            var tc:String = TextNode(desc).content;
            if (tc != n.textContent)
            {
                n.textContent = tc;
                return true;   // intrinsic width may change
            }
            return false;
        }

        public function wantsPress():Boolean { return false; }

        public function measure(n:UiNode):void
        {
            if (n.tf == null) return;
            var s:Style = n.resolved;
            PaintKit.measureField(n, n.tf, n.textContent, s);
            if (PaintKit.autoW(s)) PaintKit.setPointSize(n, LayoutConstants.AXIS_WIDTH, n.state.measuredW);
            if (PaintKit.autoH(s)) PaintKit.setPointSize(n, LayoutConstants.AXIS_HEIGHT, n.state.measuredH);
        }

        public function arrange(n:UiNode):void
        {
            if (n.tf == null) return;
            n.tf.x = PaintKit.insetX(n);
            n.tf.y = PaintKit.insetY(n);
        }

        public function paint(n:UiNode):void
        {
            var s:Style = n.resolved;
            // The field was configured during measure (it had to be, to get an
            // intrinsic size); update the format for a decor-only change.
            if (n.tf != null && s.text.color >= 0) n.tf.textColor = uint(s.text.color);
            PaintKit.paintBox(n, s, PaintKit.w1(n), PaintKit.h1(n));
        }

        public function click(n:UiNode):Boolean { return false; }
    }
}
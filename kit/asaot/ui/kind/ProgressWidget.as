// asaot.ui.kind.ProgressWidget -- a read-only track + filled portion + label.
//
// NOT interactive: `wantsPress` is false and `click` returns false, so the
// backing never registers a click handler (UiNode adds one only when
// `wantsPress()` is true) and an author `onClick` would fire unchanged.
//
// `value` is a DECORATION (a progress bar never resizes to its value), so a
// value change raises only Dirty.M_PAINT. The value is CLAMPED to 0..1 before
// drawing, so 0 draws no fill and 1 fills exactly the track width.
package asaot.ui.kind
{
    import asaot.ui.ProgressNode;
    import asaot.ui.Dirty;
    import asaot.ui.PaintKit;
    import asaot.ui.UiNode;
    import asaot.ui.Widget;
    import asaot.ui.Node;
    import asaot.ui.style.Style;

    import asaot.ui.LayoutConstants;

    import flash.display.Shape;

    public class ProgressWidget implements Widget
    {
        public function build(n:UiNode):void
        {
            n.shapeA = new Shape();   // track
            n.backing.addChild(n.shapeA);
            n.shapeB = new Shape();   // filled portion
            n.backing.addChild(n.shapeB);
            n.tf = PaintKit.makeText(false);
            n.backing.addChild(n.tf);
        }

        public function payload(n:UiNode, desc:Node):Boolean
        {
            var p:ProgressNode = ProgressNode(desc);
            var relayout:Boolean = false;
            if (p.label != n.label)
            {
                n.label = p.label;
                relayout = true;
            }
            var val:Number = p.value;
            if (val < 0) val = 0;
            if (val > 1) val = 1;
            var prev:Object = n.extra["v"];
            if (prev == null || Number(prev) != val)
            {
                n.extra["v"] = val;
                n.dirty |= Dirty.M_PAINT;   // paint only
            }
            return relayout;
        }

        public function wantsPress():Boolean { return false; }

        public function measure(n:UiNode):void
        {
            if (n.tf == null) return;
            var s:Style = n.resolved;
            PaintKit.measureField(n, n.tf, n.label, s);
            // A bar must not shrink to its label; without an explicit width it
            // gets a 160pt default and a 30pt height (label + 8pt track + margins).
            if (PaintKit.autoW(s)) PaintKit.setPointSize(n, LayoutConstants.AXIS_WIDTH, 160);
            if (PaintKit.autoH(s)) PaintKit.setPointSize(n, LayoutConstants.AXIS_HEIGHT, 30);
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
            var w:Number = n.absW > 1 ? n.absW : 1;
            var v:Number = Number(n.extra["v"]);
            if (isNaN(v)) v = 0;
            var ty:Number = n.absH - 12;   // track top
            var fill:Number = w * v;
            if (n.shapeA != null)
            {
                var g:Object = n.shapeA.graphics;
                g.clear();
                g.beginFill(0xE5E7EB, 1.0);
                g.drawRoundRect(0, ty, w, 8, 8, 8);
                g.endFill();
            }
            if (n.shapeB != null)
            {
                var g2:Object = n.shapeB.graphics;
                g2.clear();
                if (fill > 0)
                {
                    g2.beginFill(0x2563EB, 1.0);
                    g2.drawRoundRect(0, ty, fill, 8, 8, 8);
                    g2.endFill();
                }
            }
            if (n.tf != null && s.text.color >= 0) n.tf.textColor = uint(s.text.color);
        }

        public function click(n:UiNode):Boolean { return false; }
    }
}
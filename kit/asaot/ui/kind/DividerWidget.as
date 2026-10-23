// asaot.ui.kind.DividerWidget -- the hairline for DividerNode.
//
// The node IS the rule: its cross-axis auto size is 1 and its main axis is the
// author's (or stretches). The drawn stroke is ALWAYS 1px thick and CENTRED in
// the node, so a divider with an explicit larger cross size still reads as a
// hairline instead of a bar. Colour preference is `borderColor` then
// `background` -- a rule is usually authored as either.
//
// `orientation` is mirrored onto `n.extra` and a change returns true from
// `payload`: it flips which axis gets the 1px intrinsic size, so it is a LAYOUT
// change (the same discipline ChipWidget applies to its label).
package asaot.ui.kind
{
    import asaot.ui.DividerNode;
    import asaot.ui.Node;
    import asaot.ui.PaintKit;
    import asaot.ui.UiNode;
    import asaot.ui.Widget;
    import asaot.ui.style.Style;

    import asaot.ui.LayoutConstants;

    import flash.display.Shape;

    public class DividerWidget implements Widget
    {
        private static const ORIENT_KEY:String = "orient";

        public function build(n:UiNode):void
        {
            n.shapeA = new Shape();
            n.backing.addChild(n.shapeA);
        }

        public function payload(n:UiNode, desc:Node):Boolean
        {
            var d:DividerNode = DividerNode(desc);
            var o:String = d.orientation == null ? "horizontal" : d.orientation;
            var prev:Object = n.extra[ORIENT_KEY];
            if (prev == null || o != String(prev))
            {
                n.extra[ORIENT_KEY] = o;
                return true;   // the intrinsic 1px axis switches (re-measure)
            }
            return false;
        }

        public function wantsPress():Boolean { return false; }

        public function measure(n:UiNode):void
        {
            var s:Style = n.resolved;
            var vert:Boolean = String(n.extra[ORIENT_KEY]) == "vertical";
            // A hairline is 1px on its CROSS axis; the main axis is the author's
            // explicit size or stretches to the parent. So only the cross axis is
            // stamped with an intrinsic size here.
            if (vert)
            {
                if (PaintKit.autoW(s)) PaintKit.setPointSize(n, LayoutConstants.AXIS_WIDTH, 1);
            }
            else
            {
                if (PaintKit.autoH(s)) PaintKit.setPointSize(n, LayoutConstants.AXIS_HEIGHT, 1);
            }
        }

        public function arrange(n:UiNode):void
        {
            // The rule is the whole rect; nothing is placed.
        }

        public function paint(n:UiNode):void
        {
            if (n.shapeA == null) return;
            var s:Style = n.resolved;
            var col:uint = 0xE5E7EB;
            if (!isNaN(s.borderColor)) col = uint(s.borderColor) & 0xFFFFFF;
            else if (s.background != null) col = s.background.rgb();

            var w:Number = PaintKit.w1(n);
            var h:Number = PaintKit.h1(n);
            var vert:Boolean = String(n.extra[ORIENT_KEY]) == "vertical";
            var g:Object = n.shapeA.graphics;
            g.clear();
            g.beginFill(col, 1.0);
            if (vert) g.drawRect((w - 1) / 2, 0, 1, h);
            else g.drawRect(0, (h - 1) / 2, w, 1);
            g.endFill();
        }

        public function click(n:UiNode):Boolean { return false; }
    }
}

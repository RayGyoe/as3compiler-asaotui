// asaot.ui.kind.ButtonWidget -- a clickable label on a box.
//
// The label is centred INSIDE the content box by hand (see `paint`) rather than
// by the layout engine, because the label is not a UiNode and so has no engine
// node of its own. This stays true now that the style surface has
// justifyContent/alignItems: those position CHILD UiNodes, and the button's own
// label is an internal display object, not a child.
package asaot.ui.kind
{
    import asaot.ui.ButtonNode;
    import asaot.ui.PaintKit;
    import asaot.ui.UiNode;
    import asaot.ui.Widget;
    import asaot.ui.Node;
    import asaot.ui.style.Style;

    import asaot.ui.LayoutConstants;

    import flash.display.Shape;

    public class ButtonWidget implements Widget
    {
        public function build(n:UiNode):void
        {
            n.shapeA = new Shape();
            n.backing.addChild(n.shapeA);
            n.tf = PaintKit.makeText(false);
            n.backing.addChild(n.tf);
        }

        public function payload(n:UiNode, desc:Node):Boolean
        {
            var b:ButtonNode = ButtonNode(desc);
            var bl:String = b.label;
            var relayout:Boolean = false;
            if (bl != n.label)
            {
                n.label = bl;
                relayout = true;   // the intrinsic width follows the label
            }
            // Handlers and the action are re-pointed every frame: they are cheap
            // references, and the author may swap the closure on any render.
            n.onClick = b.onClick;
            n.action = b.action;
            return relayout;
        }

        public function wantsPress():Boolean { return true; }

        public function measure(n:UiNode):void
        {
            if (n.tf == null) return;
            var s:Style = n.resolved;
            PaintKit.measureField(n, n.tf, n.label, s);
            if (PaintKit.autoW(s))
            {
                PaintKit.setPointSize(n, LayoutConstants.AXIS_WIDTH,
                    n.state.measuredW + PaintKit.padH(s.padding) + PaintKit.borderH(s.borderWidths));
            }
            if (PaintKit.autoH(s))
            {
                PaintKit.setPointSize(n, LayoutConstants.AXIS_HEIGHT,
                    n.state.measuredH + PaintKit.padV(s.padding) + PaintKit.borderV(s.borderWidths));
            }
        }

        public function arrange(n:UiNode):void
        {
            // Nothing to do: the label is centred in paint, where the content box
            // is known to be final.
        }

        public function paint(n:UiNode):void
        {
            var s:Style = n.resolved;
            PaintKit.paintBox(n, s, PaintKit.w1(n), PaintKit.h1(n));
            if (n.tf == null) return;
            var tw:Number = n.state.measuredW;
            var th:Number = n.state.measuredH;
            var cw:Number = n.absW - PaintKit.borderH(s.borderWidths) - PaintKit.padH(s.padding);
            var ch:Number = n.absH - PaintKit.borderV(s.borderWidths) - PaintKit.padV(s.padding);
            n.tf.x = PaintKit.insetX(n) + (cw - tw) / 2;
            n.tf.y = PaintKit.insetY(n) + (ch - th) / 2;
        }

        public function click(n:UiNode):Boolean { return false; }
    }
}
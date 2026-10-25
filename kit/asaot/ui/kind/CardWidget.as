// asaot.ui.kind.CardWidget -- a titled surface that CONTAINS other UiNodes.
//
// Two display objects are owned here (lowest first): `shapeA`, the card's own
// box, and `tf`, the title. The card's CHILDREN are added to `n.backing` by the
// reconciler AFTER these two, so the card's children really are its children and
// the engine lays them out inside its content box -- the card is a real
// container, not a hand-placed box.
//
// The title is NOT a UiNode, so nothing reserves layout space for it: it is
// placed by hand at the content box's top-left in `paint` (the same mechanism
// ButtonWidget uses for its label). An author who wants the title clear of the
// children gives the card a top `padding`.
//
// `title` changes the intrinsic height of a title-only card, so `payload`
// returns true for it (layout change), matching ButtonWidget's label.
package asaot.ui.kind
{
    import asaot.ui.CardNode;
    import asaot.ui.Node;
    import asaot.ui.PaintKit;
    import asaot.ui.UiNode;
    import asaot.ui.Widget;
    import asaot.ui.style.Style;

    import asaot.ui.LayoutConstants;

    import flash.display.Shape;

    public class CardWidget implements Widget
    {
        public function build(n:UiNode):void
        {
            n.shapeA = new Shape();            // the card surface
            n.backing.addChild(n.shapeA);
            n.tf = PaintKit.makeText(false);   // the internal title
            n.backing.addChild(n.tf);
        }

        public function payload(n:UiNode, desc:Node):Boolean
        {
            var c:CardNode = CardNode(desc);
            if (c.title != n.label)
            {
                n.label = c.title;
                return true;   // the title feeds the intrinsic size of a bare card
            }
            return false;
        }

        public function wantsPress():Boolean { return false; }

        public function measure(n:UiNode):void
        {
            if (n.tf == null) return;
            var s:Style = n.resolved;
            PaintKit.measureField(n, n.tf, n.label, s);
            // A card WITH children gets its auto axes from the engine (a flex
            // container shrink-wraps around its children), so we must not
            // overwrite them with the title's size. Only a title-only card
            // shrink-wraps to its title.
            if (n.children.length == 0)
            {
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
        }

        public function arrange(n:UiNode):void
        {
            // The children are placed by the engine; the title is placed in paint.
        }

        public function paint(n:UiNode):void
        {
            var s:Style = n.resolved;
            PaintKit.paintBox(n, s, PaintKit.w1(n), PaintKit.h1(n));
            if (n.tf == null) return;
            n.tf.x = PaintKit.insetX(n);
            n.tf.y = PaintKit.insetY(n);
            if (s.text.color >= 0) n.tf.textColor = uint(s.text.color);
            PaintKit.decorate(n);
        }

        public function click(n:UiNode):Boolean { return false; }
    }
}
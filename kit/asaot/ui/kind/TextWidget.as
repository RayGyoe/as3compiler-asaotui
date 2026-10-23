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
            // The intrinsic size is the CONTENT size, so the box's own padding and
            // border have to be added on top: the engine's boxSizing defaults to
            // border-box, i.e. a point size is the WHOLE box. Publishing the bare
            // text width would leave the padding eating into the text -- a 4px
            // glyph with 4px padding got an 8px box and its run overflowed into
            // the next node (seen with the breadcrumb separator). Badge/Button/
            // Card/Chip already add the insets here; this one did not.
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
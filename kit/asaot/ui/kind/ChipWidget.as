// asaot.ui.kind.ChipWidget -- the pill for ChipNode.
//
// ★ REFERENCE IMPLEMENTATION (see ChipNode.as). It deliberately demonstrates the
// two kinds of state a widget can carry, because getting this wrong is what makes
// a reconcile reflow every frame:
//
//   * `label` is mirrored onto the UiNode itself, and a change returns TRUE from
//     `payload` -- the intrinsic width follows the text, so it is a LAYOUT change;
//   * `tone` is a decoration, remembered on `n.extra`, and only raises
//     Dirty.M_PAINT -- a colour change must never re-solve the layout.
//
// The tone is read back in `paint` from `n.extra` (NOT from `n.desc`) because
// paint must stay allocation-free and `extra` is a plain property read.
package asaot.ui.kind
{
    import asaot.ui.ChipNode;
    import asaot.ui.Dirty;
    import asaot.ui.Node;
    import asaot.ui.PaintKit;
    import asaot.ui.UiNode;
    import asaot.ui.Widget;
    import asaot.ui.style.Style;

    import asaot.ui.LayoutConstants;

    import flash.display.Shape;

    public class ChipWidget implements Widget
    {
        // tone -> (fill, foreground). Kept as plain ints so `paint` allocates
        // nothing.
        private static const TONE_KEY:String = "tone";

        public function build(n:UiNode):void
        {
            n.shapeA = new Shape();   // the pill
            n.backing.addChild(n.shapeA);
            n.tf = PaintKit.makeText(false);
            n.backing.addChild(n.tf);
        }

        public function payload(n:UiNode, desc:Node):Boolean
        {
            var c:ChipNode = ChipNode(desc);
            var relayout:Boolean = false;
            if (c.label != n.label)
            {
                n.label = c.label;
                relayout = true;      // the pill grows with its text
            }
            var t:String = c.tone == null ? "neutral" : c.tone;
            var prev:Object = n.extra[TONE_KEY];
            if (prev == null || t != String(prev))
            {
                n.extra[TONE_KEY] = t;
                n.dirty |= Dirty.M_PAINT;   // decoration only: never a reflow
            }
            return relayout;
        }

        public function wantsPress():Boolean { return false; }

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
                var h:Number = n.state.measuredH + PaintKit.padV(s.padding) + PaintKit.borderV(s.borderWidths);
                if (h < 20) h = 20;   // a chip is never thinner than its pill
                PaintKit.setPointSize(n, LayoutConstants.AXIS_HEIGHT, h);
            }
        }

        public function arrange(n:UiNode):void
        {
            // The label is centred in paint, where the content box is final.
        }

        public function paint(n:UiNode):void
        {
            var s:Style = n.resolved;
            var bg:uint = 0xE5E7EB;
            var fg:uint = 0x374151;
            var tone:String = String(n.extra[TONE_KEY]);
            if (tone == "info") { bg = 0xDBEAFE; fg = 0x1D4ED8; }
            else if (tone == "danger") { bg = 0xFEE2E2; fg = 0xB91C1C; }

            // Hover / press are derived, not authored (see PaintKit): a chip that
            // reacts to the pointer is the reference implementation of the rule.
            bg = PaintKit.stateColor(n, bg);
            var w:Number = PaintKit.w1(n);
            var h:Number = PaintKit.h1(n);
            if (n.shapeA != null)
            {
                var g:Object = n.shapeA.graphics;
                g.clear();
                g.beginFill(bg, 1.0);
                var r:Number = s.cornerRadii != null ? PaintKit.nz(s.cornerRadii.topLeft) : 0;
                if (r > 0) g.drawRoundRect(0, 0, w, h, r * 2, r * 2);
                else g.drawRect(0, 0, w, h);
                g.endFill();
            }

            if (n.tf != null)
            {
                var cw:Number = n.absW - PaintKit.borderH(s.borderWidths) - PaintKit.padH(s.padding);
                var ch:Number = n.absH - PaintKit.borderV(s.borderWidths) - PaintKit.padV(s.padding);
                n.tf.x = PaintKit.insetX(n) + (cw - n.state.measuredW) / 2;
                n.tf.y = PaintKit.insetY(n) + (ch - n.state.measuredH) / 2;
                n.tf.textColor = fg;
            }
            PaintKit.decorate(n);
        }

        public function click(n:UiNode):Boolean { return false; }
    }
}
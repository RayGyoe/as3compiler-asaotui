// asaot.ui.kind.BadgeWidget -- the count pill for BadgeNode.
//
// Same two-kinds-of-state discipline as ChipWidget (the reference):
//   * `label` is mirrored onto the UiNode and a change returns TRUE from
//     `payload` -- the pill's intrinsic width follows the text;
//   * `tone` is a decoration, remembered on `n.extra`, and only raises
//     Dirty.M_PAINT -- a colour change never re-solves the layout.
//
// `tone` is read back from `n.extra` in `paint` (a property read, allocation
// free) rather than from `n.desc`. The default corner radius is a full pill
// (h/2); a `cornerRadii` in the style overrides it.
package asaot.ui.kind
{
    import asaot.ui.BadgeNode;
    import asaot.ui.Dirty;
    import asaot.ui.Node;
    import asaot.ui.PaintKit;
    import asaot.ui.Theme;
    import asaot.ui.ThemeTokens;
    import asaot.ui.UiNode;
    import asaot.ui.Widget;
    import asaot.ui.style.Style;

    import asaot.ui.LayoutConstants;

    import flash.display.Shape;

    public class BadgeWidget implements Widget
    {
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
            var b:BadgeNode = BadgeNode(desc);
            var relayout:Boolean = false;
            if (b.label != n.label)
            {
                n.label = b.label;
                relayout = true;      // the pill grows with its text
            }
            var t:String = b.tone == null ? "neutral" : b.tone;
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
                var w:Number = n.state.measuredW + PaintKit.padH(s.padding) + PaintKit.borderH(s.borderWidths);
                if (w < 16) w = 16;   // one digit still gets a circular badge
                PaintKit.setPointSize(n, LayoutConstants.AXIS_WIDTH, w);
            }
            if (PaintKit.autoH(s))
            {
                var h:Number = n.state.measuredH + PaintKit.padV(s.padding) + PaintKit.borderV(s.borderWidths);
                if (h < 16) h = 16;   // a badge is never thinner than its pill
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
            var pal:ThemeTokens = Theme.tokens();
            var bg:uint = pal.surfaceSoft;
            var fg:uint = pal.textBody;
            var tone:String = String(n.extra[TONE_KEY]);
            if (tone == "info") { bg = pal.accentSoft; fg = pal.accentText; }
            else if (tone == "danger") { bg = pal.danger; fg = pal.onAccent; }

            var w:Number = PaintKit.w1(n);
            var h:Number = PaintKit.h1(n);
            if (n.shapeA != null)
            {
                var g:Object = n.shapeA.graphics;
                g.clear();
                g.beginFill(bg, 1.0);
                var r:Number = s.cornerRadii != null ? PaintKit.nz(s.cornerRadii.topLeft) : h / 2;
                if (r > h / 2) r = h / 2;
                if (r > w / 2) r = w / 2;
                if (r > 0) g.drawRoundRect(0, 0, w, h, r * 2, r * 2);
                else g.drawRect(0, 0, w, h);
                g.endFill();
            }

            if (n.tf != null)
            {
                var cw:Number = n.absW - PaintKit.borderH(s.borderWidths) - PaintKit.padH(s.padding);
                var ch:Number = n.absH - PaintKit.borderV(s.borderWidths) - PaintKit.padV(s.padding);
                PaintKit.centerText(n, PaintKit.insetX(n), PaintKit.insetY(n), cw, ch);
                n.tf.textColor = fg;
            }
            PaintKit.decorate(n);
        }

        public function click(n:UiNode):Boolean { return false; }
    }
}
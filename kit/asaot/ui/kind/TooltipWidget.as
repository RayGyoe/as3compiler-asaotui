// asaot.ui.kind.TooltipWidget -- the bubble for TooltipNode.
//
// ONE SHAPE, TWO PARTS. The bubble and the arrow are drawn into the same
// `shapeA` in one painting pass: a rounded rect for the body plus a triangle for
// the arrow, offset so the arrow sits OUTSIDE the body's edge. The arrow is a
// constant 6px (not an option) because it is a pointing cue, and its size relative
// to the 11px text is a design decision rather than a layout float.
//
// The BODY's colour comes from `tone`; the text colour is always white, because a
// light bubble with dark text is a `chip` -- two widgets, not one option.
package asaot.ui.kind
{
    import asaot.ui.Dirty;
    import asaot.ui.Node;
    import asaot.ui.PaintKit;
    import asaot.ui.TooltipNode;
    import asaot.ui.UiNode;
    import asaot.ui.Widget;
    import asaot.ui.style.Edges;
    import asaot.ui.style.Style;

    import asaot.ui.LayoutConstants;

    import flash.display.Shape;

    public class TooltipWidget implements Widget
    {
        private static const TEXT_KEY:String = "text";
        private static const ARROW_KEY:String = "arrow";
        private static const TONE_KEY:String = "tone";

        private static const ARROW:Number = 6;    // the triangle's extent, px
        private static const ARROW_W:Number = 12; // its base width, px
        private static const PAD_H:Number = 8;
        private static const PAD_V:Number = 5;
        private static const RADIUS:Number = 4;

        public function build(n:UiNode):void
        {
            n.shapeA = new Shape();   // bubble + arrow
            n.backing.addChild(n.shapeA);
            n.tf = PaintKit.makeText(false);
            n.backing.addChild(n.tf);
        }

        public function payload(n:UiNode, desc:Node):Boolean
        {
            var t:TooltipNode = TooltipNode(desc);
            var relayout:Boolean = false;
            var prevText:Object = n.extra[TEXT_KEY];
            if (prevText == null || String(prevText) != String(t.text))
            {
                n.extra[TEXT_KEY] = t.text;
                relayout = true;      // the bubble is as wide as its text
            }
            var a:String = t.arrow == null ? "up" : t.arrow;
            var prevArrow:Object = n.extra[ARROW_KEY];
            if (prevArrow == null || String(prevArrow) != a)
            {
                n.extra[ARROW_KEY] = a;
                relayout = true;      // the arrow adds to one axis
            }
            var prevTone:Object = n.extra[TONE_KEY];
            if (prevTone == null || Number(prevTone) != t.tone)
            {
                n.extra[TONE_KEY] = t.tone;
                n.dirty |= Dirty.M_PAINT;   // decoration only: never a reflow
            }
            return relayout;
        }

        public function wantsPress():Boolean { return false; }

        public function measure(n:UiNode):void
        {
            if (n.tf == null) return;
            var s:Style = n.resolved;
            PaintKit.measureField(n, n.tf, String(n.extra[TEXT_KEY]), s);
            var a:String = String(n.extra[ARROW_KEY]);
            var hasArrow:Boolean = a != "none";
            var vert:Boolean = a == "up" || a == "down";
            if (PaintKit.autoW(s))
            {
                var w:Number = n.state.measuredW + 2 * PAD_H;
                if (hasArrow && !vert) w = w + ARROW;   // a left/right arrow widens the bubble
                PaintKit.setPointSize(n, LayoutConstants.AXIS_WIDTH, w);
            }
            if (PaintKit.autoH(s))
            {
                var h:Number = n.state.measuredH + 2 * PAD_V;
                if (hasArrow && vert) h = h + ARROW;    // an up/down arrow makes it taller
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
            PaintKit.paintBox(n, s, PaintKit.w1(n), PaintKit.h1(n));
            if (n.shapeA == null) return;

            var w:Number = PaintKit.w1(n);
            var h:Number = PaintKit.h1(n);
            var a:String = String(n.extra[ARROW_KEY]);
            var tone:uint = uint(Number(n.extra[TONE_KEY]));
            var g:Object = n.shapeA.graphics;

            // The body box: the full rect minus the arrow's strip on whichever edge
            // the arrow points out of.
            var bx:Number = 0;
            var by:Number = 0;
            var bw:Number = w;
            var bh:Number = h;
            if (a == "up") { by = ARROW; bh = h - ARROW; }
            else if (a == "down") { bh = h - ARROW; }
            else if (a == "left") { bx = ARROW; bw = w - ARROW; }
            else if (a == "right") { bw = w - ARROW; }
            if (bw <= 0 || bh <= 0) { bw = w; bh = h; bx = 0; by = 0; }

            g.beginFill(tone, 1.0);
            g.drawRoundRect(bx, by, bw, bh, RADIUS * 2, RADIUS * 2);
            g.endFill();

            if (a == "up" || a == "down")
            {
                var cxm:Number = bx + bw / 2;
                g.beginFill(tone, 1.0);
                if (a == "up")
                {
                    g.moveTo(cxm, 0);
                    g.lineTo(cxm - ARROW_W / 2, ARROW);
                    g.lineTo(cxm + ARROW_W / 2, ARROW);
                }
                else
                {
                    g.moveTo(cxm, h);
                    g.lineTo(cxm - ARROW_W / 2, h - ARROW);
                    g.lineTo(cxm + ARROW_W / 2, h - ARROW);
                }
                g.endFill();
            }
            else if (a == "left" || a == "right")
            {
                var cym:Number = by + bh / 2;
                g.beginFill(tone, 1.0);
                if (a == "left")
                {
                    g.moveTo(0, cym);
                    g.lineTo(ARROW, cym - ARROW_W / 2);
                    g.lineTo(ARROW, cym + ARROW_W / 2);
                }
                else
                {
                    g.moveTo(w, cym);
                    g.lineTo(w - ARROW, cym - ARROW_W / 2);
                    g.lineTo(w - ARROW, cym + ARROW_W / 2);
                }
                g.endFill();
            }

            if (n.tf != null)
            {
                var padH:Number = nzPad(s, true, PAD_H);
                var padV:Number = nzPad(s, false, PAD_V);
                n.tf.x = bx + padH;
                n.tf.y = by + padV;
                n.tf.textColor = 0xFFFFFF;
            }
            PaintKit.decorate(n);
        }

        // The style's padding wins when the author set it; otherwise the bubble's own
        // breathing room. `Edges` uses NaN as the unset sentinel (CONTRIBUTING 3).
        private function nzPad(s:Style, horizontal:Boolean, dflt:Number):Number
        {
            var e:Edges = s.padding;
            if (e == null) return dflt;
            var v:Number = horizontal ? e.left : e.top;
            return isNaN(v) ? dflt : v;
        }

        public function click(n:UiNode):Boolean { return false; }
    }
}

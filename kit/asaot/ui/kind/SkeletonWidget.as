// asaot.ui.kind.SkeletonWidget -- the grey blocks for SkeletonNode.
//
// The last line of a "text" skeleton is 60% wide, because a placeholder that is a
// perfect rectangle reads as a broken image rather than as text. That ratio is a
// constant here (`LAST_LINE`), not an option: it is a reading cue, and offering it
// as a knob would invite layouts that look wrong.
//
// `variant` / `lines` / `barHeight` / `gap` all change the INTRINSIC size, so
// `payload` returns true when any of them changes and `measure` writes the
// resulting point sizes; `tone` is decoration and only raises M_PAINT.
package asaot.ui.kind
{
    import asaot.ui.Dirty;
    import asaot.ui.Node;
    import asaot.ui.PaintKit;
    import asaot.ui.SkeletonNode;
    import asaot.ui.UiNode;
    import asaot.ui.Widget;
    import asaot.ui.style.Style;

    import asaot.ui.LayoutConstants;

    import flash.display.Shape;

    public class SkeletonWidget implements Widget
    {
        private static const V_KEY:String = "var";
        private static const N_KEY:String = "lines";
        private static const BH_KEY:String = "bh";
        private static const GAP_KEY:String = "gap";
        private static const TONE_KEY:String = "tone";

        private static const LAST_LINE:Number = 0.6;
        private static const DEFAULT_CIRCLE:Number = 40;

        public function build(n:UiNode):void
        {
            n.shapeA = new Shape();   // background (if any) + the bars
            n.backing.addChild(n.shapeA);
        }

        public function payload(n:UiNode, desc:Node):Boolean
        {
            var sk:SkeletonNode = SkeletonNode(desc);
            var relayout:Boolean = false;
            var v:String = sk.variant == null ? "text" : sk.variant;
            relayout = setIfChanged(n, V_KEY, v) || relayout;
            relayout = setIfChanged(n, N_KEY, sk.lines) || relayout;
            relayout = setIfChanged(n, BH_KEY, sk.barHeight) || relayout;
            relayout = setIfChanged(n, GAP_KEY, sk.gap) || relayout;
            paintIfChanged(n, TONE_KEY, sk.tone);
            return relayout;
        }

        // Returns true when the value actually moved (i.e. this is a layout change).
        private function setIfChanged(n:UiNode, key:String, v:Object):Boolean
        {
            var prev:Object = n.extra[key];
            if (prev != null && String(prev) == String(v)) return false;
            n.extra[key] = v;
            return true;
        }

        private function paintIfChanged(n:UiNode, key:String, v:Object):void
        {
            if (setIfChanged(n, key, v)) n.dirty |= Dirty.M_PAINT;
        }

        public function wantsPress():Boolean { return false; }

        public function measure(n:UiNode):void
        {
            var s:Style = n.resolved;
            var v:String = String(n.extra[V_KEY]);
            var bh:Number = nzNum(Number(n.extra[BH_KEY]), 8);
            var gap:Number = nzNum(Number(n.extra[GAP_KEY]), 6);
            if (v == "circle")
            {
                if (PaintKit.autoW(s)) PaintKit.setPointSize(n, LayoutConstants.AXIS_WIDTH, DEFAULT_CIRCLE);
                if (PaintKit.autoH(s)) PaintKit.setPointSize(n, LayoutConstants.AXIS_HEIGHT, DEFAULT_CIRCLE);
                return;
            }
            if (v == "rect")
            {
                // An auto-sized rect has nothing to go on, so it takes a block
                // default rather than collapsing to zero.
                if (PaintKit.autoW(s)) PaintKit.setPointSize(n, LayoutConstants.AXIS_WIDTH, 200);
                if (PaintKit.autoH(s)) PaintKit.setPointSize(n, LayoutConstants.AXIS_HEIGHT, 80);
                return;
            }
            var lines:int = int(Number(n.extra[N_KEY]));
            if (lines < 1) lines = 1;
            if (PaintKit.autoH(s))
            {
                PaintKit.setPointSize(n, LayoutConstants.AXIS_HEIGHT,
                    lines * bh + (lines - 1) * gap);
            }
        }

        public function arrange(n:UiNode):void
        {
            // The bars are drawn straight into the solved rect by `paint`.
        }

        public function paint(n:UiNode):void
        {
            var s:Style = n.resolved;
            PaintKit.paintBox(n, s, PaintKit.w1(n), PaintKit.h1(n));
            if (n.shapeA == null) return;
            var w:Number = PaintKit.w1(n);
            var h:Number = PaintKit.h1(n);
            var g:Object = n.shapeA.graphics;
            var tone:uint = uint(Number(n.extra[TONE_KEY]));
            var v:String = String(n.extra[V_KEY]);

            if (v == "circle")
            {
                var d:Number = Math.min(w, h);
                g.beginFill(tone, 1.0);
                g.drawCircle(w / 2, h / 2, d / 2);
                g.endFill();
                return;
            }
            if (v == "rect")
            {
                g.beginFill(tone, 1.0);
                g.drawRect(0, 0, w, h);
                g.endFill();
                return;
            }

            var bh:Number = nzNum(Number(n.extra[BH_KEY]), 8);
            var gap:Number = nzNum(Number(n.extra[GAP_KEY]), 6);
            var lines:int = int(Number(n.extra[N_KEY]));
            if (lines < 1) lines = 1;
            var y:Number = 0;
            g.beginFill(tone, 1.0);
            for (var i:int = 0; i < lines; i++)
            {
                var lw:Number = (i == lines - 1 && lines > 1) ? w * LAST_LINE : w;
                g.drawRect(0, y, lw, bh);
                y = y + bh + gap;
            }
            g.endFill();
        }

        // Same NaN tolerance as PaintKit: an unset numeric option must not turn the
        // whole bar run into NaN geometry.
        private function nzNum(v:Number, dflt:Number):Number
        {
            return (isNaN(v) || v <= 0) ? dflt : v;
        }

        public function click(n:UiNode):Boolean { return false; }
    }
}

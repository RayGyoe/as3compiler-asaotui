// asaot.ui.kind.SparklineWidget -- the Shape behind SparklineNode.
//
// WHY THIS EXISTS AT ALL
// ----------------------
// `icon` is the kit's only path painter, and its box is SQUARE on purpose (a
// 24x24 glyph fitted and centred -- see IconWidget.paint). A price series is the
// opposite shape: 20..60 points spread across a WIDE box, with the y range
// decided by the data and the x range by the number of points. Reusing `icon`
// would squash the glyph into a 38pt square and leave the rest of a 104pt box
// empty, so a series needs its own non-uniform mapping. This widget is that
// mapping and nothing else: `x = i / (n-1)`, `y = (hi - v) / (hi - lo)`.
//
// NOTHING IS INTERPOLATED. The line is a polyline through the samples, which is
// what a sparkline IS (a smooth spline would draw values the data never had).
//
// WHERE THE NUMBERS COME FROM
// ---------------------------
// `min`/`max` are computed from the DATA, never from a fixed scale: a series
// whose values sit between 12.30 and 12.34 must fill the box, or every sparkline
// in a list is a flat line with a one-pixel wobble. A `baseline` (the previous
// close, in the market case) joins the range so the zero-crossing of the day is
// where the eye expects it. A series that never moves gets a +-0.5 window so the
// line lands in the middle instead of dividing by zero.
//
// ALLOCATION. `paint` allocates nothing: the series is the AUTHOR'S array, kept
// by reference (`values` is compared by identity, plus a `version` counter for an
// in-place edit -- see SparklineNode). No scratch arrays, no Math.max.apply.
package asaot.ui.kind
{
    import asaot.ui.Dirty;
    import asaot.ui.Node;
    import asaot.ui.PaintKit;
    import asaot.ui.SparklineNode;
    import asaot.ui.Theme;
    import asaot.ui.UiNode;
    import asaot.ui.Widget;
    import asaot.ui.style.Style;

    import asaot.ui.LayoutConstants;

    import flash.display.Shape;

    public class SparklineWidget implements Widget
    {
        // What payload mirrors and paint reads. Kept as constants so a typo is a
        // compile error in one place rather than a silently missing mirror.
        private static const SRC:String = "spv";      // the series (by reference)
        private static const VER:String = "spver";    // in-place edit counter
        private static const COL:String = "spcol";    // the line colour
        private static const FIL:String = "spfil";    // area under the line
        private static const SW:String = "spsw";      // stroke width (pt)
        private static const DOT:String = "spdot";    // the newest point
        private static const BASE:String = "spbase";  // the previous-close rule

        // The intrinsic box of an auto-sized sparkline: wide enough for 20 points
        // to be told apart, short enough to sit inside a 52pt list row.
        private static const DEFAULT_W:Number = 96;
        private static const DEFAULT_H:Number = 32;

        public function build(n:UiNode):void
        {
            n.shapeA = new Shape();
            n.backing.addChild(n.shapeA);
        }

        public function payload(n:UiNode, desc:Node):Boolean
        {
            var sp:SparklineNode = SparklineNode(desc);
            // The series is compared by IDENTITY. The author either hands a fresh
            // array (a new object every render) or mutates one in place and bumps
            // `version`; both are visible here, and neither allocates.
            if (n.extra[SRC] !== sp.values || Number(n.extra[VER]) != sp.version)
            {
                n.extra[SRC] = sp.values;
                n.extra[VER] = sp.version;
                n.dirty |= Dirty.M_PAINT;
            }
            if (diff(n, COL, sp.color)) n.dirty |= Dirty.M_PAINT;
            if (diff(n, FIL, sp.fill)) n.dirty |= Dirty.M_PAINT;
            if (diff(n, SW, sp.strokeWidth)) n.dirty |= Dirty.M_PAINT;
            if (diff(n, DOT, sp.dot)) n.dirty |= Dirty.M_PAINT;
            if (diff(n, BASE, sp.baseline)) n.dirty |= Dirty.M_PAINT;
            // Nothing here changes the INTRINSIC size: the box is the author's
            // (`size`) or the 96x32 default, never a function of the data.
            return false;
        }

        // String comparison so NaN ("no colour" / "no baseline") equals itself --
        // `NaN != NaN` would otherwise repaint every frame.
        private function diff(n:UiNode, key:String, v:Object):Boolean
        {
            var prev:Object = n.extra[key];
            var a:String = prev == null ? "" : String(prev);
            var b:String = v == null ? "" : String(v);
            if (a == b) return false;
            n.extra[key] = v;
            return true;
        }

        public function wantsPress():Boolean { return false; }

        public function measure(n:UiNode):void
        {
            var s:Style = n.resolved;
            if (PaintKit.autoW(s)) PaintKit.setPointSize(n, LayoutConstants.AXIS_WIDTH, DEFAULT_W);
            if (PaintKit.autoH(s)) PaintKit.setPointSize(n, LayoutConstants.AXIS_HEIGHT, DEFAULT_H);
        }

        public function arrange(n:UiNode):void { }

        public function paint(n:UiNode):void
        {
            var s:Style = n.resolved;
            var w:Number = PaintKit.w1(n);
            var h:Number = PaintKit.h1(n);
            PaintKit.paintBox(n, s, w, h);
            if (n.shapeA == null) return;
            var g:Object = n.shapeA.graphics;
            // Shape graphics ACCUMULATE. Every other painter here either fills
            // opaquely (so overdraw is invisible) or clears first; a polyline has
            // to clear, or every repaint leaves the previous frame's line behind.
            g.clear();

            var vals:Array = n.extra[SRC] as Array;
            if (vals == null || vals.length < 2) return;

            var sw:Number = n.extra[SW] == null ? 1.5 : Number(n.extra[SW]);
            if (!(sw > 0)) sw = 1.5;
            // Half a stroke plus a pixel: the top and bottom samples sit ON the
            // edge, and a stroke is centred on the path, so without this the
            // extremes are clipped in half.
            var pad:Number = sw * 0.5 + 1;
            if (w <= pad * 2 || h <= pad * 2) return;

            var lo:Number = 0;
            var hi:Number = 0;
            var any:Boolean = false;
            var i:int;
            for (i = 0; i < vals.length; i++)
            {
                var v:Number = Number(vals[i]);
                if (isNaN(v)) continue;
                if (!any) { lo = v; hi = v; any = true; }
                else { if (v < lo) lo = v; if (v > hi) hi = v; }
            }
            if (!any) return;
            var base:Number = n.extra[BASE] == null ? NaN : Number(n.extra[BASE]);
            if (!isNaN(base))
            {
                if (base < lo) lo = base;
                if (base > hi) hi = base;
            }
            if (hi - lo < 1e-9) { lo = lo - 0.5; hi = hi + 0.5; }

            var span:Number = hi - lo;
            var top:Number = pad;
            var bot:Number = h - pad;
            var x0:Number = pad;
            var dx:Number = (w - pad * 2) / (vals.length - 1);

            var col:uint = Theme.tokens().textStrong;
            var tc:Number = s.text.color;
            if (!isNaN(tc)) col = uint(tc) & 0xFFFFFF;
            var own:Number = n.extra[COL] == null ? NaN : Number(n.extra[COL]);
            if (!isNaN(own)) col = uint(own) & 0xFFFFFF;

            var wantFill:Boolean = n.extra[FIL] != null && Boolean(n.extra[FIL]);
            var wantDot:Boolean = n.extra[DOT] == null || Boolean(n.extra[DOT]);

            // The previous-close rule first, so the line covers it. A hairline at
            // 28%: a dashed rule would cost one drawRect per dash per sparkline per
            // repaint, and at 22 rows x 10 Hz that is thousands of ops a second for
            // an ornament.
            if (!isNaN(base))
            {
                var by:Number = top + ((hi - base) / span) * (bot - top);
                g.lineStyle(1, col, 0.28, false, "normal", "round", "round", 3);
                g.moveTo(x0, by);
                g.lineTo(w - pad, by);
            }

            if (wantFill)
            {
                g.beginFill(col, 0.13);
                g.moveTo(x0, top + ((hi - Number(vals[0])) / span) * (bot - top));
                for (i = 1; i < vals.length; i++)
                {
                    g.lineTo(x0 + dx * i, top + ((hi - Number(vals[i])) / span) * (bot - top));
                }
                g.lineTo(w - pad, h);
                g.lineTo(x0, h);
                g.lineTo(x0, top + ((hi - Number(vals[0])) / span) * (bot - top));
                g.endFill();
            }

            g.lineStyle(sw, col, 1.0, false, "normal", "round", "round", 3);
            g.moveTo(x0, top + ((hi - Number(vals[0])) / span) * (bot - top));
            for (i = 1; i < vals.length; i++)
            {
                g.lineTo(x0 + dx * i, top + ((hi - Number(vals[i])) / span) * (bot - top));
            }

            if (wantDot)
            {
                var last:Number = Number(vals[vals.length - 1]);
                if (!isNaN(last))
                {
                    var r:Number = sw > 2 ? sw : 2;
                    g.beginFill(col, 1.0);
                    g.drawCircle(w - pad, top + ((hi - last) / span) * (bot - top), r);
                    g.endFill();
                }
            }
        }

        public function click(n:UiNode):Boolean { return false; }
    }
}
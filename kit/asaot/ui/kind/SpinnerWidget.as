// asaot.ui.kind.SpinnerWidget -- the activity ring for SpinnerNode.
//
// TWO STATES, TWO DIRTY BITS (the ChipWidget lesson):
//   * `diameter` (when the style left the size auto) is a LAYOUT change -> payload
//     returns true and the node re-measures;
//   * `tone` / `thickness` / `phase` / `spin` are DECORATION -> M_PAINT only.
//
// SELF-PERPETUATING PAINT. While `spin` is true, `paint` derives the angle from
// `UiApp.enterFrameTicks` and ends with `markPaint(n)`, so the next frame repaints
// this node too. It never sets a layout bit, so the app repaints without ever
// re-solving -- the assertion in probes/widgets/feedback.
//
// WHY THE RING IS A FILLED BAND AND NOT A STROKE (measured, not assumed)
// ---------------------------------------------------------------------
// A stroked circle does not rasterize to the width you ask for. The radio in
// `probes/widgets/form` is `lineStyle(2, blue)` on a radius-7 circle, and its
// byte-exact frame shows the "2pt" ring as a ONE-pixel ring -- so a stroked arc is
// not something a pixel probe can pin, and its thickness is not something a
// designer can rely on. Both the track and the arc are therefore closed polygons
// (outer edge forward, inner edge back) filled with `beginFill`: a fill region
// rasterizes exactly, which is how every other widget in this kit draws.
// The spin's visual smoothness is unchanged -- 24 segments is 24 segments whether
// they are stroked or filled.
package asaot.ui.kind
{
    import asaot.ui.Dirty;
    import asaot.ui.Node;
    import asaot.ui.PaintKit;
    import asaot.ui.SpinnerNode;
    import asaot.ui.UiNode;
    import asaot.ui.Widget;
    import asaot.ui.style.Style;

    import asaot.ui.LayoutConstants;

    import flash.display.Shape;

    public class SpinnerWidget implements Widget
    {
        private static const D_KEY:String = "diam";
        private static const TH_KEY:String = "thick";
        private static const TONE_KEY:String = "tone";
        private static const SPIN_KEY:String = "spin";
        private static const PH_KEY:String = "phase";

        private static const TRACK:uint = 0xE5E7EB;
        // The arc is 3/8 of a turn, so that 0 degrees (3 o'clock) sits in the
        // MIDDLE of the sweep rather than on one of its square-cut ends: that is
        // the angle the pixel probe samples, and a fill boundary is not a colour
        // the checker may guess about.
        private static const ARC_FRAC:Number = 0.375;
        // 24 segments is enough that a 6px band never shows a corner.
        private static const SEGMENTS:int = 24;
        private static const TAU:Number = 6.283185307179586;
        private static const QUARTER:Number = 1.5707963267948966;

        public function build(n:UiNode):void
        {
            n.shapeA = new Shape();   // background (if any) + track + arc
            n.backing.addChild(n.shapeA);
        }

        public function payload(n:UiNode, desc:Node):Boolean
        {
            var sp:SpinnerNode = SpinnerNode(desc);
            var relayout:Boolean = false;
            var d:Number = sp.diameter;
            if (!(d > 0)) d = 20;
            if (Number(n.extra[D_KEY]) != d)
            {
                n.extra[D_KEY] = d;
                relayout = true;   // the intrinsic size follows the diameter
            }
            paintIfChanged(n, TH_KEY, sp.thickness);
            paintIfChanged(n, SPIN_KEY, sp.spin);
            paintIfChanged(n, PH_KEY, sp.phase);
            var t:String = sp.tone == null ? "info" : sp.tone;
            var prev:Object = n.extra[TONE_KEY];
            if (prev == null || t != String(prev))
            {
                n.extra[TONE_KEY] = t;
                n.dirty |= Dirty.M_PAINT;
            }
            return relayout;
        }

        private function paintIfChanged(n:UiNode, key:String, v:Object):void
        {
            var prev:Object = n.extra[key];
            if (prev == null || String(prev) != String(v))
            {
                n.extra[key] = v;
                n.dirty |= Dirty.M_PAINT;   // decoration only: never a reflow
            }
        }

        public function wantsPress():Boolean { return false; }

        public function measure(n:UiNode):void
        {
            var s:Style = n.resolved;
            var d:Number = Number(n.extra[D_KEY]);
            if (!(d > 0)) d = 20;
            if (PaintKit.autoW(s))
            {
                PaintKit.setPointSize(n, LayoutConstants.AXIS_WIDTH, d);
            }
            if (PaintKit.autoH(s))
            {
                PaintKit.setPointSize(n, LayoutConstants.AXIS_HEIGHT, d);
            }
        }

        public function arrange(n:UiNode):void
        {
            // Self-drawn inside the solved rect; nothing to place.
        }

        public function paint(n:UiNode):void
        {
            var s:Style = n.resolved;
            PaintKit.paintBox(n, s, PaintKit.w1(n), PaintKit.h1(n));
            if (n.shapeA == null) return;

            var w:Number = PaintKit.w1(n);
            var h:Number = PaintKit.h1(n);
            var th:Number = Number(n.extra[TH_KEY]);
            if (!(th > 0)) th = 2;
            // `rOut` is the OUTSIDE edge of the band, so the ring exactly fills the
            // node's box; `th` is the band's radial thickness.
            var rOut:Number = Math.min(w, h) / 2;
            var rIn:Number = rOut - th;
            if (!(rIn > 0) || !(rOut > 0)) return;
            var cx:Number = w / 2;
            var cy:Number = h / 2;

            var spinning:Boolean = Boolean(n.extra[SPIN_KEY]);
            var ph:Number = spinning
                ? Number(n.app.enterFrameTicks % 50) / 50.0
                : Number(n.extra[PH_KEY]);

            var g:Object = n.shapeA.graphics;
            g.beginFill(TRACK, 1.0);
            band(g, cx, cy, rOut, rIn, 0, TAU);
            g.endFill();

            // 12 o'clock, clockwise.
            var a0:Number = ph * TAU - QUARTER;
            g.beginFill(toneOf(String(n.extra[TONE_KEY])), 1.0);
            band(g, cx, cy, rOut, rIn, a0, a0 + ARC_FRAC * TAU);
            g.endFill();

            if (spinning) n.app.markPaint(n);
        }

        // A closed band between two radii, as a filled polygon: the outer edge
        // forward, then the inner edge back. `endFill` closes it implicitly, but the
        // closing `lineTo` is written out so the shape does not depend on the
        // renderer's implicit-close behaviour for a fill.
        private function band(g:Object, cx:Number, cy:Number, rOut:Number, rIn:Number,
            a0:Number, a1:Number):void
        {
            g.moveTo(cx + Math.cos(a0) * rOut, cy + Math.sin(a0) * rOut);
            for (var i:int = 1; i <= SEGMENTS; i++)
            {
                var a:Number = a0 + (a1 - a0) * (i / SEGMENTS);
                g.lineTo(cx + Math.cos(a) * rOut, cy + Math.sin(a) * rOut);
            }
            for (var j:int = SEGMENTS; j >= 0; j--)
            {
                var b:Number = a0 + (a1 - a0) * (j / SEGMENTS);
                g.lineTo(cx + Math.cos(b) * rIn, cy + Math.sin(b) * rIn);
            }
            g.lineTo(cx + Math.cos(a0) * rOut, cy + Math.sin(a0) * rOut);
        }

        private function toneOf(tone:String):uint
        {
            if (tone == "neutral") return 0x64748B;
            if (tone == "danger") return 0xDC2626;
            return 0x2563EB;
        }

        public function click(n:UiNode):Boolean { return false; }
    }
}

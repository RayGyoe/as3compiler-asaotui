// asaot.ui.kind.ImageWidget -- the Bitmap behind ImageNode.
//
// THE BITMAP IS CREATED LAZILY, in `payload`, the first time a BitmapData shows up.
// `build` cannot do it: at structure time the description may carry no pixels at
// all (a node built before its data arrives), and a `new Bitmap(null)` would leave
// a display object whose width/height are zero for the rest of the run.
//
// FITTING happens in `arrange`, never in `paint`: `Bitmap` scaling is a display
// object property, and paint is supposed to be a drawing pass. `arrange` runs after
// the engine solved the rect, so it is the first moment the destination size is
// known.
//
// Src size is read from `bitmapData.width/height` in SOURCE pixels. `bmp.width`
// would be the SCALED size after we set it, so reading it back would compound the
// scale every frame -- that is the one trap here.
package asaot.ui.kind
{
    import asaot.ui.ImageNode;
    import asaot.ui.Node;
    import asaot.ui.PaintKit;
    import asaot.ui.UiNode;
    import asaot.ui.Widget;
    import asaot.ui.style.Style;

    import asaot.ui.LayoutConstants;

    import flash.display.Bitmap;
    import flash.display.BitmapData;
    import flash.display.Shape;

    public class ImageWidget implements Widget
    {
        private static const BMP_KEY:String = "bmp";
        private static const MODE_KEY:String = "mode";
        private static const SMOOTH_KEY:String = "smooth";

        private static const PLACEHOLDER:Number = 64;

        public function build(n:UiNode):void
        {
            n.shapeA = new Shape();       // background / placeholder frame
            n.backing.addChild(n.shapeA);
            // The Bitmap itself is added later, on top of shapeA (see payload).
        }

        public function payload(n:UiNode, desc:Node):Boolean
        {
            var im:ImageNode = ImageNode(desc);
            var relayout:Boolean = false;
            var b:Bitmap = bitmapOf(n);
            var bd:BitmapData = im.bitmapData;
            if (bd != null && b == null)
            {
                b = new Bitmap(bd);
                n.extra[BMP_KEY] = b;
                n.backing.addChild(b);   // above shapeA: the pixels sit on the frame
                relayout = true;         // the intrinsic size is the bitmap's now
            }
            else if (b != null && b.bitmapData != bd)
            {
                b.bitmapData = bd;
                relayout = true;
            }
            if (b != null && b.smoothing != im.smooth) b.smoothing = im.smooth;

            var mode:String = im.scaleMode == null ? "fit" : im.scaleMode;
            var prevMode:Object = n.extra[MODE_KEY];
            if (prevMode == null || String(prevMode) != mode)
            {
                n.extra[MODE_KEY] = mode;
                // A scale-mode change is a PLACEMENT change: `arrange` is the only
                // reader and arrange does not run on a paint bit, so this has to go
                // through the relayout path even though the intrinsic size is unchanged.
                relayout = true;
            }
            return relayout;
        }

        private function bitmapOf(n:UiNode):Bitmap
        {
            var o:Object = n.extra[BMP_KEY];
            // NOT `o == null ? null : Bitmap(o)`. That exact shape -- a null LITERAL in
            // the THEN branch of a conditional -- evaluates to null even when the
            // condition is false, on every runtime we generate, for every object-typed
            // result (compiler-gaps.md G16; measured on both arms by
            // probes/g16-ternary-null). It is what made this widget build a NEW Bitmap
            // on every reconcile and never fit it: `bitmapOf` returned null, so the
            // create branch ran again and `arrange` bailed out. The if/return form is
            // the shape that works.
            if (o == null) return null;
            return Bitmap(o);
        }

        public function wantsPress():Boolean { return false; }

        public function measure(n:UiNode):void
        {
            var s:Style = n.resolved;
            var b:Bitmap = bitmapOf(n);
            var bw:Number = b != null && b.bitmapData != null ? b.bitmapData.width : PLACEHOLDER;
            var bh:Number = b != null && b.bitmapData != null ? b.bitmapData.height : PLACEHOLDER;
            if (bw <= 0) bw = PLACEHOLDER;
            if (bh <= 0) bh = PLACEHOLDER;
            if (PaintKit.autoW(s)) PaintKit.setPointSize(n, LayoutConstants.AXIS_WIDTH, bw);
            if (PaintKit.autoH(s)) PaintKit.setPointSize(n, LayoutConstants.AXIS_HEIGHT, bh);
        }

        public function arrange(n:UiNode):void
        {
            var b:Bitmap = bitmapOf(n);
            if (b == null || b.bitmapData == null) return;
            var sw:Number = b.bitmapData.width;
            var sh:Number = b.bitmapData.height;
            if (sw <= 0 || sh <= 0) return;
            var w:Number = PaintKit.contentW(n);
            var h:Number = PaintKit.contentH(n);
            if (w <= 0 || h <= 0) return;

            var mode:String = String(n.extra[MODE_KEY]);
            var dw:Number = sw;
            var dh:Number = sh;
            if (mode == "stretch")
            {
                dw = w;
                dh = h;
            }
            else if (mode != "none")
            {
                // "fit": contain, preserving aspect. Never upscales past the box on
                // either axis, so one factor for both is the whole algorithm.
                var k:Number = Math.min(w / sw, h / sh);
                if (!(k > 0)) k = 1;
                dw = sw * k;
                dh = sh * k;
            }
            b.width = dw;
            b.height = dh;
            b.x = (w - dw) / 2;
            b.y = (h - dh) / 2;
        }

        public function paint(n:UiNode):void
        {
            var s:Style = n.resolved;
            PaintKit.paintBox(n, s, PaintKit.w1(n), PaintKit.h1(n));
        }

        public function click(n:UiNode):Boolean { return false; }
    }
}

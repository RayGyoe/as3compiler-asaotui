// asaot.ui.kind.ImageWidget -- the Bitmap (or the Loader that produces one) behind
// ImageNode.
//
// TWO PATHS, ONE DISPLAY OBJECT
// -----------------------------
// The widget always ends up scaling a `Bitmap` in `arrange`; the difference is who
// owns it:
//
//   bitmapData -> the widget creates the Bitmap and adds it to the backing;
//   src        -> a `Loader` is added to the backing and its COMPLETE content (a
//                 Bitmap the Loader already parented) is adopted as the same
//                 BITMAP_KEY. Nothing is re-parented, so the pixels stay where the
//                 Loader put them and `arrange` has ONE thing to fit.
//
// THE BITMAP IS CREATED LAZILY, in `payload`, the first time pixels exist. `build`
// cannot do it: at structure time the description may carry no pixels at all (a
// node built before its data arrives), and a `new Bitmap(null)` would leave a
// display object whose width/height are zero for the rest of the run. The same is
// true of the Loader: it is created when a src first appears, never in `build`.
//
// FITTING happens in `arrange`, never in `paint`: `Bitmap` scaling is a display
// object property, and paint is supposed to be a drawing pass. `arrange` runs after
// the engine solved the rect, so it is the first moment the destination size is
// known.
//
// Src size is read from `bitmapData.width/height` in SOURCE pixels. `bmp.width`
// would be the SCALED size after we set it, so reading it back would compound the
// scale every frame -- that is the one trap here.
//
// ASYNC SAFETY
// ------------
// A load can finish after the node is gone (the IO job holds its own reference, so
// the Loader survives) or after the author changed `src` (the old Loader is still
// in flight when the new one starts). Both callbacks therefore take the Loader they
// were created for and compare it with the node's CURRENT one: a stale or late
// completion is dropped, never applied to a dead or re-pointed node.
//
// A failed load is not silent: `n.loadError` carries the message (which includes
// AIR's error number) and `onError(message)` runs. The widget does not invent error
// chrome -- the author decides what an unreachable picture looks like.
package asaot.ui.kind
{
    import asaot.ui.Dirty;
    import asaot.ui.ImageNode;
    import asaot.ui.Node;
    import asaot.ui.PaintKit;
    import asaot.ui.UiNode;
    import asaot.ui.Widget;
    import asaot.ui.style.Style;

    import asaot.ui.LayoutConstants;

    import flash.display.Bitmap;
    import flash.display.BitmapData;
    import flash.display.DisplayObject;
    import flash.display.Loader;
    import flash.display.LoaderInfo;
    import flash.display.Shape;
    import flash.events.Event;
    import flash.events.IOErrorEvent;
    import flash.geom.Rectangle;
    import flash.net.URLRequest;

    public class ImageWidget implements Widget
    {
        private static const BMP_KEY:String = "bmp";       // the Bitmap being fitted
        private static const OWN_KEY:String = "own";       // we created it (vs the Loader)
        private static const LDR_KEY:String = "ldr";       // the Loader, when src is set
        private static const LI_KEY:String = "li";         // its LoaderInfo
        private static const SRC_KEY:String = "src";       // the src currently loaded
        private static const ERR_KEY:String = "err";       // last load error text
        private static const ONC_KEY:String = "onc";       // the COMPLETE closure
        private static const ONE_KEY:String = "one";       // the IO_ERROR closure
        private static const MODE_KEY:String = "mode";
        private static const SMOOTH_KEY:String = "smooth";

        private static const PLACEHOLDER:Number = 64;

        public function build(n:UiNode):void
        {
            n.shapeA = new Shape();       // background / placeholder frame
            n.backing.addChild(n.shapeA);
            // The Bitmap (or the Loader that will hold one) is added later, on top of
            // shapeA -- see payload.
        }

        public function payload(n:UiNode, desc:Node):Boolean
        {
            var im:ImageNode = ImageNode(desc);
            var relayout:Boolean = false;

            if (im.bitmapData != null)
            {
                // Pixels handed over by the caller win over any URL: whoever passes a
                // BitmapData is not asking for a fetch.
                if (loaderOf(n) != null) { disposeLoader(n); relayout = true; }
                var b:Bitmap = bitmapOf(n);
                if (b == null || n.extra[OWN_KEY] == null)
                {
                    b = new Bitmap(im.bitmapData);
                    n.extra[BMP_KEY] = b;
                    n.extra[OWN_KEY] = b;
                    n.backing.addChild(b);   // above shapeA: the pixels sit on the frame
                    relayout = true;         // the intrinsic size is the bitmap's now
                }
                else if (b.bitmapData != im.bitmapData)
                {
                    b.bitmapData = im.bitmapData;
                    relayout = true;
                }
                if (b.smoothing != im.smooth) b.smoothing = im.smooth;
            }
            else
            {
                var prev:Object = n.extra[SRC_KEY];
                var prevSrc:String = prev == null ? null : String(prev);
                if (im.src == null)
                {
                    // An image that LOSES its source must lose its pixels: keeping the
                    // last picture would show a stale face under a new name.
                    if (loaderOf(n) != null || n.extra[OWN_KEY] != null) { disposeLoader(n); relayout = true; }
                }
                else if (prevSrc == null || prevSrc != im.src)
                {
                    startLoad(n, im.src);
                    relayout = true;
                }
            }

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

        // ---- the Loader lifecycle ----------------------------------------

        private function startLoad(n:UiNode, src:String):void
        {
            disposeLoader(n);
            var ldr:Loader = new Loader();
            var li:LoaderInfo = ldr.contentLoaderInfo;
            var self:UiNode = n;
            // The closure carries ITS OWN Loader: a late COMPLETE from a superseded
            // load must not be applied to the node's current one.
            var onc:Function = function (e:Event):void { loaded(self, ldr); };
            var one:Function = function (e:IOErrorEvent):void { failed(self, ldr, e.text); };
            n.extra[LDR_KEY] = ldr;
            n.extra[LI_KEY] = li;
            n.extra[SRC_KEY] = src;
            n.extra[ERR_KEY] = null;
            n.extra[ONC_KEY] = onc;
            n.extra[ONE_KEY] = one;
            n.backing.addChild(ldr);      // above shapeA
            n.listen(li, Event.COMPLETE, onc);
            n.listen(li, IOErrorEvent.IO_ERROR, one);
            ldr.load(new URLRequest(src));
        }

        // Unhook everything the previous load owns. The listeners are removed from the
        // LoaderInfo itself (not just at teardown) because a replaced load can still
        // complete: leaving them would keep an old closure alive per src change and
        // would run it against a node that has moved on.
        private function disposeLoader(n:UiNode):void
        {
            var ldr:Loader = loaderOf(n);
            var li:LoaderInfo = n.extra[LI_KEY] as LoaderInfo;
            if (li != null && n.extra[ONC_KEY] != null)
            {
                li.removeEventListener(Event.COMPLETE, n.extra[ONC_KEY] as Function);
                li.removeEventListener(IOErrorEvent.IO_ERROR, n.extra[ONE_KEY] as Function);
            }
            if (ldr != null)
            {
                if (ldr.parent != null) ldr.parent.removeChild(ldr);
                // unload() detaches the content; an in-flight job keeps its own
                // reference and will dispatch into a Loader nobody listens to.
                ldr.unload();
            }
            n.extra[LDR_KEY] = null;
            n.extra[LI_KEY] = null;
            n.extra[ONC_KEY] = null;
            n.extra[ONE_KEY] = null;
            n.extra[SRC_KEY] = null;
            n.extra[ERR_KEY] = null;
            n.extra[BMP_KEY] = null;
            n.extra[OWN_KEY] = null;
        }

        private function loaded(n:UiNode, ldr:Loader):void
        {
            // Torn down, or superseded by a newer src: drop it. (`app` is the
            // library's own "dead" marker.)
            if (n.app == null || loaderOf(n) != ldr) return;
            var c:DisplayObject = ldr.content;
            if (!(c is Bitmap))
            {
                // A Loader can hold an SWF. Honouring that would mean running its own
                // frames and scripts, which this widget cannot do -- say so instead of
                // painting an empty box.
                failed(n, ldr, "image src loaded something that is not a Bitmap");
                return;
            }
            var b:Bitmap = Bitmap(c);
            n.extra[BMP_KEY] = b;
            n.extra[ERR_KEY] = null;
            n.loadError = null;
            var d:Node = n.desc;
            if (d is ImageNode && b.smoothing != ImageNode(d).smooth) b.smoothing = ImageNode(d).smooth;
            // The intrinsic size just became knowable: an auto-sized image has to
            // re-measure on the next frame or it keeps the 64x64 placeholder box.
            n.markLayoutDirty();
            n.dirty = n.dirty | Dirty.M_PAINT;
            n.app.markPaint(n);
            if (d is ImageNode && ImageNode(d).onLoad != null) ImageNode(d).onLoad();
        }

        private function failed(n:UiNode, ldr:Loader, msg:String):void
        {
            if (n.app == null || loaderOf(n) != ldr) return;
            n.extra[ERR_KEY] = msg;
            n.loadError = msg;
            n.dirty = n.dirty | Dirty.M_PAINT;
            n.app.markPaint(n);
            var d:Node = n.desc;
            if (d is ImageNode && ImageNode(d).onError != null) ImageNode(d).onError(msg);
        }

        private function loaderOf(n:UiNode):Loader
        {
            var o:Object = n.extra[LDR_KEY];
            return o == null ? null : Loader(o);
        }

        private function bitmapOf(n:UiNode):Bitmap
        {
            var o:Object = n.extra[BMP_KEY];
            // `o == null ? null : Bitmap(o)` -- a null LITERAL in the THEN branch of
            // a conditional -- used to evaluate to null even when the condition was
            // false (compiler-gaps.md G16). That made this widget build a NEW Bitmap
            // on every reconcile and never fit it: `bitmapOf` returned null, so the
            // create branch ran again and `arrange` bailed out. G16 is FIXED (compiler
            // stage 266) and probes/g16-ternary-null keeps the AOT deviation set empty
            // -- that empty set is the tripwire, so this is the ordinary shape again.
            return o == null ? null : Bitmap(o);
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
                // One factor for both axes, then the BOX decides which of the two modes
                // this is: min() leaves margins ("fit"), max() overflows ("cover").
                var k:Number = mode == "cover" ? Math.max(w / sw, h / sh) : Math.min(w / sw, h / sh);
                if (!(k > 0)) k = 1;
                dw = sw * k;
                dh = sh * k;
            }
            b.width = dw;
            b.height = dh;
            if (mode == "cover")
            {
                // CLIP, don't just let it hang out: a scrollRect of the content box's
                // SIZE, offset to the CENTRE of the scaled bitmap, so the overflow is
                // cut on all four sides. The runtime anchors the window on the object's
                // own box (local 0,0) and slides the CONTENT by -x/-y, so the visible
                // part ends up at the object's origin -- which is why x/y are 0 here
                // instead of the -dx/2 centring the other modes use.
                //
                // THE RECT IS IN THE BITMAP'S OWN UNSCALED SPACE, not the box's: the
                // renderer clips through the object's matrix, and setting `b.width`
                // re-expresses the object as a scale of its SOURCE pixels. A 16x16
                // bitmap stretched to 48x48 has 16 local units across, so a 24-unit
                // window would be 72 device pixels wide -- which is exactly what the
                // first version did, and the picture vanished (measured in
                // probes/widgets/imaging: 3 cover pixels read #ffffff). Divide by the
                // uniform factor k and the local rect is the box in source units.
                var k2:Number = dw / sw;
                if (!(k2 > 0)) k2 = 1;
                b.scrollRect = new Rectangle(((dw - w) / 2) / k2, ((dh - h) / 2) / k2, w / k2, h / k2);
                b.x = 0;
                b.y = 0;
                return;
            }
            // Leaving "cover" must drop the window: a scrollRect left behind would clip
            // the next mode to a box it never asked for.
            if (b.scrollRect != null) b.scrollRect = null;
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
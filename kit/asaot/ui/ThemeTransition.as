// asaot.ui.ThemeTransition -- the opt-in animated half of a theme swap (A1).
//
// THE PROBLEM IT SOLVES. `Theme.setTheme` is an instant repaint: the whole tree
// jumps from one palette to the next in a single frame. That is correct (and stays
// the default), but a skin change is also a MOMENT the user should see -- Flutter's
// theme_toggle_animation does a circular reveal / sweep / fade. This class is that
// moment, built from the engine's own display list, with no shader and no second
// render pipeline.
//
// HOW (snapshot + per-frame composite, the only honest way without a shader):
//   * UiApp captures the stage BEFORE the swap (the OLD appearance) and AFTER the
//     swap has been reflowed (the NEW appearance), as two BitmapData at DEVICE
//     resolution (a logical-size snapshot would be upscaled on a HiDPI backing and
//     blur). The composite is displayed scaled back to logical so it lands 1:1.
//   * `fade`  : the OLD bitmap lies over the live NEW tree, alpha 1 -> 0.
//   * `circle`: a composite bitmap, rebuilt each frame: every pixel takes the NEW
//     snapshot inside a growing disc and the OLD outside, with a ~1.5px anti-
//     aliased blend at the edge.
//   * `sweep` : the same composite, the boundary is a vertical line moving left ->
//     right.
//   * At t = 1 the layer is removed and the live NEW tree is all that remains.
//
// WHY A PIXEL COMPOSITE AND NOT A DISPLAY-LIST MASK. Masking a Bitmap (or a
// container holding one) with a Shape double-images the content in this runtime --
// a light ghost offset from the dark reveal, read as blur + jitter at the moving
// edge. It happens on screen AND in BitmapData.draw's offscreen raster, with both
// the vector clipPath and the cacheAsBitmap pixel path; masking the kit's VECTOR
// containers is fine, so the defect is specific to bitmap content. copyPixels'
// alpha-mask argument is also unimplemented. So the reveal is computed directly
// from the two snapshots' pixel vectors (getVector/setVector, both implemented) and
// shown as ONE unmasked Bitmap -- no mask anywhere, no ghost. The runtime
// mask-on-bitmap defect is logged upstream in compiler-gaps.md.
//
// COST: the two snapshot vectors are read ONCE at begin; each frame is a tight
// per-pixel select (only the thin edge band pays for a sqrt + blend), then one
// setVector. No per-pixel API calls, no allocation in the loop.
//
// WHY IT IS SAFE TO FREEZE CONTENT FOR ms: the bitmaps are snapshots, so ticking
// content (a live board) holds still during the reveal -- exactly what a snapshot
// transition does everywhere. The retained tree keeps rendering underneath; nothing
// in the layout or the model is touched.
//
// REDUCED MOTION: UiApp never calls begin() when Motion.reducedMotion is set (or
// ms <= 0); the swap is then the plain instant setTheme. This class has no clock of
// its own beyond the getTimer() start it is handed, so it cannot animate behind the
// accessibility switch's back.
package asaot.ui
{
    import asaot.ui.anim.Ease;

    import flash.display.Bitmap;
    import flash.display.BitmapData;
    import flash.display.DisplayObjectContainer;
    import flash.display.Sprite;
    import flash.geom.Rectangle;
    import flash.utils.getTimer;

    public final class ThemeTransition
    {
        private var _host:DisplayObjectContainer;
        private var _layer:Sprite;
        // fade: the old snapshot, alpha-animated over the live tree.
        private var _fade:Bitmap;
        // circle/sweep: one composite bitmap, rebuilt each frame from old + new.
        private var _comp:Bitmap;
        private var _oldBd:BitmapData;
        private var _newBd:BitmapData;
        private var _compBd:BitmapData;
        private var _oldVec:Vector.<uint>;
        private var _newVec:Vector.<uint>;
        private var _compVec:Vector.<uint>;
        private var _fullRect:Rectangle;
        private var _dw:int;
        private var _dh:int;
        private var _scale:Number;
        private var _type:String;
        private var _start:Number;
        private var _ms:Number;
        private var _ox:Number;
        private var _oy:Number;
        private var _maxR:Number;
        private var _w:Number;
        private var _h:Number;
        private var _active:Boolean;
        private var _progress:Number;

        public function ThemeTransition():void
        {
            this._active = false;
            this._progress = 0;
        }

        public function get active():Boolean { return this._active; }
        // Eased 0..1 while running; 1 once landed. A probe reads this to prove the
        // reveal is PROGRESSIVE (0 at begin, strictly between mid, gone at end)
        // without depending on pixel-perfect frame timing.
        public function get progress():Number { return this._progress; }

        public function begin(host:DisplayObjectContainer, oldBd:BitmapData, newBd:BitmapData,
                              type:String, ms:Number, ox:Number, oy:Number,
                              w:Number, h:Number):void
        {
            cancel();
            this._host = host;
            this._type = type;
            this._ms = ms;
            this._ox = ox;
            this._oy = oy;
            this._w = w;
            this._h = h;
            this._scale = oldBd.width / w;
            // Reach the farthest corner so the disc always covers the whole window.
            var dx:Number = Math.max(ox, w - ox);
            var dy:Number = Math.max(oy, h - oy);
            this._maxR = Math.sqrt(dx * dx + dy * dy);
            this._start = getTimer();
            this._progress = 0;

            this._layer = new Sprite();
            if (type == "fade")
            {
                this._fade = new Bitmap(oldBd);
                this._fade.scaleX = w / oldBd.width;
                this._fade.scaleY = h / oldBd.height;
                this._layer.addChild(this._fade);
                newBd.dispose();
            }
            else
            {
                this._oldBd = oldBd;
                this._newBd = newBd;
                this._dw = oldBd.width;
                this._dh = oldBd.height;
                this._fullRect = new Rectangle(0, 0, this._dw, this._dh);
                // Read the two static snapshots once; the per-frame loop only selects
                // between them, so no pixel API call or allocation happens per frame.
                this._oldVec = oldBd.getVector(this._fullRect);
                this._newVec = newBd.getVector(this._fullRect);
                this._compVec = new Vector.<uint>(this._dw * this._dh);
                this._compBd = new BitmapData(this._dw, this._dh, true, 0x00000000);
                this._comp = new Bitmap(this._compBd);
                this._comp.scaleX = w / this._dw;
                this._comp.scaleY = h / this._dh;
                this._layer.addChild(this._comp);
            }
            host.addChild(this._layer);
            this._active = true;
            apply(0);
            top();
        }

        // Drive one frame. Returns true while still running (UiApp keeps asking for
        // frames). The layer is re-asserted on top because UiApp's own reconcile
        // lifts the overlay/HUD to the top index every frame.
        public function tick(now:Number):Boolean
        {
            if (!this._active) return false;
            var t:Number = (now - this._start) / this._ms;
            if (t >= 1)
            {
                finish();
                return false;
            }
            var p:Number = Ease.apply("outCubic", t);
            this._progress = p;
            apply(p);
            top();
            return true;
        }

        private function apply(p:Number):void
        {
            if (this._type == "fade")
            {
                this._fade.alpha = 1 - p;
                return;
            }
            var ov:Vector.<uint> = this._oldVec;
            var nv:Vector.<uint> = this._newVec;
            var cv:Vector.<uint> = this._compVec;
            var dw:int = this._dw;
            var dh:int = this._dh;
            // Edge half-width in device pixels: a ~1.5px logical band keeps the
            // moving boundary smooth instead of stair-stepping (which reads as jitter).
            var aa:Number = 1.5 * this._scale;
            var i:int = 0;
            var x:int;
            var y:int;
            if (this._type == "circle")
            {
                var cx:Number = this._ox * this._scale;
                var cy:Number = this._oy * this._scale;
                var r:Number = this._maxR * p * this._scale;
                // The nominal radius is the OUTER edge of the AA band: coverage is
                // (r - dist)/aa, so r == 0 reveals nothing (the begin frame must be
                // wholly old) and the band softens inward, never past the centre.
                var rOut:Number = r;
                var rIn:Number = r - aa;
                if (rIn < 0) rIn = 0;
                var rOut2:Number = rOut * rOut;
                var rIn2:Number = rIn * rIn;
                for (y = 0; y < dh; y++)
                {
                    var ddy:Number = y - cy;
                    var ddy2:Number = ddy * ddy;
                    for (x = 0; x < dw; x++)
                    {
                        var ddx:Number = x - cx;
                        var d2:Number = ddx * ddx + ddy2;
                        // Fast paths cover everything but the thin edge band; only the
                        // band pays for a sqrt and a channel blend.
                        if (d2 >= rOut2) cv[i] = ov[i];
                        else if (d2 <= rIn2) cv[i] = nv[i];
                        else cv[i] = blend(ov[i], nv[i], (r - Math.sqrt(d2)) / aa);
                        i++;
                    }
                }
            }
            else
            {
                var lim:Number = this._w * p * this._scale;
                var limOut:Number = lim;
                var limIn:Number = lim - aa;
                if (limIn < 0) limIn = 0;
                for (y = 0; y < dh; y++)
                {
                    for (x = 0; x < dw; x++)
                    {
                        if (x >= limOut) cv[i] = ov[i];
                        else if (x <= limIn) cv[i] = nv[i];
                        else cv[i] = blend(ov[i], nv[i], (lim - x) / aa);
                        i++;
                    }
                }
            }
            this._compBd.setVector(this._fullRect, cv);
        }

        // Straight-ARGB lerp of two opaque pixels (both snapshots are opaque, so the
        // result alpha stays 255). t is clamped coverage 0..1.
        private function blend(o:uint, n:uint, t:Number):uint
        {
            if (t <= 0) return o;
            if (t >= 1) return n;
            var ia:Number = 1 - t;
            var a:uint = uint(((o >> 24) & 255) * ia + ((n >> 24) & 255) * t);
            var r:uint = uint(((o >> 16) & 255) * ia + ((n >> 16) & 255) * t);
            var g:uint = uint(((o >> 8) & 255) * ia + ((n >> 8) & 255) * t);
            var b:uint = uint((o & 255) * ia + (n & 255) * t);
            return (a << 24) | (r << 16) | (g << 8) | b;
        }

        private function top():void
        {
            if (this._host != null && this._layer != null && this._layer.parent == this._host)
            {
                this._host.setChildIndex(this._layer, this._host.numChildren - 1);
            }
        }

        private function finish():void
        {
            if (this._layer != null && this._layer.parent != null)
            {
                this._layer.parent.removeChild(this._layer);
            }
            if (this._oldBd != null) this._oldBd.dispose();
            if (this._newBd != null) this._newBd.dispose();
            if (this._compBd != null) this._compBd.dispose();
            this._layer = null;
            this._fade = null;
            this._comp = null;
            this._oldBd = null;
            this._newBd = null;
            this._compBd = null;
            this._oldVec = null;
            this._newVec = null;
            this._compVec = null;
            this._host = null;
            this._active = false;
            this._progress = 1;
        }

        public function cancel():void
        {
            if (this._active || this._layer != null) finish();
        }
    }
}
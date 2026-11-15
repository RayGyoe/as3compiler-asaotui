// asaot.ui.ThemeTransition -- the opt-in animated half of a theme swap (A1).
//
// THE PROBLEM IT SOLVES. `Theme.setTheme` is an instant repaint: the whole tree
// jumps from one palette to the next in a single frame. That is correct (and stays
// the default), but a skin change is also a MOMENT the user should see -- Flutter's
// theme_toggle_animation does a circular reveal / sweep / fade. This class is that
// moment, built from the engine's own display list, with no shader and no second
// render pipeline.
//
// HOW (snapshot + display-list mask):
//   * UiApp captures the stage BEFORE the swap (the OLD appearance) and AFTER the
//     swap has been reflowed (the NEW appearance), as two BitmapData at DEVICE
//     resolution (a logical-size snapshot would be upscaled on a HiDPI backing and
//     blur). Each is shown as a Bitmap scaled back to logical so it lands 1:1.
//   * `fade`  : the OLD bitmap lies over the live NEW tree, alpha 1 -> 0.
//   * `circle`: OLD underneath, NEW on top masked by a Shape disc growing from the
//     click point; inside the disc the new skin shows, outside the old.
//   * `sweep` : the same pair, the mask is a rectangle widening left -> right.
//   * At t = 1 the layer is removed and the live NEW tree is all that remains.
//
// WHY A MASK IS SAFE NOW. An earlier revision computed the reveal per-pixel from
// getVector/setVector because masking bitmap content was SUSPECTED of double-imaging
// (compiler-gaps.md G50) and copyPixels' alpha mask was unimplemented (G51). Both are
// resolved: G50 was pixel-verified to have NO offset/ghost (the "ghost" was the disc
// edge crossing text, a misread) and closed as a non-gap; G51's alpha mask is now
// implemented. So the reveal uses the idiomatic display-list mask -- the Shape is
// redrawn each frame and the runtime rasterises it (no per-pixel AS3 loop).
//
// COST: each frame clears and redraws ONE Shape (a disc or a rect) and the runtime
// composites the masked bitmap. No per-pixel API calls, no allocation in the loop.
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
    import flash.display.Shape;
    import flash.display.Sprite;
    import flash.utils.getTimer;

    public final class ThemeTransition
    {
        private var _host:DisplayObjectContainer;
        private var _layer:Sprite;
        // fade: the old snapshot, alpha-animated over the live tree.
        private var _fade:Bitmap;
        // circle/sweep: old underneath, new on top masked by the reveal Shape.
        private var _old:Bitmap;
        private var _new:Bitmap;
        private var _mask:Shape;
        private var _oldBd:BitmapData;
        private var _newBd:BitmapData;
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
                this._old = new Bitmap(oldBd);
                this._old.scaleX = w / oldBd.width;
                this._old.scaleY = h / oldBd.height;
                this._new = new Bitmap(newBd);
                this._new.scaleX = w / newBd.width;
                this._new.scaleY = h / newBd.height;
                this._mask = new Shape();
                this._layer.addChild(this._old);
                this._layer.addChild(this._new);
                this._layer.addChild(this._mask);
                // The mask lives in the layer's (logical) coordinate space, so the
                // disc/rect is drawn in logical pixels even though the bitmaps are
                // device-resolution; the runtime rasterises the mask at backing scale.
                this._new.mask = this._mask;
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
            var g:Object = this._mask.graphics;
            g.clear();
            g.beginFill(0xFFFFFF, 1);
            if (this._type == "circle")
            {
                var r:Number = this._maxR * p;
                // r == 0 draws nothing: an empty mask hides the NEW bitmap entirely,
                // so the begin frame is wholly OLD (the probe pins this).
                if (r > 0) g.drawCircle(this._ox, this._oy, r);
            }
            else
            {
                var lim:Number = this._w * p;
                if (lim > 0) g.drawRect(0, 0, lim, this._h);
            }
            g.endFill();
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
            if (this._new != null) this._new.mask = null;
            if (this._layer != null && this._layer.parent != null)
            {
                this._layer.parent.removeChild(this._layer);
            }
            if (this._oldBd != null) this._oldBd.dispose();
            if (this._newBd != null) this._newBd.dispose();
            this._layer = null;
            this._fade = null;
            this._old = null;
            this._new = null;
            this._mask = null;
            this._oldBd = null;
            this._newBd = null;
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
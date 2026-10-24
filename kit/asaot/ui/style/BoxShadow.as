// asaot.ui.style.BoxShadow -- one box-shadow entry (GPUI `BoxShadow`, style.rs:349).
//
// WHY THIS IS A CLASS AND NOT AN OBJECT LITERAL
// ---------------------------------------------
// A shadow is compared (Style.diffFlags) and, on a change, turned into a
// DropShadowFilter. Doing that field-by-field on a raw `{}` at both sites is how
// the two drift apart; a parsed value with `equals` keeps one definition.
//
// WHAT THE BACKEND CAN ACTUALLY DO
// --------------------------------
// AS3's DropShadowFilter is rendered for real by this runtime
// (`as_render_filtered` in src/emit.ts, the DropShadowFilter branch), so a box
// shadow is a DRAW, not a deferred feature. Its four knobs are
// distance/angle (= our offset), color, alpha and blurX/blurY. It has NO spread
// and NO inset, so `spread != 0` and `inset == true` THROW instead of painting a
// different shadow than the author asked for (AGENTS.md 2.5: never a silent
// fallback). Both are GPUI fields, so the error names the exact gap.
//
// `blur` is passed through as DropShadowFilter.blurX/blurY unchanged. Those are
// ALSO what the renderer's filter-bounds expansion uses, so a blur the probe can
// see outside the box is the same number the author wrote -- no unit conversion
// is hidden here.
package asaot.ui.style
{
    public class BoxShadow
    {
        public var offsetX:Number;
        public var offsetY:Number;
        public var blur:Number;      // >= 0; becomes blurX = blurY
        public var color:uint;       // 0xRRGGBB
        public var alpha:Number;     // 0..1
        public var spread:Number;    // must stay 0 (unsupported)
        public var inset:Boolean;    // must stay false (unsupported)

        public function BoxShadow():void
        {
            this.offsetX = 0;
            this.offsetY = 0;
            this.blur = 0;
            this.color = 0x000000;
            this.alpha = 1.0;
            this.spread = 0;
            this.inset = false;
        }

        // Author shapes accepted by one entry:
        //   { x: 0, y: 2, blur: 8, color: 0x000000, alpha: 0.25 }
        //   { offset: [0, 2], blur: 8, ... }        (GPUI's Point form)
        //   { offsetX: 0, offsetY: 2, ... }         (the field names above)
        public static function fromAny(o:Object):BoxShadow
        {
            if (o == null) return null;
            if (o is BoxShadow) return BoxShadow(o);
            if (!(o is Object)) return null;
            var b:BoxShadow = new BoxShadow();
            if (o.offset != null && o.offset is Array)
            {
                var off:Array = o.offset as Array;
                if (off.length > 0) b.offsetX = Number(off[0]);
                if (off.length > 1) b.offsetY = Number(off[1]);
            }
            if (o.x != null) b.offsetX = Number(o.x);
            else if (o.offsetX != null) b.offsetX = Number(o.offsetX);
            if (o.y != null) b.offsetY = Number(o.y);
            else if (o.offsetY != null) b.offsetY = Number(o.offsetY);
            if (o.blur != null) b.blur = Number(o.blur);
            if (o.color != null) b.color = uint(Number(o.color)) & 0xFFFFFF;
            if (o.alpha != null) b.alpha = Number(o.alpha);
            if (o.spread != null) b.spread = Number(o.spread);
            if (o.inset != null) b.inset = Boolean(o.inset);
            // Unknown VALUES are errors, never a quiet reinterpretation.
            if (isNaN(b.offsetX) || isNaN(b.offsetY) || isNaN(b.blur))
            {
                throw new Error("asaot.ui: boxShadow x/y/blur must be numbers");
            }
            if (b.blur < 0)
            {
                throw new Error("asaot.ui: boxShadow blur must be >= 0 (got " + b.blur + ")");
            }
            if (isNaN(b.alpha) || b.alpha < 0 || b.alpha > 1)
            {
                throw new Error("asaot.ui: boxShadow alpha must be 0..1 (got " + b.alpha + ")");
            }
            if (b.spread != 0)
            {
                throw new Error("asaot.ui: boxShadow spread is not supported by this backend (got "
                    + b.spread + "; DropShadowFilter has no spread)");
            }
            if (b.inset)
            {
                throw new Error("asaot.ui: boxShadow inset is not supported by this backend");
            }
            return b;
        }

        // A single value or a list, WITHOUT `Array(v)` (OptionSupport.list's
        // header has the measured reason: `Array([a,b])` is a 1-element array).
        public static function listFromAny(o:Object):Array
        {
            if (o == null) return null;
            var src:Array = (o is Array) ? (o as Array) : null;
            var out:Array = [];
            if (src != null)
            {
                for (var i:int = 0; i < src.length; i++)
                {
                    var one:BoxShadow = fromAny(src[i]);
                    if (one != null) out.push(one);
                }
            }
            else
            {
                var single:BoxShadow = fromAny(o);
                if (single != null) out.push(single);
            }
            return out.length > 0 ? out : null;
        }

        public function equals(o:BoxShadow):Boolean
        {
            if (o == null) return false;
            return this.offsetX == o.offsetX && this.offsetY == o.offsetY
                && this.blur == o.blur && this.color == o.color && this.alpha == o.alpha
                && this.spread == o.spread && this.inset == o.inset;
        }
    }
}
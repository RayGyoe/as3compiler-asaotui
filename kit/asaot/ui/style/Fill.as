// asaot.ui.style.Fill -- a paint fill. Only SOLID fills are implemented (the
// design doc section 2.1 says gradients are deferred); `argb` is 0xAARRGGBB so a
// single Number carries both colour and alpha, matching the doc's
// `background: Fill.solid(0xFFFFFFFF)`.
//
// NO PACKAGE-LEVEL `fill(...)` HELPER: mxmlc requires one externally-visible
// definition per file named after it, and `fill.as` cannot coexist with
// `Fill.as` on a case-insensitive filesystem. Use `Fill.solid(argb)`.
package asaot.ui.style
{
    public class Fill
    {
        public var argb:Number;

        public function Fill(a:Number):void
        {
            // A 6-digit colour (0xRRGGBB, i.e. <= 0xFFFFFF) is treated as OPAQUE,
            // because that is how authors write colours and an alpha of 0 would
            // make every such fill invisible (the demo's blue button came out
            // white before this). For a translucent fill use a value with the
            // alpha byte set (> 0xFFFFFF) or `Fill.fromArgb`.
            var v:Number = a;
            if (v >= 0 && v <= 0xFFFFFF) v = v + 0xFF000000;
            this.argb = v;
        }

        public static function solid(argb:Number):Fill { return new Fill(argb); }

        public static function fromArgb(a:Number, r:Number, g:Number, b:Number):Fill
        {
            // Assign AFTER construction so an explicit alpha of 0 survives the
            // opaque-by-default normalisation above.
            var f:Fill = new Fill(0xFF000000);
            f.argb = Number(((a & 0xFF) << 24) | ((r & 0xFF) << 16) | ((g & 0xFF) << 8) | (b & 0xFF));
            return f;
        }

        // An ARRAY (a gradient stop list) must reach here only through a caller that
        // has ALREADY decided the value is an array -- see StyleRefinement.from.
        // It cannot be detected inside `fromAny(o:Object)`: an Array in an
        // Object-typed parameter is never boxed, so `is Array` on it is
        // constant-folded to FALSE and a following `is <class>` reads the array
        // header as a vtable (0xC0000005). Measured: compiler-gaps.md G14,
        // probes/obj-array-identity/ case 26.
        //
        // A stop list means a GRADIENT, and gradients are deferred (file header), so
        // this returns null. That is exactly what AIR answers for an Array today via
        // its own `fromAny`, so we stay aligned instead of inventing a meaning. The
        // typed parameter is the point: it makes `a.length` safe the day gradients land.
        public static function fromArray(a:Array):Fill
        {
            return null;
        }

        public static function fromAny(o:Object):Fill
        {
            if (o == null) return null;
            // DO NOT ADD `o is Array` HERE. It cannot work, and that was measured
            // rather than assumed: an Array put into an Object-typed parameter is
            // never boxed, our AOT constant-folds `is Array` to FALSE, and the next
            // line (`is Fill`) then reads the array header as a vtable and dies with
            // 0xC0000005. Moving the array check to the FRONT does not help either
            // (same measurement, case 26). An Array has to be recognised AT THE CALL
            // SITE, while the value still lives in a `*` dynamic read -- which is what
            // StyleRefinement.from does. A guard did live here until 2026-10-23; it
            // compiled to `if (false)`, so it was deleted rather than left looking
            // like protection.
            if (o is Number) return solid(Number(o));
            if (o is Fill) return Fill(o);
            return null;
        }

        public function rgb():uint
        {
            return uint(this.argb) & 0xFFFFFF;
        }

        public function alpha():Number
        {
            return Number((uint(this.argb) >>> 24) & 0xFF) / 255.0;
        }
    }
}
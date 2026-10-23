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

        // The typed array entry point. An ARRAY (a gradient stop list) means a
        // GRADIENT, and gradients are deferred (file header), so this returns null --
        // which is exactly what AIR's own answer is for an Array today, so we stay
        // aligned instead of inventing a meaning. The typed parameter is the point:
        // it makes `a.length` safe the day gradients land. `fromAny` delegates here,
        // so both spellings agree.
        public static function fromArray(a:Array):Fill
        {
            return null;
        }

        public static function fromAny(o:Object):Fill
        {
            if (o == null) return null;
            // The array branch is dispatched HERE, so `Fill.fromAny(x)` is total (it
            // accepts every documented shape). This check used to be impossible: an
            // Array put into an Object-typed parameter was not boxed, our AOT
            // constant-folded `is Array` to FALSE, and the next line (`is Fill`) then
            // read the array header as a vtable and died with 0xC0000005 -- measured,
            // not assumed (compiler-gaps.md G14, probes/obj-array-identity/ case 26).
            // A guard that lived here until 2026-10-23 compiled to `if (false)` and was
            // deleted rather than left looking like protection. G14 is FIXED (compiler
            // 阶段二百五十三); `probes/style-fromany/` re-measures this on BOTH runtimes,
            // so the guard is live again instead of being faith.
            if (o is Array) return fromArray(o as Array);
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
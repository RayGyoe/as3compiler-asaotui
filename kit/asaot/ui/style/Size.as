// asaot.ui.style.Size -- a (width, height) pair of `Length`s.
//
// Used for `size` / `minSize` / `maxSize`; the gap pair reuses it as
// (gapX = width, gapY = height). `null` component == unset (refine leaves the
// parent's component alone).
//
// `fromAny` IS TOTAL: it accepts every documented shape (a scalar Length/Number, or
// the [w] / [w, h] array) and dispatches internally. That used to be impossible --
// see the note below -- so callers had to branch on `is Array` and route the array
// form to `fromArray` themselves.
//
// HISTORY (asaotui/compiler-gaps.md G14, "Array in an Object slot"): until
// 2026-10-23 an AS3 Array handed to an `Object`-typed parameter lost its Array
// identity in our AOT -- `o is Array` folded to FALSE and a following
// `o is <userClass>` read the array header as a vtable (0xC0000005). That is why
// this split existed. G14 is FIXED (compiler 阶段二百五十三) and measured fixed on
// both runtimes by `probes/style-fromany/`, so the dispatch moved back in here.
// `fromArray(a:Array)` is kept as the typed entry point (it keeps `a.length`/`a[0]`
// statically typed) and is what `fromAny` delegates to.
package asaot.ui.style
{
    public class Size
    {
        public var width:Length;
        public var height:Length;

        public function Size(w:Length, h:Length):void
        {
            this.width = w; this.height = h;
        }

        public static function of(w:Length, h:Length):Size { return new Size(w, h); }

        // Array form: [w] or [w, h]; elements are Length or Number.
        public static function fromArray(a:Array):Size
        {
            if (a == null) return null;
            var ww:Length = a.length > 0 ? lenOf(a[0]) : null;
            var hh:Length = a.length > 1 ? lenOf(a[1]) : ww;
            return new Size(ww, hh);
        }

        // Scalar form: a bare Length sets both axes (a square); a Number is px.
        // Array form: dispatched here, so this accepts EVERY documented shape.
        public static function fromAny(o:Object):Size
        {
            if (o == null) return null;
            if (o is Array) return fromArray(o as Array);
            var w:Length = lenOf(o);
            if (w != null) return new Size(w, w);
            return null;
        }

        private static function lenOf(o:Object):Length
        {
            if (o == null) return null;
            if (o is Length) return Length(o);
            if (o is Number) return Length.px(Number(o));
            return null;
        }

        public function copyInto(out:Size):void
        {
            out.width = this.width; out.height = this.height;
        }

        public function widthOr(parent:Length):Length { return this.width != null ? this.width : parent; }
        public function heightOr(parent:Length):Length { return this.height != null ? this.height : parent; }
    }
}
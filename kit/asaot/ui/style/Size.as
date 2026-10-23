// asaot.ui.style.Size -- a (width, height) pair of `Length`s.
//
// Used for `size` / `minSize` / `maxSize`; the gap pair reuses it as
// (gapX = width, gapY = height). `null` component == unset (refine leaves the
// parent's component alone).
//
// COMPILER GAP (asaotui/compiler-gaps.md, "Object-parameter array boxing"): an
// AS3 Array passed as an `Object`-typed parameter loses its Array identity in our
// AOT -- `o is Array` becomes false and a subsequent `o is <userClass>` can even
// SIGSEGV. So `fromAny` is only ever called with a SCALAR (Number or Length); the
// array form goes through `fromArray(a:Array)` with an `as Array` cast at the call
// site, which the AOT does preserve.
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
        public static function fromAny(o:Object):Size
        {
            if (o == null) return null;
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
// asaot.ui.style.Edges -- a four-sided edge set (top/right/bottom/left) used by
// `padding`, `borderWidths` and (future) `margin`/`inset`.
//
// `NaN` means "this side is unset" -- that is how a partial refinement says
// "leave the parent's value alone". `refineInto` merges per COMPONENT, which is
// the behaviour GPUI's derive macro produces for an `Edges` field
// (asaotui/gpui-src/crates/refineable/src/refineable.rs: a non-Option struct is
// refined field-by-field).
//
// NO PACKAGE-LEVEL `edges(...)` HELPER: mxmlc requires every externally-visible
// definition to live in a file named after it, and `edges.as` cannot coexist
// with `Edges.as` on a case-insensitive filesystem. `Edges.of(t, r, b, l)` is
// the spelling authors use.
package asaot.ui.style
{
    public class Edges
    {
        public var top:Number;
        public var right:Number;
        public var bottom:Number;
        public var left:Number;

        public function Edges(t:Number, r:Number, b:Number, l:Number):void
        {
            this.top = t; this.right = r; this.bottom = b; this.left = l;
        }

        public static function all(n:Number):Edges { return new Edges(n, n, n, n); }
        public static function hv(h:Number, v:Number):Edges { return new Edges(v, h, v, h); }
        public static function of(t:Number, r:Number, b:Number, l:Number):Edges { return new Edges(t, r, b, l); }

        // Parse the `opts` spellings the design doc allows:
        //   padding: 12                -> all four
        //   padding: [t, r, b, l]      -> per side
        //   padding: [h, v]            -> horizontal / vertical
        // Total: the array form is dispatched here (see Size's header for why this
        // used to be split out, and why it is not any more).
        public static function fromAny(o:Object):Edges
        {
            if (o == null) return null;
            if (o is Array) return fromArray(o as Array);
            if (o is Number) { return all(Number(o)); }
            return null;
        }

        public static function fromArray(a:Array):Edges
        {
            if (a == null) return null;
            if (a.length == 4) return of(Number(a[0]), Number(a[1]), Number(a[2]), Number(a[3]));
            if (a.length == 2) return hv(Number(a[0]), Number(a[1]));
            if (a.length == 1) return all(Number(a[0]));
            return null;
        }

        public function copyInto(out:Edges):void
        {
            out.top = this.top; out.right = this.right;
            out.bottom = this.bottom; out.left = this.left;
        }

        public function equals(o:Edges):Boolean
        {
            return o != null && same(this.top, o.top) && same(this.right, o.right)
                && same(this.bottom, o.bottom) && same(this.left, o.left);
        }

        private static function same(a:Number, b:Number):Boolean
        {
            if (isNaN(a) && isNaN(b)) return true;
            return a == b;
        }
    }
}
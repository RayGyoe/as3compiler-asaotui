// asaot.ui.style.LengthEdges -- a four-sided edge set (top/right/bottom/left)
// whose sides are `Length`s, not Numbers. Used by `margin` and `inset`.
//
// WHY NOT REUSE `Edges`: `Edges` stores a Number per side, because padding and
// border width are always absolute points. `margin` and `inset` are different:
// they accept a percent (relative to the containing block) AND, for margin,
// `auto` -- and auto margin is Yoga's whole centring mechanism
// (`margin: [0, "auto"]`). A Number has nowhere to put that unit, so this class
// mirrors `Edges` but holds a `Length` per side. `null` per side == unset
// (leave the parent's value alone when refining), exactly like `Edges`'s NaN.
//
// ARRAY-BOXING COMPILER GAP (asaotui/compiler-gaps.md): an AS3 Array handed to
// an `Object`-typed parameter loses its Array identity in our AOT, so `fromAny`
// accepts only a SCALAR (a Length, a Number, or the String "auto") and the array
// form goes through `fromArray(a:Array)` with an explicit `as Array` cast at the
// call site -- see Size/Edges for the same split.
//
// NO PACKAGE-LEVEL `lengthEdges(...)` HELPER: mxmlc requires every
// externally-visible definition to live in a file named after it, and a
// lowercase spelling cannot coexist with this file on a case-insensitive
// filesystem. Authors use `LengthEdges.of(t, r, b, l)` / `LengthEdges.all(l)`.
package asaot.ui.style
{
    public class LengthEdges
    {
        public var top:Length;
        public var right:Length;
        public var bottom:Length;
        public var left:Length;

        public function LengthEdges(t:Length, r:Length, b:Length, l:Length):void
        {
            this.top = t; this.right = r; this.bottom = b; this.left = l;
        }

        public static function all(l:Length):LengthEdges { return new LengthEdges(l, l, l, l); }
        public static function of(t:Length, r:Length, b:Length, l:Length):LengthEdges
        {
            return new LengthEdges(t, r, b, l);
        }

        // Scalar form: a bare Length / Number / "auto" sets all four sides.
        // Scalar only; the array form must go through fromArray (see header).
        public static function fromAny(o:Object):LengthEdges
        {
            if (o == null) return null;
            var l:Length = lenOf(o);
            if (l != null) return all(l);
            return null;
        }

        // Array form (mirrors Edges.fromArray):
        //   [t, r, b, l]  -> per side
        //   [h, v]        -> horizontal / vertical
        //   [all]         -> all four
        public static function fromArray(a:Array):LengthEdges
        {
            if (a == null) return null;
            if (a.length == 4) return of(lenOf(a[0]), lenOf(a[1]), lenOf(a[2]), lenOf(a[3]));
            if (a.length == 2)
            {
                var h:Length = lenOf(a[0]);
                var v:Length = lenOf(a[1]);
                return new LengthEdges(v, h, v, h);
            }
            if (a.length == 1) return all(lenOf(a[0]));
            return null;
        }

        public function copyInto(out:LengthEdges):void
        {
            out.top = this.top; out.right = this.right;
            out.bottom = this.bottom; out.left = this.left;
        }

        public function equals(o:LengthEdges):Boolean
        {
            return o != null && lenSame(this.top, o.top) && lenSame(this.right, o.right)
                && lenSame(this.bottom, o.bottom) && lenSame(this.left, o.left);
        }

        // Built-in checks first (Number / String) then the user class, matching
        // the ordering Fill.fromAny/Style use for the boxed-array gap.
        private static function lenOf(o:Object):Length
        {
            if (o == null) return null;
            if (o is Length) return Length(o);
            if (o is Number) return Length.px(Number(o));
            if (o is String) return (String(o) == "auto") ? Length.AUTO : null;
            return null;
        }

        private static function lenSame(a:Length, b:Length):Boolean
        {
            if (a == null && b == null) return true;
            if (a == null || b == null) return false;
            return a.unit == b.unit && a.value == b.value;
        }
    }
}

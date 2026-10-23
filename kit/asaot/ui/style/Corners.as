// asaot.ui.style.Corners -- four corner radii (top-left / top-right /
// bottom-right / bottom-left). `NaN` == unset, exactly like `Edges`.
//
// NO PACKAGE-LEVEL `corners(...)` HELPER: mxmlc requires one externally-visible
// definition per file named after it, and `corners.as` cannot coexist with
// `Corners.as` on a case-insensitive filesystem. Use `Corners.of(tl, tr, br, bl)`.
package asaot.ui.style
{
    public class Corners
    {
        public var topLeft:Number;
        public var topRight:Number;
        public var bottomRight:Number;
        public var bottomLeft:Number;

        public function Corners(tl:Number, tr:Number, br:Number, bl:Number):void
        {
            this.topLeft = tl; this.topRight = tr;
            this.bottomRight = br; this.bottomLeft = bl;
        }

        public static function all(n:Number):Corners { return new Corners(n, n, n, n); }
        public static function of(tl:Number, tr:Number, br:Number, bl:Number):Corners
        {
            return new Corners(tl, tr, br, bl);
        }

        public static function fromAny(o:Object):Corners
        {
            if (o == null) return null;
            if (o is Number) return all(Number(o));
            return null;
        }

        public static function fromArray(a:Array):Corners
        {
            if (a == null) return null;
            if (a.length == 4) return of(Number(a[0]), Number(a[1]), Number(a[2]), Number(a[3]));
            if (a.length == 2) return of(Number(a[0]), Number(a[0]), Number(a[1]), Number(a[1]));
            if (a.length == 1) return all(Number(a[0]));
            return null;
        }

        public function copyInto(out:Corners):void
        {
            out.topLeft = this.topLeft; out.topRight = this.topRight;
            out.bottomRight = this.bottomRight; out.bottomLeft = this.bottomLeft;
        }
    }
}
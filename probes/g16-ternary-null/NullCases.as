// NullCases.as -- the case table for the G16 probe (compiler-gaps.md G16).
//
// QUESTION: in AS3, `cond ? null : objValue` must evaluate to `objValue` when the
// condition is false. Our AOT returns NULL instead -- and only in that exact shape
// (the null LITERAL in the THEN position). The table below is the minimisation:
// every neighbouring shape is here too, so the difference between "our AOT" and
// "AIR 51.4.1" points at one operator position and nothing else.
//
// EVERY case builds a FRESH BitmapData/Bitmap: a shared one would make the probe
// pass on identity rather than on the value, and would hide a case that mistakenly
// returns a stale object.
//
// The AIR arm (mxmlc -> adl) is the reference. The AOT arm must agree with it; the
// hand-derived rule lives in expect.json and must agree with AIR as well, so the
// reference is checked rather than assumed.
package
{
    import flash.display.Bitmap;
    import flash.display.BitmapData;

    public class NullCases
    {
        public static const COUNT:int = 20;

        // ---- helpers --------------------------------------------------
        private static function makeBitmap():Bitmap
        {
            return new Bitmap(new BitmapData(8, 8, false, 0x22AA55));
        }

        private static function ok(v:Object):String
        {
            return v == null ? "NULL" : "ok";
        }

        public static function label(i:int):String
        {
            if (i == 1) return "x == null ? null : Bitmap(x)      [the reported shape]";
            if (i == 2) return "x == null ? Bitmap(x) : null";
            if (i == 3) return "1 == 0 ? null : Bitmap(x)         [constant condition]";
            if (i == 4) return "x == null ? null : x              [x:Object, no cast]";
            if (i == 5) return "x == null ? null : x              [x:Bitmap, no cast]";
            if (i == 6) return "x != null ? Bitmap(x) : null      [the workaround shape]";
            if (i == 7) return "x == null ? null : anyBox.bm      [property read]";
            if (i == 8) return "x == null ? null : anyBox.list[0]  [array element]";
            if (i == 9) return "x == null ? null : bm.bitmapData   [another class type]";
            if (i == 10) return "o == null ? null : Bitmap(o)       [o out of a {} slot]";
            if (i == 11) return "x == null ? null : String('hi')    [value type: control]";
            if (i == 12) return "x == null ? 0 : 42                  [then is 0, not null: control]";
            if (i == 13) return "if (x == null) return null; return Bitmap(x)  [workaround]";
            if (i == 14) return "x == null ? null : wrap(x)         [call in ELSE]";
            if (i == 15) return "x == null ? null : 42               [Number result]";
            if (i == 16) return "x == null ? null : true             [Boolean result]";
            if (i == 17) return "x == null ? null : 7                [int result]";
            if (i == 18) return "x != null ? null : 42               [the NULL arm actually runs, Number slot]";
            if (i == 19) return "x != null ? null : true             [the NULL arm actually runs, Boolean slot]";
            if (i == 20) return "x != null ? null : 7                [the NULL arm actually runs, int slot]";
            return "?";
        }

        public static function one(i:int):String
        {
            var bm:Bitmap = makeBitmap();
            if (i == 1) return ok(t1(bm));
            if (i == 2) return ok(t2(bm));
            if (i == 3) return ok(t3(bm));
            if (i == 4) return ok(t4(bm));
            if (i == 5) return ok(t5(bm));
            if (i == 6) return ok(t6(bm));
            if (i == 7) return ok(t7(bm));
            if (i == 8) return ok(t8(bm));
            if (i == 9) return ok(t9(bm));
            if (i == 10) return ok(t10(bm));
            if (i == 11) return String(t11(bm));
            if (i == 12) return String(t12(bm));
            if (i == 13) return ok(t13(bm));
            if (i == 14) return ok(t14(bm));
            if (i == 15) return String(t15(bm));
            if (i == 16) return String(t16(bm));
            if (i == 17) return String(t17(bm));
            if (i == 18) return String(t18(bm));
            if (i == 19) return String(t19(bm));
            if (i == 20) return String(t20(bm));
            return "?";
        }

        // ---- the cases ------------------------------------------------
        private static function t1(x:Object):Bitmap { return x == null ? null : Bitmap(x); }
        private static function t2(x:Object):Bitmap { return x == null ? Bitmap(x) : null; }
        private static function t3(x:Object):Bitmap { return 1 == 0 ? null : Bitmap(x); }
        private static function t4(x:Object):Bitmap { return x == null ? null : Bitmap(x); }
        private static function t5(x:Bitmap):Bitmap { return x == null ? null : x; }
        private static function t6(x:Object):Bitmap { return x != null ? Bitmap(x) : null; }

        private static function t7(x:Object):Object
        {
            var box:Box = new Box();
            box.bm = makeBitmap();
            return x == null ? null : box.bm;
        }

        private static function t8(x:Object):Object
        {
            var box:Box = new Box();
            box.list = [makeBitmap()];
            return x == null ? null : box.list[0];
        }

        private static function t9(x:Object):Object
        {
            var bm:Bitmap = makeBitmap();
            return x == null ? null : bm.bitmapData;
        }

        private static function t10(x:Object):Bitmap
        {
            var bag:Object = {};
            bag["bmp"] = makeBitmap();
            var o:Object = bag["bmp"];
            return o == null ? null : Bitmap(o);
        }

        private static function t11(x:Object):String { return x == null ? null : String("hi"); }
        private static function t12(x:Object):Number { return x == null ? 0 : 42; }

        private static function t13(x:Object):Bitmap
        {
            if (x == null) return null;
            return Bitmap(x);
        }

        private static function t14(x:Object):Bitmap { return x == null ? null : wrap(x); }

        // Does the collapse reach VALUE-typed results too? String is protected by
        // unifyType's explicit string rule; Number/Boolean/int have no such rule.
        private static function t15(x:Object):Number { return x == null ? null : 42; }
        private static function t16(x:Object):Boolean { return x == null ? null : true; }
        private static function t17(x:Object):int { return x == null ? null : 7; }

        // Cases 18-20 run the OTHER arm: `x != null` is TRUE, so the null literal in
        // the THEN slot IS the value. A fix that only rescues the ELSE value (by
        // typing the ternary as the other branch's number/boolean) would still fold
        // this arm to 0/false. The declared return type is `*` on purpose: a
        // `:Number` slot would coerce null to 0 at the return and hide the answer.
        private static function t18(x:Object):* { return x != null ? null : 42; }
        private static function t19(x:Object):* { return x != null ? null : true; }
        private static function t20(x:Object):* { return x != null ? null : 7; }

        private static function wrap(x:Object):Bitmap { return Bitmap(x); }
    }
}

class Box
{
    // Object-typed on purpose: a helper class outside the package block cannot see
    // the package's imports (mxmlc: "cannot find type Bitmap"), and typing these as
    // Object keeps the case a plain value read with no implicit coercion at the site.
    public var bm:Object;
    public var list:Array;
}
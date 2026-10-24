// ClosureCases.as -- static fields whose ONLY read points sit inside closures.
//
// This is the G22 shape. Every static below is runtime-initialized (an array
// literal, an object literal, a `static {}` block), so the class owns a lazy
// `_cinit()`. The only reads happen inside anonymous closures created by a
// static method -- the emitter path that used to skip the `(Owner_cinit(), ...)`
// guard, leaving the C slot NULL at run time.
//
// Two things are deliberately arranged so the defect cannot hide:
//   * `one()` reads NOTHING but literals outside the closures (an ordinary
//     static read anywhere in a method runs `_cinit()` for the whole class and
//     makes every closure read look fine);
//   * the drivers write literals only -- they never touch `ClosureCases`, `Bag`
//     or `Sealed` outside `one()`.
package {
    public class ClosureCases {
        private static const NAMES:Array = ["alpha", "beta", "gamma"];
        private static const NUMBER:int = 7;
        private static const TITLE:String = "cases";
        private static const CFG:Object = { mode: "cfg" };
        private static const PAIR:Array = ["x", "y"];

        public static function one(id:int):String {
            if (id == 1) {
                // Bare name for an own static Array, read only from a closure.
                var f1:Function = function ():String { return NAMES[1]; };
                return f1();
            }
            if (id == 2) {
                // Same path with a scalar (int) static.
                var f2:Function = function ():String { return String(NUMBER * 2); };
                return f2();
            }
            if (id == 3) {
                // Control: a compile-time literal const has no `_cinit`, so it
                // must keep working before and after the fix.
                var f3:Function = function ():String { return TITLE; };
                return f3();
            }
            if (id == 4) {
                // Qualified read of ANOTHER class's runtime-initialized static.
                var f4:Function = function ():String { return Bag.NAMES[2]; };
                return f4();
            }
            if (id == 5) {
                // A second own static, so case 1 and case 5 share one `_cinit`.
                var f5:Function = function ():String { return PAIR[1]; };
                return f5();
            }
            if (id == 6) {
                // Nested closure: the inner body is the read point.
                var f6:Function = function ():String {
                    var inner:Function = function ():String { return NAMES[0]; };
                    return inner();
                };
                return f6();
            }
            if (id == 7) {
                // Object-literal static, then a dynamic property read.
                var f7:Function = function ():String { return CFG.mode; };
                return f7();
            }
            if (id == 8) {
                // Class initialized by a `static {}` block (no field initializer).
                var f8:Function = function ():String { return Sealed.VALUE; };
                return f8();
            }
            if (id == 9) {
                // The read feeds a property access, so a NULL slot throws #1009
                // instead of merely answering a wrong string.
                var f9:Function = function ():String { return String(NAMES.length); };
                return f9();
            }
            if (id == 10) {
                // The read feeds a method call on the array.
                var f10:Function = function ():String { return NAMES.join("-"); };
                return f10();
            }
            return "no-case";
        }
    }
}
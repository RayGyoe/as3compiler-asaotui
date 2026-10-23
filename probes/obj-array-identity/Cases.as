// Cases.as -- the SINGLE source of truth for the "value in an `Object` slot"
// identity cases, shared by BOTH arms (our AOT, and real AIR via mxmlc/adl).
//
// Each case builds one value in a slot of a given STATIC type and asks exactly
// one question. `one(id)` returns the answer as text. Nothing here knows which
// compiler runs it, so a difference between the two arms is a compiler
// difference, not a probe difference.
package
{
    public class Cases
    {
        public static const COUNT:int = 26;

        // Mimics asaot.ui.style.Fill.fromAny: built-in checks first, then a
        // user-class check. The `is Array` guard inside was written to keep an
        // Array away from the `is <userClass>` line -- this measures whether it can.
        private static function fillLike(o:Object):String
        {
            if (o is Number) return "solid";
            if (o is Array) return "array-guard";
            if (o is Marker) return "marker";
            return "null";
        }

        // The REORDERED guard: array check FIRST, so an Array never reaches the
        // `is <userClass>` line or even the built-in `is Number` line. If an
        // `Object`-typed parameter can detect an Array at all, this shape works;
        // if `is Array` is constant-folded on every `Object` slot, no reordering
        // inside a `fromAny(o:Object)` can ever help -- the check has to happen at
        // the CALL SITE (where the value still lives in a `*` dynamic read).
        private static function fillArrayFirst(o:Object):String
        {
            if (o is Array) return "array-guard";
            if (o is Number) return "solid";
            if (o is Marker) return "marker";
            return "null";
        }

        public static function one(id:int):String
        {
            // --- an AS3 Array stored in an `Object`-typed slot ---
            if (id == 1)  { var a1:Object = [1, 2, 3]; return "Object slot <- [1,2,3]  (is Array)=" + (a1 is Array); }
            if (id == 2)  { var a2:Object = [1, 2, 3]; return "Object slot <- [1,2,3]  (is Object)=" + (a2 is Object); }
            if (id == 3)  { var a3:Object = [1, 2, 3]; return "Object slot <- [1,2,3]  (is Marker)=" + (a3 is Marker); }
            // --- a Number in an `Object`-typed slot ---
            if (id == 4)  { var n4:Object = 3; return "Object slot <- 3        (is Number)=" + (n4 is Number); }
            if (id == 5)  { var n5:Object = 3; return "Object slot <- 3        (is Marker)=" + (n5 is Marker); }
            // --- a String in an `Object`-typed slot ---
            if (id == 6)  { var s6:Object = "x"; return "Object slot <- \"x\"      (is String)=" + (s6 is String); }
            if (id == 7)  { var s7:Object = "x"; return "Object slot <- \"x\"      (is Marker)=" + (s7 is Marker); }
            // --- a Boolean in an `Object`-typed slot ---
            if (id == 8)  { var b8:Object = true; return "Object slot <- true     (is Boolean)=" + (b8 is Boolean); }
            if (id == 9)  { var b9:Object = true; return "Object slot <- true     (is Marker)=" + (b9 is Marker); }
            // --- a genuine instance (the case that must keep working) ---
            if (id == 10) { var m10:Object = new Marker(); return "Object slot <- Marker   (is Marker)=" + (m10 is Marker); }
            // --- the same values through `*` (untyped) slots ---
            if (id == 11) { var u11:* = [1, 2, 3]; return "* slot <- [1,2,3]       (is Array)=" + (u11 is Array); }
            if (id == 12) { var u12:* = [1, 2, 3]; return "* slot <- [1,2,3]       (is Marker)=" + (u12 is Marker); }
            // --- the same values through `Array`-typed slots ---
            if (id == 13) { var y13:Array = [1, 2, 3]; return "Array slot <- [1,2,3]   (is Array)=" + (y13 is Array); }
            if (id == 14) { var y14:Array = [1, 2, 3]; return "Array slot <- [1,2,3]   (is Marker)=" + (y14 is Marker); }
            // --- other ways of reading an Object-slot Array ---
            if (id == 15) { var c15:Object = [1, 2, 3]; return "Object slot <- [1,2,3]  (as Array != null)=" + ((c15 as Array) != null); }
            if (id == 16) { var c16:Object = [1, 2, 3]; return "Object slot <- [1,2,3]  (length)=" + c16.length; }
            if (id == 17) { var c17:Object = 3; return "Object slot <- 3        (String)=" + String(c17); }
            if (id == 18) { var c18:Object = [1, 2, 3]; return "Object slot <- [1,2,3]  (typeof)=" + (typeof c18); }
            // --- the style layer's two discriminator shapes ---------------------
            // 19: an Array in an Object slot fed to a guard that tries `is Array` FIRST.
            if (id == 19) { var o19:Object = [1, 2, 3]; return "guard(Object slot <- [1,2,3])=" + fillLike(o19); }
            // 20: the discriminator the style layer REALLY uses -- on a `*` dynamic read.
            if (id == 20) { var o20:Object = { size: [4, 8] }; return "(dyn read).size is Array=" + (o20.size is Array); }
            // 21: `Fill.fromAny(o.background)` verbatim: an Array reached by a dynamic read.
            if (id == 21) { var o21:Object = { background: [255, 0, 0] }; return "guard(dyn read)= " + fillLike(o21.background); }
            // 22: the fromArray half the layer uses instead -- `as Array` then index.
            if (id == 22) { var o22:Object = { size: [4, 8] }; var q22:Array = o22.size as Array; return "(dyn read) as Array -> length=" + (q22 == null ? -1 : q22.length); }
            // --- the built-in checks `Fill.fromAny` runs BEFORE its dead array guard -----
            if (id == 23) { var o23:Object = [1, 2, 3]; return "Object slot <- [1,2,3]  (is Number)=" + (o23 is Number); }
            if (id == 24) { var o24:Object = [1, 2, 3]; return "Object slot <- [1,2,3]  (is String)=" + (o24 is String); }
            if (id == 25) { var o25:Object = [1, 2, 3]; return "Object slot <- [1,2,3]  (is Boolean)=" + (o25 is Boolean); }
            // 26: would REORDERING the guard help? (array check first)
            if (id == 26) { var o26:Object = [1, 2, 3]; return "guard, array-check FIRST=" + fillArrayFirst(o26); }
            return "id " + id + " unknown";
        }
    }
}

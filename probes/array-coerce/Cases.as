// Cases.as -- what does the AS3 conversion function `Array(x)` do with an Array?
//
// The library uses `Array(opts.items)` / `Array(opts.options)` / `Array(opts.footer)`
// as the "single value or list" coercion. If `Array(anArray)` WRAPS (a 1-element
// array holding the array) instead of returning it, every one of those call sites
// gets a nested array and the first `Node(...)` cast blows up with
// "#1034 cannot convert [object BoxNode]" -- which is exactly what happened.
//
// AS3 reference (ES3 15.4.1 + the AS3 Array class): `Array(x)` is the Array
// CONSTRUCTOR called as a function. So the hand-derived rule is:
//
//   Array(3)      -> length 1, element 3     (only new Array(3) makes 3 holes)
//   Array([1,2])  -> length 1, element [1,2]
//   Array("x")    -> length 1
//
// i.e. WRAP for everything. But the AIR arm below is the authority: whatever it
// prints IS the semantics, and this file's comments get corrected to match.
package
{
    public class Cases
    {
        public static const COUNT:int = 8;

        // Every case returns a STRING so both arms print byte-identical text.
        public static function one(i:int):String
        {
            var a:Array = [1, 2];
            var o:Object = [1, 2];
            switch (i)
            {
                case 1: return "Array([1,2]).length=" + Array([1, 2]).length;
                case 2: return "Array(a)===a -> " + (Array(a) === a);
                case 3: return "Array(3).length=" + Array(3).length;
                case 4: return "Array(\"x\").length=" + Array("x").length;
                case 5: return "Array([]).length=" + Array([]).length;
                case 6: return "Array(o).length=" + Array(o).length;
                case 7: return "Array([1,2]).join(\"-\")=" + Array([1, 2]).join("-");
                case 8: return "Array([1,2])[0] is Array -> " + (Array([1, 2])[0] is Array);
                default: return "?";
            }
        }
    }
}
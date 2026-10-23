// StyleCases.as -- the measured case table, shared by BOTH arms.
//
// QUESTION: the style layer used to split each entry point into
// `fromAny(o:Object)` (scalars) and `fromArray(a:Array)` (arrays), because an
// Array put into an `Object`-typed parameter lost its identity in our AOT and a
// following `is <userClass>` even SIGSEGV'd (compiler-gaps.md G14). G14 is fixed
// (compiler 阶段二百五十三), so the split was reverted and `fromAny` became TOTAL:
// it dispatches the array form itself.
//
// This measures that revert on BOTH runtimes -- our AOT and real AIR 51.4.1 --
// instead of trusting it. Every case is a value question, so the driver writes
// one `id=<n> <value>` line per case; `expect.json` carries the hand-derived
// answer, and the AIR arm is checked against it too (so "AIR is the reference"
// is itself a measured claim, not a slogan).
//
// CRASH EVIDENCE IS THE LINE COUNT: a case that dies (0xC0000005) stops the
// program, so the file is short. `run.cjs` fails when fewer lines than COUNT
// arrive, and prints the last one reached.
package
{
    import asaot.ui.style.Corners;
    import asaot.ui.style.Edges;
    import asaot.ui.style.Fill;
    import asaot.ui.style.Length;
    import asaot.ui.style.LengthEdges;
    import asaot.ui.style.Size;
    import asaot.ui.style.StyleRefinement;

    public class StyleCases
    {
        public static const COUNT:int = 19;

        public static function one(id:int):String
        {
            var opts:Object;
            switch (id)
            {
                // ---- Size -------------------------------------------------
                case 1:  return sizeOf(Size.fromAny([100, 50]));
                case 2:  return sizeOf(Size.fromAny(20));
                case 3:  return sizeOf(Size.fromAny([7]));
                case 4:  return Size.fromAny(null) == null ? "null" : "obj";
                case 19: return sizeOf(Size.fromAny(Length.pct(0.5)));

                // ---- Edges (padding / borderWidths / border) --------------
                case 5:  return edgeOf(Edges.fromAny([8, 4]));
                case 6:  return edgeOf(Edges.fromAny([1, 2, 3, 4]));
                case 7:  return edgeOf(Edges.fromAny(6));

                // ---- Corners (cornerRadii) --------------------------------
                case 8:  return cornerOf(Corners.fromAny([1, 2, 3, 4]));
                case 9:  return cornerOf(Corners.fromAny([2]));

                // ---- LengthEdges (margin / inset): Length per side ---------
                case 10: return lenEdgeOf(LengthEdges.fromAny([10, 20]));
                case 11: return lenEdgeOf(LengthEdges.fromAny("auto"));

                // ---- Fill (background). An array is a gradient stop list,
                // deferred -> null; a Number is a solid colour --------------
                case 12: return Fill.fromAny([11, 22]) == null ? "null" : "fill";
                case 13: return fillOf(Fill.fromAny(0x2563EB));
                case 14: return fillOf(Fill.fromAny(Fill.solid(0x112233)));

                // ---- THE MECHANISM: an Array inside an Object-typed param --
                case 15: return isArrayInObjectSlot([1]) ? "true" : "false";

                // ---- End-to-end through StyleRefinement.from (the real
                // caller: every value here is a dynamic `o.<field>` read) --
                case 16:
                    opts = { size: [3, 4], padding: 5, background: 9 };
                    return sizeOf(StyleRefinement.from(opts).size);
                case 17:
                    opts = { size: [3, 4], padding: 5, background: 9 };
                    return edgeOf(StyleRefinement.from(opts).padding);
                case 18:
                    opts = { background: [1, 2] };
                    return StyleRefinement.from(opts).background == null ? "null" : "fill";
            }
            return "id" + id + "=?";
        }

        // An Array handed to an `Object`-typed parameter. Everything above rests
        // on this one test telling the truth.
        public static function isArrayInObjectSlot(o:Object):Boolean
        {
            return o is Array;
        }

        // ---- deterministic formatters (no float formatting anywhere) ------
        private static function lenStr(l:Length):String
        {
            if (l == null) return "-";
            if (l.unit == Length.UNIT_AUTO) return "auto";
            var suffix:String = l.unit == Length.UNIT_PERCENT ? "%" : "px";
            return String(int(l.toEngineValue())) + suffix;
        }

        private static function sizeOf(s:Size):String
        {
            if (s == null) return "null";
            return "(" + lenStr(s.width) + "," + lenStr(s.height) + ")";
        }

        private static function edgeOf(e:Edges):String
        {
            if (e == null) return "null";
            return "(" + String(int(e.top)) + "," + String(int(e.right)) + ","
                + String(int(e.bottom)) + "," + String(int(e.left)) + ")";
        }

        private static function cornerOf(c:Corners):String
        {
            if (c == null) return "null";
            return "(" + String(int(c.topLeft)) + "," + String(int(c.topRight)) + ","
                + String(int(c.bottomRight)) + "," + String(int(c.bottomLeft)) + ")";
        }

        private static function lenEdgeOf(e:LengthEdges):String
        {
            if (e == null) return "null";
            return "(" + lenStr(e.top) + "," + lenStr(e.right) + ","
                + lenStr(e.bottom) + "," + lenStr(e.left) + ")";
        }

        private static function fillOf(f:Fill):String
        {
            if (f == null) return "null";
            return "#" + hex6(f.rgb()) + "@" + String(int(f.alpha() * 255 + 0.5));
        }

        private static function hex6(n:Number):String
        {
            var u:uint = uint(n) & 0xFFFFFF;
            return hex2((u >> 16) & 0xFF) + hex2((u >> 8) & 0xFF) + hex2(u & 0xFF);
        }

        private static function hex2(v:uint):String
        {
            var d:String = "0123456789ABCDEF";
            return d.charAt((v >> 4) & 0xF) + d.charAt(v & 0xF);
        }
    }
}

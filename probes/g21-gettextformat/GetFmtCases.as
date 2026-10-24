// GetFmtCases.as -- what does `TextField.getTextFormat()` report for a range?
//
// The SAME source runs on both arms. Each case builds a 10-character field, applies
// zero, one or two setTextFormat runs, then reads a range back and reports
// `size`/`color` (or the thrown error). The point is the RANGE semantics: which run
// wins when a range spans a boundary, what an empty / reversed / out-of-bounds range
// does, and what the no-argument form returns.
package {
    import flash.text.TextField;
    import flash.text.TextFormat;

    public class GetFmtCases {
        public static const COUNT:int = 30;

        private static function base():TextField {
            var t:TextField = new TextField();
            t.defaultTextFormat = new TextFormat("Arial", 20, 0x000000);
            t.text = "0123456789";
            return t;
        }

        private static function run(t:TextField, size:Number, color:uint, b:int, e:int):void {
            t.setTextFormat(new TextFormat("Arial", size, color), b, e);
        }

        private static function dump(f:TextFormat):String {
            return "size=" + f.size + " color=" + f.color;
        }

        public static function one(id:int):String {
            var t:TextField;
            try {
                // ---- no runs at all ----
                if (id == 1) {
                    t = base();
                    return dump(t.getTextFormat());                       // no args
                }
                if (id == 2) {
                    t = base();
                    return dump(t.getTextFormat(0, 10));                  // whole text
                }
                if (id == 3) {
                    t = base();
                    return dump(t.getTextFormat(3, 3));                   // empty range
                }
                if (id == 4) {
                    t = base();
                    return dump(t.getTextFormat(10, 10));                 // empty, at the end
                }
                // ---- one run over [2,6) ----
                if (id == 5) {
                    t = base();
                    run(t, 30, 0xFF0000, 2, 6);
                    return dump(t.getTextFormat());                       // no args, run present
                }
                if (id == 6) {
                    t = base();
                    run(t, 30, 0xFF0000, 2, 6);
                    return dump(t.getTextFormat(3, 5));                   // fully inside
                }
                if (id == 7) {
                    t = base();
                    run(t, 30, 0xFF0000, 2, 6);
                    return dump(t.getTextFormat(0, 2));                   // fully outside (before)
                }
                if (id == 8) {
                    t = base();
                    run(t, 30, 0xFF0000, 2, 6);
                    return dump(t.getTextFormat(6, 9));                   // fully outside (after)
                }
                if (id == 9) {
                    t = base();
                    run(t, 30, 0xFF0000, 2, 6);
                    return dump(t.getTextFormat(1, 4));                   // spans INTO the run
                }
                if (id == 10) {
                    t = base();
                    run(t, 30, 0xFF0000, 2, 6);
                    return dump(t.getTextFormat(5, 8));                   // spans OUT of the run
                }
                if (id == 11) {
                    t = base();
                    run(t, 30, 0xFF0000, 2, 6);
                    return dump(t.getTextFormat(1, 9));                   // covers the run + both sides
                }
                // ---- two adjacent runs: [0,3) size 11 blue, [3,6) size 44 green ----
                if (id == 12) {
                    t = base();
                    run(t, 11, 0x0000FF, 0, 3);
                    run(t, 44, 0x00FF00, 3, 6);
                    return dump(t.getTextFormat(0, 6));                   // spans BOTH runs
                }
                if (id == 13) {
                    t = base();
                    run(t, 11, 0x0000FF, 0, 3);
                    run(t, 44, 0x00FF00, 3, 6);
                    return dump(t.getTextFormat(4, 5));                   // inside the SECOND run
                }
                // ---- empty text ----
                if (id == 14) {
                    t = new TextField();
                    t.defaultTextFormat = new TextFormat("Arial", 20, 0x000000);
                    t.text = "";
                    return dump(t.getTextFormat());
                }
                // ---- out-of-bounds / reversed / explicit -1s ----
                if (id == 15) {
                    t = base();
                    return dump(t.getTextFormat(20, 30));                 // past the end
                }
                if (id == 16) {
                    t = base();
                    return dump(t.getTextFormat(6, 2));                   // begin > end
                }
                if (id == 17) {
                    t = base();
                    return dump(t.getTextFormat(-1, -1));                 // explicit defaults
                }

                // ---- second round: boundaries, clamps, empty-vs-uniform ----
                if (id == 18) {
                    t = new TextField();
                    t.defaultTextFormat = new TextFormat("Arial", 20, 0x000000);
                    t.text = "";
                    return dump(t.getTextFormat(0, 0));                    // empty text, empty range
                }
                if (id == 19) {
                    t = new TextField();
                    t.defaultTextFormat = new TextFormat("Arial", 20, 0x000000);
                    t.text = "";
                    return dump(t.getTextFormat(0, 1));                    // empty text, end past length
                }
                if (id == 20) {
                    t = base();
                    return dump(t.getTextFormat(0, 0));                    // empty range at 0, no runs
                }
                if (id == 21) {
                    t = base();
                    run(t, 30, 0xFF0000, 2, 6);
                    return dump(t.getTextFormat(2, 2));                    // empty range at the run start
                }
                if (id == 22) {
                    t = base();
                    return dump(t.getTextFormat(3, 5));                    // interior, no runs
                }
                if (id == 23) {
                    t = base();
                    return dump(t.getTextFormat(9, 10));                   // last character, no runs
                }
                if (id == 24) {
                    t = base();
                    return dump(t.getTextFormat(0, 11));                   // end past length (begin ok)
                }
                if (id == 25) {
                    t = base();
                    return dump(t.getTextFormat(-1, 5));                   // begin default, end given
                }
                if (id == 26) {
                    t = base();
                    return dump(t.getTextFormat(5, -1));                   // begin given, end default
                }
                if (id == 27) {
                    t = base();
                    run(t, 30, 0xFF0000, 0, 3);
                    run(t, 30, 0xFF0000, 3, 6);
                    return dump(t.getTextFormat(0, 6));                    // two runs, SAME values
                }
                if (id == 28) {
                    t = base();
                    run(t, 30, 0xFF0000, 0, 10);
                    return dump(t.getTextFormat());                        // one run covering all
                }
                if (id == 29) {
                    t = base();
                    run(t, 30, 0xFF0000, 2, 6);
                    return dump(t.getTextFormat(6, 6));                    // empty range at the run end
                }
                if (id == 30) {
                    t = base();
                    run(t, 30, 0xFF0000, 2, 6);
                    return dump(t.getTextFormat(1, 1));                    // empty range before the run
                }
                return "no-case";
            } catch (e:Error) {
                return "throw " + e.errorID;
            }
        }
    }
}
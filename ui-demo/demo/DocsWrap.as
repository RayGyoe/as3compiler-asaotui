// demo/DocsWrap.as -- word wrap for the docs' prose, at the width the READING PANE
// actually has.
//
// WHY THIS EXISTS. `prose` used to be an array of display LINES: the author broke
// every paragraph by hand at whatever width they had in mind. The window is fluid, so
// that width is a guess -- on a 1000pt stage the pane is 678 wide and a hand-broken
// paragraph stopped after "no", halfway across the pane (the reported defect). The
// catalog now stores PARAGRAPHS, and this class breaks them at the live width.
//
// WHY NOT `whiteSpace: "normal"` (the kit's own wrapper). That contract needs a POINT
// width on the text node, because the wrapped height is a MEASURE-time result and a
// percentage width is not known until the solve. A point width is fine here -- but the
// block's height has to be known BEFORE the solve too (ScrollViewWidget refuses a
// content child with no height, and DocSection.height() is the arithmetic the tour
// audits), so the line count is needed up front either way. Measuring here and
// emitting one line per TextField is the same number of shaping passes and keeps the
// per-line boxes the height arithmetic is built on.
//
// THE MEASUREMENT IS THE RENDERER'S OWN. `PaintKit.formatFor(style)` is the exact
// TextFormat TextWidget installs, and `textWidth` is the exact advance the painter
// uses, so a line this class says fits is a line that fits.
package demo
{
    import asaot.ui.PaintKit;
    import asaot.ui.style.Style;
    import flash.text.TextField;

    public final class DocsWrap
    {
        // One scratch field, reused: wrapping a page is a per-describe path and the
        // project forbids per-frame garbage (kit section 7).
        private static var scratch:TextField;
        // wrapW|paragraph -> wrapped lines. Keyed by BOTH because the answer is a
        // function of both; the catalog is ~355 paragraphs, so this stays small.
        private static var cache:Object;
        private static var cacheSize:int;

        // The width of `s` in the format of `style`, in points.
        private static function widthOf(s:String, style:Style):Number
        {
            if (scratch == null)
            {
                scratch = new TextField();
                scratch.autoSize = "left";
                scratch.multiline = false;
                scratch.wordWrap = false;
            }
            // THE TEXT FIRST, THE FORMAT SECOND. `text = ...` replaces the text flow,
            // and setTextFormat only ever applies to the run that exists at that
            // moment -- so a format applied BEFORE is silently dropped and textWidth
            // then answers for the DEFAULT face. Measured: 873.5pt instead of 986.1pt
            // for the paragraph that overflowed the reading pane.
            scratch.text = s;
            scratch.setTextFormat(PaintKit.formatFor(style));
            return scratch.textWidth;
        }

        // GREEDY FILL, ONE LINE PER RESULT. A single word wider than the pane is left
        // alone and overflows: breaking inside a word would invent hyphenation the
        // author never wrote, and the docs are full of long identifiers that must stay
        // readable.
        public static function wrap(paragraph:String, wrapW:Number, style:Style):Array
        {
            if (paragraph == null || paragraph.length == 0) return [""];
            if (!(wrapW > 0)) return [paragraph];
            if (cache == null) cache = {};
            var ck:String = wrapW + "|" + paragraph;
            var hit:Array = cache[ck] as Array;
            if (hit != null) return hit;
            // A window that is dragged around produces a new key per width; the old
            // ones are worthless once the frame is gone.
            if (cacheSize > 4000) { cache = {}; cacheSize = 0; }
            var out:Array = [];
            var words:Array = paragraph.split(" ");
            var cur:String = "";
            for (var i:int = 0; i < words.length; i++)
            {
                var w:String = String(words[i]);
                if (w.length == 0) continue;
                var cand:String = cur.length == 0 ? w : cur + " " + w;
                if (cur.length > 0 && widthOf(cand, style) > wrapW)
                {
                    out.push(cur);
                    cur = w;
                }
                else
                {
                    cur = cand;
                }
            }
            if (cur.length > 0) out.push(cur);
            if (out.length == 0) out.push("");
            cache[ck] = out;
            cacheSize = cacheSize + 1;
            return out;
        }

        // Every paragraph of a section, wrapped and flattened into display lines.
        public static function lines(paragraphs:Array, wrapW:Number, style:Style):Array
        {
            var out:Array = [];
            for (var i:int = 0; i < paragraphs.length; i++)
            {
                var one:Array = wrap(String(paragraphs[i]), wrapW, style);
                for (var j:int = 0; j < one.length; j++) out.push(one[j]);
            }
            return out;
        }
    }
}
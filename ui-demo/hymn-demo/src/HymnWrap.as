// hymn/HymnWrap.as -- word wrap for the lyric column, at the width the reader
// actually has.
//
// WHY NOT `whiteSpace: "normal"`: a scroll view refuses a content child with no
// height ("a viewport silently shrinking its content is never what the author drew"),
// so the reader's content height has to be known BEFORE the layout solve. Auto-height
// text knows its height only during the solve. Wrapping here -- one measured line per
// row, one explicit height per row -- makes the block arithmetic exact, which is what
// the reader's scroll clamp and its "which verse is on screen" logic are built on.
//
// THE MEASUREMENT IS THE PAINTER'S OWN: a scratch TextField with the same family/size
// the text nodes are given, `autoSize=left`, `wordWrap=false`, so `textWidth` is the
// advance the renderer will report for the same run.
package hymn
{
    import flash.text.TextField;
    import flash.text.TextFormat;

    public final class HymnWrap
    {
        private static var scratch:TextField;
        private static var fmt:TextFormat;
        private static var fmtKey:String = "";
        // wrapW|family|size|text -> array of display rows. The corpus is 1000 hymns but
        // only the SELECTED one is wrapped per frame, so this stays small; it is cleared
        // wholesale when it grows (a window drag mints a key per width).
        private static var cache:Object;
        private static var cacheSize:int = 0;
        private static var lineCache:Object;

        private static function widthOf(s:String, family:String, size:Number, bold:Boolean = false):Number
        {
            if (scratch == null)
            {
                scratch = new TextField();
                scratch.autoSize = "left";
                scratch.multiline = false;
                scratch.wordWrap = false;
            }
            var key:String = family + "|" + String(size) + "|" + String(bold);
            if (key != fmtKey)
            {
                fmtKey = key;
                fmt = new TextFormat();
                fmt.font = family;
                fmt.size = size;
                fmt.bold = bold;
            }
            // TEXT FIRST, FORMAT SECOND: `text = ...` rebuilds the text flow and drops a
            // format applied before it (the trap DocsWrap records).
            scratch.text = s;
            scratch.setTextFormat(fmt);
            return scratch.textWidth;
        }

        // The wrap width is only half the story: a caller that needs the advance of a
        // single run (to prove a label was measured with the same face the painter
        // uses) can ask for it directly instead of re-deriving a scratch field.
        public static function width(s:String, family:String, size:Number, bold:Boolean = false):Number
        {
            return widthOf(s, family, size, bold);
        }

        // THE LINE BOX OF ONE RUN, from the same scratch field the advance comes from.
        //
        // WHY IT IS NEEDED: a text node in this kit draws its first line at the TOP of
        // its content box (TextWidget.placeRun sets `tf.y = insetY`), so the box height
        // is the ONLY vertical control an author has. Give a label a 19pt box for a 14pt
        // run and the glyphs hang from the ceiling with the slack all below -- measured
        // on the HYMN badge: 4 device px above, 26 below (DPR 1.5), i.e. 7pt high. Every
        // label in this app states its box (a null height solves to 0), so the fix is to
        // ask the painter how tall one line actually is and split the slack evenly.
        //
        // `Agyj|` covers ascender, descender and the pipe's full height, so `textHeight`
        // is the font's own line box and not a lucky sample.
        public static function lineHeight(family:String, size:Number, bold:Boolean = false):Number
        {
            var key:String = family + "|" + String(size) + "|" + String(bold);
            var hit:Object = lineCache == null ? null : lineCache[key];
            if (hit != null) return Number(hit);
            if (scratch == null)
            {
                scratch = new TextField();
                scratch.autoSize = "left";
                scratch.multiline = false;
                scratch.wordWrap = false;
            }
            var f:TextFormat = new TextFormat();
            f.font = family;
            f.size = size;
            f.bold = bold;
            // Text first, format second -- same trap as widthOf (a format applied before
            // `text = ...` is dropped by the re-flow).
            scratch.text = "Agyj|";
            scratch.setTextFormat(f);
            // widthOf left its own format on the field; this probe owns the next one.
            fmtKey = "";
            var lh:Number = scratch.textHeight;
            if (!(lh > 0)) lh = size * 1.2;
            if (lineCache == null) lineCache = {};
            lineCache[key] = lh;
            return lh;
        }

        // The longest prefix of "s" that fits "maxW", with an ellipsis when it had to be
        // cut. A row subtitle in a 268pt column otherwise runs straight through the panel
        // edge: the painter clips NOWRAP text at its box only if the box is enforced, and
        // a clipped word with no mark reads as a bug rather than as "more to come".
        public static function fit(s:String, maxW:Number, family:String, size:Number,
                                   bold:Boolean = false):String
        {
            if (s == null) return "";
            if (!(maxW > 0)) return s;
            if (widthOf(s, family, size, bold) <= maxW) return s;
            var ell:Number = widthOf("…", family, size, bold);
            var lo:int = 0;
            var hi:int = s.length;
            // Binary search on the CHARACTER count: the advance is monotone in length for
            // a single run, and 8 probes beat 40 substring measurements.
            while (lo < hi)
            {
                var mid:int = int((lo + hi + 1) / 2);
                if (widthOf(s.substr(0, mid), family, size, bold) + ell <= maxW) lo = mid;
                else hi = mid - 1;
            }
            if (lo <= 0) return "…";
            return s.substr(0, lo) + "…";
        }

        // Greedy fill on words. A single word wider than the column is left alone and
        // overhangs -- breaking inside a word would invent hyphenation nobody wrote.
        public static function lines(text:String, wrapW:Number, family:String, size:Number,
                                    bold:Boolean = false):Array
        {
            if (text == null) return [""];
            if (!(wrapW > 0)) return [text];
            if (cache == null) cache = {};
            var ck:String = String(wrapW) + "|" + family + "|" + String(size) + "|"
                + String(bold) + "|" + text;
            var hit:Array = cache[ck] as Array;
            if (hit != null) return hit;
            if (cacheSize > 3000) { cache = {}; cacheSize = 0; }
            var out:Array = [];
            var words:Array = text.split(" ");
            var cur:String = "";
            for (var i:int = 0; i < words.length; i++)
            {
                var w:String = String(words[i]);
                if (w.length == 0)
                {
                    if (cur.length > 0) cur = cur + " ";
                    continue;
                }
                // THE SPACE IS PART OF THE MEASURED STRING. Measuring `cur + w` and
                // painting the two rows as separate text nodes dropped the inter-word
                // space entirely -- and worse, the measurement agreed with itself, so
                // nothing looked wrong until the glyphs were read: "Amazing gracehow
                // sweet". The separator must be in the string that `widthOf` sees.
                var cand:String = cur.length == 0 ? w : cur + " " + w;
                if (cur.length > 0 && widthOf(cand, family, size, bold) > wrapW)
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
    }
}

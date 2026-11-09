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
// THE MEASUREMENT IS THE RENDERER'S OWN ON THE ASCII PATH: `PaintKit.formatFor(style)`
// is the exact TextFormat TextWidget installs, and `textWidth` is the advance the
// painter reports, so a pure-ASCII line this class says fits is a line that fits.
// THE CJK PATH DOES NOT TRUST IT (see wrapCJK): on long mixed Chinese runs `textWidth`
// under-reports or answers 0, which is how a whole translated paragraph ended up as one
// line 1432pt long inside a 678pt pane. There the fill is done by SUMMING advances, and
// the CJK advance is taken as the em, which full-width glyphs are by definition.
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
        //
        // ...BUT A CHINESE PARAGRAPH HAS NO SPACES AT ALL, so the rule above would make
        // every translated paragraph ONE 2000pt line: the block arithmetic would still
        // be right and the ink would run straight off the pane (the tour's inkWide check
        // is what catches that). Han/Kana/Hangul text therefore breaks BETWEEN
        // CHARACTERS -- which is what those scripts do, no hyphenation invented -- and
        // punctuation is kept off a line's leading edge. Pure-ASCII paragraphs produce
        // exactly the same tokens (`split(" ")`) and the same joins, so every English
        // page keeps its byte-identical line count.
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
            var out:Array = (hasCJK(paragraph)) ? wrapCJK(paragraph, wrapW, style)
                                                : wrapAscii(paragraph, wrapW, style);
            if (out.length == 0) out.push("");
            cache[ck] = out;
            cacheSize = cacheSize + 1;
            return out;
        }

        // The pure-ASCII path, unchanged: a candidate STRING is measured whole.
        private static function wrapAscii(paragraph:String, wrapW:Number, style:Style):Array
        {
            var out:Array = [];
            var words:Array = segment(paragraph);
            var cur:String = "";
            for (var i:int = 0; i < words.length; i++)
            {
                var w:String = String(words[i]);
                if (w.length == 0) continue;
                var glue:Boolean = cur.length == 0 || joins(cur, w);
                var cand:String = glue ? cur + w : cur + " " + w;
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
            return out;
        }

        // A paragraph with any non-ASCII in it is filled by SUMMING token advances
        // instead of measuring the candidate string. `textWidth` is not an answer we can
        // use here: for long mixed Chinese runs it under-reports (measured: a line of 60
        // Han characters -- 180 in the byte-index era, 60 code units now -- reporting
        // 757pt, ~4.2pt per glyph against the 12pt this backend really advances), and for
        // short runs it answers 0 outright -- so `widthOf(cand) > wrapW` stayed false and
        // a whole translated paragraph was emitted as ONE line, straight out of the pane. A Han/Kana/Hangul glyph is
        // FULL-WIDTH by definition (its advance IS the em), so the wide-glyph advance is
        // the em from the TextFormat, not a per-candidate measurement; a Latin word is
        // still measured, with an over-estimate as the fallback -- which only ever breaks
        // a line earlier, and an early break cannot paint out of the box.
        private static function wrapCJK(paragraph:String, wrapW:Number, style:Style):Array
        {
            var out:Array = [];
            var words:Array = segment(paragraph);
            var em:Number = emWidth(style);
            var cur:String = "";
            var curW:Number = 0;
            for (var i:int = 0; i < words.length; i++)
            {
                var w:String = String(words[i]);
                if (w.length == 0) continue;
                var tw:Number = tokenWidth(w, style, em);
                var gap:Number = 0;
                if (cur.length > 0 && !joins(cur, w)) gap = spaceWidth(style, em);
                if (cur.length > 0 && curW + gap + tw > wrapW)
                {
                    out.push(cur);
                    cur = w;
                    curW = tw;
                }
                else
                {
                    cur = (gap > 0) ? cur + " " + w : cur + w;
                    curW = curW + gap + tw;
                }
            }
            if (cur.length > 0) out.push(cur);
            return out;
        }

        // THE CJK ADVANCE IS THE EM, and that is a definition, not a measurement:
        // full-width ideographs occupy exactly one em. Confirmed against this backend
        // twice over -- "中文字体测试" at size 22 measures 132.0pt (22 per glyph) and a
        // 40-glyph run of 漢 at size 12 measures 480.0pt (12 per glyph). Taking it from
        // the TextFormat keeps the CJK path independent of `textWidth`, which is the
        // input that failed us (see wrapCJK).
        private static function emWidth(style:Style):Number
        {
            var size:Number = Number(PaintKit.formatFor(style).size);
            if (!(size > 0)) size = 12;
            return size;
        }

        // A space is a separator we count once per break opportunity. It is measured
        // (this API is reliable for a one-character Latin run) with a conservative
        // fallback: over-estimating a gap can only break a line earlier.
        private static function spaceWidth(style:Style, em:Number):Number
        {
            var w:Number = widthOf(" ", style);
            if (!(w > 0)) w = em * 0.28;
            return w;
        }

        // One token's advance. A WIDE token is a single non-ASCII code unit and takes
        // the em; a Latin run is measured, and when the measurement answers nothing
        // usable it is over-estimated. The test is the FIRST CODE UNIT, not the length:
        // a 25-character ASCII identifier is also `length > 1`, and treating it as one
        // em under-counts it by ~140pt (measured: a line summed to 660pt painted 859pt).
        //
        // `>= 0x80` is deliberately coarse -- "non-ASCII", not "full-width". A Latin-1
        // accent (é) or an em dash therefore costs a whole em where the face charges
        // half of one. That errs in the safe direction (over-estimate -> break a line
        // earlier -> never overflow), and narrowing it to a Han/Kana/Hangul range would
        // need a wide-table this class has no business owning.
        private static function tokenWidth(w:String, style:Style, em:Number):Number
        {
            if (w.length > 0 && w.charCodeAt(0) >= 0x80) return em;
            var m:Number = widthOf(w, style);
            if (!(m > 0)) m = em * 0.5 * w.length;
            return m;
        }

        // ---- the byte-cursor helpers that used to live here are GONE (G38) ----
        // Until compiler stage 390 this file walked BYTES, because String.length,
        // charCodeAt, charAt, substr and indexOf were byte offsets into the UTF-8
        // backing store: a 60-character Chinese sentence reported length 180, and
        // `charCodeAt(i) >= 0x2E80` -- the obvious "is this Han" test -- could never be
        // true, so 71 blocks once painted a line up to 1432pt inside a 678pt pane.
        // The compiler now indexes by UTF-16 code unit (backing store still UTF-8, so
        // no other boundary changed), which makes the natural spelling the correct one:
        //   head(s) -> s.charAt(0),  tail(s) -> s.charAt(s.length - 1),
        //   a codepoint -> s.charAt(i) advanced by one UNIT.
        // "Is this wide" is still the test on the FIRST code unit, not on length: a
        // 25-character ASCII identifier is also length > 1, and treating it as one em
        // under-counts it by ~140pt (measured: a line summed to 660pt painted 859pt).
        private static function head(s:String):String
        {
            if (s.length == 0) return "";
            return s.charAt(0);
        }

        // The last code unit of `s`. For an astral character that is its LOW surrogate,
        // which is still >= 0x80 -- the only thing the callers ask of it.
        private static function tail(s:String):String
        {
            if (s.length == 0) return "";
            return s.charAt(s.length - 1);
        }

        // Any non-ASCII text at all: that is what needs the summed fill instead of
        // the candidate-string measurement (see wrapCJK). Same coarse `>= 0x80` test as
        // tokenWidth -- a paragraph of Latin-1 accented text takes this path too, and
        // pays a fraction of an em per glyph. Safe, not exact.
        private static function hasCJK(p:String):Boolean
        {
            for (var i:int = 0; i < p.length; i++)
            {
                if (p.charCodeAt(i) >= 0x80) return true;
            }
            return false;
        }

        // The tokens `wrap` fills: a run of non-space ASCII characters is ONE token
        // (a word, identifier or URL); every non-ASCII code unit is its own token,
        // because a break is legal between any two of them. Spaces are separators,
        // never tokens -- which is what keeps the ASCII path identical to `split(" ")`.
        private static function segment(p:String):Array
        {
            var out:Array = [];
            var cur:String = "";
            var i:int = 0;
            while (i < p.length)
            {
                var b:int = p.charCodeAt(i);
                if (b == 0x20)
                {
                    if (cur.length > 0) { out.push(cur); cur = ""; }
                    i = i + 1;
                    continue;
                }
                if (b >= 0x80)
                {
                    // One code unit is one break opportunity. A surrogate half is its
                    // own token (so an astral character costs two em rather than one --
                    // an over-estimate again); neither half is ever painted alone.
                    if (cur.length > 0) { out.push(cur); cur = ""; }
                    out.push(p.charAt(i));
                    i = i + 1;
                    continue;
                }
                cur = cur + p.charAt(i);
                i = i + 1;
            }
            if (cur.length > 0) out.push(cur);
            return out;
        }

        // Does `w` attach to `cur` with NO space? Two wide characters do (a Chinese
        // sentence has no inter-character space), and so does punctuation: a closing
        // mark must not start a line, and an opening mark must not end one.
        private static function joins(cur:String, w:String):Boolean
        {
            var last:String = tail(cur);
            var first:String = head(w);
            if (last.length > 0 && OPENS.indexOf(last) >= 0) return true;
            if (first.length > 0 && CLOSES.indexOf(first) >= 0) return true;
            return isWide(last) && isWide(first);
        }

        // Is this one-unit slice a wide glyph? Read the first code unit, not the
        // LENGTH -- a one-unit CJK character and a short ASCII word both report length 1.
        private static function isWide(ch:String):Boolean
        {
            return ch.length > 0 && ch.charCodeAt(0) >= 0x80;
        }

        // Where a line may NOT break. Not a full UAX #14 implementation: the two
        // rules that show on a page are "no line starts with ，。、" and "no line ends
        // with （「《". Anything else is treated as a normal break opportunity.
        // Written as literal characters, not \uXXXX escapes: the demo sources are
        // UTF-8 and the AOT compiles them as such (KitMessages already ships CJK
        // literals through this same path).
        private static const CLOSES:String = "，。、；：！？）》」』】〕”’％…·";
        private static const OPENS:String = "（《「『【〔“‘";

        // Every paragraph of a section, wrapped and flattened into display lines.
        //
        // THE TRANSLATION HAPPENS HERE, not in DocSection's constructor: this is the
        // only place that has to touch each paragraph once, and it already caches its
        // answer per (width, paragraph) -- so a locale switch re-wraps each paragraph
        // exactly once and a re-describe costs a dictionary read per paragraph. Doing
        // it in the constructor would allocate a fresh `prose` ARRAY for all 267
        // sections on every single describe.
        public static function lines(paragraphs:Array, wrapW:Number, style:Style):Array
        {
            var out:Array = [];
            for (var i:int = 0; i < paragraphs.length; i++)
            {
                var one:Array = wrap(DemoText.t(String(paragraphs[i])), wrapW, style);
                for (var j:int = 0; j < one.length; j++) out.push(one[j]);
            }
            return out;
        }
    }
}
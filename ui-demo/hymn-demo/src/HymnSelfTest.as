// hymn/HymnSelfTest.as -- the Rust original's unit tests, ported.
//
// hymnbook's `src/hymn.rs` ships fourteen tests. A port that is only checked by
// "the app looks right" would drift exactly where those tests bite: the chorus
// that survives a blank line, "Note:" that is a lyric and not a voice tag,
// "2. Ye gates" that is a verse start, "mf" that is a dynamic and not a word.
// So the same assertions run here, at startup, and the result is part of the
// demo's own verdict (HymnMain writes it to the tour report).
//
// EVERY CASE IS TESTED AGAINST SYNTHETIC INPUT except the first and last, which
// need the real corpus -- that is what the Rust tests do too.
package hymn
{
    public final class HymnSelfTest
    {
        private static var fails:Array;

        // Returns "" when every case passes, else "label: got/got vs want" lines.
        public static function run(hymns:Array):String
        {
            fails = [];

            // ---- the corpus ---------------------------------------------------
            eqInt(hymns.length, 1000, "loads all thousand");
            if (hymns.length == 1000)
            {
                eqInt(hymns[0].number, 1, "first hymn is 1");
                eqInt(hymns[999].number, 1000, "last hymn is 1000");
                var asc:Boolean = true;
                for (var i:int = 1; i < hymns.length; i++)
                {
                    if (hymns[i].number <= hymns[i - 1].number) asc = false;
                }
                if (!asc) fails.push("hymns are in ascending number order");
                var empty:Boolean = false;
                for (var j:int = 0; j < hymns.length; j++)
                {
                    if (hymns[j].blocks.length == 0) { empty = true; break; }
                }
                if (empty) fails.push("every hymn parses to at least one block");
            }

            // ---- title casing -------------------------------------------------
            eq(titleCase("ALL HAIL, IMMANUEL!"), "All Hail, Immanuel!", "title: small words");
            eq(titleCase("YE GATES LIFT UP YOUR HEADS ON HIGH"),
               "Ye Gates Lift Up Your Heads on High", "title: mid-sentence small word");
            eq(titleCase("PRAISE GOD (Doxology)"), "Praise God (Doxology)", "title: parenthesis");
            eq(titleCase("THE LORD'S MY SHEPHERD"), "The Lord's My Shepherd", "title: apostrophe");
            eq(titleCase("WE LOVE THE PLACE, O GOD"), "We Love the Place, O God", "title: O");

            // ---- block parsing -------------------------------------------------
            var b:Array = parseBody("Line one\r\nLine two\r\n\r\nChorus:\r\nSop: Hail\r\nATB: Hail to\r\n\r\n2. Second\r\nmore");
            eqInt(b.length, 3, "parse: three blocks");
            if (b.length == 3)
            {
                eqInt(b[0].kind, HymnBook.KIND_VERSE, "parse: first block is a verse");
                eqInt(b[0].verse, 1, "parse: verse 1 labelled when verse 2 exists");
                eqInt(b[0].lines.length, 2, "parse: verse 1 has two lines");
                eqInt(b[1].kind, HymnBook.KIND_CHORUS, "parse: middle block is the chorus");
                eq(b[1].lines[0].voice, "Sop", "parse: chorus voice tag");
                eq(b[1].lines[0].text, "Hail", "parse: chorus line text");
                eqInt(b[2].kind, HymnBook.KIND_VERSE, "parse: last block is a verse");
                eqInt(b[2].verse, 2, "parse: verse 2 number");
                eq(b[2].lines[0].text, "Second", "parse: verse 2 text");
            }

            var b2:Array = parseBody("4 Peace be within");
            eqInt(b2.length == 1 ? b2[0].verse : -2, 4, "parse: verse number without a dot");
            eq(b2.length == 1 ? b2[0].lines[0].text : "", "Peace be within", "parse: verse text after number");

            var b3:Array = parseBody("Chorus:\nSA: Behold\n\nTB: Behold, what manner");
            eqInt(b3.length, 1, "parse: voice tag after blank stays in the chorus");
            if (b3.length == 1) eqInt(b3[0].lines.length, 2, "parse: both chorus parts kept");

            var b4:Array = parseBody("Note: this is lyric text");
            eq(b4[0].lines[0].voice, null, "parse: non-voice prefix is a lyric");
            eq(b4[0].lines[0].text, "Note: this is lyric text", "parse: colon line kept whole");

            // ---- voice tags ----------------------------------------------------
            var tags:Array = ["S/A", "Alto/Ten/Bass", "Sop. Solo"];
            for (var t:int = 0; t < tags.length; t++)
            {
                var ln:Object = makeLine(tags[t] + ": la la");
                eq(ln.voice, tags[t], "voice tag: " + tags[t]);
            }
            if (!isChorusPrefixForTest("Full Chorus")) fails.push("voice tag: 'Full Chorus' reads as a chorus");

            // ---- dynamics ------------------------------------------------------
            var d1:Object = makeLine("mf AT the Name of Jesus");
            eq(d1.voice, null, "dynamic: no voice tag");
            eq(d1.text, "At the Name of Jesus", "dynamic: 'mf' split off, first word softened");
            eq(makeLine("p and so on").text, "p and so on", "dynamic: lowercase lyric not eaten");
            var d3:Object = makeLine("Sop: f Hail");
            eq(d3.voice, "Sop", "dynamic: after a voice tag (voice)");
            eq(d3.text, "Hail", "dynamic: after a voice tag (text)");

            // ---- first word ----------------------------------------------------
            eq(makeLine("ALL hail to Thee").text, "All hail to Thee", "soften: shouted first word");
            eq(makeLine("HALLELUJAH! HALLELUJAH!").text, "HALLELUJAH! HALLELUJAH!",
               "soften: shouting is kept");
            eq(makeLine("O come all ye faithful").text, "O come all ye faithful", "soften: 'O' untouched");

            // ---- verse numbering ------------------------------------------------
            var b5:Array = parseBody("First\n\nChorus:\nHail\n\n2. Second");
            eqInt(b5.length > 0 ? b5[0].verse : -2, 1, "verse numbering: first verse becomes 1");
            var b6:Array = parseBody("Only verse");
            eqInt(b6[0].verse, -1, "verse numbering: single verse stays unnumbered");

            // ---- search ---------------------------------------------------------
            var r:Array = HymnBook.search(hymns, "1");
            if (r.length == 0) fails.push("search: '1' finds something");
            else
            {
                eqInt(hymns[r[0]].number, 1, "search: exact number first");
                var allStartWithOne:Boolean = true;
                for (var k:int = 0; k < r.length; k++)
                {
                    if (String(hymns[r[k]].number).indexOf("1") != 0) allStartWithOne = false;
                }
                if (!allStartWithOne) fails.push("search: every '1' hit starts with 1");
            }
            var r500:Array = HymnBook.search(hymns, "500");
            eqInt(r500.length, 1, "search: '500' is one hymn");

            var rTitle:Array = HymnBook.search(hymns, "all hail");
            if (rTitle.length == 0) fails.push("search: 'all hail' finds something");
            else eqInt(hymns[rTitle[0]].number, 1, "search: a title hit outranks a lyric hit");

            if (HymnBook.search(hymns, "boundless love").length == 0) fails.push("search: lyric match");
            if (HymnBook.search(hymns, "zzzzqqq").length != 0) fails.push("search: nonsense finds nothing");
            eqInt(HymnBook.search(hymns, "").length, 1000, "search: empty query lists everything");

            return fails.length == 0 ? "" : fails.join(" | ");
        }

        // isChorusPrefix is private in HymnBook (it is an implementation detail at
        // the parse level); the case above needs it, so it is re-derived from the
        // public path: a "Full Chorus: ..." line must open a CHORUS block.
        private static function isChorusPrefixForTest(tag:String):Boolean
        {
            var b:Array = parseBody(tag + ": la la");
            return b.length == 1 && b[0].kind == HymnBook.KIND_CHORUS;
        }

        private static function parseBody(s:String):Array { return HymnBook.parseBody(s); }
        private static function makeLine(s:String):Object { return HymnBook.makeLine(s); }
        private static function titleCase(s:String):String { return HymnBook.titleCase(s); }

        private static function eq(got:*, want:*, label:String):void
        {
            if (got !== want) fails.push(label + " (got " + describe(got) + ", want " + describe(want) + ")");
        }

        private static function eqInt(got:int, want:int, label:String):void
        {
            if (got != want) fails.push(label + " (got " + got + ", want " + want + ")");
        }

        private static function describe(v:*):String
        {
            if (v == null) return "null";
            return "\"" + String(v) + "\"";
        }
    }
}

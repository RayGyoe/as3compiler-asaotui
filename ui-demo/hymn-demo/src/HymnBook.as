// hymn/HymnBook.as -- the hymn data: loading, lyric parsing and search.
//
// A direct port of the Rust original's `src/hymn.rs` (hymnbook f01beec). Keeping
// the parse identical matters more than it looks: the book is full of
// conventions a naive splitter gets wrong -- "2. Ye gates" starts a verse,
// "Chorus:" starts the chorus, "Sop: Hail" is a voice tag while "Note: ..." is
// a lyric, a bare "Hail" after a BLANK line still belongs to the chorus above
// it, and the first word is usually SHOUTED by the typesetter ("ALL hail").
// Every one of those has a test in the Rust original, and the same cases are
// pinned in probes here (see ui-demo/hymn-demo/HymnSelfTest.as).
//
// SHAPES (plain objects, not classes: this is data, and the demo never needs
// method dispatch over it):
//
//   hymn  { number:int, title:String, blocks:Array, titleKey:String,
//           fullKey:String, verseCount:int, hasChorus:Boolean,
//           firstLine:String, voiceParts:Array }
//   block { kind:int (KIND_VERSE | KIND_CHORUS), verse:int (-1 = unnumbered),
//           lines:Array }
//   line  { voice:String (null when the line has no voice tag), text:String }
package hymn
{
    public final class HymnBook
    {
        public static const KIND_VERSE:int = 0;
        public static const KIND_CHORUS:int = 1;

        // "a", "an", "and", ... stay lowercase inside a title unless they lead it.
        private static const SMALL:Array = ["a", "an", "and", "as", "at", "but", "for", "in",
                                            "of", "on", "or", "the", "to"];
        private static const VOICE_WORDS:Array = ["s", "a", "t", "b", "sop", "soprano", "alto",
                                                  "ten", "tenor", "bass", "atb", "tb", "sa", "sat",
                                                  "at", "sb", "st", "ab", "all", "gen", "duet",
                                                  "quartet", "parts", "unison", "harmony", "others"];
        private static const DYNAMICS:Array = ["f", "ff", "fff", "mf", "mp", "p", "pp", "ppp"];

        // ------------------------------------------------------------ loading

        // Parse every hymn in the generated blob. Malformed rows are skipped, like
        // the Rust original: one bad line must not cost the reader the other 999.
        public static function load():Array
        {
            var raw:Array = HymnData.RAW;
            var out:Array = [];
            for (var i:int = 0; i < raw.length; i++)
            {
                var rec:String = raw[i];
                var t1:int = rec.indexOf("\t");
                if (t1 < 0) continue;
                var t2:int = rec.indexOf("\t", t1 + 1);
                if (t2 < 0) continue;
                var numStr:String = rec.substring(0, t1);
                var title:String = rec.substring(t1 + 1, t2);
                var body:String = rec.substring(t2 + 1);
                var number:int = parseInt(numStr, 10);
                if (!(number > 0)) continue;

                var blocks:Array = parseBody(body);
                var titleKey:String = normalize(title);
                out.push({
                    number: number,
                    title: titleCase(title),
                    blocks: blocks,
                    titleKey: titleKey,
                    fullKey: titleKey + "\n" + normalize(body),
                    verseCount: countVerses(blocks),
                    hasChorus: hasChorus(blocks),
                    firstLine: firstLine(blocks),
                    voiceParts: voiceParts(blocks)
                });
            }
            out.sort(function (a:Object, b:Object):Number { return a.number - b.number; });
            return out;
        }

        public static function countVerses(blocks:Array):int
        {
            var n:int = 0;
            for (var i:int = 0; i < blocks.length; i++)
            {
                if (blocks[i].kind == KIND_VERSE) n++;
            }
            return n;
        }

        public static function hasChorus(blocks:Array):Boolean
        {
            for (var i:int = 0; i < blocks.length; i++)
            {
                if (blocks[i].kind == KIND_CHORUS) return true;
            }
            return false;
        }

        // The first non-empty lyric line: the library row's subtitle.
        public static function firstLine(blocks:Array):String
        {
            for (var i:int = 0; i < blocks.length; i++)
            {
                var lines:Array = blocks[i].lines;
                for (var j:int = 0; j < lines.length; j++)
                {
                    var t:String = lines[j].text;
                    if (t != null && t.length > 0) return t;
                }
            }
            return "";
        }

        // Distinct voice tags in order of first appearance, e.g. ["Sop","ATB"].
        public static function voiceParts(blocks:Array):Array
        {
            var out:Array = [];
            for (var i:int = 0; i < blocks.length; i++)
            {
                var lines:Array = blocks[i].lines;
                for (var j:int = 0; j < lines.length; j++)
                {
                    var v:String = lines[j].voice;
                    if (v != null && v.length > 0 && out.indexOf(v) < 0) out.push(v);
                }
            }
            return out;
        }

        // ------------------------------------------------------------ parsing

        // Split a body into verse/chorus blocks. Faithful to the Rust original,
        // including the two rules that are easy to get wrong:
        //   * a voice-tagged line after a BLANK line stays in the block above it
        //     (choruses are often split by blank lines between parts);
        //   * verse 1 is usually unnumbered in the book, and is labelled only when
        //     a later verse IS numbered, so the reader's gutter reads 1,2,3.
        public static function parseBody(body:String):Array
        {
            var blocks:Array = [];
            var afterBlank:Boolean = true;
            var lines:Array = body.split("\n");
            for (var i:int = 0; i < lines.length; i++)
            {
                var s:String = trim(lines[i]);
                if (s.length == 0)
                {
                    afterBlank = true;
                    continue;
                }

                var sp:Array = splitPrefix(s);
                if (sp != null && isChorusPrefix(sp[0]))
                {
                    var cb:Object = { kind: KIND_CHORUS, verse: -1, lines: [] };
                    if (sp[1].length > 0) cb.lines.push(makeLine(sp[1]));
                    blocks.push(cb);
                    afterBlank = false;
                    continue;
                }

                var vn:Array = splitVerseNumber(s);
                if (vn != null)
                {
                    var vb:Object = { kind: KIND_VERSE, verse: int(vn[0]), lines: [] };
                    if (vn[1].length > 0) vb.lines.push(makeLine(vn[1]));
                    blocks.push(vb);
                    afterBlank = false;
                    continue;
                }

                var line:Object = makeLine(s);
                var last:Object = blocks.length > 0 ? blocks[blocks.length - 1] : null;
                if (last != null && (!afterBlank || line.voice != null))
                {
                    last.lines.push(line);
                }
                else
                {
                    blocks.push({ kind: KIND_VERSE, verse: -1, lines: [line] });
                }
                afterBlank = false;
            }

            // Verse 1 is unnumbered in the book; label it when verse 2 exists.
            var hasSecond:Boolean = false;
            for (var k:int = 0; k < blocks.length; k++)
            {
                if (blocks[k].kind == KIND_VERSE && blocks[k].verse == 2) hasSecond = true;
            }
            if (hasSecond)
            {
                // Only inside the prefix BEFORE the first explicitly numbered verse
                // (the Rust original's take_while): an already-numbered verse keeps
                // its number.
                for (var m:int = 0; m < blocks.length; m++)
                {
                    var bm:Object = blocks[m];
                    if (bm.kind != KIND_VERSE) continue;
                    if (bm.verse != -1) break;
                    bm.verse = 1;
                    break;
                }
            }
            return blocks;
        }

        public static function makeLine(text:String):Object
        {
            var voice:String = null;
            var rest:String = text;
            var sp:Array = splitPrefix(text);
            if (sp != null && isVoicePrefix(sp[0]))
            {
                voice = trim(sp[0]);
                rest = sp[1];
            }
            var dyn:Array = splitDynamic(rest);
            rest = dyn[1];
            return { voice: voice, text: softenFirstWord(rest) };
        }

        // "Prefix: rest", only when the colon is near the start (a long line that
        // happens to contain a colon is a lyric, not a tag).
        private static function splitPrefix(s:String):Array
        {
            var idx:int = s.indexOf(":");
            if (idx < 0 || idx > 18) return null;
            return [s.substring(0, idx), trim(s.substring(idx + 1))];
        }

        private static function isVoicePrefix(prefix:String):Boolean
        {
            var any:Boolean = false;
            var toks:Array = prefix.split("/");
            for (var i:int = 0; i < toks.length; i++)
            {
                var sub:Array = toks[i].split(".");
                for (var j:int = 0; j < sub.length; j++)
                {
                    var more:Array = sub[j].split(" ");
                    for (var k:int = 0; k < more.length; k++)
                    {
                        var comma:Array = more[k].split(",");
                        for (var m:int = 0; m < comma.length; m++)
                        {
                            var tok:String = trim(comma[m]);
                            if (tok.length == 0) continue;
                            var t:String = tok.toLowerCase();
                            if (t == "solo" || VOICE_WORDS.indexOf(t) >= 0) any = true;
                            else return false;
                        }
                    }
                }
            }
            return any;
        }

        private static function isChorusPrefix(prefix:String):Boolean
        {
            var p:String = trim(prefix).toLowerCase();
            // "Chorus 2" / "Chorus 2 " -> "chorus"
            var end:int = p.length;
            while (end > 0)
            {
                var ch:String = p.charAt(end - 1);
                var code:int = p.charCodeAt(end - 1);
                if ((code >= 48 && code <= 57) || ch == " ") end--;
                else break;
            }
            p = p.substring(0, end);
            return p == "chorus" || p == "refrain" || p == "cho" || p == "full chorus"
                || p == "cho." || p == "ref";
        }

        // "2. Ye gates" / "4 Peace be" / "3" -> [2, "Ye gates"]
        private static function splitVerseNumber(s:String):Array
        {
            var digits:int = 0;
            while (digits < s.length)
            {
                var c:int = s.charCodeAt(digits);
                if (c >= 48 && c <= 57) digits++;
                else break;
            }
            if (digits == 0 || digits > 2) return null;
            var n:int = parseInt(s.substring(0, digits), 10);
            var rest:String = s.substring(digits);
            if (rest.length == 0) return [n, ""];
            var c0:String = rest.charAt(0);
            if (c0 == "." || c0 == ")") return [n, trim(rest.substring(1))];
            if (isSpace(c0)) return [n, trim(rest)];
            return null;
        }

        // "mf AT the Name" -> [mf, "AT the Name"], but only in front of a
        // capitalised word so real lyrics are never eaten.
        private static function splitDynamic(s:String):Array
        {
            var sp:int = s.indexOf(" ");
            if (sp > 0)
            {
                var first:String = s.substring(0, sp);
                var rest:String = trim(s.substring(sp + 1));
                if (DYNAMICS.indexOf(first) >= 0 && rest.length > 0 && isUpper(rest.charAt(0)))
                {
                    return [first, rest];
                }
            }
            return [null, s];
        }

        // "ALL hail to Thee" -> "All hail to Thee". The book shouts the first word;
        // needs a following word with a lowercase letter so "HALLELUJAH!
        // HALLELUJAH!" and a lone "I"/"O" are untouched.
        private static function softenFirstWord(s:String):String
        {
            var sp:int = s.indexOf(" ");
            if (sp < 0) return s;
            var first:String = s.substring(0, sp);
            var rest:String = s.substring(sp + 1);
            var letters:int = 0;
            var shouting:Boolean = true;
            for (var i:int = 0; i < first.length; i++)
            {
                var ch:String = first.charAt(i);
                if (!isAlpha(ch)) continue;
                letters++;
                if (!isUpper(ch)) shouting = false;
            }
            if (!shouting || letters < 2) return s;

            var nextWord:String = rest.indexOf(" ") >= 0 ? rest.substring(0, rest.indexOf(" ")) : rest;
            var nextLower:Boolean = false;
            for (var j:int = 0; j < nextWord.length; j++)
            {
                if (isLower(nextWord.charAt(j))) { nextLower = true; break; }
            }
            if (!nextLower) return s;
            return capitalizeWord(first.toLowerCase()) + " " + rest;
        }

        // ------------------------------------------------------------ titles

        // "ALL HAIL, IMMANUEL!" -> "All Hail, Immanuel!"
        public static function titleCase(s:String):String
        {
            var words:Array = s.split(" ");
            var out:String = "";
            var first:Boolean = true;
            for (var i:int = 0; i < words.length; i++)
            {
                if (i > 0) out += " ";
                var lower:String = words[i].toLowerCase();
                var bare:String = "";
                for (var j:int = 0; j < lower.length; j++)
                {
                    var ch:String = lower.charAt(j);
                    if (isAlpha(ch)) bare += ch;
                }
                if (!first && SMALL.indexOf(bare) >= 0) out += lower;
                else out += capitalizeWord(lower);
                if (bare.length > 0) first = false;
            }
            return out;
        }

        // Capitalise the first letter and any letter after - or ( or ". Letters
        // after an apostrophe stay lowercase ("Thy", "Ev'ry", "Jesus'").
        private static function capitalizeWord(w:String):String
        {
            var out:String = "";
            var up:Boolean = true;
            for (var i:int = 0; i < w.length; i++)
            {
                var c:String = w.charAt(i);
                if (isAlpha(c) && up)
                {
                    out += c.toUpperCase();
                    up = false;
                }
                else
                {
                    out += c;
                }
                if (c == "-" || c == "(" || c == "\"" || charCode(c) == 0x201C) up = true;
            }
            return out;
        }

        // Lowercase + straight quotes: "Thy" and "Thy" (curly) must match the same
        // way they do in the book.
        public static function normalize(s:String):String
        {
            var out:String = "";
            for (var i:int = 0; i < s.length; i++)
            {
                var c:String = s.charAt(i);
                var code:int = s.charCodeAt(i);
                if (code == 0x2019 || code == 0x2018) out += "'";
                else if (code == 0x201C || code == 0x201D) out += "\"";
                else out += c;
            }
            return out.toLowerCase();
        }

        // ------------------------------------------------------------ search

        // Indices into `hymns` matching `query`, best first.
        //   * empty: everything, in number order
        //   * digits only: numbers that START with it, exact first
        //   * otherwise: every word must appear in the title or the lyrics, and a
        //     title hit outranks a lyric hit
        public static function search(hymns:Array, query:String):Array
        {
            var q:String = normalize(trim(query));
            var out:Array = [];
            var i:int;
            if (q.length == 0)
            {
                for (i = 0; i < hymns.length; i++) out.push(i);
                return out;
            }

            var digitsOnly:Boolean = true;
            for (i = 0; i < q.length; i++)
            {
                var c:int = q.charCodeAt(i);
                if (c < 48 || c > 57) { digitsOnly = false; break; }
            }
            if (digitsOnly)
            {
                var hits:Array = [];
                for (i = 0; i < hymns.length; i++)
                {
                    var ns:String = String(hymns[i].number);
                    if (ns.indexOf(q) == 0) hits.push(i);
                }
                // Exact match first, then by number. (The Rust original sorts on
                // (number != q, number); same ordering, spelled out.)
                hits.sort(function (a:int, b:int):Number
                {
                    var ea:int = String(hymns[a].number) == q ? 0 : 1;
                    var eb:int = String(hymns[b].number) == q ? 0 : 1;
                    if (ea != eb) return ea - eb;
                    return hymns[a].number - hymns[b].number;
                });
                return hits;
            }

            var terms:Array = [];
            var parts:Array = q.split(" ");
            for (i = 0; i < parts.length; i++)
            {
                if (parts[i].length > 0) terms.push(parts[i]);
            }

            var ranked:Array = [];
            for (i = 0; i < hymns.length; i++)
            {
                var h:Object = hymns[i];
                var all:Boolean = true;
                for (var t:int = 0; t < terms.length; t++)
                {
                    if (h.fullKey.indexOf(terms[t]) < 0) { all = false; break; }
                }
                if (!all) continue;
                var rank:int = 2;
                if (h.titleKey.indexOf(q) == 0) rank = 0;
                else
                {
                    var titleAll:Boolean = true;
                    for (var u:int = 0; u < terms.length; u++)
                    {
                        if (h.titleKey.indexOf(terms[u]) < 0) { titleAll = false; break; }
                    }
                    if (titleAll) rank = 1;
                }
                ranked.push({ rank: rank, ix: i });
            }
            ranked.sort(function (a:Object, b:Object):Number
            {
                if (a.rank != b.rank) return a.rank - b.rank;
                return hymns[a.ix].number - hymns[b.ix].number;
            });
            for (i = 0; i < ranked.length; i++) out.push(ranked[i].ix);
            return out;
        }

        // ------------------------------------------------------------ char classes

        // ASCII whitespace, which is what the book contains. Rust's `trim` is
        // Unicode-aware; a non-breaking space would differ, and none appear in
        // this corpus (checked when the port was written).
        public static function isSpace(c:String):Boolean
        {
            return c == " " || c == "\t" || c == "\n" || c == "\r";
        }

        // A letter, for the purposes of capitalisation. Everything from Latin-1
        // up counts: the book's accented words must keep their accents when
        // capitalised, and treating them as "not a letter" would leave "É" alone
        // in a title that should read "É".
        public static function isAlpha(c:String):Boolean
        {
            if (c.length == 0) return false;
            var code:int = c.charCodeAt(0);
            if ((code >= 65 && code <= 90) || (code >= 97 && code <= 122)) return true;
            return code >= 0xC0;
        }

        public static function isUpper(c:String):Boolean
        {
            if (!isAlpha(c)) return false;
            return c.toUpperCase() == c && c.toLowerCase() != c;
        }

        public static function isLower(c:String):Boolean
        {
            if (!isAlpha(c)) return false;
            return c.toLowerCase() == c && c.toUpperCase() != c;
        }

        private static function charCode(c:String):int
        {
            return c.length == 0 ? -1 : c.charCodeAt(0);
        }

        public static function trim(s:String):String
        {
            var a:int = 0;
            var b:int = s.length;
            while (a < b && isSpace(s.charAt(a))) a++;
            while (b > a && isSpace(s.charAt(b - 1))) b--;
            return a == 0 && b == s.length ? s : s.substring(a, b);
        }
    }
}

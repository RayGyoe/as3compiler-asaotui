// asaot.ui.I18n -- the message catalog and the effective UI locale.
//
// WHY THIS SHAPE (and not a `msgKey` field on Node)
// -------------------------------------------------
// Text in this kit is a STRING PAYLOAD: `TextNode.content`, mirrored onto the
// retained node by TextWidget.payload (kind/TextWidget.as), which compares by
// value and raises a re-measure only when it changes. Fifty factories take a
// plain `String` (text/label/button/placeholder/...), and every one of them
// already works if the author resolves the message BEFORE calling the factory:
//     text(I18n.t("app.welcome"))
// Putting a key on the node instead would push i18n knowledge into every widget
// kind, into measure (intrinsic width) and into paint (the displayed run) -- two
// more places to get wrong -- for no capability the string form lacks.
//
// THE EPOCH, AND WHY IT IS NOT A Dirty BIT
// ---------------------------------------
// A locale change has to reach the next frame as "re-describe"; that is exactly
// what Theme.themeEpoch() does for a palette swap and how UiApp.onEnterFrame
// consumes it. This class mirrors that pattern with its own counter, because the
// two events are different: a theme swap must ALSO re-resolve every node's style
// (Theme marks nodes stale), while a locale swap only changes payload strings --
// TextWidget.payload then raises measure/arrange/paint by itself
// (UiNode.applyPayload). `Dirty.ALL` is 15 and 16/32/64 are the pass bits, so a
// new "locale" bit would have to renumber the vocabulary; the honest value is
// Dirty.VALUE -- the app-level input these strings are computed from changed.
//
// ZERO ALLOCATION ON THE STEADY PATH
// ----------------------------------
// `t(key)` with no params returns the String INSTANCE stored in the catalog, so
// a re-describe compares two identical pointers' contents and allocates nothing.
// Only a message with placeholders builds a new string, and that cost is the
// same `+` concatenation it replaces -- so there is no cache here. A per-frame
// cache keyed by (key, params) would be a global table whose size follows the
// DATA, which is the unbounded-growth shape the memo contract forbids; if a view
// really needs it, View.memo is the bounded place.
//
// MISSING KEYS ARE NEVER SILENT
// -----------------------------
// `t()` returns the visible marker `[[key]]`, records the key in missingKeys(),
// and (optionally) throws when setStrict(true). A probe asserts the list is
// empty after exercising the UI, so "not translated" shows up as a red gate
// rather than as an app that quietly renders English (or the raw key) in a
// Chinese window.
package asaot.ui
{
    public final class I18n
    {
        // locale tags (lowercased) -> { key -> String }
        private static var _catalogs:Object;
        // The lookup order for the CURRENT locale, PRE-BUILT: building it per
        // lookup would allocate an Array per string per describe.
        private static var _chain:Array;
        private static var _locale:String;
        private static var _default:String;
        private static var _epoch:int;
        private static var _missing:Object;
        private static var _missingList:Array;
        private static var _strict:Boolean;
        private static var _initialized:Boolean;

        // Languages whose script runs right-to-left. A static list, not a guess
        // from the tag: this is DATA, and an unknown language is LTR.
        private static const RTL_LANGS:Array = ["ar", "he", "fa", "ur", "ps", "sd",
            "ug", "yi", "dv", "ckb"];

        // Languages with a single plural form for counts (CLDR "other" only).
        private static const OTHER_ONLY_LANGS:Array = ["zh", "ja", "ko", "vi", "th",
            "id", "ms", "lo", "my", "km"];

        // Languages with one/other on exactly n == 1.
        private static const ONE_OTHER_LANGS:Array = ["en", "de", "nl", "sv", "da",
            "no", "fi", "es", "it", "pt", "el", "he", "hu", "tr", "bg", "ca", "eu",
            "af", "et"];

        // ---- setup --------------------------------------------------------

        // Lazily installs the kit's own messages (KitMessages) and the defaults.
        // Every public entry point calls this first, so an app that never
        // configures anything still gets localized kit strings at the default
        // locale -- the same "honest floor" rule as DesktopEnv.
        private static function ensure():void
        {
            if (_initialized) return;
            _epoch = 0;
            reset();
        }

        // Back to the shipped state: every app catalog dropped, the kit's own
        // messages reinstalled, locale = default = "en". FOR TESTS AND PROBES --
        // an app has no reason to un-translate itself at run time.
        public static function reset():void
        {
            _initialized = true;
            _catalogs = {};
            _locale = "en";
            _default = "en";
            _missing = {};
            _missingList = [];
            _strict = false;
            _epoch = _epoch + 1;
            addMessages("en", KitMessages.en());
            addMessages("zh-CN", KitMessages.zhCN());
            rebuildChain();
        }

        // Merge a per-locale table. CALLED FOR EVERY SHIPPED LOCALE AT STARTUP and
        // for an app's own copy; later registrations win for the keys they
        // contain (per locale), which is how an app overrides one kit string
        // without replacing the whole catalog.
        //
        // Bumps the epoch: registering a catalog can change what the CURRENT
        // locale renders, and that must reach the next frame like any setLocale.
        public static function addMessages(locale:String, table:Object):void
        {
            if (table == null)
            {
                throw new Error('asaot.ui: I18n.addMessages("' + locale + '", null) -- '
                    + 'pass an object of key -> string');
            }
            var tag:String = normalize(locale);
            if (tag == "")
            {
                throw new Error('asaot.ui: I18n.addMessages("", table) -- a catalog needs a '
                    + 'locale tag ("en", "zh-CN", ...)');
            }
            ensure();
            // STORED LOWERCASED: the lookup chain is lowercased, so an app may
            // register "zh-cn" and setLocale("zh-CN") still finds it. Two catalogs
            // that differ only in case are therefore the SAME catalog (and merge),
            // which is the only sane answer -- "zh-CN" is one locale, not two.
            var key:String = tag.toLowerCase();
            var cat:Object = _catalogs[key];
            if (cat == null)
            {
                cat = {};
                _catalogs[key] = cat;
            }
            for (var k:String in table) cat[k] = table[k];
            _epoch = _epoch + 1;
        }

        // The locale every fallback ends at. Changing it re-points the chain, so a
        // window whose system locale is "de-CH" (no catalog) still shows the app's
        // default text instead of markers.
        public static function setDefault(tag:String):void
        {
            ensure();
            var t:String = normalize(tag);
            if (t == "") throw new Error('asaot.ui: I18n.setDefault("") -- pass a locale tag');
            if (t == _default) return;
            _default = t;
            _epoch = _epoch + 1;
            rebuildChain();
        }

        // The effective UI locale. Changing it does NOT redraw: the epoch moves and
        // UiApp turns that into a describe at the next frame boundary (the same
        // latched discipline as Env notifications -- a platform callback may arrive
        // outside the frame, and text must not be re-measured there).
        //
        // An UNKNOWN tag is legal: the chain falls back per key and every key that
        // ends up unresolvable renders as [[key]] + a missingKeys() entry, so an
        // app that ships 3 of its 6 locales is visibly incomplete, not silently
        // English.
        public static function setLocale(tag:String):void
        {
            ensure();
            var t:String = normalize(tag);
            if (t == "") throw new Error('asaot.ui: I18n.setLocale("") -- pass a locale tag');
            if (t == _locale) return;
            _locale = t;
            _epoch = _epoch + 1;
            rebuildChain();
        }

        // "Follow the platform": set the locale from the Env now and on every
        // change until the returned Subscription is cancelled. EXPLICIT, not
        // automatic: the library must not re-language an app behind its author's
        // back (the same reason `UiApp.bindEnv(null)` throws instead of guessing).
        // An empty Env.locale (EnvBase's neutral default) is ignored.
        //
        // THE LISTENER IS A STATIC FUNCTION, not a closure over `env`: the AOT's
        // closure capture boxes an interface-typed variable by VALUE, and its GC
        // marker then casts that struct to `void*` -- the build fails at
        // `gc_mark_ptr((void*)e->env)` (compiler-gaps G37). Reading a static field
        // is also the cheaper shape: subscribing allocates nothing.
        public static function followEnv(env:Env):Subscription
        {
            if (env == null)
            {
                throw new Error('asaot.ui: I18n.followEnv(null) -- an app always has an Env');
            }
            ensure();
            _env = env;
            var first:String = env.locale;
            if (first != null && first != "") setLocale(first);
            return env.subscribe(onEnvChanged);
        }

        // The Env being followed (null until followEnv). A STATIC because a
        // Subscription is not a place to keep state: cancel() must leave nothing to
        // read, and UiApp owns the only other subscriber.
        private static var _env:Env;

        private static function onEnvChanged(d:int):void
        {
            if (_env == null) return;
            var tag:String = _env.locale;
            if (tag != null && tag != "") setLocale(tag);
        }

        // ---- reading ------------------------------------------------------

        public static function locale():String
        {
            ensure();
            return _locale;
        }

        public static function defaultLocale():String
        {
            ensure();
            return _default;
        }

        // Changes on setLocale/setDefault/addMessages/reset. UiApp compares it once
        // per frame; a memo slot compares it on every hit.
        public static function epoch():int
        {
            ensure();
            return _epoch;
        }

        public static function isRTL():Boolean
        {
            ensure();
            return inList(RTL_LANGS, primary(_locale));
        }

        public static function has(key:String):Boolean
        {
            ensure();
            return lookup(key) != null;
        }

        // `{name}` placeholders, single pass, no RegExp (the regex engine is for
        // the author's patterns, not for the library's own formatting).
        //
        // With `params == null` the catalog's own String is returned UNCHANGED and
        // un-copied -- the steady-state path allocates nothing.
        public static function t(key:String, params:Object = null):String
        {
            ensure();
            var v:String = lookup(key);
            if (v == null) v = markMissing(key);
            if (params == null) return v;
            return interpolate(v, params, 0, false);
        }

        // Plural-aware lookup. Category selection is a small explicit table, NOT
        // CLDR: this kit supports the languages it ships, everything else gets
        // "other" (a catalog may still provide `key#other`).
        //
        //     "cart.items#one":   "1 item"
        //     "cart.items#other": "{n} items"
        //
        // `{n}` is filled from the count unless `params` defines its own `n`.
        public static function tn(key:String, n:Number, params:Object = null):String
        {
            ensure();
            var cat:String = pluralCategory(n);
            var v:String = lookup(key + "#" + cat);
            if (v == null && cat != "other") v = lookup(key + "#other");
            if (v == null) v = lookup(key);
            if (v == null) v = markMissing(key);
            return interpolate(v, params, n, true);
        }

        // Grouped / fixed-decimal number text. `decimals < 0` keeps the number's
        // own text (no rounding). Separators come from the catalog
        // (`kit.number.group` / `kit.number.decimal`), so a locale that groups with
        // "." and separates with "," needs no code change.
        public static function number(v:Number, decimals:int = -1, grouping:Boolean = true):String
        {
            ensure();
            var grp:String = opt("kit.number.group", ",");
            var dec:String = opt("kit.number.decimal", ".");
            var neg:Boolean = v < 0;
            var a:Number = neg ? -v : v;
            var s:String = decimals >= 0 ? a.toFixed(decimals) : String(a);
            // Exponent / NaN / Infinity: not a plain digit run -- leave it alone
            // rather than grouping characters inside "1e+21".
            if (s.indexOf("e") >= 0 || s.indexOf("E") >= 0 || !allDigits(s))
            {
                return (neg ? "-" : "") + s;
            }
            var dot:int = s.indexOf(".");
            var ip:String = dot < 0 ? s : s.substring(0, dot);
            var fp:String = dot < 0 ? null : s.substring(dot + 1);
            return (neg ? "-" : "") + (grouping ? group3(ip, grp) : ip)
                + (fp == null ? "" : dec + fp);
        }

        // The keys `t()` could not resolve, in first-seen order. A probe asserts
        // this is empty after rendering every localized surface.
        public static function missingKeys():Array
        {
            ensure();
            var out:Array = [];
            for (var i:int = 0; i < _missingList.length; i++) out.push(_missingList[i]);
            return out;
        }

        public static function clearMissing():void
        {
            ensure();
            _missing = {};
            _missingList = [];
        }

        public static function setStrict(v:Boolean):void
        {
            ensure();
            _strict = v;
        }

        // ---- lookup machinery ---------------------------------------------

        private static function lookup(key:String):String
        {
            if (key == null) return null;
            for (var i:int = 0; i < _chain.length; i++)
            {
                var cat:Object = _catalogs[_chain[i]];
                if (cat == null) continue;
                var v:Object = cat[key];
                if (v != null) return String(v);
            }
            return null;
        }

        // Internal data (separators, first-day-of-week) whose absence is not an
        // app-visible gap: a missing `kit.number.group` must not add a
        // `[[kit.number.group]]` to missingKeys().
        private static function opt(key:String, fallback:String):String
        {
            var v:String = lookup(key);
            return v != null ? v : fallback;
        }

        private static function markMissing(key:String):String
        {
            var text:String = "[[" + key + "]]";
            if (_missing[key] == null)
            {
                _missing[key] = true;
                _missingList.push(key);
            }
            if (_strict)
            {
                throw new Error('asaot.ui: missing i18n key "' + key + '" in locale "'
                    + _locale + '" (fallbacks: ' + _chain.join(" -> ") + ')');
            }
            return text;
        }

        // locale -> ["zh-hant-tw", "zh-hant", "zh", <default chain>]
        private static function rebuildChain():void
        {
            var out:Array = [];
            pushChain(out, _locale);
            pushChain(out, _default);
            _chain = out;
        }

        private static function pushChain(out:Array, tag:String):void
        {
            var t:String = tag;
            while (t != null && t != "")
            {
                var low:String = t.toLowerCase();
                if (!inList(out, low)) out.push(low);
                var d:int = lastDash(t);
                if (d < 0) return;
                t = t.substring(0, d);
            }
        }

        // "zh_TW" -> "zh-TW"; separators are unified, CASE IS KEPT for display.
        // Matching is case-insensitive because the chain is lowercased, so an app
        // may register "zh-cn" and still be found by setLocale("zh-CN").
        private static function normalize(tag:String):String
        {
            if (tag == null) return "";
            var out:String = "";
            var i:int = 0;
            while (i < tag.length)
            {
                var ch:String = tag.charAt(i);
                i = i + 1;
                if (ch == " ") continue;          // " zh-CN " is the same locale
                out = out + (ch == "_" ? "-" : ch);
            }
            return out;
        }

        private static function primary(tag:String):String
        {
            var d:int = tag.indexOf("-");
            return (d < 0 ? tag : tag.substring(0, d)).toLowerCase();
        }

        private static function lastDash(s:String):int
        {
            var found:int = -1;
            for (var i:int = 0; i < s.length; i++)
            {
                if (s.charAt(i) == "-") found = i;
            }
            return found;
        }

        private static function inList(a:Array, v:String):Boolean
        {
            for (var i:int = 0; i < a.length; i++)
            {
                if (String(a[i]) == v) return true;
            }
            return false;
        }

        // ---- formatting ---------------------------------------------------

        private static function interpolate(tmpl:String, params:Object, n:Number,
                                            hasN:Boolean):String
        {
            if (tmpl.indexOf("{") < 0) return tmpl;
            var out:String = "";
            var seg:int = 0;
            var i:int = 0;
            var len:int = tmpl.length;
            while (i < len)
            {
                if (tmpl.charAt(i) != "{") { i = i + 1; continue; }
                var j:int = i + 1;
                while (j < len && tmpl.charAt(j) != "}") j = j + 1;
                if (j >= len) break;    // unmatched brace: literal text
                out = out + tmpl.substring(seg, i);
                var name:String = tmpl.substring(i + 1, j);
                var rep:String = null;
                if (params != null)
                {
                    var given:Object = params[name];
                    if (given != null) rep = String(given);
                }
                // `{n}` is filled from the count only when the caller did not
                // supply its own -- so a catalog can keep the raw input.
                if (rep == null && hasN && name == "n") rep = String(n);
                if (rep == null) rep = "{" + name + "}";   // visible, never dropped
                out = out + rep;
                seg = j + 1;
                i = j + 1;
            }
            return out + tmpl.substring(seg);
        }

        private static function pluralCategory(n:Number):String
        {
            var i:Number = n < 0 ? -n : n;
            if (i != Math.floor(i)) return "other";     // fractions are always "other"
            var lang:String = primary(_locale);
            if (inList(OTHER_ONLY_LANGS, lang)) return "other";
            if (inList(ONE_OTHER_LANGS, lang)) return i == 1 ? "one" : "other";
            if (lang == "fr") return (i == 0 || i == 1) ? "one" : "other";
            var m10:int = int(i) % 10;
            var m100:int = int(i) % 100;
            if (lang == "ru" || lang == "uk" || lang == "be")
            {
                if (m10 == 1 && m100 != 11) return "one";
                if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return "few";
                return "many";
            }
            if (lang == "pl")
            {
                if (m10 == 1 && m100 != 11) return "one";
                if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return "few";
                return "many";
            }
            if (lang == "cs" || lang == "sk")
            {
                if (i == 1) return "one";
                if (i >= 2 && i <= 4) return "few";
                return "other";
            }
            if (lang == "ar")
            {
                if (i == 0) return "zero";
                if (i == 1) return "one";
                if (i == 2) return "two";
                if (m100 >= 3 && m100 <= 10) return "few";
                if (m100 >= 11 && m100 <= 99) return "many";
                return "other";
            }
            return "other";
        }

        private static function group3(digits:String, sep:String):String
        {
            var n:int = digits.length;
            if (n <= 3) return digits;
            var out:String = "";
            var i:int = n;
            while (i > 0)
            {
                var start:int = i - 3;
                if (start < 0) start = 0;
                var part:String = digits.substring(start, i);
                out = (out == "" ? part : part + sep + out);
                i = start;
            }
            return out;
        }

        // A digit run with at most one "." -- the only shape group3 may touch.
        private static function allDigits(s:String):Boolean
        {
            var seenDot:Boolean = false;
            for (var i:int = 0; i < s.length; i++)
            {
                var c:String = s.charAt(i);
                if (c == "." && !seenDot) { seenDot = true; continue; }
                if (c < "0" || c > "9") return false;
            }
            return s.length > 0;
        }

        public function I18n() { }
    }
}

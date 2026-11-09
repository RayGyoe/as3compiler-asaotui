// demo/DemoText.as -- the docs app's own prose, looked up by its ENGLISH TEXT.
//
// WHY THE ENGLISH IS THE KEY
// --------------------------
// The docs app shows ~680 display strings that are written INLINE, next to the live
// demo and the source snippet they describe (267 section headings, their
// paragraphs, 60 page blurbs, and the shell's own labels). Two ways to localize it:
//
//   (a) invent a key per string (`demo.box.s3.p2`) and wrap every literal at the
//       call site, or
//   (b) keep the sentence itself as the key, and keep the translations in a table.
//
// (b), here. A heading is written once, where it is read; a translator sees the
// sentence they are translating; and a lookup is ONE dictionary read with no string
// building -- the source literal IS the key instance, so the steady path allocates
// nothing. That last property is not decoration: these strings are resolved on
// every describe, and the describe path is the one the perf probe measures.
//
// The price of (b) is that a MISS is silent -- an untranslated line would just stay
// English. That is paid at BUILD time instead of at run time:
// `tools/demo-i18n.cjs` extracts every display string from `demo/*.as` and fails if
// `DemoMessages.zh()` does not cover it (and fails on a stale row too). So this
// table cannot rot quietly, and nothing here has to throw at run time.
//
// WHY NOT I18n.t() DIRECTLY: `I18n` keys are short identifiers and its `t()` is
// built for them. The demo uses BOTH -- this table for prose, real I18n keys
// (`demo.meta`, `demo.foot`, `demo.items`) for the parameterized chrome, because
// `{placeholder}` filling and plurals are exactly what I18n already does and a
// second implementation here would be a second thing to get wrong.
//
// THE LOCALE COMES FROM I18n, THE TABLE IS REBUILT ON ITS EPOCH. A switch is a
// frame-boundary event: `UiApp` turns the epoch into one describe, and the first
// lookup of that describe rebuilds the table once. Between switches this class is
// two reads (epoch compare, dictionary hit).
package demo
{
    import asaot.ui.I18n;

    public final class DemoText
    {
        // The epoch the current table was built for. -1 = never built.
        private static var _epoch:int = -1;
        // english -> translated, or null when the current locale needs no table
        // (the demo ships exactly one translation; anything else reads English).
        private static var _dict:Object;
        private static var _installed:Boolean;
        private static var _locale:String = "";

        // Called once from the first lookup, and by DocsView so the shell's keys are
        // registered even on a page that has no sections.
        public static function ensure():void
        {
            if (_installed) return;
            _installed = true;
            DemoMessages.install();
            // Read the epoch AFTER installing: addMessages bumps it.
            _epoch = -1;
        }

        // The locale whose table is loaded (for the docs page that explains this).
        public static function table():String
        {
            refresh();
            return _dict == null ? "" : _locale;
        }

        // One display string. Returns the SOURCE string itself when there is no
        // table or no row -- an untranslated line stays readable, and the build gate
        // is what guarantees no row is ever missing.
        public static function t(s:String):String
        {
            if (s == null) return null;
            if (I18n.epoch() != _epoch) refresh();
            var d:Object = _dict;
            if (d == null) return s;
            var v:Object = d[s];
            return v == null ? s : String(v);
        }

        private static function refresh():void
        {
            ensure();
            _epoch = I18n.epoch();
            _locale = I18n.locale().toLowerCase();
            _dict = DemoMessages.table(_locale);
        }
    }
}

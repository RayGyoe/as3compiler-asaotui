// demo/DocsI18n.as -- the `i18n` page: message catalogs, the locale epoch, plurals,
// number grouping, and the one layout input a locale changes (RTL).
//
// WHY ITS OWN FILE, not another branch of DocsSystem: the other six framework pages
// are about the LAYOUT and the model (style, theme, state, events, keyboard, env).
// This one is about the TEXT, and it is the only page whose subject is also the thing
// that renders it -- every live part below reads the running catalog, so switching the
// language with the buttons at the bottom of the index changes this page's own words,
// plural form and digit grouping. A page that could go stale against its own library
// would be the worst page to ship.
//
// THE DEMO LABELS ARE NOT TRANSLATED, on purpose: `text("hello")` inside a builder is
// the sample data, and the code block beside it shows the same literal. Translating
// one side of that pair would make the visible source disagree with the visible result.
package demo
{
    import asaot.ui.I18n;
    import asaot.ui.Node;
    import asaot.ui.button;
    import asaot.ui.chip;
    import asaot.ui.column;
    import asaot.ui.row;
    import asaot.ui.text;
    import asaot.ui.style.StyleRefinement;

    public final class DocsI18n
    {
        private static const MONO:StyleRefinement = DocsDemo.MONO;
        private static const LABEL:StyleRefinement = DocsDemo.LABEL;

        public static function sections(view:DocsView, id:String):Array
        {
            if (id != "i18n") return null;
            return [
                new DocSection("Text is a payload, not a field", [
                    "A localized string is resolved BEFORE the factory is called: `text(I18n.t(\"demo.greet\"))`. Nothing in the tree knows what a message key is, and no widget grew a `msgKey` field for it. That is deliberate -- measure reads an intrinsic width and paint reads the displayed run, so a key on the node would push catalog knowledge into two more places and buy nothing the string form lacks.",
                    "`t()` with no parameters returns the String INSTANCE stored in the catalog, so a re-describe compares text by pointer and allocates nothing. Only a message carrying `{placeholders}` builds a new string."
                ], [
                    "text(I18n.t(\"demo.greet\"));",
                    "text(I18n.t(\"demo.saved\", { n: 3 }));   // {n} filled, one pass",
                    "I18n.setLocale(\"zh-CN\");   // moves the epoch, not the tree"
                ], 96, function ():Node
                {
                    return column({ gap: 6, alignItems: "flex-start" }, [
                        text(I18n.t("demo.greet"), { key: "i18nGreet",
                            style: StyleRefinement.from({ text: {
                                fontSize: 16, fontWeight: "bold", color: 0x0F172A } }),
                            ariaName: "" }),
                        text(I18n.t("demo.saved", { n: 3 }), { key: "i18nSaved",
                            style: LABEL, ariaName: "" })
                    ]);
                }),

                new DocSection("One catalog per locale, merged per key", [
                    "A catalog is a flat `key -> string` table. `addMessages` MERGES, so an app overrides the two kit strings it disagrees with instead of forking all 55. Lookup walks the current locale's chain and then the default one: `zh-Hant-TW` falls back to `zh-Hant`, then `zh`, then the default, so a locale that ships half a translation still reads.",
                    "The kit's own messages -- every widget's default accessible name, the date picker's month and weekday rows -- are the FLOOR, installed lazily by `I18n` itself. An app that registers nothing still gets a localized library."
                ], [
                    "I18n.addMessages(\"zh-CN\", { \"demo.greet\": \"欢迎回来\" });",
                    "I18n.setDefault(\"en\");       // where every chain ends",
                    "I18n.has(\"kit.date.today\");  // the kit's floor is already there",
                    "I18n.locale();               // the EFFECTIVE tag",
                    "I18n.epoch();                // moves on every change"
                ], 88, function ():Node
                {
                    return row({ gap: 8, alignItems: "center" }, [
                        chip("locale " + I18n.locale(), { key: "i18nLocale" }),
                        chip("default " + I18n.defaultLocale(), { key: "i18nDefault" }),
                        chip("kit.date.today " + I18n.has("kit.date.today"), { key: "i18nHasKit" }),
                        chip("epoch " + I18n.epoch(), { key: "i18nEpochChip" })
                    ]);
                }),

                new DocSection("A missing key is never silent", [
                    "`t()` cannot return null and cannot quietly return the key: an unresolved message renders as `[[key]]` and is recorded in `missingKeys()`. A probe asserts that list is empty after rendering every localized surface, so \"not translated yet\" shows up as a red gate instead of as an app that silently speaks English in a Chinese window.",
                    "`setStrict(true)` turns the same event into a thrown error, for a build that would rather not ship at all. The marker below is the point of this section: it is what an untranslated string LOOKS like, and it is why this page is the only place in this app where `missingKeys()` is not empty."
                ], [
                    "text(I18n.t(\"demo.typo\"));   // nobody registered it",
                    "// -> the literal marker [[demo.typo]]",
                    "I18n.missingKeys();           // [\"demo.typo\"]",
                    "I18n.setStrict(true);         // ... or throw instead"
                ], 76, function ():Node
                {
                    return row({ gap: 12, alignItems: "center" }, [
                        text(I18n.t("demo.typo"), { key: "i18nMissing",
                            style: MONO, ariaName: "" }),
                        text("missingKeys(): " + I18n.missingKeys().length, { key: "i18nMissingN",
                            style: LABEL, ariaName: "" })
                    ]);
                }),

                new DocSection("Plurals and grouped numbers", [
                    "A count is not a concatenation: English needs \"1 item\" and \"5 items\". `tn(key, n)` picks `#one`/`#other` from a small explicit table (NOT CLDR -- the kit supports the languages it ships), falls back to `#other`, and fills `{n}` itself. Chinese answers `#other` for every count, which is why the demo's zh-CN catalog has exactly one of the two rows.",
                    "`number()` groups digits with the locale's own separators (`kit.number.group` / `kit.number.decimal`), so the amount below changes with the language without a line of code on this page."
                ], [
                    "I18n.tn(\"demo.items\", 1);   // -> 1 item in the cart",
                    "I18n.tn(\"demo.items\", 5);   // -> 5 items in the cart",
                    "I18n.number(1234567.891, 2);  // grouping + 2 decimals",
                    "I18n.t(\"demo.money\", { amount: I18n.number(1250, 2) });"
                ], 104, function ():Node
                {
                    return column({ gap: 6, alignItems: "flex-start" }, [
                        row({ gap: 12, alignItems: "center" }, [
                            text(I18n.tn("demo.items", 1), { key: "i18nOne", style: LABEL, ariaName: "" }),
                            text(I18n.tn("demo.items", 5), { key: "i18nMany", style: LABEL, ariaName: "" })
                        ]),
                        text(I18n.t("demo.money", { amount: I18n.number(1234567.891, 2) }),
                            { key: "i18nMoney", style: MONO, ariaName: "" }),
                        text(I18n.number(7.5, 1, false) + "   // grouping off",
                            { key: "i18nNoGroup", style: MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("A locale switch is a frame, and RTL is a layout input", [
                    "`setLocale` does not redraw. It bumps an epoch; `UiApp` compares that epoch once per frame and turns it into ONE describe plus a layout re-solve. The describe is where the new strings are computed -- the same latch a theme swap uses, kept separate because a theme swap also re-resolves every node's style and a locale swap does not.",
                    "Mirroring is not part of the strings at all: `I18n.isRTL()` is a LAYOUT input, read on every solve, so an Arabic window mirrors rows and start/end padding while the text it shows may still be English. That is exactly what `ar` does in this app -- the buttons below prove the mirror, not the translation."
                ], [
                    "I18n.setLocale(\"ar\");        // epoch + 1",
                    "// UiApp.onEnterFrame: epoch moved -> invalidate(Dirty.VALUE)",
                    "//                    -> measure/arrange the root again",
                    "I18n.isRTL();                 // true: rows and start/end mirror"
                ], 96, function ():Node
                {
                    return row({ gap: 10, alignItems: "center" }, [
                        langButton("en", "EN"),
                        langButton("zh-CN", "中文"),
                        langButton("ar", "AR"),
                        text("isRTL " + I18n.isRTL(), { key: "i18nRtl", style: MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("This app's prose is a table keyed by the sentence", [
                    "The 267 section headings, the paragraphs under them and the 60 page blurbs are not message keys: they are written inline, next to the live demo they describe, and `DemoMessages.zh()` maps each ENGLISH SENTENCE to its translation. A lookup is one dictionary read, so the describe path allocates nothing, and a translator sees the sentence they are translating.",
                    "That choice's price is a silent miss -- an untranslated line would just stay English -- so it is paid at BUILD time: `tools/demo-i18n.cjs` extracts every display string from the sources and fails if the table does not cover it, or if a row has gone stale."
                ], [
                    "// demo/DemoMessages.as",
                    "\"Text is a payload, not a field\": \"文本是负载，不是字段\",",
                    "// demo/DocsWrap.as translates while it wraps:",
                    "wrap(DemoText.t(paragraph), wrapW, DocsStyle.PROSE);"
                ], 76, function ():Node
                {
                    return column({ gap: 6, alignItems: "flex-start" }, [
                        text("table: " + DemoText.table() + "   (empty = English)",
                            { key: "i18nTable", style: MONO, ariaName: "" }),
                        text("this heading came through it: "
                            + DemoText.t("Text is a payload, not a field"),
                            { key: "i18nProof", style: LABEL, ariaName: "" })
                    ]);
                })
            ];
        }

        // The page's own language buttons: the same one-liner as DocsView.langBtn,
        // because a reader who is ON this page should not have to scroll back to the
        // index to try the thing the page is about. `setLocale` is the whole body --
        // the epoch does the rest.
        private static function langButton(tag:String, label:String):Node
        {
            var on:Boolean = I18n.locale().toLowerCase() == tag.toLowerCase();
            return button({
                key: "i18nBtn:" + tag, label: label,
                style: on ? DocsStyle.LANG_ITEM_ON : DocsStyle.LANG_ITEM,
                ariaName: DemoText.t("Language") + ": " + label,
                onClick: function ():void { I18n.setLocale(tag); }
            });
        }

        public function DocsI18n() { }
    }
}

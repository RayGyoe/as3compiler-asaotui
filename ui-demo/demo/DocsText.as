// demo/DocsText.as -- text / label / chip / badge / avatar / divider: the leaves
// that carry a string or a rule and own no layout of their own.
package demo
{
    import asaot.ui.Node;
    import asaot.ui.avatar;
    import asaot.ui.badge;
    import asaot.ui.box;
    import asaot.ui.chip;
    import asaot.ui.column;
    import asaot.ui.divider;
    import asaot.ui.label;
    import asaot.ui.row;
    import asaot.ui.text;
    import asaot.ui.textField;
    import asaot.ui.style.Length;
    import asaot.ui.style.StyleRefinement;

    public final class DocsText
    {
        private static const AVATAR:StyleRefinement = StyleRefinement.from({ size: [36, 36] });
        public static function sections(view:DocsView, id:String):Array
        {
            var m:DocsModel = view.model;

            if (id == "text") return [
                new DocSection("A run of text", [
                    "text() is the only node that owns a string. It measures itself through a real",
                    "TextField, so it needs no size: the engine gets the measured width as a point size."
                ], [
                    "text(\"Layout, not drawing. The engine solves every rect.\", {",
                    "    style: { text: { fontSize: 14, color: 0x0F172A } }",
                    "})"
                ], 76, function ():Node
                {
                    return text("Layout, not drawing. The engine solves every rect.",
                        { style: StyleRefinement.from({ text: { fontSize: 14, color: 0x0F172A } }), ariaName: "" });
                }),

                new DocSection("Type scale", [
                    "Every size the toolkit ships is a plain number: 11 for metadata, 12 for prose,",
                    "13/14 for body, 20/22 for titles. Nothing is scaled by a theme at run time."
                ], [
                    "text(\"22  Title\",   { style: { text: { fontSize: 22, fontWeight: \"bold\" } } })",
                    "text(\"14  Body\"),",
                    "text(\"12  Caption\", { style: { text: { fontSize: 12, color: 0x64748B } } })"
                ], 118, function ():Node
                {
                    return column({ gap: 2 }, [
                        text("22  Title", { style: StyleRefinement.from({
                            text: { fontSize: 22, fontWeight: "bold", color: 0x0F172A } }), ariaName: "" }),
                        text("14  Body", { style: StyleRefinement.from({
                            text: { fontSize: 14, color: 0x1F2937 } }), ariaName: "" }),
                        text("12  Caption", { style: StyleRefinement.from({
                            text: { fontSize: 12, color: 0x64748B } }), ariaName: "" })
                    ]);
                }),

                new DocSection("Inheritance", [
                    "Text style INHERITS: a child that sets no colour picks up its ancestor's. That is",
                    "why a tile needs no per-child style -- set it on the box and every label follows."
                ], [
                    "box({ style: { background: 0xEEF2FF, text: { color: 0x3730A3 } } }, [",
                    "    text(\"inherited\"),",
                    "    text(\"also inherited\")",
                    "])"
                ], 96, function ():Node
                {
                    return box({ style: StyleRefinement.from({
                        padding: 10, gap: 4, background: 0xEEF2FF, cornerRadii: 8,
                        text: { fontSize: 13, color: 0x3730A3 } }) }, [
                        text("inherited", { ariaName: "" }),
                        text("also inherited", { ariaName: "" })
                    ]);
                }),

                new DocSection("Wrapping", [
                    "whiteSpace: \"normal\" wraps at the node's POINT width and publishes the WRAPPED",
                    "height, which is what an auto-height node needs. The height depends on the width,",
                    "so a percent width is refused (throws) rather than guessed at measure time."
                ], [
                    "text(LONG, { style: { size: [260, null],",
                    "    text: { whiteSpace: \"normal\" } } })"
                ], 150, function ():Node
                {
                    return box({ style: StyleRefinement.from({
                        size: [300, null], padding: 10, background: 0xF8FAFC, cornerRadii: 8 }) }, [
                        text("Wrapping needs a definite width: the engine asks for the height before",
                            { style: StyleRefinement.from({ size: [272, null],
                                text: { whiteSpace: "normal", fontSize: 12, color: 0x334155 } }), ariaName: "" })
                    ]);
                }),

                new DocSection("Ellipsis", [
                    "textOverflow: \"ellipsis\" truncates one line to the FINAL box width, so it can only",
                    "happen at paint time. A wrapped node ignores it -- truncating a wrapped run would",
                    "collapse the lines the measure pass just laid out."
                ], [
                    "text(LONG, { style: { width: 180, text: { textOverflow: \"ellipsis\" } } })"
                ], 84, function ():Node
                {
                    return column({ gap: 8 }, [
                        text("A single line that is far too long for its 180px box...",
                            { style: StyleRefinement.from({ size: [180, null],
                                text: { textOverflow: "ellipsis", fontSize: 12 } }), ariaName: "" }),
                        text("and a short one fits",
                            { style: StyleRefinement.from({ size: [180, null],
                                text: { textOverflow: "ellipsis", fontSize: 12 } }), ariaName: "" })
                    ]);
                }),

                new DocSection("Underline, strikethrough, overline", [
                    "textDecoration draws a rule under, through or over EVERY line, from the line metrics the",
                    "layout pass already produced -- so the rule and the glyphs cannot disagree about where a line",
                    "is, and a wrapped run carries a rule per line rather than one long line across the wrap.",
                    "It does not go through TextFormat.underline: that property's gap (compiler-gaps.md G28) was",
                    "closed in v0.4.303, so the runtime paints its own underline now, but this style must also",
                    "cover strikethrough and overline -- AIR's TextFormat has no property for either -- and drawing",
                    "all three from one set of line metrics is what keeps them on the same row.",
                    "strikethrough and overline are therefore ADDITIONS: AIR has no equivalent. An unknown value",
                    "THROWS rather than silently drawing nothing."
                ], [
                    "text(\"underlined\", { style: { text: { textDecoration: \"underline\" } } })",
                    "text(\"struck out\", { style: { text: { textDecoration: \"line-through\" } } })",
                    "text(\"overlined\",  { style: { text: { textDecoration: \"overline\" } } })"
                ], 132, function ():Node
                {
                    return column({ gap: 10 }, [
                        text("underlined with textDecoration: \"underline\"",
                            { style: StyleRefinement.from({ text: { fontSize: 14,
                                color: 0x1F2937, textDecoration: "underline" } }), ariaName: "" }),
                        text("struck out with \"line-through\"",
                            { style: StyleRefinement.from({ text: { fontSize: 14,
                                color: 0x1F2937, textDecoration: "line-through" } }), ariaName: "" }),
                        text("overlined with \"overline\"",
                            { style: StyleRefinement.from({ text: { fontSize: 14,
                                color: 0x1F2937, textDecoration: "overline" } }), ariaName: "" }),
                        // Wrapped: one rule PER LINE, each starting at that line's own left
                        // edge -- the reason the rule is derived from line metrics.
                        text("A wrapped run gets a rule on every line it occupies, not one rule",
                            { style: StyleRefinement.from({ size: [300, null], text: {
                                fontSize: 12, color: 0x64748B, whiteSpace: "normal",
                                textDecoration: "underline" } }), ariaName: "" })
                    ]);
                }),

                // The four TextStyle fields nothing else on this site writes: textAlign
                // is alignment INSIDE the node's own width (which is why every line here
                // is given one), leading is the line box, letterSpacing is per character
                // and fontStyle picks the face's italic cut.
                new DocSection("Alignment, italic, tracking, leading", [
                    "`textAlign` aligns the line inside the FIELD. A text node that does not wrap",
                    "auto-sizes its field to the line itself (`autoSize: \"left\"`), so there is no",
                    "slack and the alignment is silently a no-op -- which is why `whiteSpace: \"normal\"`",
                    "is part of this recipe rather than an extra: that is what gives the field a width.",
                    "The three tinted 300px boxes below share one size and differ only in alignment.",
                    "`leading` is the line box (line height), not the gap: 12px text with `leading: 24`",
                    "occupies 24 per line. `letterSpacing` adds per character, and `fontStyle: \"italic\"`",
                    "selects the face's italic cut rather than skewing the roman one."
                ], [
                    "text(\"right\", { style: { size: [300, 16], background: 0xE2E8F0,",
                    "                        text: { whiteSpace: \"normal\", textAlign: \"right\" } } })",
                    "// drop whiteSpace \"normal\" and the field shrinks to the line: align does nothing",
                    "text(\"tracked\", { style: { text: { fontStyle: \"italic\", letterSpacing: 2 } } })",
                    "text(\"one\\ntwo\", { style: { size: [150, null],",
                    "                            text: { leading: 24, whiteSpace: \"normal\" } } })"
                ], 156, function ():Node
                {
                    return column({ gap: 8, key: "txType" }, [
                        text("left", { key: "txAl", style: StyleRefinement.from({
                            size: [300, 16], background: 0xE2E8F0,
                            text: { fontSize: 12, whiteSpace: "normal", textAlign: "left" } }),
                            ariaName: "" }),
                        text("center", { key: "txAc", style: StyleRefinement.from({
                            size: [300, 16], background: 0xE2E8F0,
                            text: { fontSize: 12, whiteSpace: "normal", textAlign: "center" } }),
                            ariaName: "" }),
                        text("right", { key: "txAr", style: StyleRefinement.from({
                            size: [300, 16], background: 0xE2E8F0,
                            text: { fontSize: 12, whiteSpace: "normal", textAlign: "right" } }),
                            ariaName: "" }),
                        row({ gap: 16, alignItems: "flex-start" }, [
                            text("italic, letterSpacing 2", { key: "txIt", style: StyleRefinement.from({
                                size: [150, 16],
                                text: { fontSize: 13, fontStyle: "italic", letterSpacing: 2 } }),
                                ariaName: "" }),
                            text("leading 24 wraps to two lines", { key: "txLd",
                                style: StyleRefinement.from({ size: [150, null],
                                    text: { fontSize: 12, leading: 24, whiteSpace: "normal" } }),
                                ariaName: "" })
                        ])
                    ]);
                })
            ];

            if (id == "label") return [
                new DocSection("An alias for text()", [
                    "label(content, opts) is text() -- it registers no kind of its own, so it costs",
                    "nothing at run time. It exists to say \"this is a form row's name\" at the call site."
                ], [
                    "row({ gap: 10, alignItems: \"center\" }, [",
                    "    label(\"Account\", { style: { size: [80, null] } }),",
                    "    textField({ key: \"acc\", placeholder: \"you@example.com\" })",
                    "])"
                ], 84, function ():Node
                {
                    return row({ gap: 10, alignItems: "center" }, [
                        label("Account", { style: StyleRefinement.from({
                            size: [80, null], text: { fontSize: 13, color: 0x374151 } }), ariaName: "" }),
                        textField({ key: "acc", placeholder: "you@example.com",
                            style: StyleRefinement.from({ size: [220, null] }) })
                    ]);
                })
            ];

            if (id == "chip") return [
                new DocSection("Tones", [
                    "A chip is a small tonal tag. `tone` picks one of the kit's three semantic fills:",
                    "neutral, info or danger -- there is no per-chip colour to keep in sync."
                ], [
                    "chip(\"neutral\"), chip(\"info\", { tone: \"info\" }),",
                    "chip(\"danger\", { tone: \"danger\" })"
                ], 76, function ():Node
                {
                    return row({ gap: 8, alignItems: "center" }, [
                        chip("neutral"),
                        chip("info", { tone: "info" }),
                        chip("danger", { tone: "danger" })
                    ]);
                }),

                new DocSection("Clickable", [
                    "A chip takes onClick like any control, so a filter bar is a row of chips and one",
                    "model field. The selected chip is the one whose tone the render chose."
                ], [
                    "chip(label, {",
                    "    tone: on ? \"info\" : \"neutral\",",
                    "    onClick: function ():void { model.chip = label; }",
                    "})"
                ], 76, function ():Node
                {
                    var on:String = m.val("chip.on", "all");
                    return row({ gap: 8, alignItems: "center" }, [
                        pickChip(m, "all", on), pickChip(m, "open", on), pickChip(m, "closed", on)
                    ]);
                }),

                new DocSection("In a list", [
                    "Chips wrap: the row is a `row` with flexWrap, and the chip's own intrinsic width",
                    "means nothing has to be measured by hand."
                ], [
                    "row({ gap: 6, flexWrap: \"wrap\", size: [300, null] }, [ chip(\"a\"), chip(\"b\"), ... ])"
                ], 76, function ():Node
                {
                    return row({ gap: 6, flexWrap: "wrap", style: StyleRefinement.from({ size: [320, null] }) }, [
                        chip("alpha"), chip("beta"), chip("gamma"), chip("delta"), chip("epsilon"),
                        chip("zeta"), chip("eta"), chip("theta")
                    ]);
                })
            ];

            if (id == "badge") return [
                new DocSection("A count pill", [
                    "A badge is a number or short string in a pill. It has no layout of its own either:",
                    "you place it in a row, or absolutely on a corner."
                ], [
                    "row({ gap: 10, alignItems: \"center\" }, [",
                    "    text(\"Inbox\"),",
                    "    badge(\"12\", { tone: \"info\" }),",
                    "    badge(\"3\",  { tone: \"danger\" })",
                    "])"
                ], 84, function ():Node
                {
                    return row({ gap: 10, alignItems: "center" }, [
                        text("Inbox", { style: DocsDemo.LABEL_B, ariaName: "" }),
                        badge("12", { tone: "info" }),
                        text("Alerts", { style: DocsDemo.LABEL_B, ariaName: "" }),
                        badge("3", { tone: "danger" })
                    ]);
                }),

                new DocSection("On a corner", [
                    "Pinned to a corner with position:absolute -- the container is `relative`, the badge",
                    "is offset from its top-right, and neither node moves the other."
                ], [
                    "box({ size: [40, 40], position: \"relative\" }, [",
                    "    icon,",
                    "    badge(\"9\", { style: { position: \"absolute\", inset: [-6, -6, null, null] } })",
                    "])"
                ], 96, function ():Node
                {
                    return box({ style: StyleRefinement.from({
                        size: [44, 44], position: "relative", background: 0xE0E7FF, cornerRadii: 10 }) }, [
                        badge("9", { key: "bgBadge", tone: "danger",
                            style: StyleRefinement.from({ position: "absolute", inset: [-6, -6, null, null] }) })
                    ]);
                })
            ];

            if (id == "avatar") return [
                new DocSection("Initials from a name", [
                    "The avatar takes a NAME, not a character: it derives the initial itself, so it can",
                    "be fed straight from data without a helper at the call site."
                ], [
                    "avatar(\"Ada Lovelace\", { tone: \"info\" }),",
                    "avatar(\"Grace Hopper\"),",
                    "avatar(\"Linus Torvalds\", { tone: \"danger\" })"
                ], 84, function ():Node
                {
                    // An avatar has no intrinsic size (it is a circle drawn into the box it
                    // was given), so each one is sized explicitly -- three 36px circles.
                    return row({ gap: 10, alignItems: "center" }, [
                        avatar("Ada Lovelace", { key: "avA", tone: "info", style: AVATAR }),
                        avatar("Grace Hopper", { key: "avB", style: AVATAR }),
                        avatar("Linus Torvalds", { key: "avC", tone: "danger", style: AVATAR })
                    ]);
                })
            ];

            if (id == "divider") return [
                new DocSection("Horizontal", [
                    "A hairline that measures itself: 1px tall in a column (width stretches), 1px wide in",
                    "a row (height stretches). Nothing to size."
                ], [
                    "column({ gap: 10 }, [",
                    "    text(\"Above\"),",
                    "    divider(),",
                    "    text(\"Below\")",
                    "])"
                ], 96, function ():Node
                {
                    return column({ style: StyleRefinement.from({ size: [260, null], gap: 10 }) }, [
                        text("Above", { style: DocsDemo.LABEL_B, ariaName: "" }),
                        divider(),
                        text("Below", { style: DocsDemo.LABEL_B, ariaName: "" })
                    ]);
                }),

                new DocSection("Vertical", [
                    "orientation:\"vertical\" in a row. This is the usual way to separate two toolbars",
                    "without a border on either of them."
                ], [
                    "row({ gap: 10, alignItems: \"center\" }, [",
                    "    text(\"Left\"), divider({ orientation: \"vertical\" }), text(\"Right\")",
                    "])"
                ], 76, function ():Node
                {
                    return row({ style: StyleRefinement.from({ size: [null, 40], gap: 12, alignItems: "center" }) }, [
                        text("Left", { style: DocsDemo.LABEL_B, ariaName: "" }),
                        divider({ orientation: "vertical" }),
                        text("Right", { style: DocsDemo.LABEL_B, ariaName: "" })
                    ]);
                })
            ];

            return null;
        }

        // One chip per label, wired by a METHOD so each closure captures its own
        // `lb`: AS3 `var` is function-scoped, so a closure built inside a loop would
        // see the last value for every chip.
        private static function pickChip(m:DocsModel, lb:String, on:String):Node
        {
            return chip(lb, { key: "chip:" + lb, tone: on == lb ? "info" : "neutral",
                onClick: function ():void { m.put("chip.on", lb); } });
        }
    }
}

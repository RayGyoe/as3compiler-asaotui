// demo/DocsLayout.as -- box / column / row / card / overlay.
package demo
{
    import asaot.ui.Node;
    import asaot.ui.box;
    import asaot.ui.button;
    import asaot.ui.card;
    import asaot.ui.column;
    import asaot.ui.row;
    import asaot.ui.text;
    import asaot.ui.style.Length;
    import asaot.ui.style.StyleRefinement;

    public final class DocsLayout
    {
        private static const FILLED:StyleRefinement = StyleRefinement.from({
            padding: 12, gap: 6, background: 0xF1F5F9, cornerRadii: 8,
            borderWidths: 1, borderColor: 0xDCE6F0, text: { fontSize: 12, color: 0x334155 }
        });
        // Force this class's lazy static initializer. compiler-gaps G21: a static
        // read emitted INSIDE a closure omits the class's _cinit() guard, so a field
        // whose only readers are demo closures is still NULL when the closure first
        // runs (measured: a static const Array came back null -> #1009). Reading one
        // field from a plain method runs the guard, which initialises the WHOLE class
        // in one go. DocsMain calls this before the first render. Remove when G21 is
        // fixed.
        public static function warmUp():void
        {
            var probe:Object = FILLED;
        }

        public static function sections(view:DocsView, id:String):Array
        {
            var m:DocsModel = view.model;

            if (id == "box") return [
                new DocSection("Basic", [
                    "A box is the plain container: it lays its children out along one axis and can carry",
                    "a background, a border and rounded corners. It owns no widget behaviour at all."
                ], [
                    "box({",
                    "    padding: 12, gap: 6, background: 0xF1F5F9,",
                    "    cornerRadii: 8, borderWidths: 1, borderColor: 0xDCE6F0",
                    "}, [ text(\"a box holds children\") ])"
                ], 76, function ():Node
                {
                    return box({ style: StyleRefinement.from({
                        size: [260, 54], padding: 12, gap: 6, background: 0xF1F5F9,
                        cornerRadii: 8, borderWidths: 1, borderColor: 0xDCE6F0
                    }) }, [
                        text("a box holds children", { style: StyleRefinement.from({
                            text: { fontSize: 12, color: 0x334155 } }), ariaName: "" })
                    ]);
                }),

                new DocSection("Direction", [
                    "The default axis is a column. `row` is the same node with direction \"row\", and it is",
                    "the only way to place children side by side -- a box's direction overrides inheritance."
                ], [
                    "column({ gap: 6 }, [ text(\"one\"), text(\"two\") ])",
                    "row({ gap: 12 }, [",
                    "    box({ style: TILE }, [ text(\"A\") ]),",
                    "    box({ style: TILE }, [ text(\"B\") ])",
                    "])"
                ], 104, function ():Node
                {
                    return row({ gap: 16 }, [
                        column({ style: FILLED }, [
                            text("one", { ariaName: "" }), text("two", { ariaName: "" })
                        ]),
                        row({ style: FILLED }, [
                            text("A", { ariaName: "" }), text("B", { ariaName: "" })
                        ]),
                        text("column            row", { style: DocsDemo.MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("Percent and flex", [
                    "A length is a number of px or a percentage of the parent's content box. `flexGrow` then",
                    "shares whatever is LEFT after the fixed children, so 1:2 splits a 300px box as 100:200."
                ], [
                    "box({ size: [300, 44], gap: 8, flexDirection: \"row\" }, [",
                    "    box({ flexGrow: 1, background: 0xDBEAFE }),",
                    "    box({ flexGrow: 2, background: 0xBFDBFE })",
                    "])"
                ], 76, function ():Node
                {
                    return box({ style: StyleRefinement.from({
                        size: [300, 44], flexDirection: "row", gap: 8
                    }) }, [
                        box({ style: StyleRefinement.from({
                            flexGrow: 1, background: 0xDBEAFE, cornerRadii: 6 }) }),
                        box({ style: StyleRefinement.from({
                            flexGrow: 2, background: 0xBFDBFE, cornerRadii: 6 }) })
                    ]);
                })
            ];

            if (id == "column") return [
                new DocSection("Shorthand", [
                    "column(opts, children) is exactly box() with direction \"column\", which is also the",
                    "default -- so the two spellings are interchangeable, and this one reads better."
                ], [
                    "column({ gap: 6 }, [",
                    "    text(\"first\"),",
                    "    text(\"second\"),",
                    "    text(\"third\")",
                    "])"
                ], 132, function ():Node
                {
                    return column({ style: StyleRefinement.from({
                        size: [220, null],
                        padding: 10, gap: 6, background: 0xF1F5F9, cornerRadii: 8,
                        text: { fontSize: 12, color: 0x334155 }
                    }) }, [
                        text("first", { ariaName: "" }),
                        text("second", { ariaName: "" }),
                        text("third", { ariaName: "" })
                    ]);
                }),

                new DocSection("Main-axis alignment", [
                    "justifyContent distributes the children along the column's own axis; the box has a",
                    "fixed height here so there is slack to distribute."
                ], [
                    "column({ size: [120, 96], justifyContent: \"space-between\" }, [ ... ])"
                ], 132, function ():Node
                {
                    return row({ gap: 16, alignItems: "stretch" }, [
                        column({ style: StyleRefinement.from({
                            size: [120, 96], padding: 8, justifyContent: "flex-start", gap: 4,
                            background: 0xF1F5F9, cornerRadii: 8,
                            text: { fontSize: 11, color: 0x334155 } }) }, [
                            text("start", { ariaName: "" }), text("x", { ariaName: "" })
                        ]),
                        column({ style: StyleRefinement.from({
                            size: [120, 96], padding: 8, justifyContent: "center", gap: 4,
                            background: 0xF1F5F9, cornerRadii: 8,
                            text: { fontSize: 11, color: 0x334155 } }) }, [
                            text("center", { ariaName: "" }), text("x", { ariaName: "" })
                        ]),
                        column({ style: StyleRefinement.from({
                            size: [120, 96], padding: 8, justifyContent: "space-between",
                            background: 0xF1F5F9, cornerRadii: 8,
                            text: { fontSize: 11, color: 0x334155 } }) }, [
                            text("between", { ariaName: "" }), text("x", { ariaName: "" })
                        ])
                    ]);
                })
            ];

            if (id == "row") return [
                new DocSection("Shorthand", [
                    "row(opts, children) is box() with direction \"row\". Children keep their own widths;",
                    "`gap` is the space between them, and `alignItems` places them on the cross axis."
                ], [
                    "row({ gap: 10, alignItems: \"center\" }, [",
                    "    button({ label: \"Save\", style: PRIMARY }),",
                    "    button({ label: \"Cancel\", style: QUIET })",
                    "])"
                ], 84, function ():Node
                {
                    return row({ gap: 10, alignItems: "center" }, [
                        button({ label: "Save", style: DocsDemo.PRIMARY, onClick: function ():void { } }),
                        button({ label: "Cancel", style: DocsDemo.QUIET, onClick: function ():void { } })
                    ]);
                }),

                new DocSection("Cross-axis alignment", [
                    "alignItems is start / center / end. It is what centres a label against a taller",
                    "neighbour -- the text node keeps its measured height and the row places it."
                ], [
                    "row({ size: [280, 64], alignItems: \"center\", gap: 10 }, [",
                    "    box({ size: [64, 64] }), text(\"centred against 64px\")",
                    "])"
                ], 96, function ():Node
                {
                    return row({ style: StyleRefinement.from({
                        size: [320, 66], alignItems: "center", gap: 10 }) }, [
                        box({ style: StyleRefinement.from({
                            size: [52, 52], background: 0xBFDBFE, cornerRadii: 6 }) }),
                        text("centred against a 52px box", { style: DocsDemo.LABEL, ariaName: "" })
                    ]);
                })
            ];

            if (id == "card") return [
                new DocSection("Surface", [
                    "A card is a box with a surface: background, a 1px border and rounded corners. It is a",
                    "container, so it takes children -- and it lays them out as a column by default."
                ], [
                    "card({ padding: 14, gap: 8, background: 0xFFFFFF,",
                    "       borderWidths: 1, borderColor: 0xE5E7EB, cornerRadii: 10 }, [",
                    "    text(\"Card title\"),",
                    "    text(\"Body copy\")",
                    "])"
                ], 118, function ():Node
                {
                    return card({ style: StyleRefinement.from({
                        size: [260, 96], padding: 14, gap: 8, background: 0xFFFFFF,
                        borderWidths: 1, borderColor: 0xE5E7EB, cornerRadii: 10 }) }, [
                        text("Card title", { style: DocsDemo.LABEL_B, ariaName: "" }),
                        text("Body copy sits under it.", { style: DocsDemo.LABEL, ariaName: "" })
                    ]);
                }),

                new DocSection("Nested surface", [
                    "Cards nest -- and a title is just a text child, which is the shape that always lays out",
                    "correctly. (The `title:` option draws its text without reserving space; avoid it.)"
                ], [
                    "card({ padding: 12 }, [",
                    "    card({ padding: 10, background: 0xF8FAFC }, [ text(\"inner\") ])",
                    "])"
                ], 118, function ():Node
                {
                    return card({ style: StyleRefinement.from({
                        padding: 12, background: 0xFFFFFF, borderWidths: 1, borderColor: 0xE5E7EB,
                        cornerRadii: 10, gap: 8 }) }, [
                        card({ style: StyleRefinement.from({
                            padding: 10, background: 0xF8FAFC, borderWidths: 1, borderColor: 0xE2E8F0,
                            cornerRadii: 8 }) }, [
                            text("inner card", { style: DocsDemo.LABEL, ariaName: "" })
                        ]),
                        text("outer card", { style: DocsDemo.LABEL, ariaName: "" })
                    ]);
                })
            ];

            if (id == "overlay") return [
                new DocSection("The second tree", [
                    "renderOverlay() returns a tree reconciled on TOP of render()'s. It is how a floating",
                    "surface escapes its parent's box: the page behind it is neither re-laid out nor clipped."
                ], [
                    "override public function renderOverlay():Node {",
                    "    if (!open) return null;         // null tears the whole layer down",
                    "    return overlay([ popover({ key: \"p\", open: true,",
                    "                               anchorKey: \"ovBtn\", placement: \"bottom\" },",
                    "                             [ text(\"floats\") ]) ]);",
                    "}"
                ], 84, function ():Node
                {
                    return row({ gap: 12, alignItems: "center" }, [
                        button({ key: "ovBtn", label: m.bool("ov.open", false) ? "Close" : "Open popover",
                                 style: DocsDemo.PRIMARY,
                                 onClick: function ():void { m.put("ov.open", !m.bool("ov.open", false)); } }),
                        text("the anchor is found by KEY, in the live tree",
                             { style: DocsDemo.LABEL, ariaName: "" })
                    ]);
                }),

                new DocSection("Order is stacking order", [
                    "This engine has no z-index and no such style field: the LAST child of the overlay is",
                    "painted last and wins a hit test. Dialogs go last, popovers and menus before them."
                ], [
                    "return overlay([",
                    "    popover(...),   // under",
                    "    menu(...),      // under",
                    "    dialog(...)     // on top of both",
                    "]);"
                ], 84, function ():Node
                {
                    return box({ style: StyleRefinement.from({
                        size: [280, 60], flexDirection: "row", position: "relative",
                        background: 0xF1F5F9, cornerRadii: 8 }) }, [
                        box({ key: "ovSampleA", style: StyleRefinement.from({
                            position: "absolute", inset: [10, null, null, 10],
                            size: [140, 40], background: 0xBFDBFE, cornerRadii: 6,
                            text: { fontSize: 11, color: 0x1E3A8A } }) }, [
                            text("popover", { ariaName: "" })
                        ]),
                        box({ key: "ovSampleB", style: StyleRefinement.from({
                            position: "absolute", inset: [20, null, null, 90],
                            size: [140, 40], background: 0x2563EB, cornerRadii: 6,
                            text: { fontSize: 11, color: 0xFFFFFF } }) }, [
                            text("dialog on top", { ariaName: "" })
                        ])
                    ]);
                })
            ];

            return null;
        }
    }
}

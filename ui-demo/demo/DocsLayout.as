// demo/DocsLayout.as -- box / column / row / card / overlay.
package demo
{
    import asaot.ui.Node;
    import asaot.ui.box;
    import asaot.ui.button;
    import asaot.ui.card;
    import asaot.ui.chip;
    import asaot.ui.column;
    import asaot.ui.row;
    import asaot.ui.splitPane;
    import asaot.ui.text;
    import asaot.ui.style.Length;
    import asaot.ui.style.StyleRefinement;

    public final class DocsLayout
    {
        private static const FILLED:StyleRefinement = StyleRefinement.from({
            padding: 12, gap: 6, background: 0xF1F5F9, cornerRadii: 8,
            borderWidths: 1, borderColor: 0xDCE6F0, text: { fontSize: 12, color: 0x334155 }
        });
        // The splitPane page: a 360-wide splitter whose panes carry NO main-axis size
        // (the widget's flex basis is the only thing that may decide the share).
        private static const SP_BOX:StyleRefinement = StyleRefinement.from({
            size: [360, 76], background: 0xFFFFFF, borderWidths: 1, borderColor: 0xE5E7EB
        });
        private static const SP_L:StyleRefinement = StyleRefinement.from({
            size: [null, 74], padding: 10, background: 0xEEF2FF, text: { fontSize: 12, color: 0x1E3A8A }
        });
        private static const SP_R:StyleRefinement = StyleRefinement.from({
            size: [null, 74], padding: 10, background: 0xFFF1F2, text: { fontSize: 12, color: 0x881337 }
        });
        // The vertical split: panes carry a null size on BOTH axes (in a column the
        // main axis is height, and an authored height would beat the widget's basis).
        private static const SP_BOX_V:StyleRefinement = StyleRefinement.from({
            size: [360, 150], background: 0xFFFFFF, borderWidths: 1, borderColor: 0xE5E7EB
        });
        private static const SP_VP:StyleRefinement = StyleRefinement.from({
            size: [null, null], padding: 10, background: 0xEEF2FF,
            text: { fontSize: 12, color: 0x1E3A8A }
        });
        private static const SP_VP2:StyleRefinement = StyleRefinement.from({
            size: [null, null], padding: 10, background: 0xFFF1F2,
            text: { fontSize: 12, color: 0x881337 }
        });
        public static function sections(view:DocsView, id:String):Array
        {
            var m:DocsModel = view.model;

            if (id == "box") return [
                new DocSection("Basic", [
                    "A box is the plain container: it lays its children out along one axis and can carry a background, a border and rounded corners. It owns no widget behaviour at all."
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
                    "The default axis is a column; `flexDirection: \"row\"` in a style makes a row.",
                    "`row(opts, children)` is that same box with the axis PINNED, so a style merged in later cannot stack it again -- use `row`/`column` when the axis is the control's own shape, and a plain `box` when it is only styling."
                ], [
                    "column({ gap: 6 }, [ text(\"one\"), text(\"two\") ])",
                    "row({ gap: 12 }, [",
                    "    box({ style: TILE }, [ text(\"A\") ]),",
                    "    box({ style: TILE }, [ text(\"B\") ])",
                    "])",
                    "box({ style: { flexDirection: \"row\" } }, [ ... ])   // a row too"
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
                    "A length is a number of px or a percentage of the parent's content box. `flexGrow` then shares whatever is LEFT after the fixed children, so 1:2 splits a 300px box as 100:200."
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
                }),

                new DocSection("Box shadow", [
                    "boxShadow is DRAWN, not deferred: the runtime really renders a DropShadowFilter, and it lands on the node's background shape only -- a filter on the backing would shade the label and the children too. offset/blur/color/alpha are the four knobs AS3 has; `spread` and `inset` are GPUI fields this backend cannot honour, so they THROW."
                ], [
                    "box({ style: { padding: 12, background: 0xFFFFFF, cornerRadii: 8,",
                    "               boxShadow: { y: 2, blur: 8, color: 0x000000, alpha: 0.25 } } })"
                ], 108, function ():Node
                {
                    return row({ gap: 20, alignItems: "center" }, [
                        box({ style: StyleRefinement.from({
                            size: [150, 64], padding: 12, background: 0xFFFFFF, cornerRadii: 8,
                            borderWidths: 1, borderColor: 0xE2E8F0,
                            boxShadow: { y: 2, blur: 8, color: 0x000000, alpha: 0.25 }
                        }) }, [ text("drop shadow", { ariaName: "" }) ]),
                        box({ style: StyleRefinement.from({
                            size: [150, 64], padding: 12, background: 0xFFFFFF, cornerRadii: 8,
                            borderWidths: 1, borderColor: 0xE2E8F0,
                            boxShadow: [ { y: 1, blur: 2, color: 0x000000, alpha: 0.18 },
                                         { y: 6, blur: 14, color: 0x3B82F6, alpha: 0.30 } ]
                        }) }, [ text("a stack of two", { ariaName: "" }) ])
                    ]);
                }),

                new DocSection("Gradient background", [
                    "A background is a Fill: one colour, or TWO OR MORE stops. An Array is a gradient, and `angle` is in degrees (0 = left to right, 90 = top to bottom). This backend paints LINEAR only -- radial/focal throws at construction instead of painting a different gradient than the one asked for."
                ], [
                    "box({ style: { background: [0x3B82F6, 0x8B5CF6], height: 48 } })",
                    "box({ style: { background: { colors: [0xF97316, 0xFDE047], angle: 90 } } })"
                ], 108, function ():Node
                {
                    return row({ gap: 16, alignItems: "center" }, [
                        box({ style: StyleRefinement.from({
                            size: [140, 56], background: [0x3B82F6, 0x8B5CF6], cornerRadii: 8,
                            justifyContent: "center", alignItems: "center"
                        }) }, [ text("horizontal", { style: StyleRefinement.from({
                            text: { color: 0xFFFFFF } }), ariaName: "" }) ]),
                        box({ style: StyleRefinement.from({
                            size: [140, 56], cornerRadii: 8,
                            background: { colors: [0xF97316, 0xFDE047], angle: 90 },
                            justifyContent: "center", alignItems: "center"
                        }) }, [ text("vertical", { ariaName: "" }) ])
                    ]);
                }),

                // A box is a NODE, so it is clickable: `onClick` makes it a hit target
                // (and `cursor: "hand"` is the author's promise that it looks like one --
                // the kit never guesses that a container is interactive).
                new DocSection("A container can be the button", [
                    "`box()` takes `onClick` like every other node, so a card, a tile or a whole row can be the hit target -- no wrapper control and no event plumbing. It is the same dispatch a button uses: press, release inside, then the callback."
                ], [
                    "box({ style: { size: [180, 44], cursor: \"hand\", background: 0x2563EB,",
                    "             cornerRadii: 8, justifyContent: \"center\", alignItems: \"center\" },",
                    "      onClick: function ():void { model.clicks++; } })"
                ], 96, function ():Node
                {
                    return column({ gap: 6 }, [
                        box({ key: "boxClick", style: StyleRefinement.from({
                                size: [180, 44], cursor: "hand", background: 0x2563EB,
                                cornerRadii: 8, justifyContent: "center", alignItems: "center" }),
                            ariaName: "clickable box",
                            onClick: function ():void { m.put("box.clicks", int(m.num("box.clicks", 0)) + 1); } }, [
                            text("click me", { style: StyleRefinement.from({
                                text: { color: 0xFFFFFF, fontSize: 13 } }), ariaName: "" })
                        ]),
                        text("clicks: " + int(m.num("box.clicks", 0)) + "  (cursor: hand is a style, not a default)",
                            { style: DocsDemo.MONO, ariaName: "" })
                    ]);
                })
            ];

            if (id == "column") return [
                new DocSection("Shorthand", [
                    "column(opts, children) is exactly box() with direction \"column\", which is also the default -- so the two spellings are interchangeable, and this one reads better."
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
                    "justifyContent distributes the children along the column's own axis; the box has a fixed height here so there is slack to distribute."
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
                }),

                new DocSection("An auto-height column hugs its children", [
                    "Leave the height null and the column is exactly its padding plus the sum of its children plus the gaps between them. The border below is drawn on that computed box, which is why it sits tight against the two lines -- nothing was measured by hand to make it fit."
                ], [
                    "column({ padding: 10, gap: 6 }, [ text(\"a\"), text(\"b\") ])",
                    "// height = 10 + 10 + a.h + 6 + b.h"
                ], 108, function ():Node
                {
                    return row({ gap: 16, alignItems: "flex-start" }, [
                        column({ style: StyleRefinement.from({
                            padding: 10, gap: 6, borderWidths: 1, borderColor: 0x94A3B8,
                            cornerRadii: 6, text: { fontSize: 12, color: 0x334155 } }) }, [
                            text("one line", { ariaName: "" }), text("two lines", { ariaName: "" })
                        ]),
                        column({ style: StyleRefinement.from({
                            padding: 10, gap: 6, borderWidths: 1, borderColor: 0x94A3B8,
                            cornerRadii: 6, text: { fontSize: 12, color: 0x334155 } }) }, [
                            text("one line", { ariaName: "" }), text("two lines", { ariaName: "" }),
                            text("three lines", { ariaName: "" })
                        ])
                    ]);
                }),

                new DocSection("A percentage belongs to the parent", [
                    "`size: [0.5, null]` means half of the PARENT's content width, so two of them plus a gap overflow the row -- which is why the pair below is sized with flexGrow instead: 1 and 1 split what is left AFTER the gap, whatever the window did."
                ], [
                    "row({ gap: 8, size: [320, null] }, [",
                    "    box({ style: { flexGrow: 1 } }), box({ style: { flexGrow: 1 } })",
                    "])"
                ], 96, function ():Node
                {
                    return row({ gap: 8, style: StyleRefinement.from({ size: [320, null] }) }, [
                        box({ style: StyleRefinement.from({
                            flexGrow: 1, size: [null, 40], background: 0xBFDBFE, cornerRadii: 6,
                            text: { fontSize: 11, color: 0x1E3A8A } }) }, [
                            text("flexGrow 1", { ariaName: "" })
                        ]),
                        box({ style: StyleRefinement.from({
                            flexGrow: 1, size: [null, 40], background: 0xDBEAFE, cornerRadii: 6,
                            text: { fontSize: 11, color: 0x1E3A8A } }) }, [
                            text("flexGrow 1", { ariaName: "" })
                        ])
                    ]);
                }),

                new DocSection("A column wraps into a second column", [
                    "flexWrap on a fixed-height column: children that do not fit start a new column to the right. The same five nodes fit the 60pt band in three columns here, and the author wrote no width at all."
                ], [
                    "column({ size: [null, 60], gap: 6, flexWrap: \"wrap\" }, [ five children ])"
                ], 108, function ():Node
                {
                    return column({ style: StyleRefinement.from({
                        size: [300, 60], gap: 6, flexWrap: "wrap", padding: 6,
                        background: 0xF8FAFC, borderWidths: 1, borderColor: 0xE2E8F0 }) }, [
                        chip("a"), chip("b"), chip("c"), chip("d"), chip("e"), chip("f")
                    ]);
                })
            ];

            if (id == "row") return [
                new DocSection("Shorthand", [
                    "row(opts, children) is box() with direction \"row\". Children keep their own widths; `gap` is the space between them, and `alignItems` places them on the cross axis."
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
                    "alignItems is start / center / end. It is what centres a label against a taller neighbour -- the text node keeps its measured height and the row places it."
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
                }),

                new DocSection("One child grows, the rest keep their size", [
                    "The middle box carries flexGrow 1 and no width; the two ends declare 64pt each. The growth comes out of the space the fixed children and the gaps left over, so the middle one is wider in the wider row below without any arithmetic in the page."
                ], [
                    "row({ gap: 8 }, [",
                    "    box({ size: [64, 36] }), box({ size: [null, 36], flexGrow: 1 }),",
                    "    box({ size: [64, 36] })",
                    "])"
                ], 96, function ():Node
                {
                    return column({ gap: 8 }, [
                        row({ gap: 8, style: StyleRefinement.from({ size: [300, 36] }) }, [
                            box({ style: StyleRefinement.from({ size: [64, 36], background: 0xBFDBFE,
                                cornerRadii: 6, text: { fontSize: 11, color: 0x1E3A8A } }) }, [
                                text("64", { ariaName: "" })]),
                            box({ style: StyleRefinement.from({ size: [null, 36], flexGrow: 1,
                                background: 0x2563EB, cornerRadii: 6,
                                text: { fontSize: 11, color: 0xFFFFFF } }) }, [
                                text("grows", { ariaName: "" })]),
                            box({ style: StyleRefinement.from({ size: [64, 36], background: 0xBFDBFE,
                                cornerRadii: 6, text: { fontSize: 11, color: 0x1E3A8A } }) }, [
                                text("64", { ariaName: "" })])
                        ]),
                        row({ gap: 8, style: StyleRefinement.from({ size: [420, 36] }) }, [
                            box({ style: StyleRefinement.from({ size: [64, 36], background: 0xBFDBFE,
                                cornerRadii: 6, text: { fontSize: 11, color: 0x1E3A8A } }) }, [
                                text("64", { ariaName: "" })]),
                            box({ style: StyleRefinement.from({ size: [null, 36], flexGrow: 1,
                                background: 0x2563EB, cornerRadii: 6,
                                text: { fontSize: 11, color: 0xFFFFFF } }) }, [
                                text("still grows", { ariaName: "" })]),
                            box({ style: StyleRefinement.from({ size: [64, 36], background: 0xBFDBFE,
                                cornerRadii: 6, text: { fontSize: 11, color: 0x1E3A8A } }) }, [
                                text("64", { ariaName: "" })])
                        ])
                    ]);
                }),

                new DocSection("Two ends, nothing in between", [
                    "space-between is the whole of a toolbar: a title that hugs the left and a control that hugs the right, with the slack handed to the gap. No spacer node."
                ], [
                    "row({ justifyContent: \"space-between\", alignItems: \"center\" }, [",
                    "    text(\"Inbox\"), button({ label: \"Compose\" })",
                    "])"
                ], 84, function ():Node
                {
                    return row({ justifyContent: "space-between", alignItems: "center",
                        style: StyleRefinement.from({ size: [420, null], padding: 8,
                        background: 0xF8FAFC, borderWidths: 1, borderColor: 0xE2E8F0,
                        cornerRadii: 8 }) }, [
                        text("Inbox", { style: DocsDemo.LABEL_B, ariaName: "" }),
                        button({ key: "rowCompose", label: "Compose", style: DocsDemo.QUIET,
                                 onClick: function ():void { } })
                    ]);
                }),

                new DocSection("Nested rows make a two-column page", [
                    "A row of two columns is a page split. Each column is an ordinary column and both grow, so the split survives a window resize without a single constant."
                ], [
                    "row({ gap: 12 }, [",
                    "    column({ style: { flexGrow: 1 } }, [...]),",
                    "    column({ style: { flexGrow: 1 } }, [...])",
                    "])"
                ], 132, function ():Node
                {
                    return row({ gap: 12, style: StyleRefinement.from({ size: [380, null] }) }, [
                        column({ style: StyleRefinement.from({ flexGrow: 1, gap: 6, padding: 8,
                            background: 0xF8FAFC, cornerRadii: 6,
                            text: { fontSize: 11, color: 0x334155 } }) }, [
                            text("left 1", { ariaName: "" }), text("left 2", { ariaName: "" })
                        ]),
                        column({ style: StyleRefinement.from({ flexGrow: 1, gap: 6, padding: 8,
                            background: 0xF1F5F9, cornerRadii: 6,
                            text: { fontSize: 11, color: 0x334155 } }) }, [
                            text("right 1", { ariaName: "" }), text("right 2", { ariaName: "" }),
                            text("right 3", { ariaName: "" })
                        ])
                    ]);
                })
            ];

            if (id == "card") return [
                new DocSection("Surface", [
                    "A card is a box with a surface: background, a 1px border and rounded corners. It is a container, so it takes children -- and it lays them out as a column by default."
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
                    "Cards nest -- and a title is just a text child, which is the shape that always lays out correctly. (The `title:` option draws its text without reserving space; avoid it.)"
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
                }),

                new DocSection("A heading is a child, not the title option", [
                    "The `title:` option draws its text WITHOUT reserving space in the card's flow, so anything after it overlaps the heading. The shape that always lays out correctly is a text child first, then the body -- and a divider if the card needs one."
                ], [
                    "card({ padding: 12, gap: 8 }, [",
                    "    text(\"Invoice\", { style: { fontSize: 13, fontWeight: \"bold\" } }),",
                    "    text(body)",
                    "])"
                ], 118, function ():Node
                {
                    return card({ style: StyleRefinement.from({
                        size: [260, null], padding: 12, gap: 8, background: 0xFFFFFF,
                        borderWidths: 1, borderColor: 0xE5E7EB, cornerRadii: 10 }) }, [
                        text("Invoice", { style: DocsDemo.LABEL_B, ariaName: "" }),
                        text("3 lines, 1 payment", { style: DocsDemo.MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("A card in a row keeps its own height", [
                    "The default cross-axis alignment of a row is stretch, so two cards side by side become equally tall even when their contents differ. Say `alignItems: flex-start` when each card should hug its own text -- the difference is visible below."
                ], [
                    "row({ gap: 12, alignItems: \"stretch\" },    [ card(...), card(...) ])  // equal",
                    "row({ gap: 12, alignItems: \"flex-start\" }, [ card(...), card(...) ])  // hugging"
                ], 132, function ():Node
                {
                    return row({ gap: 12, alignItems: "flex-start" }, [
                        card({ style: StyleRefinement.from({
                            size: [150, null], padding: 10, gap: 6, background: 0xFFFFFF,
                            borderWidths: 1, borderColor: 0xE5E7EB, cornerRadii: 8 }) }, [
                            text("short", { style: DocsDemo.LABEL, ariaName: "" })
                        ]),
                        row({ gap: 12, alignItems: "stretch",
                            style: StyleRefinement.from({ size: [150, null] }) }, [
                            card({ style: StyleRefinement.from({
                                padding: 10, gap: 6, background: 0xFFFFFF, flexGrow: 1,
                                borderWidths: 1, borderColor: 0xE5E7EB, cornerRadii: 8 }) }, [
                                text("tall", { style: DocsDemo.LABEL, ariaName: "" }),
                                text("two lines", { style: DocsDemo.LABEL, ariaName: "" }),
                                text("three lines", { style: DocsDemo.LABEL, ariaName: "" })
                            ])
                        ])
                    ]);
                })
            ];

            if (id == "splitPane") return [
                new DocSection("A share, not two sizes", [
                    "splitPane(first, second, { ratio }) puts two ORDINARY nodes around a grip and keeps their sizes in step with one number: `ratio` is the FIRST pane's share of the space left after the grip (0.5 = half). The panes are children like any other -- a box, a list, a scrollView -- and the widget writes their flex basis with grow and shrink at 0, so a pane whose content is wider than its share cannot quietly eat the other one.",
                    "Drag the grip: `onResize(ratio)` reports the new share on every move and again on release. Storing it in the model is the whole contract -- nothing is cached inside the widget, so resizing the window keeps the SHARE, not the pixel width.",
                    "A pane leaves its MAIN-axis size null (`size: [null, 74]`): the widget writes the flex basis, and an explicit width in the pane's own style would win over it."
                ], [
                    "splitPane(left, right, {",
                    "    ratio: m.num(\"sp.ratio\", 0.5), minSize: 40, dividerSize: 6,",
                    "    onResize: function (r:Number):void { m.put(\"sp.ratio\", r); }",
                    "})"
                ], 116, function ():Node
                {
                    return column({ gap: 8 }, [
                        splitPane(
                            box({ style: SP_L }, [ text("first pane",
                                { style: DocsDemo.LABEL, ariaName: "" }) ]),
                            box({ style: SP_R }, [ text("second pane",
                                { style: DocsDemo.LABEL, ariaName: "" }) ]),
                            { key: "spDemo", style: SP_BOX, direction: "row",
                              ratio: m.num("sp.ratio", 0.5), minSize: 40, dividerSize: 6,
                              onResize: function (r:Number):void { m.put("sp.ratio", r); } }
                        ),
                        text("share " + Math.round(m.num("sp.ratio", 0.5) * 100) + "%",
                            { key: "spShare", style: DocsDemo.MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("minSize is a floor, and the ratio obeys it", [
                    "`ratio` stays inside 0..1 -- anything else is refused at factory time, because a share above 1 is not a share. `minSize` is applied ON TOP of it, to both panes, so a tiny authored ratio produces a usable grip instead of a pane you cannot see: a 0.02 share of a 294pt area would be 6pt, and 6pt loses to the 40pt minimum. A minimum wider than half the area cannot hold twice, so it is halved rather than handing one pane a negative size."
                ], [
                    "splitPane(left, right, { ratio: 0.02, minSize: 40, dividerSize: 6 })",
                    "// 294 available -> round(294 * 0.02) = 6 -> clamped up to 40"
                ], 116, function ():Node
                {
                    return column({ gap: 8 }, [
                        splitPane(
                            box({ style: SP_L }, [ text("40pt floor",
                                { style: DocsDemo.LABEL, ariaName: "" }) ]),
                            box({ style: SP_R }, [ text("the rest",
                                { style: DocsDemo.LABEL, ariaName: "" }) ]),
                            { key: "spLow", style: SP_BOX, direction: "row",
                              ratio: 0.02, minSize: 40, dividerSize: 6 }
                        ),
                        text("an authored ratio of 0.02 still yields a 40pt pane",
                            { key: "spLowCap", style: DocsDemo.MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("The same two nodes, stacked", [
                    "`direction: column` splits vertically. Nothing else changes: the grip becomes a horizontal bar, the panes keep null main-axis sizes, and `ratio` is still the FIRST pane's share of what is left after the grip."
                ], [
                    "splitPane(top, bottom, { direction: \"column\", ratio: 0.4, dividerSize: 6 })"
                ], 168, function ():Node
                {
                    return splitPane(
                        box({ style: SP_VP }, [ text("top pane",
                            { style: DocsDemo.LABEL, ariaName: "" }) ]),
                        box({ style: SP_VP2 }, [ text("bottom pane",
                            { style: DocsDemo.LABEL, ariaName: "" }) ]),
                        { key: "spVert", style: SP_BOX_V, direction: "column",
                          ratio: m.num("sp.vratio", 0.4), minSize: 30, dividerSize: 6,
                          onResize: function (r:Number):void { m.put("sp.vratio", r); } }
                    );
                }),

                new DocSection("A floor that cannot hold twice is halved", [
                    "minSize 200 in a 300pt area would leave nothing for the second pane, so the widget halves it instead of handing one side a negative size: both panes end up at 150 and the split is equal. A floor is a promise about the SMALLER pane, never a licence to overflow."
                ], [
                    "splitPane(a, b, { ratio: 0.5, minSize: 200 })   // 300pt area -> 150 / 150"
                ], 116, function ():Node
                {
                    return column({ gap: 8 }, [
                        box({ style: StyleRefinement.from({ size: [300, null] }) }, [
                            splitPane(
                                box({ style: SP_L }, [ text("150",
                                    { style: DocsDemo.LABEL, ariaName: "" }) ]),
                                box({ style: SP_R }, [ text("150",
                                    { style: DocsDemo.LABEL, ariaName: "" }) ]),
                                { key: "spFloor", style: SP_BOX, direction: "row",
                                  ratio: 0.5, minSize: 200, dividerSize: 6 }
                            )
                        ]),
                        text("minSize 200 in a 300pt area -> 150 / 150",
                            { key: "spFloorCap", style: DocsDemo.MONO, ariaName: "" })
                    ]);
                })
            ];

            if (id == "overlay") return [
                new DocSection("The second tree", [
                    "renderOverlay() returns a tree reconciled on TOP of render()'s. It is how a floating surface escapes its parent's box: the page behind it is neither re-laid out nor clipped."
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
                    "This engine has no z-index and no such style field: the LAST child of the overlay is painted last and wins a hit test. Dialogs go last, popovers and menus before them."
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
                }),

                new DocSection("Returning null is the teardown", [
                    "The layer is not hidden, it is ABSENT: `renderOverlay` returns null and the reconciler removes the nodes, which is what releases their handlers and their place in the focus walk. A closed popover left in the tree at opacity 0 would keep both."
                ], [
                    "if (!open) return null;   // removed, not hidden"
                ], 84, function ():Node
                {
                    return row({ gap: 12, alignItems: "center" }, [
                        button({ key: "ovTear", label: "Toggle layer", style: DocsDemo.QUIET,
                                 onClick: function ():void { m.put("ov.tear", !m.bool("ov.tear", false)); } }),
                        text(m.bool("ov.tear", false) ? "layer present" : "layer is null",
                            { key: "ovTearState", style: DocsDemo.MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("An anchor that is gone takes the surface with it", [
                    "The anchor is found by KEY in the live tree every frame. If the node it named is not there -- scrolled away, filtered out, conditionally rendered -- the popover is not placed: there is no stale position to fall back to, and no second copy of the layout to keep in sync."
                ], [
                    "anchorKey: \"ovBtn\"    // looked up in the live tree, every frame"
                ], 84, function ():Node
                {
                    var has:Boolean = m.bool("ov.anchor", true);
                    return row({ gap: 12, alignItems: "center" }, [
                        button({ key: "ovAnchorToggle", label: has ? "Remove anchor" : "Restore anchor",
                                 style: DocsDemo.QUIET,
                                 onClick: function ():void { m.put("ov.anchor", !has); } }),
                        has ? button({ key: "ovAnchorLive", label: "I am the anchor",
                                style: DocsDemo.PRIMARY,
                                onClick: function ():void { } })
                            : text("anchor absent this frame", { style: DocsDemo.MONO, ariaName: "" })
                    ]);
                })
            ];

            return null;
        }
    }
}

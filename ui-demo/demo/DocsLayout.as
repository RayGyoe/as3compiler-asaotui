// demo/DocsLayout.as -- box / column / row / card / overlay.
package demo
{
    import asaot.ui.Node;
    import asaot.ui.box;
    import asaot.ui.button;
    import asaot.ui.card;
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
                }),

                new DocSection("Box shadow", [
                    "boxShadow is DRAWN, not deferred: the runtime really renders a DropShadowFilter, and",
                    "it lands on the node's background shape only -- a filter on the backing would shade",
                    "the label and the children too. offset/blur/color/alpha are the four knobs AS3 has;",
                    "`spread` and `inset` are GPUI fields this backend cannot honour, so they THROW."
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
                    "A background is a Fill: one colour, or TWO OR MORE stops. An Array is a gradient, and",
                    "`angle` is in degrees (0 = left to right, 90 = top to bottom). This backend paints",
                    "LINEAR only -- radial/focal throws at construction instead of painting a different",
                    "gradient than the one asked for."
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
                    "`box()` takes `onClick` like every other node, so a card, a tile or a whole",
                    "row can be the hit target -- no wrapper control and no event plumbing. It is",
                    "the same dispatch a button uses: press, release inside, then the callback."
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

            if (id == "splitPane") return [
                new DocSection("A share, not two sizes", [
                    "splitPane(first, second, { ratio }) puts two ORDINARY nodes around a grip and",
                    "keeps their sizes in step with one number: `ratio` is the FIRST pane's share of",
                    "the space left after the grip (0.5 = half). The panes are children like any",
                    "other -- a box, a list, a scrollView -- and the widget writes their flex basis",
                    "with grow and shrink at 0, so a pane whose content is wider than its share",
                    "cannot quietly eat the other one.",
                    "Drag the grip: `onResize(ratio)` reports the new share on every move and again",
                    "on release. Storing it in the model is the whole contract -- nothing is cached",
                    "inside the widget, so resizing the window keeps the SHARE, not the pixel width."
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
                    "`ratio` stays inside 0..1 -- anything else is refused at factory time, because",
                    "a share above 1 is not a share. `minSize` is applied ON TOP of it, to both",
                    "panes, so a tiny authored ratio produces a usable grip instead of a pane you",
                    "cannot see: a 0.02 share of a 294pt area would be 6pt, and 6pt loses to the",
                    "40pt minimum. A minimum wider than half the area cannot hold twice, so it is",
                    "halved rather than handing one pane a negative size."
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

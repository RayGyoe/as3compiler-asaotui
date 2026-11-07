// demo/DocsMotion.as -- the Motion group: `animation` (time) and `gesture` (the
// pointer). Two pages about MECHANISMS rather than about a widget.
//
// WHY THESE PAGES EXIST AT ALL. Every style field already carried `transitionMs` /
// `transitionEase`, and the tween core has been shipping since the first animation
// (Anim / Tween / Ease / AnimState under kit/asaot/ui/anim), the pointer router
// since MOBILE.md P1 -- and NONE of it was on a page. A reader could find
// `transitionMs` in the style table and still not learn that every widget animates
// with no code in the widget, or that a paint field never re-solves the layout
// while a width change does.
//
// WHAT THIS PAGE DOES NOT CLAIM. `hitSlop` and `pointerEvents` do not exist in this
// toolkit (MOBILE.md records them as P6/P5 work, still open). Rather than dress a
// missing feature up as a demonstration, the gesture page shows the mechanism that
// DOES exist -- a hit area larger than the drawn area, i.e. a container whose own
// background paints the target -- and says plainly that the declared-inset form is
// not implemented. A docs page that quietly faked a `hitSlop` would be worse than
// no page at all.
//
// HEIGHTS ARE ARITHMETIC, NOT HOPE. A DocSection's demo surface has 12pt of padding
// on each side, so the CONTENT box is `demoH - 24`; every section below sizes its
// demoH from the sum of its own rows (the tour's sweep fails a child that escapes
// its block, and it is right to).
package demo
{
    import asaot.ui.Dirty;
    import asaot.ui.Env;
    import asaot.ui.Node;
    import asaot.ui.anim.Ease;
    import asaot.ui.box;
    import asaot.ui.button;
    import asaot.ui.column;
    import asaot.ui.row;
    import asaot.ui.splitPane;
    import asaot.ui.style.Length;
    import asaot.ui.style.StyleRefinement;
    import asaot.ui.text;

    public final class DocsMotion
    {
        private static const SWATCH:StyleRefinement = StyleRefinement.from({
            size: [96, 44], cornerRadii: 8, background: 0xDBEAFE, borderWidths: 1, borderColor: 0xBFDBFE
        });
        private static const TAB:StyleRefinement = StyleRefinement.from({
            size: [26, 26], background: 0x2563EB, cornerRadii: 5
        });
        // The four curves, in the order Ease's own table lists them.
        private static const EASES:Array = ["linear", "outQuad", "outCubic", "inOutCubic"];

        public static function sections(view:DocsView, id:String):Array
        {
            if (id == "animation") return animation(view);
            if (id == "gesture") return gesture(view);
            return null;
        }

        // ---- animation -------------------------------------------------------

        private static function animation(view:DocsView):Array
        {
            var m:DocsModel = view.model;

            return [
                new DocSection("One field, one transition", [
                    "Write `transitionMs` and `transitionEase` and the field eases instead of snapping.",
                    "No widget knows: UiNode.resolveStyle compares what it just resolved against what the",
                    "node had, and hands the difference to the tween core. Every kind animates, unchanged."
                ], [
                    "box({ style: { background: on ? 0x2563EB : 0xE2E8F0, transitionMs: 260,",
                    "              transitionEase: \"outCubic\" } })"
                ], 88, function ():Node
                {
                    var on:Boolean = m.bool("anim.a", false);
                    return row({ gap: 18, alignItems: "flex-start" }, [
                        tick("no transitionMs", "animSnap", on, 0),
                        tick("transitionMs: 260", "animEase", on, 260),
                        button({ key: "animFlipA", label: on ? "Back" : "Flip", style: DocsDemo.QUIET,
                                 onClick: function ():void { m.put("anim.a", !on); } })
                    ]);
                }),

                new DocSection("Four names, four paths to the same width", [
                    "The curve is a NAME, not a function pointer: a style is a data record built once at",
                    "class load, so it cannot capture a closure. An unknown name throws -- a typo must not",
                    "silently become a linear animation."
                ], [
                    "width = 40 + 260 * Ease.apply(\"outCubic\", t);  // linear | outQuad | outCubic | ...",
                    "Ease.has(\"outCubic\");                           // non-throwing membership test"
                ], 152, function ():Node
                {
                    // Every bar is the SAME node at the SAME moment, so the four widths differ by
                    // the curve alone. Stepping `t` tweens each one along its own path: they move
                    // together in time, never together in distance, and they land on 300 as one.
                    var step:Boolean = m.bool("anim.b", false);
                    var t:Number = step ? 0.7 : 0.3;
                    var rows:Array = [];
                    for (var i:int = 0; i < EASES.length; i++)
                    {
                        var name:String = String(EASES[i]);
                        var eased:Number = Ease.apply(name, t);
                        rows.push(row({ gap: 8, alignItems: "center" }, [
                            text(name, { style: StyleRefinement.from({
                                size: [Length.px(76), Length.px(12)],
                                text: { fontFamily: "Courier New", fontSize: 10, color: 0x64748B } }),
                                ariaName: "" }),
                            box({ key: "animBar:" + name, style: StyleRefinement.from({
                                size: [Length.px(40 + 260 * eased), Length.px(14)],
                                background: 0x2563EB, cornerRadii: 7,
                                transitionMs: 460, transitionEase: name }) }, []),
                            text(eased.toFixed(3), { style: DocsDemo.MONO, ariaName: "" })
                        ]));
                    }
                    rows.push(row({ gap: 10, alignItems: "center" }, [
                        button({ key: "animFlipB", label: step ? "Step t back" : "Step t forward",
                                 style: DocsDemo.QUIET,
                                 onClick: function ():void { m.put("anim.b", !step); } }),
                        text("t = " + (step ? "0.70" : "0.30") + ", one moment, four curves",
                             { style: DocsDemo.MONO, ariaName: "" })
                    ]));
                    return column({ gap: 6 }, rows);
                }),

                new DocSection("Paint fields do not reflow", [
                    "opacity, background, borderColor, textColor and cornerRadius change pixels only, so a",
                    "tween on them costs a repaint and nothing else. Width, height, padding and gap change",
                    "what flexbox must compute -- that is not a leak in the redraw rule, it is the author",
                    "asking the layout to move, and it is why those fields are opt-in per node."
                ], [
                    "Anim.isLayoutField(Anim.FIELD_WIDTH);     // true",
                    "Anim.isLayoutField(Anim.FIELD_OPACITY);   // false"
                ], 88, function ():Node
                {
                    var dim:Boolean = m.bool("anim.c", false);
                    return row({ gap: 18, alignItems: "center" }, [
                        box({ key: "animPaint", style: StyleRefinement.from({
                            size: [Length.px(96), Length.px(44)], cornerRadii: 8,
                            background: 0x2563EB, opacity: dim ? 0.18 : 1,
                            transitionMs: 300, transitionEase: "outQuad" }) }, []),
                        box({ key: "animLayout", style: StyleRefinement.from({
                            size: [Length.px(dim ? 180 : 96), Length.px(dim ? 64 : 44)],
                            cornerRadii: 8, background: 0x93C5FD,
                            transitionMs: 300, transitionEase: "outQuad" }) }, []),
                        button({ key: "animFlipC", label: dim ? "Restore" : "Fade + grow",
                                 style: DocsDemo.QUIET,
                                 onClick: function ():void { m.put("anim.c", !dim); } })
                    ]);
                }),

                new DocSection("The curve, drawn", [
                    "Not a screenshot: 44 boxes, each one's height written as `2 + 14 * Ease.apply(...)`.",
                    "That is the easing table itself, and the reason a tween lands exactly on its target is",
                    "visible in the last column -- every curve reaches 1, so every bar is the same height."
                ], [
                    "for (i = 0; i <= 10; i++)",
                    "    box({ style: { size: [11, 2 + 14 * Ease.apply(name, i / 10)] } })"
                ], 96, function ():Node
                {
                    return curveTable();
                })
            ];
        }

        // One swatch, optionally eased. A method, so the two swatches in the first
        // section cannot drift apart in colour or size.
        private static function tick(label:String, key:String, on:Boolean, ms:Number):Node
        {
            var style:StyleRefinement = StyleRefinement.from({
                size: [Length.px(96), Length.px(44)], cornerRadii: 8,
                background: on ? 0x2563EB : 0xE2E8F0
            });
            if (ms > 0) style = style.withPatch(StyleRefinement.from({
                transitionMs: ms, transitionEase: "outCubic" }));
            return column({ gap: 6 }, [
                text(label, { style: DocsDemo.MONO, ariaName: "" }),
                box({ key: key, style: style }, [])
            ]);
        }

        // 4 curves x 11 samples, drawn with the ease itself. Heights are POINT sizes
        // and the smallest is 2, so no bar is a zero-height box (the tour treats a
        // zero rect as a layout bug, and it would be right to).
        private static function curveTable():Node
        {
            var rows:Array = [];
            for (var r:int = 0; r < EASES.length; r++)
            {
                var name:String = String(EASES[r]);
                var cols:Array = [
                    text(name, { style: StyleRefinement.from({
                        size: [Length.px(76), Length.px(10)],
                        text: { fontFamily: "Courier New", fontSize: 9, color: 0x64748B } }),
                        ariaName: "" })
                ];
                for (var i:int = 0; i <= 10; i++)
                {
                    var t:Number = i / 10;
                    var h:Number = 2 + 14 * Ease.apply(name, t);
                    cols.push(box({ style: StyleRefinement.from({
                        size: [Length.px(11), Length.px(h)],
                        background: i == 10 ? 0x1D4ED8 : 0x93C5FD, cornerRadii: 2 }) }, []));
                }
                rows.push(row({ gap: 3, alignItems: "flex-end" }, cols));
            }
            return column({ gap: 2 }, rows);
        }

        // ---- gesture ---------------------------------------------------------

        private static function gesture(view:DocsView):Array
        {
            var m:DocsModel = view.model;

            return [
                new DocSection("The target is a rectangle, and it can be bigger", [
                    "Left: a 26pt tab. Right: the same tab inside a 44x44 container that carries the",
                    "handler -- the container is what the pick walk finds, so the whole box answers.",
                    "This is the technique, not a workaround: the runtime hits what a node PAINTED, so the",
                    "hit area is whatever the node drew. (An alpha-0 background is the invisible form.)"
                ], [
                    "box({ onClick: tap, style: { size: [44, 44], background: 0xF1F5F9 } },",
                    "    [ tabNode ])   // 44pt of target, 26pt of ink"
                ], 108, function ():Node
                {
                    return row({ gap: 28, alignItems: "center" }, [
                        column({ gap: 6, alignItems: "center" }, [
                            text("26pt", { style: DocsDemo.MONO, ariaName: "" }),
                            box({ key: "gsSmall", style: TAB,
                                  onClick: function ():void { m.put("gs.small", int(m.num("gs.small", 0)) + 1); } }, []),
                            text("hits: " + int(m.num("gs.small", 0)),
                                 { style: DocsDemo.MONO, ariaName: "" })
                        ]),
                        column({ gap: 6, alignItems: "center" }, [
                            text("44pt target", { style: DocsDemo.MONO, ariaName: "" }),
                            box({ key: "gsBig", style: StyleRefinement.from({
                                    size: [Length.px(44), Length.px(44)], background: 0xF1F5F9,
                                    cornerRadii: 6, alignItems: "center", justifyContent: "center" }),
                                  onClick: function ():void { m.put("gs.big", int(m.num("gs.big", 0)) + 1); } },
                                [ box({ style: TAB }, []) ]),
                            text("hits: " + int(m.num("gs.big", 0)),
                                 { style: DocsDemo.MONO, ariaName: "" })
                        ])
                    ]);
                }),

                new DocSection("Dragging is a divider that answers the pick", [
                    "The grip below is a splitPane: its divider is an ordinary child node painted as a bar,",
                    "which is what makes it hit-testable at all. A pointer series is normalized by",
                    "PointerRouter (Pointer in, press / move / release out), and a viewport a finger can",
                    "drag implements TouchScrollable. Both speak ROOT coordinates, so no transform maths."
                ], [
                    "splitPane(left, right, { direction: \"row\", ratio: 0.35, minSize: 110,",
                    "    dividerSize: 8, onResize: function (r:Number):void { m.put(\"gs.ratio\", r); } })"
                ], 156, function ():Node
                {
                    var ratio:Number = m.num("gs.ratio", 0.35);
                    // The column carries a DEFINITE width: a percentage child inside an auto-width
                    // parent has nothing to take a percentage OF, and would collapse.
                    return column({ gap: 6, style: StyleRefinement.from({
                            size: [Length.px(520), Length.px(140)] }) }, [
                        splitPane(
                            // [null, h]: a pane must NOT declare its MAIN-axis size. The widget
                            // writes each pane's flex basis (grow/shrink 0), and an explicit width
                            // in the pane's own style wins over that basis -- the split then falls
                            // back to equal halves. Leave the main axis null.
                            box({ style: StyleRefinement.from({
                                size: [null, 110], background: 0xDBEAFE,
                                padding: 10, cornerRadii: 6 }) },
                                [text("left pane", { style: DocsDemo.LABEL, ariaName: "" })]),
                            box({ style: StyleRefinement.from({
                                size: [null, 110], background: 0xF1F5F9,
                                padding: 10, cornerRadii: 6 }) },
                                [text("right pane", { style: DocsDemo.LABEL, ariaName: "" })]),
                            { key: "gsSplit", direction: "row", ratio: ratio,
                              minSize: 110, dividerSize: 8,
                              style: StyleRefinement.from({ size: [520, 110] }),
                              onResize: function (r:Number):void { m.put("gs.ratio", r); } }),
                        text("ratio " + ratio.toFixed(3),
                             { style: DocsDemo.MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("Disabled is inherited and it stops the pick", [
                    "One rule in the pick walk (UiNode.inert, walking the ancestor chain) means a disabled",
                    "container disables its whole subtree -- and the runtime's own hit test already",
                    "honours `mouseEnabled` / `mouseChildren`, so `disabled` is the only knob a page needs.",
                    "Click both: the right one is drawn, and it never answers."
                ], [
                    "box({ onClick: tap }, [...]),                 // answers",
                    "box({ onClick: tap, disabled: true }, [...]) // drawn, never picked"
                ], 72, function ():Node
                {
                    return row({ gap: 18, alignItems: "center" }, [
                        box({ key: "gsOn", style: StyleRefinement.from({
                            size: [Length.px(120), Length.px(40)], background: 0x2563EB,
                            cornerRadii: 8, alignItems: "center", justifyContent: "center" }),
                          onClick: function ():void { m.put("gs.on", int(m.num("gs.on", 0)) + 1); } },
                            [text("enabled " + int(m.num("gs.on", 0)),
                                  { style: StyleRefinement.from({
                                      text: { fontSize: 12, fontWeight: "bold", color: 0xFFFFFF } }),
                                    ariaName: "" })]),
                        box({ key: "gsOff", disabled: true, style: StyleRefinement.from({
                            size: [Length.px(120), Length.px(40)], background: 0x2563EB,
                            cornerRadii: 8, alignItems: "center", justifyContent: "center" }),
                          onClick: function ():void { m.put("gs.off", int(m.num("gs.off", 0)) + 1); } },
                            [text("disabled " + int(m.num("gs.off", 0)),
                                  { style: StyleRefinement.from({
                                      text: { fontSize: 12, fontWeight: "bold", color: 0xFFFFFF } }),
                                    ariaName: "" })])
                    ]);
                }),

                new DocSection("The platform's answers arrive through Env", [
                    "A phone shell binds an Env before mount; every value is a plain getter, and a change is",
                    "announced through the same Observable the data flow uses. A node that opts in with",
                    "`safeArea: true` gets the insets folded into its padding. Bind a fake phone here and",
                    "watch the box below grow a notch margin: that is the production path, not a mock."
                ], [
                    "app.bindEnv(phoneEnv);   // an EnvBase: setSafeArea(44,0,34,0), setHasHover(false)",
                    "box({ safeArea: true, style: { ... } })   // padding += the insets"
                ], 124, function ():Node
                {
                    return envDemo(view);
                })
            ];
        }

        private static function envDemo(view:DocsView):Node
        {
            var on:Boolean = view.isSimulated();
            var e:Env = view.app == null ? null : view.app.env;
            var readout:String = "no app yet";
            if (e != null)
            {
                readout = "insets "
                    + int(e.safeArea.top) + "/" + int(e.safeArea.right) + "/"
                    + int(e.safeArea.bottom) + "/" + int(e.safeArea.left)
                    + "   hover " + (e.hasHover ? "on" : "off");
            }
            return column({ gap: 8 }, [
                row({ gap: 10, alignItems: "center" }, [
                    button({ key: "gsSim", label: on ? "Phone bound" : "Bind a phone",
                             style: DocsDemo.QUIET,
                             onClick: function ():void { view.simulatePhone(); } }),
                    button({ key: "gsRestore", label: "Back to desktop", style: DocsDemo.QUIET,
                             onClick: function ():void { view.restoreEnv(); } }),
                    text(readout, { style: DocsDemo.MONO, ariaName: "" })
                ]),
                box({ key: "gsSafe", safeArea: true, style: StyleRefinement.from({
                    size: [Length.pct(1), Length.px(52)], background: 0xE8F0FE,
                    borderWidths: 1, borderColor: 0xBFDBFE, cornerRadii: 6 }) },
                    [text("safeArea: true -- my padding grows by the insets above",
                          { style: DocsDemo.LABEL, ariaName: "" })])
            ]);
        }
    }
}
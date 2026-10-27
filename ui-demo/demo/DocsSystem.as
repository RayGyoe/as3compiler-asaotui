// demo/DocsSystem.as -- the five pages that are about the FRAMEWORK rather than
// about one widget: `style` (the field vocabulary), `theme` (the four layers the
// resolver merges), `state` (bindings and notifications), `events` (the three
// pointer callbacks and what the runtime gates) and `keyboard` (focus, the ring,
// which kind answers to which key, and the keymap).
//
// WHY THESE FOUR PAGES EXIST (audit, 2026-10-26)
// ----------------------------------------------
// Every one of the 37 kinds had a page, and the cross-cutting half of the library
// was still invisible: 14 of the 35 style fields (minSize, maxSize, flexShrink,
// boxSizing, alignSelf, alignContent, overflow, display, aspectRatio, opacity,
// visibility, cursor, transitionMs, transitionEase), 4 of the 11 text fields
// (fontStyle, leading, letterSpacing, textAlign) and ALL of `bindTo`/`Binding`
// were never written by a single page -- even though `pagination`'s and `tabs`'
// prose CLAIMED a Binding. A capability nobody can see is a capability nobody
// will use, and prose alone cannot be checked: each section here carries a live
// demo and the source that produced it, the same unit the widget pages use.
//
// `theme` USED TO say a live switch was impossible. That stopped being true on
// 2026-10-27, when `setControlDefault` became an override layer (survives a swap)
// and `Theme.setTheme` grew an epoch that `UiApp` turns into a re-describe. The
// page now OPENS with the swap demo and closes with what `setControlDefault`
// does and does not reach: the next resolve, not the nodes already on screen.
package demo
{
    import asaot.ui.ActionRegistry;
    import asaot.ui.Dirty;
    import asaot.ui.Node;
    import asaot.ui.Subscription;
    import asaot.ui.Theme;
    import asaot.ui.ThemeTokens;
    import asaot.ui.UiApp;
    import asaot.ui.badge;
    import asaot.ui.bindTo;
    import asaot.ui.box;
    import asaot.ui.button;
    import asaot.ui.card;
    import asaot.ui.checkbox;
    import asaot.ui.chip;
    import asaot.ui.column;
    import asaot.ui.progress;
    import asaot.ui.row;
    import asaot.ui.tabs;
    import asaot.ui.text;
    import asaot.ui.textField;
    import asaot.ui.style.StyleRefinement;

    public final class DocsSystem
    {
        private static const A:uint = 0x2563EB;      // blue
        private static const B:uint = 0x7C3AED;      // violet
        private static const C:uint = 0x059669;      // green
        private static const D:uint = 0xF59E0B;      // amber

        private static const MONO:StyleRefinement = DocsDemo.MONO;
        private static const BOLD:StyleRefinement = DocsDemo.LABEL_B;
        // A fixed-width gutter label, so the two "overflow" rows line their boxes up.
        private static const OV_LABEL:StyleRefinement = StyleRefinement.from({
            size: [54, 16], text: { fontFamily: "Courier New", fontSize: 11, color: 0x64748B }
        });

        // One demo subscription for the `state` page's unsubscribe section. The
        // COUNT is a static, not a model field: a listener that wrote the model
        // while the model notifies would recurse through its own notify.
        private static var SUB:Subscription = null;
        private static var SUB_CALLS:int = 0;

        public static function sections(view:DocsView, id:String):Array
        {
            var m:DocsModel = view.model;
            var app:UiApp = view.getApp();

            if (id == "events") return [
                new DocSection("A right click brings its own point", [
                    "`onRightClick(x, y)` hands you the STAGE coordinates of the press, because a",
                    "right click exists to say \"open something HERE\" -- a handler without the point",
                    "would have to guess it from the pointer, which no event field exposes.",
                    "That pair is exactly what `menu({ atX, atY })` wants, so opening a menu at the",
                    "click is one assignment. The press BUBBLES like any other event, so a handler",
                    "on a container also hears its children."
                ], [
                    "box({ onRightClick: function (x:Number, y:Number):void {",
                    "    this.atX = x; this.atY = y; this.open = true;",
                    "    view.invalidate(Dirty.ALL);",
                    "} })"
                ], 104, function ():Node
                {
                    return row({ gap: 14, alignItems: "center" }, [
                        box({ key: "evRight", onRightClick: function (x:Number, y:Number):void
                                {
                                    m.put("ev.x", x);
                                    m.put("ev.y", y);
                                },
                                style: StyleRefinement.from({
                                    size: [180, 56], padding: 10, background: 0xDBEAFE,
                                    cornerRadii: 8, text: { fontSize: 12, color: 0x1E3A8A } }),
                                ariaName: "right click target" }, [
                                text("right-click anywhere here", { ariaName: "" })
                            ]),
                        text("last press: (" + int(m.num("ev.x", -1)) + ", "
                            + int(m.num("ev.y", -1)) + ") stage px",
                            { key: "evWhere", style: MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("A double click has to be switched on", [
                    "The runtime only emits `doubleClick` when the HIT TARGET's own",
                    "`doubleClickEnabled` is true, and it defaults to FALSE (measured on adl 51.4.1).",
                    "Switching it on globally would change what a fast second click means for every",
                    "control in the app, so `UiNode` sets it on exactly the nodes that carry an",
                    "`onDoubleClick` handler -- the flag follows the handler, not the author.",
                    "Double-click the left box: it counts. The right box has no handler, so the flag",
                    "stays off and the same gesture reaches nothing."
                ], [
                    "box({ onDoubleClick: pick })          // doubleClickEnabled = true",
                    "box({ onClick: pick })                // stays false",
                    "// UiNode.applyPayload:",
                    "backing.doubleClickEnabled = (this.onDoubleClick != null);"
                ], 104, function ():Node
                {
                    return row({ gap: 14, alignItems: "center" }, [
                        box({ key: "evDbl", onDoubleClick: function ():void
                                {
                                    m.put("ev.dbl", int(m.num("ev.dbl", 0)) + 1);
                                },
                                style: StyleRefinement.from({
                                    size: [150, 56], padding: 10, background: 0xDCFCE7,
                                    cornerRadii: 8, text: { fontSize: 12, color: 0x14532D } }),
                                ariaName: "double click target" }, [
                                text("double-click me", { ariaName: "" })
                            ]),
                        box({ style: StyleRefinement.from({
                            size: [150, 56], padding: 10, background: 0xF1F5F9,
                            cornerRadii: 8, text: { fontSize: 12, color: 0x64748B } }),
                            ariaName: "no double click target" }, [
                            text("no handler here", { ariaName: "" })
                        ]),
                        text("counted " + int(m.num("ev.dbl", 0)),
                            { key: "evDblCount", style: MONO, ariaName: "" })
                    ]);
                })
            ];

            if (id == "style") return [
                new DocSection("size, minSize, maxSize", [
                    "`size` is the box you ask for; `minSize` and `maxSize` clamp what you get. The",
                    "clamp wins over the request in both directions, and it is applied by the layout",
                    "engine AFTER the flex solve -- which is why a scroll view stops its own content",
                    "from shrinking with a min and never with a flex."
                ], [
                    "box({ size: [180, 36] }),                      // 180 wide",
                    "box({ size: [180, 36], maxSize: [96, 36] }),   // 96: the max wins",
                    "box({ size: [96, 36],  minSize: [180, 36] })   // 180: the min wins"
                ], 96, function ():Node
                {
                    return column({ gap: 4 }, [
                        row({ gap: 10, alignItems: "flex-start" }, [
                            box({ style: StyleRefinement.from({
                                size: [180, 36], background: A, cornerRadii: 6 }), ariaName: "" }),
                            box({ style: StyleRefinement.from({
                                size: [180, 36], maxSize: [96, 36], background: B,
                                cornerRadii: 6 }), ariaName: "" }),
                            box({ style: StyleRefinement.from({
                                size: [96, 36], minSize: [180, 36], background: C,
                                cornerRadii: 6 }), ariaName: "" })
                        ]),
                        text("requested 180 / 180 / 96  ->  laid out 180 / 96 / 180",
                            { key: "stCap1", style: MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("flexShrink: who gives way", [
                    "Three 120-wide children in a 300-wide row is 360 of demand, so 60 has to go.",
                    "`flexShrink` (default 1) shares that deficit by SIZE: the two shrinkers give 30",
                    "each. A child with `flexShrink: 0` is a floor -- it keeps its 120 and the others",
                    "pay the whole deficit. This is also the switch that makes `overflow` visible: a",
                    "shrinkable child never sticks out.",
                    "THE ONE TRAP: writing ANY flex field (grow, shrink or basis) REPLACES the item's",
                    "base size, so `flexShrink: 0` alone means `flex: 0 0 0` and the node collapses to",
                    "nothing -- measured here, 120 -> 0. Write the basis you start from."
                ], [
                    "row({ size: [300, 36], gap: 0 }, [",
                    "    box({ width: 120, flexBasis: 120, flexShrink: 1 }),",
                    "    box({ width: 120, flexBasis: 120, flexShrink: 0 }),   // keeps 120",
                    "    box({ width: 120, flexBasis: 120, flexShrink: 1 })",
                    "])"
                ], 96, function ():Node
                {
                    return column({ gap: 4 }, [
                        row({ style: StyleRefinement.from({ size: [300, 36], gap: 0 }) }, [
                            box({ style: StyleRefinement.from({
                                size: [120, 36], flexBasis: 120, flexShrink: 1,
                                background: A, cornerRadii: 6 }), ariaName: "" }),
                            box({ style: StyleRefinement.from({
                                size: [120, 36], flexBasis: 120, flexShrink: 0,
                                background: B, cornerRadii: 6 }), ariaName: "" }),
                            box({ style: StyleRefinement.from({
                                size: [120, 36], flexBasis: 120, flexShrink: 1,
                                background: C, cornerRadii: 6 }), ariaName: "" })
                        ]),
                        text("90 / 120 / 90 -- the middle child was the only one that could not give",
                            { key: "stCap2", style: MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("boxSizing: where the border and the padding live", [
                    "`borderBox` (the kit's default, and CSS's own default once you opt in) means",
                    "`size` INCLUDES padding and border. `contentBox` means `size` is the CONTENT, so",
                    "the padding and the border grow the box outward -- the same 120-wide request",
                    "becomes a 144-wide node. Pick one per component and never mix them in a row."
                ], [
                    "// borderBox: 120 total",
                    "box({ size: [120, 40], padding: 10, border: 2 }),",
                    "// contentBox: 120 content + 20 padding + 4 border = 144",
                    "box({ size: [120, 40], padding: 10, border: 2, boxSizing: \"contentBox\" })"
                ], 96, function ():Node
                {
                    return column({ gap: 4 }, [
                        row({ gap: 24, alignItems: "flex-start" }, [
                            box({ style: StyleRefinement.from({
                                size: [120, 40], padding: 10, borderWidths: 2, borderColor: 0x1D4ED8,
                                background: 0xDBEAFE, cornerRadii: 4 }), ariaName: "" }),
                            box({ style: StyleRefinement.from({
                                size: [120, 40], padding: 10, borderWidths: 2, borderColor: 0x6D28D9,
                                boxSizing: "contentBox", background: 0xEDE9FE,
                                cornerRadii: 4 }), ariaName: "" })
                        ]),
                        text("borderBox 120x40   /   contentBox 144x64",
                            { key: "stCap4", style: MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("margin is outside, padding is inside", [
                    "`padding` pushes the CONTENT in from the node's own edge. `margin` moves the node",
                    "itself away from its siblings and from its parent's content edge -- the row below",
                    "has `gap: 0`, so every pixel between the tiles is the middle tile's margin."
                ], [
                    "row({ gap: 0 }, [",
                    "    box({ width: 60 }),",
                    "    box({ width: 60, margin: 12 }),   // 12 on every side",
                    "    box({ width: 60 })",
                    "])"
                ], 118, function ():Node
                {
                    return column({ gap: 4 }, [
                        row({ style: StyleRefinement.from({ size: [null, 60], gap: 0 }) }, [
                            box({ style: StyleRefinement.from({
                                size: [60, 36], background: A, cornerRadii: 6 }), ariaName: "" }),
                            box({ style: StyleRefinement.from({
                                size: [60, 36], margin: 12, background: B,
                                cornerRadii: 6 }), ariaName: "" }),
                            box({ style: StyleRefinement.from({
                                size: [60, 36], background: C, cornerRadii: 6 }), ariaName: "" })
                        ]),
                        text("gap 0, and yet 12px of air on each side of the middle tile",
                            { key: "stCap5", style: MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("alignSelf: one child disagrees with the row", [
                    "`alignItems` is the row's default for the cross axis; `alignSelf` lets ONE child",
                    "opt out of it. Both take flex-start / flex-end / center / stretch / baseline, and",
                    "an unknown value THROWS rather than quietly centring."
                ], [
                    "row({ size: [null, 80], alignItems: \"flex-start\" }, [",
                    "    box({ width: 60, height: 32 }),",
                    "    box({ width: 60, height: 32, alignSelf: \"flex-end\" }),",
                    "    box({ width: 60, height: 32 })",
                    "])"
                ], 138, function ():Node
                {
                    return column({ gap: 4 }, [
                        row({ style: StyleRefinement.from({
                            size: [null, 80], alignItems: "flex-start", gap: 10,
                            background: 0xF1F5F9, cornerRadii: 6 }) }, [
                            box({ style: StyleRefinement.from({
                                size: [60, 32], background: A, cornerRadii: 4 }), ariaName: "" }),
                            box({ style: StyleRefinement.from({
                                size: [60, 32], alignSelf: "flex-end", background: B,
                                cornerRadii: 4 }), ariaName: "" }),
                            box({ style: StyleRefinement.from({
                                size: [60, 32], background: C, cornerRadii: 4 }), ariaName: "" })
                        ]),
                        text("alignItems flex-start, the middle child alignSelf flex-end",
                            { key: "stCap6", style: MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("alignContent: where the wrapped lines go", [
                    "Only meaningful once the row WRAPS. `alignContent` places the LINE BOXES in the",
                    "cross-axis space the lines did not use: `space-between` pushes the first line to",
                    "the top, the last to the bottom and spreads the rest."
                ], [
                    "row({ size: [240, 120], flexWrap: \"wrap\", gap: 6,",
                    "      alignContent: \"space-between\" }, [ six 110x24 tiles ])"
                ], 178, function ():Node
                {
                    return column({ gap: 4 }, [
                        row({ style: StyleRefinement.from({
                            size: [240, 120], flexWrap: "wrap", gap: 6,
                            alignContent: "space-between", background: 0xF1F5F9,
                            cornerRadii: 6, padding: 4 }) }, [
                            solid(110, 24, A), solid(110, 24, B), solid(110, 24, C),
                            solid(110, 24, D), solid(110, 24, 0x0EA5E9), solid(110, 24, 0xDB2777)
                        ]),
                        text("three lines of two, spread over 120px of cross axis",
                            { key: "stCap7", style: MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("overflow: accepted, not yet painted", [
                    "`overflow` is where painting stops: `visible` (default), `hidden` (clip to the padding",
                    "box), `scroll` (reserved for a scroll view). The value is validated at describe time",
                    "and handed to the layout engine -- but NO painter clips with it yet (registered",
                    "as G29). Both strips below are 200 wide, both boxes 120: with `hidden` the strip still",
                    "paints its full width, and the box's own grey is hidden BEHIND it.",
                    "So treat it as reserved, not as a mask. What DOES clip today is component-level:",
                    "`scrollView` clips its viewport, and `image` with \"cover\" crops via scrollRect."
                ], [
                    "box({ width: 120, overflow: \"hidden\" }, [ strip ])   // accepted; not painted yet",
                    "// clipping that exists today:",
                    "//   scrollView({ ... })                      the viewport clips its content",
                    "//   image({ scaleMode: \"cover\" })           crops through scrollRect"
                ], 116, function ():Node
                {
                    return column({ gap: 6 }, [
                        overflowRow("visible", A),
                        overflowRow("hidden", B),
                        text("identical: the child keeps its 200px on both (G29)",
                            { key: "stCap8", style: MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("visible: false keeps the box, and the space", [
                    "The Element flag `visible: false` is CSS `visibility: hidden`: nothing paints,",
                    "but the node still measures, still arranges, and still holds its slot -- so a",
                    "page does not jump when it comes back. The style spelling of the same thing is",
                    "`visibility: \"hidden\"`, and it INHERITS to the subtree (a hidden card hides its",
                    "buttons), which is what `display: none` would otherwise be reached for.",
                    "Removing a node from LAYOUT is the author's decision in this kit, not a style's:",
                    "`render()` returns what exists this pass, and a node that should take no space is",
                    "a node you do not build. (The style field `display: \"none\"` exists and the",
                    "native engine implements it -- the AS3 engine does not; see the last section.)"
                ], [
                    "row([ tile, tile({ visible: false }), tile ])   // three tiles, middle invisible",
                    "// or, as a style: tile({ visibility: \"hidden\" })"
                ], 96, function ():Node
                {
                    return column({ gap: 6 }, [
                        row({ gap: 8 }, [
                            solid(56, 28, A), solidHidden(), solid(56, 28, C)
                        ]),
                        text("the middle tile paints nothing; its 56px and both 8px gaps stay",
                            { key: "stCap9", style: MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("opacity", [
                    "`opacity` multiplies what the node PAINTS (it is the backing object's alpha), and",
                    "it INHERITS: a 0.4 parent makes its children 0.4 too, which is what makes a dimmed",
                    "modal a single number instead of a colour per child. Hover and press modulation",
                    "composes on top of it, so a disabled area at 0.4 is still visibly disabled."
                ], [
                    "box({ opacity: 1.0 }),   box({ opacity: 0.6 }),   box({ opacity: 0.25 })"
                ], 98, function ():Node
                {
                    return column({ gap: 4 }, [
                        row({ gap: 12 }, [
                            solid(90, 40, A), dim(90, 40, A, 0.6), dim(90, 40, A, 0.25)
                        ]),
                        text("one colour, three opacities: 1.0 / 0.6 / 0.25",
                            { key: "stCap10", style: MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("Transitions: transitionMs + transitionEase", [
                    "`transitionMs` + `transitionEase` retarget the ANIMATABLE fields after every",
                    "resolve, so the tween intercepts the single place every widget paints from and no",
                    "widget file knows about it: opacity, background, borderColor, text colour, a",
                    "uniform corner radius, width/height, padding and gap.",
                    "A node with no `transitionMs` snaps. Unknown ease names THROW (linear | outQuad |",
                    "outCubic | inOutCubic). Gradients, percent sizes and non-uniform radii do NOT",
                    "tween -- there is nothing exact to interpolate, so the tween is dropped rather",
                    "than approximated. The frame loop drives the clock (`getTimer`, wall time, so a",
                    "120Hz display does not run the same tween twice as fast).",
                    "Press Toggle: the left tile eases 120->220 and blue->red in 320ms; the right one",
                    "has the same two styles and no transition, so it jumps."
                ], [
                    "box({ width: on ? 220 : 120, transitionMs: 320,",
                    "      transitionEase: \"outCubic\",",
                    "      background: on ? 0xDC2626 : 0x2563EB })"
                ], 132, function ():Node
                {
                    var on:Boolean = m.bool("tr.on", false);
                    return column({ gap: 10 }, [
                        row({ gap: 10, alignItems: "center" }, [
                            button({ key: "stTrBtn", label: on ? "Set off" : "Set on",
                                     style: DocsDemo.QUIET,
                                     onClick: function ():void { m.put("tr.on", !on); } }),
                            text("on: " + on, { key: "stTrState", style: MONO, ariaName: "" })
                        ]),
                        row({ gap: 10, alignItems: "center" }, [
                            tweenBox(on, true), tweenBox(on, false)
                        ]),
                        text("left: transitionMs 320   right: none",
                            { key: "stTrCap", style: MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("Three engine calls the AS3 layout engine refuses", [
                    "This page documents the WHOLE style vocabulary, so it has to say which parts",
                    "of it the shipped layout engine actually implements. `seam/asaot/ui/as3/`",
                    "throws on three calls by design (seam/README.md's table): a wrong rectangle",
                    "would be worse than a refused one, and the refusal names the gap.",
                    "The native arm (NativeLayoutEngine, Yoga) implements all three. So `display`",
                    "and `aspectRatio` are real fields -- they typecheck, they merge, they reach",
                    "UiNode -- and on the pure-AS3 arm they are a ONE-WAY DOOR INTO AN ERROR, which",
                    "is why this page cannot show them live: a page that throws takes the whole tour",
                    "with it, and the correct thing to show is the refusal itself.",
                    "What to write instead: `visible: false` (previous section) hides without",
                    "reclaiming space; a node that should take NO space is a node `render()` does",
                    "not return this pass; and an aspect ratio is `size: [w, w / 2]`."
                ], [
                    "// kit/asaot/ui/UiNode.as -> eng.setDisplay / setAspectRatio",
                    "display \"none\"   -> As3LayoutEngine.setDisplay:      未实现",
                    "aspectRatio     -> As3LayoutEngine.setAspectRatio:   未实现",
                    "// and the seam's intrinsic-size hook: setMeasure:     未实现"
                ], 96, function ():Node
                {
                    return column({ gap: 6 }, [
                        text("display      -> setDisplay      -> throw",
                            { key: "stGap1", style: MONO, ariaName: "" }),
                        text("aspectRatio  -> setAspectRatio  -> throw",
                            { key: "stGap2", style: MONO, ariaName: "" }),
                        text("the native arm has all three; the docs run on the AS3 arm",
                            { key: "stGap3", style: MONO, ariaName: "" })
                    ]);
                })
            ];

            if (id == "theme") return [
                new DocSection("A palette you can swap at run time", [
                    "Theme.tokens() is the live palette: 47 slots, ONE instance, read by every",
                    "widget at paint time. Theme.setTheme(ThemeTokens.dark()) copies a palette in,",
                    "rebuilds the per-kind baselines and the overlay chrome, and bumps",
                    "themeEpoch(). UiApp compares that epoch at the frame boundary, marks every",
                    "node style-stale and asks for one re-describe -- so the whole tree follows in",
                    "ONE frame, with no relayout (a palette never changes a number).",
                    "The buttons below swap the DOCS APP itself, not a card inside it. That is the",
                    "feature: a theme is application-wide, and a preview that themed one panel",
                    "only would be a lie about what the call does. Press Light to come back.",
                    "An author colour does not move. A swap replaces the BASELINE, so the blue chip",
                    "below stays blue in both themes; only the unspecific things (surfaces,",
                    "borders, text, tracks) follow.",
                    "Theme.tokens() is read-only by contract. To customise one slot: clone it,",
                    "assign, then setTheme -- copying in is what keeps the epoch honest."
                ], [
                    "Theme.setTheme(ThemeTokens.dark());    // a whole palette, one call",
                    "Theme.setTheme(ThemeTokens.light());",
                    "",
                    "var t:ThemeTokens = Theme.tokens().clone();",
                    "t.accent = 0x059669;                  // one slot off the shipped palette",
                    "Theme.setTheme(t);                    // copies in, bumps the epoch"
                ], 92, function ():Node
                {
                    return column({ gap: 10 }, [
                        row({ gap: 10, alignItems: "center" }, [
                            button({ key: "thmL", label: "Light", onClick: themeLight }),
                            button({ key: "thmD", label: "Dark", onClick: themeDark }),
                            button({ key: "thmA", label: "Green accent", onClick: themeGreen }),
                            text("epoch " + Theme.themeEpoch(), { style: MONO, ariaName: "" })
                        ]),
                        row({ gap: 10, alignItems: "center" }, [
                            progress("", { value: 0.4,
                                           style: StyleRefinement.from({ size: [120, 10] }) }),
                            badge("follows", { tone: "info" }),
                            chip("author: blue", { style: StyleRefinement.from({
                                background: 0x2563EB, text: { color: 0xFFFFFF } }) }),
                            text("surfaces + text follow, authored colours do not",
                                 { style: MONO, ariaName: "" })
                        ])
                    ]);
                }),

                new DocSection("Layer 1: the control default", [
                    "With no style at all, a control is painted by the kit's baseline FOR ITS KIND -- a",
                    "button gets 9/14 padding, a 1px #D0D0D0 border, a 6px radius and #FFF1F3F5; a",
                    "text input gets 7/10 and a white fill; a checkbox gets neither. Nothing here is a",
                    "constant of the layout engine: it is a table (`Theme.controlDefault`)."
                ], [
                    "button({ label: \"Default\" })          // no style key at all",
                    "textField({ placeholder: \"Default\" }) // only the width is set below",
                    "checkbox({ label: \"Default\" })"
                ], 96, function ():Node
                {
                    return column({ gap: 10 }, [
                        row({ gap: 12, alignItems: "center" }, [
                            button({ key: "thA", label: "Default", onClick: function ():void { } }),
                            textField({ key: "thF", placeholder: "Default field",
                                        style: StyleRefinement.from({ size: [170, null] }) }),
                            checkbox({ key: "thC", label: "Default", checked: false,
                                       onChange: function (v:Boolean):void { } })
                        ]),
                        text("every control above carries zero style keys of its own",
                            { key: "thCap1", style: MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("Layer 3: text inherits, layout does not", [
                    "Only the typography subset cascades (fontFamily, fontSize, fontWeight, fontStyle,",
                    "colour, leading, letterSpacing, textAlign, whiteSpace, textOverflow,",
                    "textDecoration) plus `visibility`. So the box below sets 16px bold indigo once and",
                    "BOTH children pick it up -- including the button, whose own 14px baseline is",
                    "lower priority than the inherited value.",
                    "Layout never cascades: the button keeps its own 9/14 padding and its own height,",
                    "because inheriting padding or size is the classic flexbox trap that looks right",
                    "on a shallow tree and diverges from every browser."
                ], [
                    "box({ text: { fontSize: 16, fontWeight: \"bold\", color: 0x3730A3 } }, [",
                    "    text(\"inherits 16/bold/indigo\"),",
                    "    button({ label: \"and so does a button\" })   // but not its padding",
                    "])"
                ], 138, function ():Node
                {
                    return box({ style: StyleRefinement.from({
                        padding: 12, gap: 8, background: 0xEEF2FF, cornerRadii: 8,
                        text: { fontSize: 16, fontWeight: "bold", color: 0x3730A3 } }), ariaName: "" }, [
                        text("inherits 16 / bold / indigo", { ariaName: "" }),
                        row({ gap: 10, alignItems: "center" }, [
                            button({ label: "and so does a button", onClick: function ():void { } }),
                            text("(its padding stays 9/14)", { style: MONO, ariaName: "" })
                        ])
                    ]);
                }),

                new DocSection("Layer 4: the author wins", [
                    "The node's own refinement is merged LAST, so it beats the control default and the",
                    "inherited value. Two buttons, one style key apart -- and this is why variants are",
                    "styles and not kinds: there is exactly one button behaviour."
                ], [
                    "button({ label: \"Theme\" }),",
                    "button({ label: \"Author\", style: StyleRefinement.from({",
                    "    background: 0x2563EB, borderColor: 0x1D4ED8,",
                    "    text: { color: 0xFFFFFF } }) })"
                ], 96, function ():Node
                {
                    return column({ gap: 8 }, [
                        row({ gap: 10, alignItems: "center" }, [
                            button({ key: "thL4a", label: "Theme",
                                     onClick: function ():void { } }),
                            button({ key: "thL4b", label: "Author",
                                     style: StyleRefinement.from({
                                         background: 0x2563EB, borderColor: 0x1D4ED8,
                                         text: { color: 0xFFFFFF } }),
                                     onClick: function ():void { } }),
                            text("same kind, same size, one refinement apart",
                                { style: MONO, ariaName: "" })
                        ])
                    ]);
                }),

                new DocSection("The cursor is a policy, not a default", [
                    "Kinds whose whole region IS the interactive thing (button, checkbox, radio, switch,",
                    "slider, select, combobox, tabs, menu, accordion, pagination, breadcrumb, chip,",
                    "datePicker) get `hand` from the theme. A SELECTABLE REGION -- list, table, tree,",
                    "scroll view -- does not: a hand over every pixel of a 400px list claims every",
                    "pixel is clickable, and a pointer that lies feels broken.",
                    "An author opts in per node with `cursor`, and an unknown name THROWS rather than",
                    "falling back to the arrow: auto | arrow | button | hand | ibeam."
                ], [
                    "chip(\"theme: hand\"),                      // kind default",
                    "box({ onClick: pick, cursor: \"hand\" }),   // author opt-in",
                    "box({ /* nothing */ })                    // arrow"
                ], 110, function ():Node
                {
                    return column({ gap: 8 }, [
                        row({ gap: 14, alignItems: "center" }, [
                            chip("theme: hand"),
                            box({ style: StyleRefinement.from({
                                size: [140, 32], background: 0xE0E7FF, cornerRadii: 6,
                                cursor: "hand", justifyContent: "center",
                                alignItems: "center", text: { fontSize: 11, color: 0x3730A3 } }),
                                ariaName: "", onClick: function ():void { } }, [
                                text("author: hand", { ariaName: "" })
                            ]),
                            box({ style: StyleRefinement.from({
                                size: [110, 32], background: 0xF1F5F9, cornerRadii: 6,
                                justifyContent: "center", alignItems: "center",
                                text: { fontSize: 11, color: 0x475569 } }), ariaName: "" }, [
                                text("arrow", { ariaName: "" })
                            ])
                        ]),
                        text("hover them: the shape changes, the region does not",
                            { key: "thCap4", style: MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("setControlDefault: an override layer, and it survives a swap", [
                    "A control's baseline is replaceable one kind at a time. Build the Style FROM the",
                    "current default and change only what you mean -- a partial Style would write its",
                    "own unset (null) fields over the baseline and erase the rest.",
                    "It is an OVERRIDE LAYER, not a write into the default table: the resolver reads",
                    "it before the kind baseline, and Theme.setTheme does not touch it. So flipping",
                    "light/dark keeps the author's custom button -- call clearControlDefault to get",
                    "the shipped baseline back.",
                    "The call still takes effect on the NEXT resolve, and a mounted node only",
                    "re-resolves when something stales it. To see it now, bump the epoch yourself:",
                    "Theme.setTheme(Theme.tokens().clone()) -- the same path a theme swap takes, one",
                    "call, no re-mount."
                ], [
                    "var s:Style = new Style();",
                    "Theme.controlDefault(\"button\").copyInto(s);   // keep what you do not change",
                    "s.padding = Edges.of(8, 12, 8, 12);",
                    "s.cornerRadii = Corners.all(999);",
                    "s.background = Fill.solid(0x0F172A);",
                    "s.text.color = 0xFFFFFF;",
                    "Theme.setControlDefault(\"button\", s);        // then mount"
                ], 96, function ():Node
                {
                    return column({ gap: 6 }, [
                        text("the four layers, low to high priority:",
                            { style: BOLD, ariaName: "" }),
                        text("1 controlDefault(kind)  2 theme slot  3 inherited subset  4 node.style",
                            { style: MONO, ariaName: "" })
                    ]);
                })
            ];

            if (id == "state") return [
                new DocSection("A Binding is a field pointer", [
                    "`bindTo(model, \"field\")` reads one public field and writes it back, notifying",
                    "Dirty.VALUE on every write. Eleven factories accept one where a value is an index,",
                    "a flag or a string: checkbox.checked, toggle.checked, radio.selected,",
                    "slider.value, textField.value, textArea.value, list.selectedIndex,",
                    "table.selectedIndex, tabs.selectedIndex, pagination.page, and",
                    "accordion.activeIndex/openIndices.",
                    "The point is not brevity: a bound control has NO local copy of the value, so the",
                    "field and the pixels cannot disagree."
                ], [
                    "tabs([\"Overview\", \"Billing\", \"Keys\"], {",
                    "    selectedIndex: bindTo(model, \"tabIdx\")",
                    "}),",
                    "checkbox({ label: \"bound\", checked: bindTo(model, \"chkOn\") })"
                ], 132, function ():Node
                {
                    return column({ gap: 10 }, [
                        tabs(["Overview", "Billing", "Keys"],
                            { key: "stTabs", gap: 6,
                              style: StyleRefinement.from({ size: [340, 32] }),
                              selectedIndex: bindTo(m, "tabIdx"),
                              onChange: function (i:int):void { } }),
                        row({ gap: 14, alignItems: "center" }, [
                            checkbox({ key: "stChk", label: "bound to model.chkOn",
                                       checked: bindTo(m, "chkOn"),
                                       onChange: function (v:Boolean):void { } }),
                            text("tabIdx " + m.tabIdx + "  chkOn " + m.chkOn,
                                { key: "stBindLive", style: MONO, ariaName: "" })
                        ])
                    ]);
                }),

                new DocSection("The field is the only owner", [
                    "Nothing below reaches into a widget: the button writes the field and notifies, and",
                    "the strip re-describes from the same number. That is the whole interaction",
                    "contract of the kit -- a widget reports, the author writes, the next render",
                    "re-describes -- and a Binding is just the shortest way to hold up your end."
                ], [
                    "button({ label: \"Next tab\", onClick: function ():void {",
                    "    model.tabIdx = (model.tabIdx + 1) % 3;",
                    "    model.notify(Dirty.VALUE);",
                    "} })"
                ], 138, function ():Node
                {
                    return column({ gap: 10 }, [
                        tabs(["Overview", "Billing", "Keys"],
                            { key: "stTabs2", gap: 6,
                              style: StyleRefinement.from({ size: [340, 32] }),
                              selectedIndex: bindTo(m, "tabIdx"),
                              onChange: function (i:int):void { } }),
                        row({ gap: 10, alignItems: "center" }, [
                            button({ key: "stNext", label: "Next tab", style: DocsDemo.QUIET,
                                     onClick: function ():void
                                     {
                                         m.tabIdx = (m.tabIdx + 1) % 3;
                                         m.notify(Dirty.VALUE);
                                     } }),
                            text("tabIdx " + m.tabIdx, { style: MONO, ariaName: "" })
                        ])
                    ]);
                }),

                new DocSection("notify: what a bit actually costs", [
                    "The mask is recorded (`invalidate(dirty)` ORs it) and the frame boundary asks one",
                    "question: is anything pending? If yes, the view is described and reconciled ONCE.",
                    "The bits themselves are the vocabulary a view uses to say what changed -- all",
                    "four behave alike at the boundary today.",
                    "What really saves work is the PER-NODE bit: a repaint never re-solves layout,",
                    "which is why a hover and a spinner cost no measure/arrange at all. The counters",
                    "below are the app's own fields, read on every render."
                ], [
                    "model.notify(Dirty.VALUE);      // 1: a data value changed",
                    "model.notify(Dirty.STRUCTURE);  // 4: children/keys changed",
                    "model.notify(Dirty.ALL);        // 15",
                    "app.invalidate(Dirty.VALUE);    // the same entry point the app subscribes to"
                ], 132, function ():Node
                {
                    var d:String = app == null ? "-" : String(app.describeCalls);
                    var s:String = app == null ? "-" : String(app.layoutSolves);
                    var p:String = app == null ? "-" : String(app.paintPasses);
                    return column({ gap: 8 }, [
                        text("describe " + d + "   solves " + s + "   paints " + p,
                            { key: "stCounters", style: MONO, ariaName: "" }),
                        row({ gap: 10, alignItems: "center" }, [
                            button({ key: "stVal", label: "notify(VALUE)", style: DocsDemo.QUIET,
                                     onClick: function ():void { m.notify(Dirty.VALUE); } }),
                            button({ key: "stAll", label: "notify(ALL)", style: DocsDemo.QUIET,
                                     onClick: function ():void { m.notify(Dirty.ALL); } })
                        ])
                    ]);
                }),

                new DocSection("subscribe returns a Subscription", [
                    "`Observable.subscribe(listener)` returns a `Subscription`; `unsubscribe(s)` detaches",
                    "it. Listeners run synchronously in registration order and are never called after",
                    "they are removed -- which is what makes a controller free to subscribe in its",
                    "constructor and unsubscribe in its teardown.",
                    "The docs app does exactly this once: `DocsMain` subscribes and turns every notify",
                    "into `app.invalidate(dirty)`. The counter below is a SECOND listener, so",
                    "subscribing and unsubscribing changes the count without changing the page."
                ], [
                    "var sub:Subscription = model.subscribe(function (d:int):void {",
                    "    calls = calls + 1;",
                    "});",
                    "model.unsubscribe(sub);   // no further calls"
                ], 138, function ():Node
                {
                    return column({ gap: 8 }, [
                        text("listener calls: " + SUB_CALLS, { key: "stSubCount", style: MONO,
                                                              ariaName: "" }),
                        row({ gap: 10, alignItems: "center" }, [
                            button({ key: "stSub", label: "Subscribe", style: DocsDemo.QUIET,
                                     onClick: function ():void { subscribeDemo(m); } }),
                            button({ key: "stUnsub", label: "Unsubscribe", style: DocsDemo.QUIET,
                                     onClick: function ():void { unsubscribeDemo(m); } }),
                            button({ key: "stEmit", label: "notify", style: DocsDemo.QUIET,
                                     onClick: function ():void { m.notify(Dirty.VALUE); } })
                        ])
                    ]);
                })
            ];

            if (id == "keyboard") return [
                new DocSection("Tab moves the ring; Shift+Tab walks it back", [
                    "`UiApp` walks the RETAINED tree in reading order and moves the library's focus",
                    "pointer, then CANCELS the runtime's own Tab walk -- otherwise one press would",
                    "move two rings. A stop is a node with `tabEnabled` that is visible and not inside",
                    "a disabled subtree.",
                    "Wake the field with Focus it and press Tab: the ring goes field -> Second ->",
                    "back to the field."
                ], [
                    "// UiApp.onKeyDown",
                    "if (kc == 9) {",
                    "    this.focusNext(e.shiftKey ? -1 : 1);",
                    "    e.preventDefault();   // the runtime must not move it too",
                    "    return;",
                    "}"
                ], 138, function ():Node
                {
                    return column({ gap: 10 }, [
                        row({ gap: 10, alignItems: "center" }, [
                            textField({ key: "kbField", placeholder: "Tab from here",
                                        style: StyleRefinement.from({ size: [180, null] }) }),
                            button({ key: "kbSecond", label: "Second", style: DocsDemo.QUIET,
                                     onClick: function ():void { } })
                        ]),
                        row({ gap: 10, alignItems: "center" }, [
                            button({ key: "kbFocus1", label: "Focus it", style: DocsDemo.PRIMARY,
                                     onClick: function ():void { focusKey(view, "kbField"); } }),
                            text("then Tab / Shift+Tab", { style: MONO, ariaName: "" })
                        ])
                    ]);
                }),

                new DocSection("Only some kinds are stops", [
                    "A Control is a stop by default. The kinds that are a readout or a GROUP opt out --",
                    "badge, avatar, chip, progress, breadcrumb, pagination, accordion -- because a stop",
                    "that does nothing when you press Enter is worse than no stop at all.",
                    "A list, table, tree, tab strip or menu is ONE stop for the whole widget: the",
                    "arrows move INSIDE it, which is the ARIA listbox/grid/tablist model and the only",
                    "way a 200-row table is reachable without 200 Tab presses.",
                    "The four nodes below sit in one row on purpose: press Tab and the ring only",
                    "ever lights the last one, because a chip is a tag and a progress bar is a readout."
                ], [
                    "// Control() sets tabEnabled = true; these kinds set it back to false:",
                    "badge, avatar, chip, progress, breadcrumb, pagination, accordion",
                    "// these are one stop for the WHOLE widget:",
                    "list, table, virtualList, tree, tabs, menu, select, combobox, datePicker"
                ], 118, function ():Node
                {
                    return column({ gap: 10 }, [
                        row({ gap: 12, alignItems: "center" }, [
                            badge("7", { tone: "info" }),
                            chip("chip"),
                            progress("half", { value: 0.5,
                                style: StyleRefinement.from({ size: [120, 18] }) }),
                            button({ key: "kbStop", label: "a stop", style: DocsDemo.QUIET,
                                     onClick: function ():void { } })
                        ]),
                        text("badge / chip / progress are skipped; the button is where the ring stops",
                            { key: "kbCap2", style: MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("Enter and Space press the focused control", [
                    "UiApp turns Enter or Space into the focused node's click, so a keyboard user never",
                    "needs a per-kind key handler for the simple case. The one exception is deliberate:",
                    "when the focus target is an editable TextField, Enter is that field's COMMIT and",
                    "Space is a character -- swallowing either would break typing."
                ], [
                    "if (kc == 13 || kc == 32) {",
                    "    if (f.focusTarget() is TextField) return;",
                    "    e.preventDefault();",
                    "    f.handleClick();",
                    "}"
                ], 138, function ():Node
                {
                    return column({ gap: 10 }, [
                        row({ gap: 10, alignItems: "center" }, [
                            button({ key: "kbAct", label: "Press me: 0", style: DocsDemo.QUIET,
                                     onClick: function ():void
                                     {
                                         m.put("kb.n", int(m.num("kb.n", 0)) + 1);
                                     } }),
                            text("pressed " + int(m.num("kb.n", 0)) + " time(s)",
                                { key: "kbCount", style: MONO, ariaName: "" })
                        ]),
                        row({ gap: 10, alignItems: "center" }, [
                            button({ key: "kbFocus2", label: "Focus it", style: DocsDemo.PRIMARY,
                                     onClick: function ():void { focusKey(view, "kbAct"); } }),
                            text("then press Enter (or Space) a few times",
                                { style: MONO, ariaName: "" })
                        ])
                    ]);
                }),

                new DocSection("Which keys each kind answers", [
                    "`WidgetKeys` is an OPTIONAL interface -- one `is` test at the one call site, so the",
                    "26 kinds that do not care pay nothing. It is called only for the FOCUSED node,",
                    "after Tab, and a return of true means \"consumed\" (the caller then cancels the",
                    "runtime's default action for that key).",
                    "The map below is kept in `WidgetKeys`'s own header, because \"which control answers",
                    "to which arrow\" is the one part of this contract nobody can guess: WRAP vs CLAMP",
                    "is semantics, not taste -- a tab strip or a tree is a ring, a list or a grid is a",
                    "sequence whose ends are walls (ARIA listbox/grid)."
                ], [
                    "menu          Up/Down (wrap), Enter/Space, Esc",
                    "select        Up/Down (wrap), Enter/Space, Esc; Down/Enter opens",
                    "combobox      as select, plus typing in the field",
                    "datePicker    Left/Right days (wrap), Up/Down a week, PgUp/PgDn a month",
                    "dialog/drawer/popover   Esc -> onClose",
                    "textField     Enter commits, Esc reverts to the last committed value",
                    "textArea      Esc reverts; Enter is NOT consumed (it inserts a newline)",
                    "tree          Up/Down (wrap), Left/Right collapse/expand, Home/End",
                    "list          Up/Down (CLAMP), Home/End",
                    "table         Up/Down (CLAMP), PgUp/PgDn a window, Home/End",
                    "virtualList   Up/Down, PgUp/PgDn, Home/End",
                    "tabs          Left/Right (WRAP), Home/End"
                ], 96, function ():Node
                {
                    return column({ gap: 6 }, [
                        text("one stop, arrows inside: list, table, virtualList, tree, tabs",
                            { style: BOLD, ariaName: "" }),
                        text("Esc closes what is open: dialog, drawer, popover, menu, select, datePicker",
                            { style: MONO, ariaName: "" }),
                        text("a keymap is consulted BEFORE all of it -- see the last two sections",
                            { style: MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("Disabled and hidden leave the ring", [
                    "A stop must be visible and not `inert()`. `disabled` INHERITS down the tree: a",
                    "disabled card takes its whole subtree out of the mouse AND out of the ring, which",
                    "is why it is one flag per element rather than a copy-down into every child.",
                    "The button below really tries to focus the inner control and reports the refusal:",
                    "`focusNode` returns without focusing an inert or invisible node instead of",
                    "half-focusing it."
                ], [
                    "card({ disabled: true }, [ button({ key: \"inner\", label: \"inner\" }) ])",
                    "app.focusNode(app.findByKey(\"inner\"));",
                    "app.focusedNode() == null   // still null: refused, not silently accepted"
                ], 138, function ():Node
                {
                    return column({ gap: 10 }, [
                        row({ gap: 12, alignItems: "center" }, [
                            card({ style: StyleRefinement.from({
                                size: [220, 64], padding: 10, background: 0xFFFFFF,
                                borderWidths: 1, borderColor: 0xE5E7EB, cornerRadii: 8,
                                gap: 6 }), ariaName: "", disabled: true }, [
                                text("a disabled card", { style: BOLD, ariaName: "" }),
                                button({ key: "kbInner", label: "inner button",
                                         onClick: function ():void { } })
                            ]),
                            text("focus attempt: " + m.val("kb.try", "-"),
                                { key: "kbTry", style: MONO, ariaName: "" })
                        ]),
                        button({ key: "kbFocus3", label: "Try to focus the inner one",
                                 style: DocsDemo.QUIET,
                                 onClick: function ():void
                                 {
                                     var a:UiApp = view.getApp();
                                     if (a == null) return;
                                     a.focusNode(a.findByKey("kbInner"));
                                     m.put("kb.try", a.focusedNode() == null ? "refused" : "focused");
                                 } })
                    ]);
                }),

                new DocSection("A keymap binds keys to ACTIONS, not to widgets", [
                    "Three pieces, one job each. `KeyStroke` parses \"ctrl-shift-s\" into a key code",
                    "plus four modifier flags; `ContextExpr` parses \"editor > modal\" into a predicate",
                    "over the tags on the FOCUS CHAIN; `ActionRegistry` holds the actions and the map",
                    "from a keystroke to an action id.",
                    "`setKeymap` takes an ARRAY of { context, bindings } objects -- there is no JSON",
                    "class in this compiler, so a JSON string would need its own parser -- and it",
                    "validates every string ONCE, at install time: a typo in a modifier fails when",
                    "you install the map, not at 3am on the one key the user pressed.",
                    "Matching is FIRST-ENTRY-WINS in declaration order, modifiers are matched",
                    "EXACTLY (a binding for `ctrl-s` does not fire while Shift is also held), and a",
                    "keystroke that matches nothing falls through to the built-ins, so typing is",
                    "untouched. The map is consulted BEFORE Tab as well: bind Tab and Tab is yours.",
                    "Install the map, focus the field, press ctrl-k."
                ], [
                    "ActionRegistry.register(\"palette.open\", openThePalette);",
                    "ActionRegistry.setKeymap([",
                    "    { context: \"docskey\", bindings: {",
                    "        \"ctrl-k\": [\"palette.open\", { from: \"keymap\" }],",
                    "        \"escape\": \"palette.close\" } },",
                    "    { context: \"docskey > modal\", bindings: { \"escape\": \"modal.cancel\" } }",
                    "]);",
                    "// the tag the predicate reads: column({ keyContext: \"docskey\" }, [...])"
                ], 150, function ():Node
                {
                    return column({ gap: 10, keyContext: "docskey", alignItems: "flex-start" }, [
                        row({ gap: 10, alignItems: "center" }, [
                            textField({ key: "kmField", placeholder: "focus, then ctrl-k",
                                        style: StyleRefinement.from({ size: [190, null] }) }),
                            button({ key: "kmInstall", label: "Install keymap",
                                     style: DocsDemo.QUIET,
                                     onClick: function ():void { installDemoKeymap(m); } })
                        ]),
                        text("fired " + int(m.num("km.n", 0)) + " time(s); map has "
                            + ActionRegistry.keymapEntryCount() + " entr(y/ies), "
                            + ActionRegistry.bindingCount() + " binding(s)",
                            { key: "kmCount", style: MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("`action` takes over Enter; `tabIndex` orders the ring", [
                    "`Control.action` is an action ID. With one set, Enter or Space runs the ACTION",
                    "and does NOT also run `onClick` -- one press, one effect. A control without an",
                    "action keeps the plain click, so nothing changes for code that never names one.",
                    "`tabIndex` orders the ring the way HTML does: every node with an explicit index",
                    "comes first, ascending (ties in document order), and everything left at -1",
                    "follows in document order. -1 means \"no explicit index\", NOT \"unreachable\" --",
                    "that is what `tabEnabled` and `disabled` are for.",
                    "Below, the LAST two buttons carry indices 0 and 1, so the ring starts at the",
                    "third row, not at the first button."
                ], [
                    "button({ action: \"docs.act\", label: \"Enter runs the action\" })",
                    "button({ label: \"first in the document\" })",
                    "button({ label: \"index 0\", tabIndex: 0 })",
                    "button({ label: \"index 1\", tabIndex: 1 })"
                ], 150, function ():Node
                {
                    if (!ActionRegistry.has("docs.act"))
                    {
                        ActionRegistry.register("docs.act", function (p:Object):void
                        {
                            m.put("ka.acts", int(m.num("ka.acts", 0)) + 1);
                        }, null);
                    }
                    return column({ gap: 10, alignItems: "flex-start" }, [
                        button({ key: "kaAct", label: "Enter runs the action",
                                 action: "docs.act", style: DocsDemo.QUIET,
                                 onClick: function ():void
                                 {
                                     m.put("ka.clicks", int(m.num("ka.clicks", 0)) + 1);
                                 } }),
                        text("action " + int(m.num("ka.acts", 0)) + " time(s), onClick "
                            + int(m.num("ka.clicks", 0)) + " time(s) -- Enter must move only the first",
                            { key: "kaCount", style: MONO, ariaName: "" }),
                        row({ gap: 10, alignItems: "center" }, [
                            button({ key: "kaIdx0", label: "index 0", tabIndex: 0,
                                     style: DocsDemo.QUIET,
                                     onClick: function ():void { } }),
                            button({ key: "kaIdx1", label: "index 1", tabIndex: 1,
                                     style: DocsDemo.QUIET,
                                     onClick: function ():void { } }),
                            text("Tab reaches index 0 first", { style: MONO, ariaName: "" })
                        ])
                    ]);
                })
            ];

            return null;
        }

        // ---- the little shapes the demos draw with ------------------------

        // A filled tile with no text: the geometry demos only need the box.
        private static function solid(w:Number, h:Number, c:uint):Node
        {
            return box({ style: StyleRefinement.from({
                size: [w, h], background: c, cornerRadii: 6 }), ariaName: "" });
        }

        // `visible: false` -- the same tile with its space still reserved.
        private static function solidHidden():Node
        {
            return box({ style: StyleRefinement.from({
                size: [56, 28], background: 0x94A3B8, cornerRadii: 6 }),
                ariaName: "", visible: false });
        }

        private static function dim(w:Number, h:Number, c:uint, o:Number):Node
        {
            return box({ style: StyleRefinement.from({
                size: [w, h], background: c, cornerRadii: 6, opacity: o }), ariaName: "" });
        }

        // A box whose width and fill the tween follows. The transition lives on ONE
        // node so the two are otherwise identical -- that is what makes the 320ms
        // visible as a difference rather than as "two red things".
        private static function tweenBox(on:Boolean, eased:Boolean):Node
        {
            var o:Object = {
                size: [on ? 220 : 120, 28],
                background: on ? 0xDC2626 : 0x2563EB,
                cornerRadii: 6
            };
            if (eased)
            {
                o.transitionMs = 320;
                o.transitionEase = "outCubic";
            }
            return box({ style: StyleRefinement.from(o), ariaName: "" });
        }

        // A 120-wide box holding a 200-wide strip. The TWO ROWS ARE DELIBERATELY IDENTICAL: no
        // painter honours `overflow` yet (G29), and a demo that pretended otherwise would be
        // the one thing this site must never be -- a picture that disagrees with the pixels.
        // The strip keeps its width through `minSize`, NOT through a flex field: a flex field
        // REPLACES the item's base size, and on a clipped box this engine then resolves that
        // basis on the WRONG axis (measured: a 200x28 strip came out 200 TALL).
        private static function overflowRow(ov:String, c:uint):Node
        {
            return row({ gap: 10, alignItems: "center" }, [
                text(ov, { style: OV_LABEL, ariaName: "" }),
                box({ style: StyleRefinement.from({
                    size: [120, 28], overflow: ov, background: 0xE2E8F0,
                    cornerRadii: 6 }) }, [
                    box({ style: StyleRefinement.from({
                        size: [200, 28], minSize: [200, 28],
                        background: c, cornerRadii: 6 }), ariaName: "" })
                ])
            ]);
        }

        // ---- the calls the keyboard demos make ----------------------------

        private static function focusKey(view:DocsView, key:String):void
        {
            var app:UiApp = view.getApp();
            if (app == null) return;
            app.focusNode(app.findByKey(key));
        }

        // The keymap demo installs ONE context-scoped binding, replacing any previous
        // map (setKeymap is a whole-map install, never an append -- that is what makes
        // it a configuration). Re-installing is therefore safe and idempotent.
        private static function installDemoKeymap(m:DocsModel):void
        {
            ActionRegistry.register("docs.bell", function (p:Object):void
            {
                m.put("km.n", int(m.num("km.n", 0)) + 1);
            }, null);
            ActionRegistry.setKeymap([
                { context: "docskey", bindings: { "ctrl-k": "docs.bell" } }
            ]);
            m.put("km.on", true);
        }

        // ---- the calls the theme demo makes -------------------------------
        //
        // A theme is application-wide by construction: `setTheme` copies a palette into
        // the ONE live instance, rebuilds the kind baselines and the overlay chrome, and
        // bumps the epoch. `UiApp` turns the epoch change into "mark every node
        // style-stale + re-describe", which is why these three one-line handlers can
        // repaint the whole docs app between two frames.
        //
        // The third one exists to show the CONTRACT, not a feature: `tokens()` is
        // read-only, so a custom palette is always clone -> assign -> setTheme. Mutating
        // the live instance would change pixels without bumping the epoch, which is the
        // silent inconsistency the palette copy exists to prevent.

        private static function themeLight():void
        {
            Theme.setTheme(ThemeTokens.light());
        }

        private static function themeDark():void
        {
            Theme.setTheme(ThemeTokens.dark());
        }

        private static function themeGreen():void
        {
            var t:ThemeTokens = Theme.tokens().clone();
            t.accent = 0x059669;
            Theme.setTheme(t);
        }

        private static function subscribeDemo(m:DocsModel):void
        {
            if (SUB != null) return;
            SUB = m.subscribe(function (d:int):void { SUB_CALLS = SUB_CALLS + 1; });
        }

        private static function unsubscribeDemo(m:DocsModel):void
        {
            if (SUB == null) return;
            m.unsubscribe(SUB);
            SUB = null;
        }
    }
}
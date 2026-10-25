// demo/DocsFeedback.as -- progress / spinner / skeleton / tooltip / image / icon: the
// leaves that show a state rather than an interaction.
package demo
{
    import asaot.ui.Node;
    import asaot.ui.box;
    import asaot.ui.button;
    import asaot.ui.column;
    import asaot.ui.icon;
    import asaot.ui.image;
    import asaot.ui.progress;
    import asaot.ui.row;
    import asaot.ui.skeleton;
    import asaot.ui.spinner;
    import asaot.ui.text;
    import asaot.ui.tooltip;
    import asaot.ui.style.StyleRefinement;

    import flash.display.BitmapData;
    import flash.geom.Rectangle;

    public final class DocsFeedback
    {
        // One static source for every image demo: identity is part of the contract
        // (the widget compares the BitmapData it was given last frame, and a fresh
        // bitmap per render would reload the texture every frame).
        private static var SRC8:BitmapData = null;

        // The band the cover demo crops: two halves, so a crop is a visible fact
        // rather than a guess about which pixels survived.
        private static var BAND:BitmapData = null;

        // The glyph data, written as an author would copy it out of an icon set. Kept in
        // one place so the two sizes in a row are provably the SAME data.
        private static const P_GLYPH_CROSS:String = "M12 5 V19 M5 12 H19";
        private static const P_GLYPH_CHECK:String = "M4 13 L9 18 L20 5";
        private static const P_GLYPH_BOLT:String = "M13 2 L4 14 H11 L10 22 L20 10 H13 Z";
        // Deliberately carries a cubic (C) and a smooth continuation (S): this is the
        // path that proves the subdivider ran, in a screenshot a human can look at.
        private static const P_GLYPH_HEART:String =
            "M12 20 C6 15 3 12 3 8 C3 5 5 3 8 3 C10 3 11 4 12 6 S14 3 16 3 C19 3 21 5 21 8 C21 12 18 15 12 20 Z";
        private static const P_GLYPH_STAR:String =
            "M12 2 L15 9 L22 9 L16 14 L18 21 L12 17 L6 21 L8 14 L2 9 L9 9 Z";

        private static const ICON24:StyleRefinement = StyleRefinement.from({ size: [24, 24] });
        private static const ICON32:StyleRefinement = StyleRefinement.from({ size: [32, 32] });
        private static const ICON48:StyleRefinement = StyleRefinement.from({ size: [48, 48] });

        public static function sections(view:DocsView, id:String):Array
        {
            var m:DocsModel = view.model;

            if (id == "progress") return [
                new DocSection("A determinate bar", [
                    "`value` is 0..1 and the label is the widget's own first argument -- not a text",
                    "node you have to place and keep in sync."
                ], [
                    "progress(\"Uploading\", { value: 0.45 }),",
                    "progress(\"Indexing\",  { value: 0.9 })"
                ], 96, function ():Node
                {
                    return column({ gap: 10, style: StyleRefinement.from({ size: [320, null] }) }, [
                        progress("Uploading " + int(m.num("pr.v", 0.45) * 100) + "%",
                            { key: "prA", value: m.num("pr.v", 0.45) }),
                        progress("Indexing", { key: "prB", value: 0.9 })
                    ]);
                }),

                new DocSection("Driven by the model", [
                    "Nothing animates on its own: a task that advances writes the value and invalidates.",
                    "That keeps the frame cost at \"one repaint\" and makes the demo's evidence exact."
                ], [
                    "button({ label: \"+10%\", onClick: function ():void {",
                    "    model.p = Math.min(1, model.p + 0.1); model.notify(Dirty.VALUE);",
                    "} })"
                ], 76, function ():Node
                {
                    return row({ gap: 12, alignItems: "center" }, [
                        button({ key: "prBtn", label: "+10%", style: DocsDemo.QUIET,
                                 onClick: function ():void
                                 {
                                     var v:Number = m.num("pr.v", 0.45) + 0.1;
                                     if (v > 1) v = 1;
                                     m.put("pr.v", v);
                                 } }),
                        text("value " + m.num("pr.v", 0.45), { style: DocsDemo.MONO, ariaName: "" })
                    ]);
                })
            ];

            if (id == "spinner") return [
                new DocSection("An indeterminate ring", [
                    "A spinner is sized by `diameter` and stroke `thickness`; `phase` turns it, and the",
                    "app's frame loop is what keeps the phase moving."
                ], [
                    "spinner({ diameter: 18, thickness: 2 }),",
                    "spinner({ diameter: 28, thickness: 3, tone: \"info\" })"
                ], 96, function ():Node
                {
                    return row({ gap: 16, alignItems: "center" }, [
                        spinner({ key: "spA", diameter: 18, thickness: 2 }),
                        spinner({ key: "spB", diameter: 28, thickness: 3, tone: "info" }),
                        spinner({ key: "spC", diameter: 40, thickness: 4, tone: "danger" })
                    ]);
                }),

                new DocSection("Beside a label", [
                    "It has no intrinsic margin: spacing is the row's `gap`, like every other leaf."
                ], [
                    "row({ gap: 8, alignItems: \"center\" }, [ spinner({ diameter: 16 }), text(\"Loading\") ])"
                ], 76, function ():Node
                {
                    return row({ gap: 8, alignItems: "center" }, [
                        spinner({ diameter: 16, thickness: 2 }),
                        text("Loading the index...", { style: DocsDemo.LABEL, ariaName: "" })
                    ]);
                })
            ];

            if (id == "skeleton") return [
                new DocSection("Placeholders that match the layout", [
                    "A skeleton reserves the space the real content will take, so the page does not jump",
                    "when the data arrives. `variant` picks text / circle / rect."
                ], [
                    "skeleton({ variant: \"circle\", style: { size: [32, 32] } }),",
                    "skeleton({ variant: \"text\", lines: 3, barHeight: 8, gap: 6 })"
                ], 118, function ():Node
                {
                    return row({ gap: 12, alignItems: "flex-start" }, [
                        skeleton({ key: "skA", variant: "circle",
                            style: StyleRefinement.from({ size: [36, 36] }) }),
                        column({ gap: 6 }, [
                            skeleton({ key: "skB", variant: "text", lines: 3, barHeight: 8, gap: 6,
                                style: StyleRefinement.from({ size: [220, null] }) })
                        ])
                    ]);
                }),

                new DocSection("Rect", [
                    "The rect variant is what a media card's thumbnail uses -- a fixed block that keeps",
                    "the column's height stable while the image loads."
                ], [
                    "skeleton({ variant: \"rect\", style: { size: [200, 64] } })"
                ], 96, function ():Node
                {
                    return skeleton({ key: "skC", variant: "rect",
                        style: StyleRefinement.from({ size: [240, 64] }) });
                })
            ];

            if (id == "tooltip") return [
                new DocSection("A bubble with an arrow", [
                    "A tooltip is a static leaf: place it, do not hover it. Hover behaviour is the",
                    "author's (show it from a model flag), because the timing policy is not universal.",
                    "`arrow` is up | down | left | right | none, and `tone` is the bubble's FILL colour."
                ], [
                    "tooltip(\"Saves the document\", { arrow: \"down\" }),",
                    "tooltip(\"Read-only\", { arrow: \"left\", tone: 0x2563EB })"
                ], 104, function ():Node
                {
                    return row({ gap: 16, alignItems: "center" }, [
                        tooltip("Saves the document", { key: "tipA", arrow: "down" }),
                        tooltip("Read-only", { key: "tipB", arrow: "left", tone: 0x2563EB })
                    ]);
                }),

                new DocSection("In a row with its anchor", [
                    "The arrow points at the anchor; the bubble's own size comes from its text, so it",
                    "never needs a width."
                ], [
                    "row({ gap: 6, alignItems: \"center\" }, [ button({ label: \"Save\" }), tooltip(\"Ctrl+S\") ])"
                ], 76, function ():Node
                {
                    return row({ gap: 8, alignItems: "center" }, [
                        button({ label: "Save", style: DocsDemo.QUIET, onClick: function ():void { } }),
                        tooltip("Ctrl+S", { arrow: "left" })
                    ]);
                })
            ];

            if (id == "icon") return [
                new DocSection("A glyph from path data", [
                    "An icon is SVG path data (`d` syntax) drawn into its box, so it has no file, no",
                    "texture and no second copy per colour -- it takes the colour and the size it is",
                    "given and stays sharp at any scale. With no `size`, the box IS the `viewBox` (24",
                    "by default), which is the convention every public icon set is authored in."
                ], [
                    "icon(\"M12 5 V19 M5 12 H19\", { size: [24, 24] }),",
                    "icon(\"M4 13 L9 18 L20 5\",   { size: [32, 32], color: 0x16A34A })"
                ], 104, function ():Node
                {
                    return row({ gap: 18, alignItems: "center" }, [
                        icon(P_GLYPH_CROSS, { key: "icA", style: ICON24, color: 0x2563EB }),
                        icon(P_GLYPH_CHECK, { key: "icB", style: ICON32, color: 0x16A34A }),
                        icon(P_GLYPH_BOLT, { key: "icC", style: ICON32, color: 0xDC2626, fill: true, stroke: false }),
                        text("stroke / stroke / fill", { style: DocsDemo.MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("Stroke width is a viewBox width", [
                    "`strokeWidth` is in the data's own units, so it scales with the glyph: the same",
                    "glyph at 24 and at 48 has a 2px and a 4px outline. That is what the source SVG",
                    "means by `stroke-width`, and it is why an icon stays legible when it is scaled up."
                ], [
                    "icon(d, { size: [24, 24], strokeWidth: 2 }),",
                    "icon(d, { size: [48, 48], strokeWidth: 2 })   // 4px, not 2px"
                ], 96, function ():Node
                {
                    return row({ gap: 18, alignItems: "center" }, [
                        icon(P_GLYPH_HEART, { key: "icD", style: ICON24, color: 0xE11D48 }),
                        icon(P_GLYPH_HEART, { key: "icE", style: ICON48, color: 0xE11D48 }),
                        text("a cubic, subdivided to the engine's quadratics", { style: DocsDemo.MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("What it will not draw", [
                    "`M L H V Z` are exact, `Q T` are exact, and `C S` are converted: this engine has a",
                    "quadratic `curveTo` and no cubic, so each cubic is split until the quadratics are",
                    "within a quarter of a rendered pixel of it. An elliptical arc (`A`) THROWS -- an arc",
                    "is not a curve this engine can draw without going through a cubic, and quietly",
                    "drawing a chord instead would be an icon that looks fine and is the wrong shape.",
                    "Unknown commands throw too, at the call site: `icon()` parses its data when you",
                    "describe it, so the stack frame is the line you wrote."
                ], [
                    "icon(\"M12 3 A9 9 0 1 0 12 21 A9 9 0 1 0 12 3\")   // THROWS: use fill: true,",
                    "                                                       // or an arc-free path"
                ], 76, function ():Node
                {
                    return row({ gap: 14, alignItems: "center" }, [
                        icon(P_GLYPH_STAR, { key: "icF", style: ICON48, color: 0xF59E0B, fill: true, stroke: false }),
                        text("a ten-command polygon: no curve at all", { style: DocsDemo.MONO, ariaName: "" })
                    ]);
                })
            ];

            if (id == "image") return [
                new DocSection("A BitmapData in a box", [
                    "The image scales a bitmap into the box it was given; `scaleMode` picks how. Keep the",
                    "BitmapData STABLE across renders -- a new one every frame would re-upload the texture."
                ], [
                    "image({ bitmapData: SRC, scaleMode: \"fit\",",
                    "        style: { size: [120, 80] } })"
                ], 104, function ():Node
                {
                    ensureSrc();
                    return row({ gap: 14, alignItems: "center" }, [
                        image({ key: "imgA", bitmapData: SRC8, scaleMode: "fit",
                            style: StyleRefinement.from({ size: [120, 72] }) }),
                        image({ key: "imgB", bitmapData: SRC8, scaleMode: "stretch",
                            style: StyleRefinement.from({ size: [72, 72] }) })
                    ]);
                }),

                new DocSection("Scale modes", [
                    "There are four: `fit` contains the picture and pads (the default), `stretch` fills the",
                    "box and ignores the aspect, `none` draws it 1:1, centred, and `cover` fills the box and",
                    "CROPS. An unknown mode THROWS at describe time -- a silent fallback to `fit` would",
                    "leave a picture the wrong size with nothing on screen saying why. `letterbox` and",
                    "`zoom` throw too: both used to fall into the contain branch, so `zoom` (which reads",
                    "as cover) did not zoom at all."
                ], [
                    "image({ bitmapData: SRC, scaleMode: \"none\" })   // 1:1, centred"
                ], 76, function ():Node
                {
                    ensureSrc();
                    return row({ gap: 14, alignItems: "center" }, [
                        image({ key: "imgC", bitmapData: SRC8, scaleMode: "none",
                            style: StyleRefinement.from({ size: [64, 64], background: 0xF3F4F6 }) }),
                        text("fit / stretch / none", { style: DocsDemo.MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("cover: fill the box, then crop", [
                    "`cover` scales until the picture COVERS the box and clips the overflow -- the opposite of",
                    "`fit`, which contains the whole picture and pads. Both keep the aspect ratio; only one of",
                    "them may throw pixels away.",
                    "The clip is a `scrollRect` on the bitmap, and the window is in the BITMAP's own units: the",
                    "renderer clips through the object's own matrix, so a window measured in box pixels is a",
                    "window divided by the scale factor too -- the first version asked for a box-sized window on",
                    "a 3x picture and cropped to nothing. Leaving cover CLEARS the window, because a stale crop",
                    "is invisible right up until the next mode inherits it.",
                    "One source (a 16x8 two-tone band), one 96x96 box, both modes below."
                ], [
                    "image({ bitmapData: BAND, scaleMode: \"cover\", style: { size: [96, 96] } })",
                    "// k = max(96/16, 96/8) = 12 -> drawn 192x96; window w = 96/12 = 8 source units,",
                    "// centred at ((192 - 96) / 2) / 12 = 4 -- so source x 4..12 is what survives"
                ], 132, function ():Node
                {
                    ensureBand();
                    return row({ gap: 14, alignItems: "center" }, [
                        column({ gap: 2 }, [
                            image({ key: "imgFit", bitmapData: BAND, scaleMode: "fit",
                                style: StyleRefinement.from({ size: [96, 96], background: 0xF3F4F6 }) }),
                            text("fit", { style: DocsDemo.MONO, ariaName: "" })
                        ]),
                        column({ gap: 2 }, [
                            image({ key: "imgCover", bitmapData: BAND, scaleMode: "cover",
                                style: StyleRefinement.from({ size: [96, 96], background: 0xF3F4F6 }) }),
                            text("cover", { style: DocsDemo.MONO, ariaName: "" })
                        ])
                    ]);
                }),

                new DocSection("From a file or a URL", [
                    "`src` hands the loading to the widget: it owns a Loader, so the author writes no COMPLETE",
                    "wiring and no torn-down-node guard. The path is resolved by the RUNTIME (relative to the",
                    "process's working directory), and a load is ASYNC: until it lands the box is the 64x64",
                    "placeholder, so give an auto-sized image a `size` if it must not jump. A failure is not",
                    "silent -- `onLoad()` takes nothing, `onError(message)` takes the IOError text, and",
                    "`UiNode.loadError` keeps it on the node."
                ], [
                    "image({ src: \"avatar.png\", scaleMode: \"fit\", style: { size: [64, 64] },",
                    "        onError: function (msg:String):void { trace(msg); } })"
                ], 96, function ():Node
                {
                    return row({ gap: 14, alignItems: "center" }, [
                        image({ key: "imgSrc", src: "as-image.png", scaleMode: "fit",
                            style: StyleRefinement.from({ size: [64, 64], background: 0xF3F4F6 }) }),
                        text("loaded from as-image.png", { style: DocsDemo.MONO, ariaName: "" })
                    ]);
                })
            ];

            return null;
        }

        private static function ensureSrc():void
        {
            if (SRC8 != null) return;
            SRC8 = new BitmapData(8, 8, false, 0x2563EB);
        }

        private static function ensureBand():void
        {
            if (BAND != null) return;
            BAND = new BitmapData(16, 8, false, 0xDC2626);
            BAND.fillRect(new Rectangle(8, 0, 8, 8), 0x2563EB);
        }
    }
}

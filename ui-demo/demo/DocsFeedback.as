// demo/DocsFeedback.as -- progress / spinner / skeleton / tooltip / image: the
// leaves that show a state rather than an interaction.
package demo
{
    import asaot.ui.Node;
    import asaot.ui.box;
    import asaot.ui.button;
    import asaot.ui.column;
    import asaot.ui.image;
    import asaot.ui.progress;
    import asaot.ui.row;
    import asaot.ui.skeleton;
    import asaot.ui.spinner;
    import asaot.ui.text;
    import asaot.ui.tooltip;
    import asaot.ui.style.StyleRefinement;

    import flash.display.BitmapData;

    public final class DocsFeedback
    {
        // One static source for every image demo: identity is part of the contract
        // (the widget compares the BitmapData it was given last frame, and a fresh
        // bitmap per render would reload the texture every frame).
        private static var SRC8:BitmapData = null;

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
                    "There are three: `fit` contains the picture and pads (the default), `stretch` fills the",
                    "box and ignores the aspect, `none` draws it 1:1, centred. An unknown mode THROWS at",
                    "describe time -- a silent fallback to `fit` would leave a picture the wrong size with",
                    "nothing on screen saying why. There is no cover/fill: covering means clipping what falls",
                    "outside the box, and clipping belongs to a scrollView's viewport, not to a scale mode."
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
    }
}

// demo/DocsStart.as -- the "Getting started" page: how a tree is described,
// mounted, styled and kept in step with a model. It is the only page whose
// examples are about the FRAMEWORK rather than about one widget.
package demo
{
    import asaot.ui.Dirty;
    import asaot.ui.Node;
    import asaot.ui.box;
    import asaot.ui.button;
    import asaot.ui.card;
    import asaot.ui.column;
    import asaot.ui.row;
    import asaot.ui.style.StyleRefinement;
    import asaot.ui.text;

    public final class DocsStart
    {
        private static const NOTE:StyleRefinement = StyleRefinement.from({
            text: { fontSize: 12, color: 0x64748B }
        });
        private static const HEADLINE:StyleRefinement = StyleRefinement.from({
            text: { fontSize: 20, fontWeight: "bold", color: 0x0F172A }
        });
        private static const SWATCH:StyleRefinement = StyleRefinement.from({
            size: [160, 44], padding: 8, background: 0x2563EB, cornerRadii: 8,
            text: { fontSize: 11, color: 0xFFFFFF }
        });
        public static function sections(view:DocsView, id:String):Array
        {
            if (id != "start") return null;
            var m:DocsModel = view.model;
            var n:int = int(m.num("start.n", 0));

            return [
                new DocSection("Describe", [
                    "render() returns a description -- a tree of factories. It is pure: no addChild, no",
                    "side effects, no reliance on evaluation order. It is called only on a dirty frame."
                ], [
                    "override public function render():Node {",
                    "    return column({ padding: 24, gap: 12 }, [",
                    "        text(\"Hello\", { style: { text: { fontSize: 24 } } }),",
                    "        button({ label: \"Save\", onClick: save })",
                    "    ]);",
                    "}"
                ], 104, function ():Node
                {
                    return card({ style: StyleRefinement.from({
                        flexDirection: "column", gap: 8, padding: 14, size: [240, null],
                        background: 0xF8FAFC, border: 1, borderColor: 0xE5E7EB, cornerRadii: 10
                    }) }, [
                        text("Hello", { style: HEADLINE, ariaName: "" }),
                        button({ label: "Save", style: SWATCH, onClick: function ():void { } })
                    ]);
                }),

                new DocSection("Mount", [
                    "UiApp owns the retained tree and the frame loop. mount() binds it to a stage;",
                    "attachRoot() runs the first describe + reconcile + measure/arrange/paint."
                ], [
                    "var app:UiApp = new UiApp(new HelloView());",
                    "app.mount(stage);      // ENTER_FRAME drives reflow()",
                    "app.attachRoot();      // first frame, synchronously",
                    "app.invalidate(Dirty.ALL);   // ask for another frame"
                ], 76, function ():Node
                {
                    return column({ gap: 6 }, [
                        text("UiApp", { style: HEADLINE, ariaName: "" }),
                        text("mounted on this stage; the docs app you are reading runs the same loop.",
                             { style: NOTE, ariaName: "" })
                    ]);
                }),

                new DocSection("Style", [
                    "Every node takes a style refinement: shorthand keys (padding, gap, background,",
                    "border, text, ...) or an explicit partial. Sizes are [width, height]."
                ], [
                    "box({",
                    "    size: [160, 44], padding: 8, gap: 6,",
                    "    background: 0x2563EB, cornerRadii: 8,",
                    "    text: { fontSize: 11, color: 0xFFFFFF }",
                    "})"
                ], 76, function ():Node
                {
                    return box({ style: SWATCH }, [
                        text("size: [160, 44]", { style: StyleRefinement.from({
                            size: [null, 20], text: { fontSize: 11, color: 0xFFFFFF } }), ariaName: "" })
                    ]);
                }),

                new DocSection("State", [
                    "A widget never keeps its own state: it reports through a callback, the model writes,",
                    "and the next render re-describes the tree. This button's count lives in DocsModel."
                ], [
                    "button({",
                    "    label: \"Clicked \" + model.n + \"x\",",
                    "    onClick: function ():void { model.n = model.n + 1; model.notify(Dirty.VALUE); }",
                    "})"
                ], 76, function ():Node
                {
                    return row({ gap: 12, alignItems: "center" }, [
                        button({ key: "startBtn", label: "Clicked " + n + "x",
                                 style: StyleRefinement.from({
                                     size: [160, 44], background: 0x2563EB, borderColor: 0x1D4ED8,
                                     cornerRadii: 8,
                                     text: { fontSize: 13, fontWeight: "bold", color: 0xFFFFFF } }),
                                 onClick: function ():void { m.put("start.n", int(m.num("start.n", 0)) + 1); } }),
                        text("the model is the only owner of `n`", { style: NOTE, ariaName: "" })
                    ]);
                })
            ];
        }
    }
}

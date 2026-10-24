// demo/DocsNav.as -- tabs / breadcrumb / accordion: three ways to say "this is one
// of N", each with its own chrome.
package demo
{
    import asaot.ui.Node;
    import asaot.ui.accordion;
    import asaot.ui.breadcrumb;
    import asaot.ui.column;
    import asaot.ui.row;
    import asaot.ui.tabs;
    import asaot.ui.text;
    import asaot.ui.style.StyleRefinement;

    public final class DocsNav
    {
        public static function sections(view:DocsView, id:String):Array
        {
            var m:DocsModel = view.model;

            if (id == "tabs") return [
                new DocSection("An index you can click", [
                    "tabs() takes plain labels and reports the index. `selectedIndex` also accepts a",
                    "Binding, which is the shortest way to keep it in a model field."
                ], [
                    "tabs([\"Overview\", \"Members\", \"Billing\"], {",
                    "    key: \"t\", size: [320, 32], gap: 6,",
                    "    selectedIndex: model.tab,",
                    "    onChange: function (i:int):void { model.tab = i; }",
                    "})"
                ], 84, function ():Node
                {
                    return column({ gap: 8 }, [
                        tabs(["Overview", "Members", "Billing"], { key: "demoTabs", gap: 6,
                            style: StyleRefinement.from({ size: [340, 32] }),
                            selectedIndex: int(m.num("tabs.i", 0)),
                            onChange: function (i:int):void { m.put("tabs.i", i); } }),
                        text("index " + int(m.num("tabs.i", 0)), { style: DocsDemo.MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("The strip is painted, not built", [
                    "There are no per-tab child nodes: the widget measures the labels and paints the",
                    "selected band itself, so a switch is one repaint and no reconcile."
                ], [
                    "// onChange -> model write -> one reflow, zero child churn"
                ], 76, function ():Node
                {
                    return text("Click a segment: the band moves, the tree does not.",
                        { style: DocsDemo.LABEL, ariaName: "" });
                })
            ];

            if (id == "breadcrumb") return [
                new DocSection("A trail of crumbs", [
                    "Items are plain labels and the callback reports an INDEX, so a crumb that needs a",
                    "route or a key carries it in the author's own closure."
                ], [
                    "breadcrumb([\"Library\", \"Data\", \"Raw\"], {",
                    "    key: \"bc\", separator: \"/\",",
                    "    onNavigate: function (i:int):void { model.crumb = i; }",
                    "})"
                ], 76, function ():Node
                {
                    return row({ gap: 12, alignItems: "center" }, [
                        breadcrumb(["Library", "Data", "Raw"], { key: "demoBc", separator: "/",
                            currentIndex: int(m.num("bc.cur", 2)),
                            onNavigate: function (i:int):void { m.put("bc.cur", i); } }),
                        text("current " + int(m.num("bc.cur", 2)), { style: DocsDemo.MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("The last crumb is the current one", [
                    "currentIndex decides which crumb is drawn as current (grey, not a link). Leaving it",
                    "unset means \"the last item\", which is what a trail almost always means."
                ], [
                    "breadcrumb(labels, { separator: \"\\u203A\" })   // currentIndex defaults to the last"
                ], 76, function ():Node
                {
                    return breadcrumb(["Workspace", "asaotui", "demo", "DocsView.as"],
                        { key: "demoBc2", separator: "\u203A" });
                })
            ];

            if (id == "accordion") return [
                new DocSection("One panel at a time", [
                    "Headers are row children with role \"button\" -- the ARIA shape, and also how the",
                    "widget tells a header from a panel, so no key parsing or index arithmetic."
                ], [
                    "accordion([",
                    "    { title: \"General\",  content: column({}, [ ... ]) },",
                    "    { title: \"Advanced\", content: column({}, [ ... ]) }",
                    "], { key: \"a\", size: [320, 168], gap: 1, activeIndex: model.open,",
                    "     onToggle: function (i:int):void { model.open = i; } })"
                ], 196, function ():Node
                {
                    var secs:Array = [
                        { title: "General", content: column({ gap: 4 }, [
                            text("Name: docs", { style: DocsDemo.LABEL, ariaName: "" }),
                            text("Kind: accordion", { style: DocsDemo.LABEL, ariaName: "" })
                        ]) },
                        { title: "Advanced", content: column({ gap: 4 }, [
                            text("gap: 1 (a hairline)", { style: DocsDemo.LABEL, ariaName: "" }),
                            text("activeIndex: -1 closes all", { style: DocsDemo.LABEL, ariaName: "" })
                        ]) }
                    ];
                    return accordion(secs, { key: "demoAcc", gap: 1,
                        style: StyleRefinement.from({ size: [340, 168] }),
                        activeIndex: int(m.num("acc.i", 0)),
                        onToggle: function (i:int):void { m.put("acc.i", i); } });
                }),

                new DocSection("Open index is data", [
                    "onToggle reports the header's index; nothing opens by itself, and -1 (or any",
                    "out-of-range index) closes every panel."
                ], [
                    "// activeIndex: -1  -> all closed; model-owned, like every other open state"
                ], 76, function ():Node
                {
                    return text("activeIndex: " + int(m.num("acc.i", 0)),
                        { style: DocsDemo.MONO, ariaName: "" });
                })
            ];

            return null;
        }
    }
}

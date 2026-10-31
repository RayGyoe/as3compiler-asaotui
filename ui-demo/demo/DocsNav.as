// demo/DocsNav.as -- tabs / breadcrumb / accordion: three ways to say "this is one
// of N", each with its own chrome.
package demo
{
    import asaot.ui.AccordionNode;
    import asaot.ui.Node;
    import asaot.ui.accordion;
    import asaot.ui.appBar;
    import asaot.ui.breadcrumb;
    import asaot.ui.button;
    import asaot.ui.column;
    import asaot.ui.icon;
    import asaot.ui.navStack;
    import asaot.ui.row;
    import asaot.ui.slider;
    import asaot.ui.tabBar;
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
                }),

                new DocSection("Keyboard: Left / Right WRAP", [
                    "Press \"Focus it\", then Left / Right. A tab strip is a RING, not a sequence: Right on the",
                    "last tab goes to the FIRST and Left on the first goes to the last, where a list would stop",
                    "at the end. Home and End jump to the ends, and the ends are the first and last tab, not a",
                    "dead stop before them.",
                    "This is the one place the keyboard deliberately differs between kinds, because the shapes",
                    "differ -- a strip has no end, a listbox does (ARIA tabs wrap; a listbox selection clamps)."
                ], [
                    "app.focusNode(app.findByKey(\"myTabs\"));   // tabs sets tabEnabled",
                    "// Left/Right: (i + 1) % n and (i + n - 1) % n -- nothing to configure"
                ], 96, function ():Node
                {
                    return column({ gap: 6 }, [
                        tabs(["Overview", "Members", "Billing"], { key: "demoTabsKeys", gap: 6,
                            style: StyleRefinement.from({ size: [340, 32] }),
                            selectedIndex: int(m.num("tabs.k", 0)),
                            onChange: function (i:int):void { m.put("tabs.k", i); } }),
                        row({ gap: 8, alignItems: "center" }, [
                            button({ label: "Focus it", key: "focusTabs", onClick: function ():void
                            {
                                view.getApp().focusNode(view.getApp().findByKey("demoTabsKeys"));
                            } }),
                            text("index " + int(m.num("tabs.k", 0)) + "  (Right on Billing comes back to Overview)",
                                { style: DocsDemo.MONO, ariaName: "" })
                        ])
                    ]);
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
                    "Headers are row children with role 'button' -- the ARIA shape, and also how the",
                    "widget tells a header from a panel, so no key parsing or index arithmetic."
                ], [
                    "accordion([",
                    "    { title: 'General',  content: column({}, [ ... ]) },",
                    "    { title: 'Advanced', content: column({}, [ ... ]) }",
                    "], { key: 'a', size: [320, 168], gap: 1, activeIndex: model.open,",
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
                }),

                new DocSection("Several open at once", [
                    "mode 'multi' takes openIndices -- an ARRAY of open sections -- where single mode",
                    "takes one activeIndex. The two are mutually exclusive and passing the wrong one",
                    "THROWS, so a page cannot believe it is remembering a set that nothing reads."
                ], [
                    "accordion(secs, { mode: 'multi', openIndices: model.openSet, gap: 1,",
                    "     onToggle: function (i:int):void { model.openSet = toggled(model.openSet, i); } })",
                    "// single: activeIndex (one int)   multi: openIndices (a set)"
                ], 236, function ():Node
                {
                    var open:Array = m.val("acc.set", [0, 2]) as Array;
                    var secs3:Array = [
                        { title: "One", content: text("opened by the set", { style: DocsDemo.LABEL, ariaName: "" }) },
                        { title: "Two", content: text("independent of One", { style: DocsDemo.LABEL, ariaName: "" }) },
                        { title: "Three", content: text("closing One keeps Two", { style: DocsDemo.LABEL, ariaName: "" }) }
                    ];
                    var shown:String = "";
                    for (var q2:int = 0; q2 < open.length; q2++)
                    {
                        shown = shown + (q2 > 0 ? ", " : "") + int(open[q2]);
                    }
                    return column({ gap: 4 }, [
                        accordion(secs3, { key: "demoAccM", gap: 1,
                            style: StyleRefinement.from({ size: [340, 212] }),
                            mode: "multi",
                            openIndices: open,
                            onToggle: function (i:int):void
                            {
                                // Rebuilt in INDEX ORDER, the way the widget does it: a set whose
                                // contents depend on click order makes "the same set" untestable.
                                var wasOpen:Boolean = AccordionNode.isOpen(open, i);
                                var next:Array = [];
                                for (var k:int = 0; k < 3; k++)
                                {
                                    if (k == i ? !wasOpen : AccordionNode.isOpen(open, k)) next.push(k);
                                }
                                m.put("acc.set", next);
                            } }),
                        text("openIndices: [" + shown + "]", { style: DocsDemo.MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("Every header has its own key", [
                    "A header is a row child with role button and a key of its own, prefixed with the key of",
                    "the accordion that owns it: demoAccM:h0, demoAccM:h1, demoAccM:h2 above.",
                    "The prefix is not decoration. findByKey documents a key as unique across the whole tree,",
                    "and two accordions on one page used to hand out h0 twice -- the lookup could only ever",
                    "find the first one, so the second accordion was unreachable from any test or any a11y pass."
                ], [
                    "// the key of header i of the accordion keyed \"side\": side:h0, side:h1, ...",
                    "app.findByKey(\"side:h1\")"
                ], 76, function ():Node
                {
                    return column({ gap: 2 }, [
                        text("demoAccM:h0    demoAccM:h1    demoAccM:h2",
                            { style: DocsDemo.MONO, ariaName: "" }),
                        text("a second accordion keyed side would own side:h0 -- no collision.",
                            { style: DocsDemo.LABEL, ariaName: "" })
                    ]);
                })

            ];

            if (id == "navStack") return [
                new DocSection("Pages that stay mounted", [
                    "Only the top page is VISIBLE; every page is measured and laid out regardless.",
                    "That is the whole point of a stack: a page keeps its scroll offset and its",
                    "typed text across a push and a pop, because its nodes were never rebuilt.",
                    "`activeIndex` picks the top (-1, the default, means the last page). `onBack`",
                    "is the system BACK key; a desktop window has none, so the buttons here",
                    "drive the same state the key would."
                ], [
                    "navStack([home, detail], { key: \"nav\", activeIndex: model.depth,",
                    "                           onBack: function ():void { model.depth = 0; } })",
                    "// the pages overlap (absolute, inset:0) -- a stack is not a column"
                ], 186, function ():Node
                {
                    var depth:int = int(m.num("nav.i", 0));

                    var pageA:Node = column({ key: "navA", style: StyleRefinement.from({
                        background: 0xF8FAFC, padding: 10, gap: 6 }) }, [
                        text("Page one -- press Next", { style: DocsDemo.LABEL, ariaName: "" }),
                        button({ label: "Next", key: "navNext",
                            onClick: function ():void { m.put("nav.i", 1); } })
                    ]);
                    var pageB:Node = column({ key: "navB", style: StyleRefinement.from({
                        background: 0xEEF2FF, padding: 10, gap: 6 }) }, [
                        text("Page two -- press Back", { style: DocsDemo.LABEL, ariaName: "" }),
                        button({ label: "Back", key: "navBack",
                            onClick: function ():void { m.put("nav.i", 0); } })
                    ]);
                    return column({ gap: 6 }, [
                        navStack([pageA, pageB], { key: "demoNav",
                            activeIndex: depth,
                            onBack: function ():void { m.put("nav.i", 0); },
                            style: StyleRefinement.from({ size: [340, 148],
                                background: 0xFFFFFF }) }),
                        text("activeIndex " + depth, { style: DocsDemo.MONO, ariaName: "" })
                    ]);
                }),
            ];

            if (id == "appBar") return [
                new DocSection("Large title, collapsed by one number", [
                    "The bar folds a large title into the compact row as the page scrolls: `collapse`",
                    "goes 0 (open, `largeExtra` taller) to `largeExtra` (shut), and the fold is a",
                    "CLIP -- the title slides under the compact row instead of jumping rows.",
                    "Its height is the bar's to own, so a `style.height` would only fight it."
                ], [
                    "appBar({ key: \"bar\", title: \"Inbox\", large: true,",
                    "         leading: icon(\"M15 6l-6 6 6 6\"), trailing: [icon(\"...\")],",
                    "         collapse: model.collapse })   // 0 .. largeExtra (48)",
                    "// safeArea: \"top\" adds the notch inset as PADDING -- the background",
                    "// still covers it, the row starts below it"
                ], 200, function ():Node
                {
                    var coll:Number = m.num("bar.c", 0);
                    return column({ key: "demoBarWrap", gap: 6, style: StyleRefinement.from({
                        size: [340, null] }) }, [
                        appBar({ key: "demoBar", title: "Inbox", large: true,
                            collapse: coll,
                            leading: icon("M15 6l-6 6 6 6",
                                { size: [24, 24], color: 0x334155 }),
                            trailing: [ icon("M4 5h16M4 12h16M4 19h16",
                                { size: [24, 24], color: 0x334155 }) ],
                            style: StyleRefinement.from({ background: 0xFFFFFF }) }),
                        slider("collapse " + int(coll), { key: "barC",
                            value: coll / 48,
                            onChange: function (v:Number):void { m.put("bar.c", v * 48); } })
                    ]);
                }),
            ];

            if (id == "tabBar") return [
                new DocSection("Equal cells, one selected", [
                    "`items` is fixed-length on purpose: the cells share the bar equally, so a fifth",
                    "tab makes the others narrower instead of scrolling. The selected state is a",
                    "TINT (accent for the current tab, muted otherwise) applied to the cell, so a",
                    "badge or a custom node inside the cell inherits it too.",
                    "A tap on the CURRENT tab is still reported -- that is how \"scroll this section",
                    "to the top\" stays expressible."
                ], [
                    "tabBar({ key: \"tabs\", selectedIndex: model.tab, barHeight: 56,",
                    "         items: [ { key: \"home\", label: \"Home\", icon: \"M4 20 V10 L12 4 L20 10 V20 Z\" },",
                    "                  { key: \"find\", label: \"Search\", icon: \"M11 4 A7 7 0 1 1 10.99 4 Z M15.5 15.5 L20 20\" },",
                    "                  { key: \"me\",   label: \"Me\",   icon: \"M4 20 A8 8 0 0 1 20 20 Z\" } ],",
                    "         onSelect: function (i:int):void { model.tab = i; } })"
                ], 132, function ():Node
                {
                    var sel:int = int(m.num("tab.i", 1));
                    return column({ key: "demoTabsWrap", gap: 6, style: StyleRefinement.from({
                        size: [340, null] }) }, [
                        tabBar({ key: "demoTabs", selectedIndex: sel, barHeight: 56,
                            items: [
                                { key: "tA", label: "Home",
                                  icon: "M4 20 V10 L12 4 L20 10 V20 Z" },
                                { key: "tB", label: "Search",
                                  icon: "M11 4 A7 7 0 1 1 10.99 4 Z M15.5 15.5 L20 20" },
                                { key: "tC", label: "Me",
                                  icon: "M4 20 A8 8 0 0 1 20 20 Z" }
                            ],
                            onSelect: function (i:int):void { m.put("tab.i", i); },
                            style: StyleRefinement.from({ background: 0xFFFFFF }) }),
                        text("selectedIndex " + sel, { style: DocsDemo.MONO, ariaName: "" })
                    ]);
                })
            ];

            return null;
        }
    }
}

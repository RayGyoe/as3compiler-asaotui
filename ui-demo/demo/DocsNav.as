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
                }),

                new DocSection("The index picks the panel", [
                    "A tab strip is not a router, so the page below it is an ordinary conditional: the",
                    "same selectedIndex decides which column is mounted. Switching tabs therefore",
                    "replaces three nodes, not twenty -- the strip itself never changes."
                ], [
                    "tabs([...], { selectedIndex: i, onChange: set }),",
                    "i == 0 ? overview : (i == 1 ? members : billing)"
                ], 132, function ():Node
                {
                    var i:int = int(m.num("tabs.p", 0));
                    var body:Node;
                    if (i == 0) body = column({ gap: 4, key: "tabBody0" }, [
                        text("Overview panel", { style: DocsDemo.LABEL_B, ariaName: "" }),
                        text("three nodes replaced on every switch", { style: DocsDemo.LABEL, ariaName: "" })
                    ]);
                    else if (i == 1) body = column({ gap: 4, key: "tabBody1" }, [
                        text("Members panel", { style: DocsDemo.LABEL_B, ariaName: "" }),
                        text("avatar name, role, one chip", { style: DocsDemo.MONO, ariaName: "" })
                    ]);
                    else body = column({ gap: 4, key: "tabBody2" }, [
                        text("Billing panel", { style: DocsDemo.LABEL_B, ariaName: "" }),
                        text("card, divider, one button", { style: DocsDemo.MONO, ariaName: "" })
                    ]);
                    return column({ gap: 10 }, [
                        tabs(["Overview", "Members", "Billing"], { key: "demoTabsPanel", gap: 6,
                            style: StyleRefinement.from({ size: [340, 32] }),
                            selectedIndex: i,
                            onChange: function (k:int):void { m.put("tabs.p", k); } }),
                        body
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
                }),

                new DocSection("A click reports an index, not a route", [
                    "onNavigate gets the CRUMB'S index -- 0 for the first label, and never for the",
                    "current one. The author's closure is what turns that index into a page change,",
                    "which is why a breadcrumb needs no router to be useful."
                ], [
                    "onNavigate: function (i:int):void { model.crumb = i; }   // 0-based",
                    "// the current crumb is drawn as text, so it never reports"
                ], 96, function ():Node
                {
                    return column({ gap: 8 }, [
                        breadcrumb(["Library", "Data", "Raw"], { key: "demoBcClick", separator: "/",
                            currentIndex: int(m.num("bc.c2", 2)),
                            onNavigate: function (i:int):void {
                                m.put("bc.c2", i);
                                m.put("bc.last", String(i));
                            } }),
                        text("last onNavigate: " + m.val("bc.last", "none yet"),
                            { style: DocsDemo.MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("The separator is a string", [
                    "It is drawn BETWEEN the crumbs only -- not before the first and not after the last --",
                    "so a slash, an angle bracket or a dot all read correctly with no spacing written by",
                    "the author."
                ], [
                    "breadcrumb([...], { separator: \">\" })"
                ], 108, function ():Node
                {
                    return column({ gap: 8 }, [
                        breadcrumb(["a", "b", "c"], { key: "bcSep1", separator: ">" }),
                        breadcrumb(["a", "b", "c"], { key: "bcSep2", separator: " / " }),
                        breadcrumb(["a", "b", "c"], { key: "bcSep3", separator: "." })
                    ]);
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

                new DocSection("A three-deep stack", [
                    "The same two nodes again with three pages: Push writes 0 -> 1 -> 2 and Pop writes",
                    "back. Nothing is unmounted on the way, so page one is still behind page three after",
                    "two pushes -- and activeIndex -1 (the default) means the last page, which is the",
                    "one a freshly built stack should show."
                ], [
                    "navStack([home, detail, edit], { activeIndex: depth,",
                    "                                   onBack: function ():void { depth = depth - 1; } })"
                ], 168, function ():Node
                {
                    var depth:int = int(m.num("nav3.i", 0));
                    var pages:Array = [];
                    for (var k:int = 0; k < 3; k++)
                    {
                        var label:String = "page " + (k + 1);
                        if (k == 0) label = "page 1 (home)";
                        if (k == 2) label = "page 3 (edit)";
                        pages.push(column({ key: "nav3p" + k, style: StyleRefinement.from({
                            background: k == depth ? 0xEEF2FF : 0xF8FAFC,
                            padding: 10, gap: 6 }) }, [
                            text(label, { style: DocsDemo.LABEL, ariaName: "" })
                        ]));
                    }
                    return column({ gap: 6 }, [
                        navStack(pages, { key: "demoNav3", activeIndex: depth,
                            onBack: function ():void {
                                if (depth > 0) m.put("nav3.i", depth - 1);
                            },
                            style: StyleRefinement.from({ size: [340, 112], background: 0xFFFFFF }) }),
                        row({ gap: 8, alignItems: "center" }, [
                            button({ key: "nav3Push", label: "Push", style: DocsDemo.QUIET,
                                onClick: function ():void {
                                    if (depth < 2) m.put("nav3.i", depth + 1);
                                } }),
                            button({ key: "nav3Pop", label: "Pop", style: DocsDemo.QUIET,
                                onClick: function ():void {
                                    if (depth > 0) m.put("nav3.i", depth - 1);
                                } }),
                            text("depth " + depth, { style: DocsDemo.MONO, ariaName: "" })
                        ])
                    ]);
                }),

                new DocSection("A typed field survives a push", [
                    "Every page is laid out every frame, visible or not -- so the text field on page one",
                    "is never rebuilt by a push. Type something, press Next, press Back: the caret and",
                    "the text are where you left them, and no page wrote a restore path to make that",
                    "true. (The model still owns the string; the point is that nothing had to rebuild.)"
                ], [
                    "navStack([pageWithField, other], { activeIndex: depth })",
                    "// both pages measurable every frame: no rebuild, no restore"
                ], 168, function ():Node
                {
                    var depth:int = int(m.num("nav4.i", 0));
                    var home:Node = column({ key: "nav4a", style: StyleRefinement.from({
                        background: 0xF8FAFC, padding: 10, gap: 8 }) }, [
                        textField({ key: "nav4Field", placeholder: "type, then push",
                            value: String(m.val("nav4.text", "")),
                            onCommit: function (s:String):void { m.put("nav4.text", s); },
                            style: StyleRefinement.from({ size: [240, null] }) }),
                        button({ key: "nav4Next", label: "Next", style: DocsDemo.QUIET,
                            onClick: function ():void { m.put("nav4.i", 1); } })
                    ]);
                    var other:Node = column({ key: "nav4b", style: StyleRefinement.from({
                        background: 0xEEF2FF, padding: 10, gap: 8 }) }, [
                        text("Page two", { style: DocsDemo.LABEL, ariaName: "" }),
                        button({ key: "nav4Back", label: "Back", style: DocsDemo.QUIET,
                            onClick: function ():void { m.put("nav4.i", 0); } })
                    ]);
                    return column({ gap: 6 }, [
                        navStack([home, other], { key: "demoNav4", activeIndex: depth,
                            onBack: function ():void { m.put("nav4.i", 0); },
                            style: StyleRefinement.from({ size: [340, 112], background: 0xFFFFFF }) }),
                        text("model: '" + m.val("nav4.text", "") + "'",
                            { style: DocsDemo.MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("The box is the author's", [
                    "The page wrappers are absolute and inset 0, so they contribute no height: the stack",
                    "is exactly the box you declare. That is deliberate -- a stack whose height came from",
                    "the tallest page would jump the moment a shorter page was pushed onto it."
                ], [
                    "navStack([a, b], { style: { size: [340, 112] } })",
                    "// the pages fill it; neither one sizes it"
                ], 140, function ():Node
                {
                    return navStack([
                        column({ key: "nav5a", style: StyleRefinement.from({
                            background: 0xF8FAFC, padding: 10, gap: 6 }) }, [
                            text("page A -- three lines", { style: DocsDemo.LABEL, ariaName: "" }),
                            text("one", { style: DocsDemo.LABEL, ariaName: "" }),
                            text("two", { style: DocsDemo.LABEL, ariaName: "" })
                        ]),
                        column({ key: "nav5b", style: StyleRefinement.from({
                            background: 0xEEF2FF, padding: 10, gap: 6 }) }, [
                            text("page B -- one line", { style: DocsDemo.LABEL, ariaName: "" })
                        ])
                    ], { key: "demoNav5", activeIndex: 1,
                        style: StyleRefinement.from({ size: [340, 112], background: 0xFFFFFF,
                            borderWidths: 1, borderColor: 0xE5E7EB,
                            cornerRadii: 8 }) });
                })
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

                new DocSection("leading and trailing are nodes", [
                    "Neither end is an icon name: leading takes one node and trailing takes an array,",
                    "so a back chevron, a busy spinner or a chip all fit without a second API. The title",
                    "between them is the bar's own, which is why it can fold."
                ], [
                    "appBar({ title: \"Inbox\",",
                    "         leading: chip(\"back\"),",
                    "         trailing: [ chip(\"3 new\", { tone: \"danger\" }) ] })"
                ], 132, function ():Node
                {
                    return column({ key: "bar2Wrap", gap: 6, style: StyleRefinement.from({
                        size: [340, null] }) }, [
                        appBar({ key: "demoBar2", title: "Inbox", large: false,
                            leading: chip("back"),
                            trailing: [ chip("3 new", { tone: "danger" }) ],
                            style: StyleRefinement.from({ background: 0xFFFFFF }) })
                    ]);
                }),

                new DocSection("Two bars, two numbers", [
                    "barHeight is the compact row and largeExtra is what a large title adds on top of",
                    "it. A compact bar ignores largeExtra entirely, so the same app can use one shape on",
                    "a phone and the other on a desktop without branching in the page."
                ], [
                    "appBar({ title: \"Compact\", large: false })                 // barHeight only",
                    "appBar({ title: \"Large\",   large: true, collapse: 0 })      // + largeExtra"
                ], 168, function ():Node
                {
                    return column({ key: "bar3Wrap", gap: 8, style: StyleRefinement.from({
                        size: [300, null] }) }, [
                        appBar({ key: "demoBar3C", title: "Compact", large: false,
                            style: StyleRefinement.from({ background: 0xFFFFFF }) }),
                        appBar({ key: "demoBar3L", title: "Large", large: true, collapse: 0,
                            style: StyleRefinement.from({ background: 0xFFFFFF }) })
                    ]);
                }),

                new DocSection("The title is re-pointed every frame", [
                    "Nothing is cached: the string the bar shows is the one this render returned, so a",
                    "title that follows the selection needs no setter. The fold still works -- the title",
                    "slides under the compact row rather than jumping to it."
                ], [
                    "appBar({ title: \"Inbox - 3 unread\" })   // just a string expression"
                    "appBar({ title: sel == 0 ? \"Inbox\" : \"Sent\" })"
                ], 132, function ():Node
                {
                    var sel:int = int(m.num("bar4.i", 0));
                    return column({ key: "bar4Wrap", gap: 8, style: StyleRefinement.from({
                        size: [300, null] }) }, [
                        appBar({ key: "demoBar4", title: sel == 0 ? "Inbox" : "Sent", large: false,
                            style: StyleRefinement.from({ background: 0xFFFFFF }) }),
                        row({ gap: 8, alignItems: "center" }, [
                            button({ key: "bar4Flip", label: "Switch", style: DocsDemo.QUIET,
                                onClick: function ():void { m.put("bar4.i", sel == 0 ? 1 : 0); } }),
                            text("title: " + (sel == 0 ? "Inbox" : "Sent"),
                                { style: DocsDemo.MONO, ariaName: "" })
                        ])
                    ]);
                })
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
                }),

                new DocSection("Five cells are narrower, not scrolled", [
                    "The bar divides its width by the number of items, so a fifth tab makes every cell",
                    "sixteen percent narrower. Nothing scrolls and no tab is ever off screen -- which is",
                    "the property a phone tab bar needs and a desktop tab strip does not."
                ], [
                    "tabBar({ items: [home, find, add, inbox, me], barHeight: 56 })"
                ], 168, function ():Node
                {
                    var sel:int = int(m.num("tab5.i", 2));
                    return column({ key: "tab5Wrap", gap: 6, style: StyleRefinement.from({
                        size: [340, null] }) }, [
                        tabBar({ key: "demoTab5", selectedIndex: sel, barHeight: 56,
                            items: [
                                { key: "f1", label: "Home", icon: "M4 20 V10 L12 4 L20 10 V20 Z" },
                                { key: "f2", label: "Search", icon: "M11 4 A7 7 0 1 1 10.99 4 Z M15.5 15.5 L20 20" },
                                { key: "f3", label: "Add", icon: "M12 5 V19 M5 12 H19" },
                                { key: "f4", label: "Inbox", icon: "M4 6 H20 V18 H4 Z M4 12 H9 L11 15 H13 L15 12 H20" },
                                { key: "f5", label: "Me", icon: "M4 20 A8 8 0 0 1 20 20 Z" }
                            ],
                            onSelect: function (i:int):void { m.put("tab5.i", i); },
                            style: StyleRefinement.from({ background: 0xFFFFFF }) }),
                        text("selectedIndex " + sel, { style: DocsDemo.MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("Tapping the current tab still reports", [
                    "onSelect fires for every tap, the selected one included: \"tap the tab you are on to",
                    "scroll back to the top\" is the usual behaviour and it needs the event, not a guard.",
                    "The counter below only moves because the widget kept talking."
                ], [
                    "onSelect: function (i:int):void { taps = taps + 1; }   // i may equal selectedIndex"
                ], 168, function ():Node
                {
                    var sel:int = int(m.num("tab6.i", 0));
                    return column({ key: "tab6Wrap", gap: 6, style: StyleRefinement.from({
                        size: [340, null] }) }, [
                        tabBar({ key: "demoTab6", selectedIndex: sel, barHeight: 56,
                            items: [
                                { key: "g1", label: "Home", icon: "M4 20 V10 L12 4 L20 10 V20 Z" },
                                { key: "g2", label: "Search", icon: "M11 4 A7 7 0 1 1 10.99 4 Z M15.5 15.5 L20 20" },
                                { key: "g3", label: "Me", icon: "M4 20 A8 8 0 0 1 20 20 Z" }
                            ],
                            onSelect: function (i:int):void {
                                m.put("tab6.i", i);
                                m.put("tab6.taps", int(m.num("tab6.taps", 0)) + 1);
                            },
                            style: StyleRefinement.from({ background: 0xFFFFFF }) }),
                        text("taps " + int(m.num("tab6.taps", 0)) + ", selected " + sel,
                            { style: DocsDemo.MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("barHeight is the whole cell", [
                    "The selected tint fills the cell from the bar's top to its bottom, so a taller bar is",
                    "a bigger target and not a bigger gap. Below: 56 against 72, same three items."
                ], [
                    "tabBar({ barHeight: 56, items: [...] }),",
                    "tabBar({ barHeight: 72, items: [...] })"
                ], 200, function ():Node
                {
                    return column({ key: "tab7Wrap", gap: 10, style: StyleRefinement.from({
                        size: [300, null] }) }, [
                        tabBar({ key: "demoTab7a", selectedIndex: 0, barHeight: 56,
                            items: [
                                { key: "h1", label: "Home", icon: "M4 20 V10 L12 4 L20 10 V20 Z" },
                                { key: "h2", label: "Me", icon: "M4 20 A8 8 0 0 1 20 20 Z" }
                            ],
                            onSelect: function (i:int):void { },
                            style: StyleRefinement.from({ background: 0xFFFFFF }) }),
                        tabBar({ key: "demoTab7b", selectedIndex: 0, barHeight: 72,
                            items: [
                                { key: "i1", label: "Home", icon: "M4 20 V10 L12 4 L20 10 V20 Z" },
                                { key: "i2", label: "Me", icon: "M4 20 A8 8 0 0 1 20 20 Z" }
                            ],
                            onSelect: function (i:int):void { },
                            style: StyleRefinement.from({ background: 0xFFFFFF }) })
                    ]);
                })
            ];

            return null;
        }
    }
}

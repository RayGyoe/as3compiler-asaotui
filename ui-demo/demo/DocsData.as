// demo/DocsData.as -- list / table / tree / virtualList / scrollView: the five
// ways the kit shows a collection, from "all rows are nodes" to "only the visible
// ones exist".
package demo
{
    import asaot.ui.Node;
    import asaot.ui.box;
    import asaot.ui.button;
    import asaot.ui.column;
    import asaot.ui.list;
    import asaot.ui.row;
    import asaot.ui.scrollView;
    import asaot.ui.table;
    import asaot.ui.text;
    import asaot.ui.tree;
    import asaot.ui.virtualList;
    import asaot.ui.style.Length;
    import asaot.ui.style.StyleRefinement;

    public final class DocsData
    {
        private static const NAMES:Array = ["Widget", "Gadget", "Sprocket", "Flange", "Bolt"];
        private static const PEOPLE:Array = ["Ada Lovelace", "Grace Hopper", "Alan Turing", "Edsger Dijkstra"];
        private static const FILES:Array = [
            { key: "src", label: "src", children: [
                { key: "src/kit.as", label: "kit.as" },
                { key: "src/app.as", label: "app.as" }
            ] },
            { key: "docs", label: "docs", children: [
                { key: "docs/api.md", label: "api.md" }
            ] },
            { key: "README", label: "README.md" }
        ];
        private static const ROW_H:Number = 26;
        public static function sections(view:DocsView, id:String):Array
        {
            var m:DocsModel = view.model;

            if (id == "list") return [
                new DocSection("Items become rows", [
                    "The builder runs once per item per render, at factory time -- not per mounted row.",
                    "So a row is an ordinary Node (a text, a row of chips, anything)."
                ], [
                    "list(items, function (item:Object, i:int):Node {",
                    "    return text(String(item), { key: \"p\" + i });",
                    "}, { key: \"people\", itemHeight: 26, separator: true,",
                    "     selectedIndex: model.row,",
                    "     onSelect: function (i:int):void { model.row = i; } })"
                ], 132, function ():Node
                {
                    return list(PEOPLE, function (item:Object, i:int):Node
                    {
                        return text(String(item), { key: "p" + i, style: DocsDemo.LABEL_B,
                                                    ariaName: "" });
                    }, { key: "demoList", itemHeight: ROW_H, separator: true,
                         style: StyleRefinement.from({ size: [260, ROW_H * 4] }),
                         selectedIndex: int(m.num("li.row", 1)),
                         onSelect: function (i:int):void { m.put("li.row", i); } });
                }),

                new DocSection("Selection is a decoration", [
                    "A selected-row change raises only a paint dirty bit: the rows keep their rects, so",
                    "selecting never re-solves layout. The widget paints the band behind the rows."
                ], [
                    "// style the row, not the selection -- the band is the widget's"
                ], 76, function ():Node
                {
                    return text("row " + int(m.num("li.row", 1)) + " is selected in the list above.",
                        { style: DocsDemo.MONO, ariaName: "" });
                }),

                new DocSection("Keyboard: the arrows move the selection", [
                    "Press \"Focus it\", then Up / Down / Home / End. A key goes to whatever holds FOCUS, and AIR",
                    "does not focus a plain Sprite on mouseDown -- only a TextField is focused by a click -- so a",
                    "widget is reached with Tab (list sets tabEnabled) or, as here, programmatically.",
                    "A list is a SEQUENCE, the ARIA listbox shape, so the ends CLAMP: Down on the last row stays",
                    "there and still CONSUMES the key, which is what stops the press from falling through to",
                    "whatever scrolls the page.",
                    "There is no second copy of the selection: a key calls the same select() a click calls."
                ], [
                    "app.focusNode(app.findByKey(\"myList\"));   // or Tab, once it is a tab stop",
                    "// list implements WidgetKeys -- there is nothing to switch on"
                ], 150, function ():Node
                {
                    return column({ gap: 6 }, [
                        list(PEOPLE, function (item:Object, i:int):Node
                        {
                            return text(String(item), { key: "k" + i, style: DocsDemo.LABEL_B,
                                                        ariaName: "" });
                        }, { key: "demoListKeys", itemHeight: ROW_H, separator: true,
                             style: StyleRefinement.from({ size: [260, ROW_H * 4] }),
                             selectedIndex: int(m.num("li.krow", 0)),
                             onSelect: function (i:int):void { m.put("li.krow", i); } }),
                        row({ gap: 8, alignItems: "center" }, [
                        button({ label: "Focus it", key: "focusList", onClick: function ():void
                        {
                            // Tab reaches the same node: this is the ring, called directly.
                            view.getApp().focusNode(view.getApp().findByKey("demoListKeys"));
                        } }),
                            text("row " + int(m.num("li.krow", 0)) + " of " + (PEOPLE.length - 1)
                                + "  (Up/Down clamp at the ends)",
                                { style: DocsDemo.MONO, ariaName: "" })
                        ])
                    ]);
                })
            ];

            if (id == "table") return [
                new DocSection("Columns and rows", [
                    "A column without a width shares whatever is left, and every cell in a column",
                    "carries the SAME style pointer, so alignment is the engine's job, not arithmetic."
                ], [
                    "table([{ key: \"name\", title: \"Name\", width: 150 }, { key: \"qty\", title: \"Qty\" }],",
                    "      rows, { key: \"t\", size: [340, 116], rowHeight: 26,",
                    "              stripes: true, onSelect: onRow })"
                ], 132, function ():Node
                {
                    var rows:Array = [];
                    // Three data rows + the header = 4 * 26 = 104, which fits the
                    // demo surface: a table's height is the sum of its rows.
                    for (var i:int = 0; i < 3; i++)
                        rows.push({ name: String(NAMES[i]), qty: (i + 1) * 3 });
                    return table([{ key: "name", title: "Name", width: 150 }, { key: "qty", title: "Qty" }], rows,
                        { key: "demoTable", rowHeight: ROW_H, stripes: true,
                          style: StyleRefinement.from({ size: [340, ROW_H * 4] }),
                          selectedIndex: int(m.num("tb.row", 0)),
                          onSelect: function (r:int):void { m.put("tb.row", r); } });
                }),

                new DocSection("Cells come from cellText", [
                    "One formatter maps a row object to the string for a column -- so a number, a status",
                    "or a date is formatted in one place, and the table stays a layout object."
                ], [
                    "cellText: function (col:Object, row:Object, r:int, c:int):String { ... }"
                ], 76, function ():Node
                {
                    return text("selected row: " + int(m.num("tb.row", 0)),
                        { style: DocsDemo.MONO, ariaName: "" });
                }),

                new DocSection("Keyboard: arrows, Home/End, PageUp/PageDown", [
                    "Same contract as the list, plus a PAGE step, which moves by the rows the BODY can show",
                    "rather than by one. The selection is always a data row: the header is not a row and can",
                    "never be selected, so Home goes to the first row under the header, not to the header."
                ], [
                    "table(cols, rows, { selectedIndex: model.row, onSelect: onRow })",
                    "// the keys call the same select() the click does -- one write path"
                ], 182, function ():Node
                {
                    var rows:Array = [];
                    for (var i:int = 0; i < 4; i++)
                        rows.push({ name: String(NAMES[i]), qty: (i + 1) * 3 });
                    return column({ gap: 10 }, [
                        table([{ key: "name", title: "Name", width: 150 },
                               { key: "qty", title: "Qty" }], rows,
                            { key: "demoTableKeys", rowHeight: ROW_H, stripes: true,
                              style: StyleRefinement.from({ size: [340, ROW_H * 5] }),
                              selectedIndex: int(m.num("tb.krow", 0)),
                              onSelect: function (r:int):void { m.put("tb.krow", r); } }),
                        row({ gap: 8, alignItems: "center" }, [
                        button({ label: "Focus it", key: "focusTable", onClick: function ():void
                        {
                            // Tab reaches the same node: this is the ring, called directly.
                            view.getApp().focusNode(view.getApp().findByKey("demoTableKeys"));
                        } }),
                            text("row " + int(m.num("tb.krow", 0)) + "  (PageUp/PageDown step by a page)",
                                { style: DocsDemo.MONO, ariaName: "" })
                        ])
                    ]);
                }),

                // SORTING. The arrow is a fact about the MODEL (`sortColumn`), which is why
                // this demo works at all: the widget reports the intent and the page stores
                // it, so the order survives every re-render.
                new DocSection("Sorting: the model owns the order", [
                    "`onSort(column, descending)` reports an INTENT and nothing else -- the widget never",
                    "reorders your rows. `sortColumn` is the order you hand back, and the arrow is drawn",
                    "from it, so the header can never claim an order the rows do not have.",
                    "The cycle is the browser's: another column sorts ascending, the same column",
                    "descending, and a third click reports -1 (unsorted). Numbers compare as numbers",
                    "while text compares as text, which is what makes a Qty column sort 1, 2, 10."
                ], [
                    "table(cols, rows, { rowHeight: 26, onSort: function (c:int, d:Boolean):void {",
                    "    model.col = c; model.desc = d;          // then re-render with",
                    "}, sortColumn: model.col, sortDescending: model.desc })"
                ], 132, function ():Node
                {
                    var rows:Array = [
                        { name: "Gadget", qty: 2 },
                        { name: "Widget", qty: 10 },
                        { name: "Bolt", qty: 1 }
                    ];
                    return table([{ key: "name", title: "Name", width: 200 },
                                  { key: "qty", title: "Qty" }], rows,
                        { key: "demoTableSort", rowHeight: ROW_H, stripes: true,
                          style: StyleRefinement.from({ size: [340, ROW_H * 4] }),
                          sortColumn: int(m.num("tb.col", -1)),
                          sortDescending: m.val("tb.desc", "0") == "1",
                          onSort: function (c:int, d:Boolean):void
                          {
                              m.put("tb.col", c);
                              m.put("tb.desc", d ? "1" : "0");
                          } });
                }),

                // COLUMN RESIZE. The width lives in the author's model too, so `resizable`
                // only has to REPORT -- which is also the only way this demo can keep the
                // width across the re-render the drag itself triggers.
                new DocSection("Column widths are yours", [
                    "Drag the divider in the header: a 1px preview line follows the pointer and, on",
                    "release, `onColumnResize(index, width)` fires ONCE. The widget never writes into",
                    "your `columns` array -- it is usually an inline literal rebuilt every render, so a",
                    "width written there would vanish on the next pass.",
                    "The click that the window sends after a release is swallowed, so resizing a",
                    "column never also sorts it."
                ], [
                    "table(cols, rows, { resizable: true,",
                    "    onColumnResize: function (i:int, w:Number):void {",
                    "        model.widths[i] = w;                 // then re-render with it",
                    "    } })"
                ], 132, function ():Node
                {
                    var rows:Array = [
                        { name: "Widget", qty: 12 },
                        { name: "Gadget", qty: 7 }
                    ];
                    var w0:int = int(m.num("tb.w0", 140));
                    return table([{ key: "name", title: "Name", width: w0 },
                                  { key: "qty", title: "Qty" }], rows,
                        { key: "demoTableResize", rowHeight: ROW_H, stripes: true, resizable: true,
                          style: StyleRefinement.from({ size: [340, ROW_H * 3] }),
                          onColumnResize: function (i:int, w:Number):void
                          {
                              if (i == 0) m.put("tb.w0", int(w));
                          } });
                }),

                // VIRTUAL. Two hundred rows, eleven nodes.
                new DocSection("Virtual: mount only what shows", [
                    "`virtual` mounts the visible window plus one partial row that the clip hides --",
                    "the rest of the model never becomes a node. It needs a POINT height (the body is",
                    "`height - rowHeight`) and `onScroll(offsetY)`, which reports the new offset for you",
                    "to re-render with; the header does not scroll.",
                    "Row keys are ABSOLUTE (r0, r1, ...), so a window that shifts mounts genuinely new",
                    "nodes instead of handing a scrolled-in row the node of the row that just left."
                ], [
                    "table([{ key: \"i\", title: \"#\" }], twoHundredRows, {",
                    "    virtual: true, rowHeight: 22, offsetY: model.off,",
                    "    onScroll: function (y:Number):void { model.off = y; } })"
                ], 148, function ():Node
                {
                    var rows:Array = [];
                    for (var i:int = 0; i < 200; i++) rows.push({ i: i });
                    return table([{ key: "i", title: "row" }], rows,
                        { key: "demoTableVirt", rowHeight: 22, virtual: true,
                          style: StyleRefinement.from({ size: [340, 110] }),
                          offsetY: m.num("tb.off", 0),
                          onScroll: function (y:Number):void { m.put("tb.off", y); } });
                }),

                new DocSection("A virtual table reveals the row it selects", [
                    "With virtual: true only the mounted window exists, so a key can select a row that is not on",
                    "screen: the index is valid, the model moved, and NOTHING changed -- a state no property",
                    "assertion can see. So the widget REVEALS it: it reports the offset that brings the row into",
                    "the window through onScroll, and the next render mounts it there.",
                    "Press Down and watch the offset start stepping once the window edge is reached; End jumps to",
                    "the last of the two hundred rows, and the offset to the very bottom."
                ], [
                    "table(cols, rows, { virtual: true, rowHeight: 22, offsetY: model.off,",
                    "                    onScroll: function (y:Number):void { model.off = y; } })",
                    "// Down at the window edge -> onScroll(y + rowHeight): the row comes INTO view"
                ], 152, function ():Node
                {
                    var rows:Array = [];
                    for (var i:int = 0; i < 200; i++) rows.push({ i: i });
                    return column({ gap: 6 }, [
                        table([{ key: "i", title: "row" }], rows,
                            { key: "demoTableKeysVirt", rowHeight: 22, virtual: true,
                              style: StyleRefinement.from({ size: [340, 110] }),
                              offsetY: m.num("tb.koff", 0),
                              selectedIndex: int(m.num("tb.kvis", 0)),
                              onScroll: function (y:Number):void { m.put("tb.koff", y); },
                              onSelect: function (r:int):void { m.put("tb.kvis", r); } }),
                        row({ gap: 8, alignItems: "center" }, [
                        button({ label: "Focus it", key: "focusTableVirt", onClick: function ():void
                        {
                            // Tab reaches the same node: this is the ring, called directly.
                            view.getApp().focusNode(view.getApp().findByKey("demoTableKeysVirt"));
                        } }),
                            text("row " + int(m.num("tb.kvis", 0)) + "  (window at offset "
                                + int(m.num("tb.koff", 0)) + " of " + ((200 * 22) - 88) + ")",
                                { style: DocsDemo.MONO, ariaName: "" })
                        ])
                    ]);
                }),

                // `grid` is the other answer to "which row am I on": rules instead of
                // alternating fills. They are PAINT, so they cost nothing at layout time.
                new DocSection("Grid lines instead of stripes", [
                    "`grid: true` draws the row rules and the column rules in the table's border",
                    "colour; `stripes` paints every other row instead. They compose (both on is a",
                    "spreadsheet look) but on a tight row height the rules are usually enough --",
                    "and a rule is drawn INSIDE the row, so it never changes a row's height."
                ], [
                    "table(cols, rows, { grid: true, stripes: false, rowHeight: 24,",
                    "                    header: true, style: { size: [340, 120] } })",
                    "// 4 data rows + the header = 5 * 24 = 120, exactly the box"
                ], 156, function ():Node
                {
                    var rows:Array = [];
                    for (var i:int = 0; i < 4; i++)
                        rows.push({ name: String(NAMES[i]), qty: (i + 1) * 7 });
                    return table([{ key: "name", title: "Name", width: 150 },
                                  { key: "qty", title: "Qty" }], rows,
                        { key: "demoTableGrid", rowHeight: 24, header: true,
                          grid: true, stripes: false,
                          style: StyleRefinement.from({ size: [340, 120] }) });
                })
            ];

            if (id == "tree") return [
                new DocSection("A flattened hierarchy", [
                    "A branch's children become rows of the SAME node while it is open, so there is no",
                    "nested container and no recursive reconciliation -- depth is a padding, not a parent."
                ], [
                    "tree(FILES, { key: \"files\", width: 240, rowHeight: 26,",
                    "              expanded: model.expanded,",
                    "              selectedKey: model.sel,",
                    "              onToggle: function (k:String):void { toggle(model, k); },",
                    "              onSelect: function (k:String):void { model.sel = k; } })"
                ], 164, function ():Node
                {
                    return tree(FILES, { key: "demoTree", width: 260, rowHeight: ROW_H,
                        expanded: m.val("tr.exp", "src"),
                        selectedKey: m.val("tr.sel", "src/kit.as"),
                        style: StyleRefinement.from({ size: [260, ROW_H * 5] }),
                        onToggle: function (k:String):void { m.put("tr.exp", k == m.val("tr.exp", "src") ? "" : k); },
                        onSelect: function (k:String):void { m.put("tr.sel", k); } });
                }),

                new DocSection("Expansion is the author's", [
                    "onToggle reports the key; nothing expands by itself. The kit keeps the rule that a",
                    "widget never owns state the reconciler cannot re-describe."
                ], [
                    "// expanded: [] or [\"src\"] -- both are just data"
                ], 76, function ():Node
                {
                    return text("expanded: '" + m.val("tr.exp", "src") + "'  selected: '"
                        + m.val("tr.sel", "src/kit.as") + "'", { style: DocsDemo.MONO, ariaName: "" });
                })
            ];

            if (id == "virtualList") return [
                new DocSection("Only the visible rows exist", [
                    "count 10000 and nine mounted rows: the window is row-granular and the factory",
                    "recomputes it, so scrolling mounts and unmounts rows like any other reconcile."
                ], [
                    "virtualList({ key: \"log\", size: [280, 104], rowHeight: 26, count: 10000,",
                    "              offsetY: model.off, overscan: 1,",
                    "              renderRow: function (i:int):Node { return text(\"row \" + i); },",
                    "              onScroll: function (y:Number):void { model.off = y; } })"
                ], 132, function ():Node
                {
                    return virtualList({ key: "demoVl", rowHeight: ROW_H, count: 10000,
                        offsetY: m.num("vl.off", 0), overscan: 1,
                        style: StyleRefinement.from({ size: [280, ROW_H * 4] }),
                        renderRow: function (i:int):Node
                        {
                            return text("row " + i, { key: "vr" + i, style: DocsDemo.LABEL, ariaName: "" });
                        },
                        onScroll: function (y:Number):void { m.put("vl.off", y); } });
                }),

                new DocSection("Wheel it", [
                    "Scrolling reports a row-aligned offset; writing it back re-renders, and the",
                    "reconciler mounts exactly the rows that entered the window."
                ], [
                    "// onScroll(y) -> model.offsetY = y -> the next render windows again"
                ], 76, function ():Node
                {
                    return text("offsetY " + m.num("vl.off", 0) + " of 10000 rows",
                        { style: DocsDemo.MONO, ariaName: "" });
                })
            ];

            if (id == "scrollView") return [
                new DocSection("A clipped viewport", [
                    "A scrollView clips and slides its child, which therefore needs an explicit height:",
                    "a container that measured itself would leave nothing to scroll."
                ], [
                    "scrollView({ key: \"sv\", wheelStep: 26,",
                    "             style: { size: [280, 96] } }, [",
                    "    column({ size: [null, 260] }, rows)   // taller than the viewport",
                    "])"
                ], 132, function ():Node
                {
                    var rows:Array = [];
                    for (var i:int = 0; i < 10; i++)
                        rows.push(text("line " + (i + 1), { key: "svr" + i, style: DocsDemo.LABEL,
                                                            ariaName: "" }));
                    return scrollView({ key: "demoSv", wheelStep: 26,
                        style: StyleRefinement.from({ size: [280, 96], background: 0xF8FAFC }) }, [
                        column({ key: "demoSvCol", style: StyleRefinement.from({
                            size: [Length.pct(1), Length.px(260)], gap: 6, padding: 8 }) }, rows)
                    ]);
                }),

                // The 2-D case is the one that shows BOTH bars. `always` is used so the
                // demo does not depend on the content having been measured before the
                // first frame -- and this page is also where the MODE itself is
                // documented, so the source under it has to be what produced it.
                new DocSection("Scrollbars on both axes", [
                    "A bar appears where the content overflows: drag the thumb, or click the track",
                    "to page by one viewport. Bars are OVERLAY chrome -- they never change a rect."
                ], [
                    "scrollView({ key: \"sv2\", scrollbarX: \"always\",",
                    "             scrollbarY: \"always\", barThickness: 10,",
                    "             style: { size: [280, 120] } }, [",
                    "    column({ size: [460, 300] }, rows)   // wider AND taller",
                    "])"
                ], 148, function ():Node
                {
                    var rows:Array = [];
                    for (var i:int = 0; i < 6; i++)
                    {
                        rows.push(box({ key: "svb" + i, style: StyleRefinement.from({
                            size: [Length.px(460), Length.px(50)],
                            background: (i % 2 == 0) ? 0xE0F2FE : 0xDBEAFE }) }, [
                            text("row " + (i + 1), { key: "svb" + i + "t", style: DocsDemo.LABEL,
                                                   ariaName: "" })
                        ]));
                    }
                    return scrollView({ key: "demoSv2", wheelStep: 26,
                        scrollbarX: "always", scrollbarY: "always", barThickness: 10,
                        style: StyleRefinement.from({ size: [280, 120], background: 0xF8FAFC }) }, [
                        column({ key: "demoSv2Col", style: StyleRefinement.from({
                            size: [Length.px(460), Length.px(300)] }) }, rows)
                    ]);
                }),

                new DocSection("Wheel, thumb, track", [
                    "One wheel notch is `wheelStep` px; with nothing to scroll vertically, the wheel",
                    "falls back to the horizontal axis. There is no momentum and no elastic edge."
                ], [
                    "// wheel -> offsetY; dragging a thumb writes the same offset back",
                    "// scrollbarX/scrollbarY: \"auto\" | \"always\" | \"never\""
                ], 76, function ():Node
                {
                    return text("Drag the thumb in the panel above; its source stays in sync.",
                        { style: DocsDemo.LABEL, ariaName: "" });
                }),

                // STICK TO BOTTOM. The one scroll feature whose whole contract is a
                // QUESTION ABOUT THE PAST ("was I at the end before this grew?"), so the
                // demo is live: scroll up and the next two lines no longer follow you.
                new DocSection("Logs that follow their end", [
                    "`stickToBottom` makes the view follow the END of its content as it grows -- a chat",
                    "or a console. A fresh view counts as being at the end, so a log opens on its",
                    "newest line rather than its oldest.",
                    "Scroll up and it lets go immediately (one pixel off the end is a reader, not a",
                    "rounding error); scroll back down and it re-attaches, because the rule is",
                    "re-derived from the live offset every frame rather than kept in a stuck flag.",
                    "The auto-scroll is a real move: `onScroll` fires and `offsetY` is written back,",
                    "so your model never disagrees with the screen."
                ], [
                    "scrollView({ stickToBottom: true,",
                    "             onScroll: function (x:Number, y:Number):void {",
                    "                 model.off = y;            // the follow is reported too",
                    "             } }, rows)"
                ], 148, function ():Node
                {
                    // Eight lines in a 96px viewport: 160px of content, so the view opens on
                    // line 8 and stays there. There is no append button in this demo -- the
                    // growth path is pinned by probes/widgets/stick, which is where a
                    // mutation can take the rule apart.
                    var rows:Array = [];
                    var n:int = int(m.num("sv.stickN", 8));
                    for (var i:int = 0; i < n; i++)
                        rows.push(text("line " + (i + 1), { key: "svs" + i, style: DocsDemo.LABEL,
                                                            ariaName: "" }));
                    return scrollView({ key: "demoSvStick", wheelStep: 26, stickToBottom: true,
                        onScroll: function (x:Number, y:Number):void { m.put("sv.stickOff", y); },
                        style: StyleRefinement.from({ size: [280, 96], background: 0xF8FAFC }) }, [
                        column({ key: "demoSvStickCol", style: StyleRefinement.from({
                            size: [Length.pct(1), Length.px(n * 20)], gap: 2, padding: 6 }) }, rows)
                    ]);
                }),

                // The view can be born scrolled, and the bars are author-styled rather
                // than theme-styled -- they are the one piece of chrome that sits on top
                // of the content and is therefore per-instance, not per-kind.
                new DocSection("Where it starts, and what the bars look like", [
                    "`offset` (or `offsetX` / `offsetY`) is the view's top-left in CONTENT",
                    "coordinates, so a restored scroll position needs no scrolling and no frame",
                    "with the wrong offset on screen. It is clamped to the real range.",
                    "The bars are the author's: `barThickness`, `barColor`, `barHoverColor` and",
                    "`trackColor`. `never` hides one axis entirely without changing the layout."
                ], [
                    "scrollView({ offset: [120, 0], scrollbarX: \"always\",",
                    "             scrollbarY: \"never\", barThickness: 8,",
                    "             barColor: 0x2563EB, trackColor: 0xE2E8F0,",
                    "             style: { size: [260, 56] } }, [ four 140px tiles ])"
                ], 116, function ():Node
                {
                    var tiles:Array = [];
                    for (var i:int = 0; i < 4; i++)
                        tiles.push(box({ key: "svx" + i, style: StyleRefinement.from({
                            size: [140, 40], background: (i % 2 == 0) ? 0xBFDBFE : 0xC7D2FE,
                            cornerRadii: 6, justifyContent: "center", alignItems: "center" }) }, [
                            text("tile " + (i + 1), { style: StyleRefinement.from({
                                text: { fontSize: 12, color: 0x1E3A8A } }), ariaName: "" })
                        ]));
                    return column({ gap: 6 }, [
                        scrollView({ key: "demoSvOff", offsetX: 120,
                            scrollbarX: "always", scrollbarY: "never",
                            barThickness: 8, barColor: 0x2563EB, trackColor: 0xE2E8F0,
                            style: StyleRefinement.from({ size: [260, 56],
                                background: 0xF8FAFC, padding: 6 }) }, [
                            // a ROW, with an explicit height: a container child of a
                            // scroll view must carry its own cross size (the viewport
                            // THROWS on an unmeasured child), and a container's default
                            // direction is a column -- four tiles dropped in loose would
                            // stack and never overflow x.
                            row({ style: StyleRefinement.from({ size: [560, 40] }) }, tiles)
                        ]),
                        text("born at x=120: the first tile is cut, not the row's start",
                            { style: DocsDemo.MONO, ariaName: "" })
                    ]);
                })
            ];

            return null;
        }
    }
}

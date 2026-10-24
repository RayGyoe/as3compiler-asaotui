// asaot.ui.table -- the author-facing factory for TableNode (see TableNode.as for
// why the file is lowercase and the class is not).
//
//   table(
//     [{ key: "name", title: "Name", width: 120 },
//      { key: "qty",  title: "Qty" }],                 // no width -> shares the rest
//     [{ name: "Widget", qty: 3 }, { name: "Gadget", qty: 12 }],
//     { key: "t", style: { size: [320, 160] }, rowHeight: 28, stripes: true,
//       selectedIndex: bindTo(model, "row"), onSelect: onRow })
//
// STRUCTURE IS BUILT HERE, per render pass: one `row` child for the header (unless
// `header:false`) and one `row` child per mounted data row, each holding one cell per
// column. The reconciler key-diffs the rows and the layout engine places them --
// the widget positions nothing.
//
// WHAT CHANGES WITH THE THREE OPT-INS (see TableNode's header for the contracts):
//   * `sortColumn >= 0` reorders a COPY of `rows` through TableNode.sortRows before
//     anything is built, so the display order is a pure function of the description;
//   * `virtual: true` mounts only rows [firstRow, lastRow] under keys `r<ABSOLUTE
//     index>`, so scrolling mounts new nodes instead of reusing a window's worth of
//     keys for different data;
//   * `resizable: true` only tags the description (the widget does the dragging) --
//     the width the author's model holds is still the only width the layout sees.
//
// WHY CELLS GET A FLEX BASIS RATHER THAN A WIDTH: alignment across rows is the
// engine's job. Every cell in column c carries the SAME style pointer (one per
// column per pass, shared by all rows -- the resolver's pointer-identity skip test
// then keeps steady frames free), so a flexed column is exactly as wide in row 3
// as in row 0 with no widget arithmetic and no second layout pass.
//
// NOTE ON HELPERS: the two loops below are inlined rather than factored into
// package-level helpers, because a package-level function must live in a file
// NAMED after it (that is why OptionSupport is a class) and a package-level `const`
// would be a second externally-visible definition in this file (G7). The palette
// they need is declared once on TableNode.
package asaot.ui
{
    import asaot.ui.kind.VirtualListWidget;
    import asaot.ui.style.StyleRefinement;

    public function table(columns:Array, rows:Array, opts:Object = null):Node
    {
        var n:TableNode = new TableNode();
        if (opts == null) opts = {};
        n.columns = columns == null ? [] : columns;
        n.rows = rows == null ? [] : rows;
        OptionSupport.applyOpts(n, opts);
        if (n.ariaName == null || n.ariaName == "") n.ariaName = "table";
        {
            if (opts.selectedIndex is Binding)
            {
                n.binding = Binding(opts.selectedIndex);
                // `*`, NOT `Object`: an `Object` slot would box the value once per read.
                // Number() never depended on the G9 fix (阶段二四八) and the G14 Array-identity
                // hazard (阶段二百五十三) is closed too, so `*` is now purely the cheaper default.
                var v:* = n.binding.get();
                n.selectedIndex = v == null ? -1 : Number(v);
            }
            else if (opts.selectedIndex != null) n.selectedIndex = Number(opts.selectedIndex);
            if (opts.onSelect != null) n.onSelect = (opts.onSelect as Function);
            if (opts.cellText != null) n.cellText = (opts.cellText as Function);
            if (opts.header != null) n.header = Boolean(opts.header);
            if (opts.stripes != null) n.stripes = Boolean(opts.stripes);
            if (opts.grid != null) n.grid = Boolean(opts.grid);
            if (opts.rowHeight != null) n.rowHeight = Number(opts.rowHeight);
            // ---- the three opt-ins -------------------------------------------
            if (opts.sortColumn != null) n.sortColumn = int(opts.sortColumn);
            if (opts.sortDescending != null) n.sortDescending = Boolean(opts.sortDescending);
            if (opts.onSort != null) n.onSort = (opts.onSort as Function);
            if (opts.resizable != null) n.resizable = Boolean(opts.resizable);
            if (opts.onColumnResize != null) n.onColumnResize = (opts.onColumnResize as Function);
            if (opts.virtual != null) n.virtual = Boolean(opts.virtual);
            if (opts.offsetY != null) n.offsetY = Number(opts.offsetY);
            if (opts.onScroll != null) n.onScroll = (opts.onScroll as Function);
        }

        var cols:int = n.columns.length;
        // A sort column outside the column list is a silent no-op in most toolkits;
        // here it is a bug in the author's model (they sorted by a column they
        // deleted), and the next render would show the model order with no hint why.
        if (n.sortColumn >= cols)
        {
            throw new Error("asaot.ui.table: sortColumn " + n.sortColumn
                + " is out of range (" + cols + " column(s)) -- -1 means unsorted.");
        }

        // ---- sorting: a COPY, never the author's array ----------------------
        var data:Array = n.rows;
        if (n.sortColumn >= 0 && cols > 0)
            data = TableNode.sortRows(n.rows, String(n.columns[n.sortColumn].key), n.sortDescending);
        n.rowCount = data.length;

        // ---- the window ------------------------------------------------------
        // Non-virtual: every row is mounted (the historical behaviour).
        var first:int = 0;
        var last:int = data.length - 1;
        var fit:int = data.length;
        if (n.virtual)
        {
            if (!(n.rowHeight > 0))
            {
                // Same rule as virtualList: without a row height there is no
                // definition of "which rows are visible", so a default would silently
                // show the wrong slice.
                throw new Error("asaot.ui.table: `virtual` needs a positive `rowHeight` (got "
                    + n.rowHeight + ") -- the window is row-granular.");
            }
            if (n.onScroll == null)
            {
                // A window that cannot move is a frozen table with no error: the wheel
                // would be swallowed and nothing would ever ask for the next slice.
                throw new Error("asaot.ui.table: `virtual` needs `onScroll(offsetY)` --"
                    + " the widget reports the scroll and the author re-renders with the new offset.");
            }
            var vh:Number = VirtualListWidget.viewportHeight(n.style);
            if (!(vh > 0)) vh = VirtualListWidget.DEFAULT_H;
            // The header never scrolls, so the BODY viewport is what is left of it.
            var bodyH:Number = vh - (n.header ? n.rowHeight : 0);
            if (bodyH < n.rowHeight) bodyH = n.rowHeight;
            fit = int(Math.ceil(bodyH / n.rowHeight));
            var maxFirst:int = data.length - fit;
            if (maxFirst < 0) maxFirst = 0;
            first = Math.round(n.offsetY / n.rowHeight);
            if (first > maxFirst) first = maxFirst;
            if (first < 0) first = 0;
            n.offsetY = first * n.rowHeight;
            // +1: a viewport whose height is not a multiple of rowHeight shows a
            // PARTIAL last row, and that row is real. The container's scrollRect clips
            // it, so it cannot leak out (see TableWidget).
            last = first + fit;
            if (last > data.length - 1) last = data.length - 1;
        }
        n.firstRow = first;
        n.visibleRows = fit;
        var colStyle:Array = new Array();    // body cells, one style per column
        var headCellStyle:Array = new Array();
        var pad:StyleRefinement = StyleRefinement.from({ padding: [TableNode.CELL_PAD, 0] });
        if (n.rowHeight > 0)
        {
            // A CELL FILLS ITS ROW. The engine's cross-axis default is flex-start, so
            // without a pinned height a cell shrinks to its TEXT height (13px at the
            // default font) inside a 26px row. Pinning it here -- rather than reaching
            // for `alignItems: stretch`, which this engine does not resolve yet -- keeps
            // the layout a function of the author's own numbers, not of font metrics.
            pad = pad.withPatch(StyleRefinement.from({ height: n.rowHeight }));
        }
        var headPad:StyleRefinement = pad.withPatch(StyleRefinement.from({
            text: { fontWeight: "bold", color: TableNode.HEAD_TEXT } }));
        for (var c:int = 0; c < cols; c++)
        {
            var col:Object = n.columns[c];
            // A column with an explicit width is a fixed basis; otherwise it grows
            // into an equal share of the leftover (basis 0 + grow 1 -- flexbox's
            // "equal columns", which is what makes the grid line up).
            var base:StyleRefinement;
            if (col.width != null && Number(col.width) > 0)
                base = StyleRefinement.from({ flexGrow: 0, flexShrink: 0, flexBasis: Number(col.width) });
            else
                base = StyleRefinement.from({ flexGrow: 1, flexShrink: 1, flexBasis: 0 });
            if (col.style != null) base = base.withPatch(StyleRefinement(col.style));
            colStyle.push(base.withPatch(pad));
            headCellStyle.push(base.withPatch(headPad));
        }

        var rowH:StyleRefinement = n.rowHeight > 0 ? StyleRefinement.from({ height: n.rowHeight }) : null;
        var headBg:StyleRefinement = StyleRefinement.from({ background: TableNode.HEAD_BG });
        // Patching rowH (rather than passing both keys: OptionSupport.applyOpts
        // reads EITHER `opts.style` OR the shorthand keys, never both) keeps the
        // header background while pinning its height.
        var headRow:StyleRefinement = rowH == null ? headBg : rowH.withPatch(headBg);
        var kids:Array = [];

        // ---- the header row -------------------------------------------------
        if (n.header)
        {
            var heads:Array = [];
            for (var h:int = 0; h < cols; h++)
            {
                var hcol:Object = n.columns[h];
                var title:String = hcol.title != null ? String(hcol.title) : String(hcol.key);
                // The indicator is part of the LABEL, not a separate node: the header
                // cell is a plain text node, and a second child would need a style per
                // state plus an extra node on every render. U+25B2/U+25BC are the
                // browser's own table arrows.
                if (n.sortColumn == h)
                    title = title + (n.sortDescending ? " \u25BC" : " \u25B2");
                var hstyle:StyleRefinement = headCellStyle[h];
                // A sortable header announces itself with the pointer shape (batch 1:
                // Style.cursor): only when there IS an onSort to answer the click.
                if (n.onSort != null) hstyle = hstyle.withPatch(StyleRefinement.from({ cursor: "hand" }));
                // Column positions go into the key: the header cell of column 3 is
                // the same node across frames even when the titles change.
                heads.push(text(title, { key: "h:" + h, style: hstyle }));
            }
            kids.push(row({ key: "hdr", style: headRow }, heads));
        }

        // ---- the body rows (the mounted window under `virtual`) --------------
        for (var r:int = first; r <= last; r++)
        {
            var cells:Array = [];
            var rowValue:Object = data[r];
            for (var cc:int = 0; cc < cols; cc++)
            {
                var key:String = String(n.columns[cc].key);
                // `rowValue == null ? null : rowValue[key]` -- a null LITERAL in a
                // ternary's THEN slot -- used to collapse the whole conditional to a
                // constant null (compiler-gaps G16), so every cell rendered empty.
                // G16 is FIXED (stage 266) and probes/g16-ternary-null keeps the AOT
                // deviation set empty. This exact line is what found the gap.
                var cv:Object = rowValue == null ? null : rowValue[key];
                var s:String;
                if (n.cellText != null) s = String(n.cellText(cv, r, cc));
                else if (cv == null) s = "";
                else s = String(cv);
                cells.push(text(s, { key: "r" + r + "c" + cc, style: colStyle[cc] }));
            }
            // The key is the ABSOLUTE row index, so a window shift mounts genuinely
            // new nodes; keying by position within the window would hand a scrolled-in
            // row the previous occupant's node (same key, different data) and hide
            // whatever the widget hung on it.
            // `rowH == null` picks the branch without `style` at all: passing
            // {style:null} would build an empty refinement per row per frame.
            kids.push(rowH == null ? row({ key: "r" + r }, cells) : row({ key: "r" + r, style: rowH }, cells));
        }

        OptionSupport.addChildren(n, kids);
        return n;
    }
}
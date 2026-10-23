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
// `header:false`) and one `row` child per data row, each holding one cell per
// column. The reconciler key-diffs the rows and the layout engine places them --
// the widget positions nothing.
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
    import asaot.ui.style.StyleRefinement;

    public function table(columns:Array, rows:Array, opts:Object = null):Node
    {
        var n:TableNode = new TableNode();
        n.columns = columns == null ? [] : columns;
        n.rows = rows == null ? [] : rows;
        OptionSupport.applyOpts(n, opts);
        if (n.ariaName == null || n.ariaName == "") n.ariaName = "table";
        if (opts != null)
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
        }

        var cols:int = n.columns.length;
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
                // Column positions go into the key: the header cell of column 3 is
                // the same node across frames even when the titles change.
                heads.push(text(title, { key: "h:" + h, style: headCellStyle[h] }));
            }
            kids.push(row({ key: "hdr", style: headRow }, heads));
        }

        // ---- the body rows --------------------------------------------------
        var rc:int = n.rows.length;
        for (var r:int = 0; r < rc; r++)
        {
            var cells:Array = [];
            var rowValue:Object = n.rows[r];
            for (var cc:int = 0; cc < cols; cc++)
            {
                var key:String = String(n.columns[cc].key);
                // NOT `rowValue == null ? null : rowValue[key]`: a null LITERAL in the
                // THEN slot makes the whole conditional collapse to a constant null
                // (compiler-gaps G16) -- every cell would render empty. if/else is the
                // workaround shape, and this exact line is one of the places that found
                // the gap while this widget was being written.
                var cv:Object;
                if (rowValue == null) cv = null;
                else cv = rowValue[key];
                var s:String;
                if (n.cellText != null) s = String(n.cellText(cv, r, cc));
                else if (cv == null) s = "";
                else s = String(cv);
                cells.push(text(s, { key: "r" + r + "c" + cc, style: colStyle[cc] }));
            }
            // `rowH == null` picks the branch without `style` at all: passing
            // {style:null} would build an empty refinement per row per frame.
            kids.push(rowH == null ? row({ key: "r" + r }, cells) : row({ key: "r" + r, style: rowH }, cells));
        }

        OptionSupport.addChildren(n, kids);
        return n;
    }
}
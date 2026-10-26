// asaot.ui.tree -- the author-facing factory for TreeNode.
//
//   tree([ { key: "src", label: "src", children: [ { key: "src/a.as", label: "a.as" } ] } ],
//        { key: "files", expanded: ["src"], selectedKey: "src/a.as",
//          rowHeight: 26, width: 240,
//          onToggle: function (key:String):void { ... },   // the author flips `expanded`
//          onSelect: function (key:String):void { ... } })
//
// ONE PASS, AN EXPLICIT STACK. A branch's children become ROWS OF THIS SAME NODE only
// while the branch is open (see TreeNode's header); depth shows up as a left padding
// of TREE_PAD + depth*TREE_INDENT and as the `depth` field the widget's hit test
// reads. No recursive helper is used because a package-level function needs its own
// file (compiler-gaps G7) -- an explicit stack keeps all of it in this one function.
//
// `itemHeight`/`rowHeight` is optional: at 0 the rows size themselves (a text row's
// natural height); at >0 every row is pinned, which is what a probe wants.
package asaot.ui
{
    import asaot.ui.kind.VirtualListWidget;
    import asaot.ui.style.Fill;
    import asaot.ui.style.StyleRefinement;

    public function tree(items:Array, opts:Object = null):Node
    {
        var n:TreeNode = new TreeNode();
        n.items = items == null ? [] : items;
        OptionSupport.applyOpts(n, opts);
        if (n.ariaName == null || n.ariaName == "") n.ariaName = "tree";
        if (opts != null)
        {
            if (opts.expanded != null) n.expanded = OptionSupport.list(opts.expanded);
            if (opts.selectedKey != null) n.selectedKey = String(opts.selectedKey);
            if (opts.rowHeight != null) n.rowHeight = Number(opts.rowHeight);
            if (opts.onToggle != null) n.onToggle = (opts.onToggle as Function);
            if (opts.onSelect != null) n.onSelect = (opts.onSelect as Function);
            if (opts.virtual != null) n.virtual = Boolean(opts.virtual);
            if (opts.offsetY != null) n.offsetY = Number(opts.offsetY);
            if (opts.onScroll != null) n.onScroll = (opts.onScroll as Function);
        }

        var base:String = n.key == null ? "tree" : String(n.key);
        var rows:Array = [];

        // Frames are { list, i, depth }. Only open branches push a frame, so the walk
        // is exactly "the visible subtree", in document order.
        var stack:Array = [{ list: n.items, i: 0, depth: 0 }];
        while (stack.length > 0)
        {
            var f:Object = stack[stack.length - 1];
            var list:Array = f.list;
            if (int(f.i) >= list.length) { stack.pop(); continue; }
            var item:Object = list[int(f.i)];
            f.i = int(f.i) + 1;
            if (item == null) continue;

            var key:String = item.key == null ? String(rows.length) : String(item.key);
            var label:String = item.label == null ? key : String(item.label);
            var children:Array = item.children == null ? [] : (item.children as Array);
            var branch:Boolean = children.length > 0;
            var open:Boolean = branch && TreeNode.holds(n.expanded, key);

            var left:Number = OverlayChrome.TREE_PAD + int(f.depth) * OverlayChrome.TREE_INDENT;
            // The row SPEC is collected first and materialised second: under `virtual`
            // the window is not known until the flatten finishes (it needs the total
            // row count), and creating nodes we would immediately discard is exactly
            // the work virtualisation exists to avoid.
            rows.push({ key: key, label: label, depth: int(f.depth), left: left,
                        branch: branch, open: open });

            if (open) stack.push({ list: children, i: 0, depth: int(f.depth) + 1 });
        }

        n.rows = rows;
        n.rowCount = rows.length;

        var first:int = 0;
        var last:int = rows.length - 1;
        if (n.virtual)
        {
            if (!(n.rowHeight > 0))
            {
                throw new Error("asaot.ui.tree: `virtual: true` needs a positive `rowHeight` (got "
                    + n.rowHeight + "). The window is row-granular: without a row height"
                    + " there is no definition of which rows are visible.");
            }
            var vh:Number = VirtualListWidget.viewportHeight(n.style);
            if (!(vh > 0))
            {
                throw new Error("asaot.ui.tree: `virtual: true` needs an explicit point height"
                    + " on the tree (style.size/height, e.g. [240, 300]). The window has to"
                    + " know how many rows fit before layout runs.");
            }
            var fit:int = int(Math.ceil(vh / n.rowHeight));
            if (fit < 1) fit = 1;
            var maxFirst:int = rows.length - fit;
            if (maxFirst < 0) maxFirst = 0;
            var off:Number = isNaN(n.offsetY) ? 0 : n.offsetY;
            first = int(Math.round(off / n.rowHeight));
            if (first > maxFirst) first = maxFirst;
            if (first < 0) first = 0;
            n.offsetY = first * n.rowHeight;
            n.firstRow = first;
            n.visibleRows = fit;
            last = first + fit;   // +1: the partial row
            if (last > rows.length - 1) last = rows.length - 1;
        }

        var kids:Array = [];
        for (var r:int = first; r <= last; r++)
        {
            var spec:Object = rows[r];
            // AN ALPHA-0 FILL ON EVERY ROW, and it is not decoration: the hit test is
            // BOUNDS-based (as_pick_hit in the runtime), so a row that paints nothing is
            // only clickable where its LABEL happens to be. Without this line the twisty
            // strip -- the whole point of OverlayChrome.TREE_HIT -- cannot be clicked by a
            // mouse at all, and neither can the empty right half of a short label.
            var rowStyle:StyleRefinement = StyleRefinement.from({
                height: n.rowHeight > 0 ? n.rowHeight : OverlayChrome.TREE_ROW_H,
                background: Fill.fromArgb(0, 0, 0, 0),
                padding: [0, 0, 0, Number(spec.left)]
            });
            rowStyle = OverlayChrome.TREE_ROW.withPatch(rowStyle);
            if (n.virtual)
            {
                // Both halves, for the reason virtualList.as records: `height` alone is
                // overridden by the flexbox solve when the window overflows, and
                // `flexShrink: 0` encodes as a zero basis and collapses the row.
                rowStyle = rowStyle.withPatch(StyleRefinement.from({
                    minSize: [null, n.rowHeight]
                }));
            }
            if (n.selectedKey != null && n.selectedKey == String(spec.key))
            {
                rowStyle = rowStyle.withPatch(StyleRefinement.from({
                    background: OverlayChrome.ITEM_SELECTED
                }));
            }

            // row() AND NOT box(): a BoxNode's `direction` field OVERRIDES the style's
            // flexDirection in Theme.resolve (it defaults to "column"), so a row built
            // with box() stays a column however row-like its style looks -- the label
            // then sits CENTERED by alignItems instead of at the indent. That is exactly
            // how this probe first caught it (label at x=142, not 42).
            var rowKey:String = String(spec.key);
            var rowNode:Node = row({ key: base + ":t" + rowKey, style: rowStyle,
                                     ariaName: String(spec.label) });
            rowNode.addChild(text(String(spec.label), { key: base + ":t" + rowKey + ":l",
                                          style: OverlayChrome.TREE_TEXT, ariaName: "" }));
            kids.push(rowNode);
        }

        OptionSupport.addChildren(n, kids);
        return n;
    }
}
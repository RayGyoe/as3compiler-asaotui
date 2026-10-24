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
        }

        var base:String = n.key == null ? "tree" : String(n.key);
        var rows:Array = [];
        var kids:Array = [];

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
            var rowStyle:StyleRefinement = StyleRefinement.from({
                height: n.rowHeight > 0 ? n.rowHeight : OverlayChrome.TREE_ROW_H,
                padding: [0, 0, 0, left]
            });
            rowStyle = OverlayChrome.TREE_ROW.withPatch(rowStyle);
            if (n.selectedKey != null && n.selectedKey == key)
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
            var rowNode:Node = row({ key: base + ":t" + key, style: rowStyle, ariaName: label });
            rowNode.addChild(text(label, { key: base + ":t" + key + ":l",
                                          style: OverlayChrome.TREE_TEXT, ariaName: "" }));
            kids.push(rowNode);
            rows.push({ key: key, label: label, depth: int(f.depth),
                        branch: branch, open: open });

            if (open) stack.push({ list: children, i: 0, depth: int(f.depth) + 1 });
        }

        n.rows = rows;
        OptionSupport.addChildren(n, kids);
        return n;
    }
}
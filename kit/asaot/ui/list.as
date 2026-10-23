// asaot.ui.list -- the author-facing factory for ListNode (see ListNode.as for
// why the file is lowercase and the class is not).
//
//   list(items, function(item:Object, index:int):Node { return row(...); },
//        { key: "l", style: { size: [320, 240] }, separator: true, itemHeight: 40,
//          selectedIndex: bindTo(model, "row"), onSelect: onRow })
//
// The items are mapped to child Nodes HERE, at factory time. render() is only
// re-evaluated on a dirty frame, so this is exactly one Node per item per frame;
// the reconciler keyed-diffs them and the layout engine places them. The widget
// does NOT hand-position anything.
//
// `itemHeight > 0` stamps a fixed height onto each row through a style patch
// (StyleRefinement.withPatch), which preserves whatever the builder set (e.g. a
// width) and only pins the height. It is applied at the row level, not to the
// container, so a row can still carry its own layout.
package asaot.ui
{
    import asaot.ui.style.StyleRefinement;

    public function list(items:Array, builder:Function, opts:Object = null):Node
    {
        var n:ListNode = new ListNode();
        n.items = items;
        n.builder = builder;
        OptionSupport.applyOpts(n, opts);
        if (n.ariaName == null || n.ariaName == "") n.ariaName = "list";
        if (opts != null)
        {
            if (opts.selectedIndex is Binding)
            {
                n.binding = Binding(opts.selectedIndex);
                // `*`, NOT `Object`: a binding value can be anything; `Object` would box
                // it (one allocation per read) and an Array would lose its identity there
                // (G9 + G14). Number() was never affected by the G9 bug.
                var v:* = n.binding.get();
                n.selectedIndex = v == null ? 0 : Number(v);
            }
            else if (opts.selectedIndex != null) n.selectedIndex = Number(opts.selectedIndex);
            if (opts.onSelect != null) n.onSelect = (opts.onSelect as Function);
            if (opts.separator != null) n.separator = Boolean(opts.separator);
            if (opts.itemHeight != null) n.itemHeight = Number(opts.itemHeight);
        }

        var kids:Array = [];
        var count:int = items == null ? 0 : items.length;
        var hRef:StyleRefinement = null;
        if (n.itemHeight > 0) hRef = StyleRefinement.from({ height: n.itemHeight });
        // A hairline between rows. `width` is intentionally NOT set: in a column
        // the cross axis (width) stretches, and the divider's own auto size pins
        // the height to 1 (DividerWidget.measure).
        var sepRef:StyleRefinement = StyleRefinement.from({ background: 0xD1D5DB });
        for (var i:int = 0; i < count; i++)
        {
            var child:Node = builder(items[i], i);
            if (child != null)
            {
                if (hRef != null)
                {
                    if (child.style == null) child.style = hRef;
                    else child.style = child.style.withPatch(hRef);
                }
                kids.push(child);
            }
            if (n.separator && i < count - 1)
            {
                kids.push(divider({ key: "sep:" + i, style: sepRef }));
            }
        }
        OptionSupport.addChildren(n, kids);
        return n;
    }
}
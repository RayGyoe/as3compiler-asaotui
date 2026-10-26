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
                // `*`, NOT `Object`: an `Object` slot would box the value once per read.
                // Number() never depended on the G9 fix (阶段二四八) and the G14 Array-identity
                // hazard (阶段二百五十三) is closed too, so `*` is now purely the cheaper default.
                var v:* = n.binding.get();
                n.selectedIndex = v == null ? 0 : Number(v);
            }
            else if (opts.selectedIndex != null) n.selectedIndex = Number(opts.selectedIndex);
            if (opts.onSelect != null) n.onSelect = (opts.onSelect as Function);
            if (opts.separator != null) n.separator = Boolean(opts.separator);
            if (opts.itemHeight != null) n.itemHeight = Number(opts.itemHeight);
            if (opts.virtual != null) n.virtual = Boolean(opts.virtual);
            if (opts.offsetY != null) n.offsetY = Number(opts.offsetY);
            if (opts.onScroll != null) n.onScroll = (opts.onScroll as Function);
        }

        var count:int = items == null ? 0 : items.length;
        n.count = count;
        if (n.virtual)
        {
            ListNode.mountWindow(n, items, builder, count);
            return n;
        }

        var kids:Array = [];
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
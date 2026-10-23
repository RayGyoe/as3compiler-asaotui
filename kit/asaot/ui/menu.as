// asaot.ui.menu -- the author-facing factory for MenuNode.
//
//   menu({ key, open, anchorKey, placement, offset, width, items, selectedIndex,
//          onSelect, onClose, closeOnOutside, style })
//
// Items accept either a plain string or `{ label, value }`; the factory only needs
// the LABEL (the value is the author's business -- onSelect reports the index, so a
// model can do `items.indexOf(...)` without this library ever touching its data
// shape). A row is a fixed-height box with one text child: no per-row widget, which
// is why a 50-item menu costs 100 nodes and no behaviour.
package asaot.ui
{
    import asaot.ui.style.Length;
    import asaot.ui.style.Size;
    import asaot.ui.style.StyleRefinement;

    public function menu(opts:Object = null):Node
    {
        var n:MenuNode = new MenuNode();
        OptionSupport.applyOpts(n, opts);
        if (opts != null)
        {
            if (opts.open != null) n.open = Boolean(opts.open);
            if (opts.anchorKey != null) n.anchorKey = String(opts.anchorKey);
            if (opts.placement != null) n.placement = String(opts.placement);
            if (opts.offset != null) n.offset = Number(opts.offset);
            if (opts.width != null) n.width = Number(opts.width);
            if (opts.items != null) n.items = OptionSupport.list(opts.items);
            if (opts.selectedIndex != null) n.selectedIndex = int(Number(opts.selectedIndex));
            if (opts.onSelect != null) n.onSelect = (opts.onSelect as Function);
            if (opts.closeOnOutside != null) n.closeOnOutside = Boolean(opts.closeOnOutside);
            if (opts.onClose != null) n.onClose = (opts.onClose as Function);
        }
        n.visible = n.open;

        var w:StyleRefinement = new StyleRefinement();
        w.size = Size.of(Length.px(n.width), null);
        w.position = "absolute";
        n.style = (n.style == null ? new StyleRefinement() : n.style)
            .withPatch(OverlayChrome.MENU_PANEL.withPatch(w));
        if (n.ariaName == null) n.ariaName = "menu";

        var base:String = n.key == null ? "menu" : String(n.key);
        var items:Array = n.items == null ? [] : n.items;
        for (var i:int = 0; i < items.length; i++)
        {
            var it:Object = items[i];
            var label:String = OverlayList.labelOf(it);
            var rowNode:Node = box({ key: base + ":i" + i, style: OverlayChrome.MENU_ITEM,
                                     ariaName: label });
            rowNode.addChild(text(label, { key: base + ":i" + i + ":t", style: OverlayChrome.MENU_TEXT }));
            n.addChild(rowNode);
        }
        return n;
    }
}
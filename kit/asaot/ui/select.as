// asaot.ui.select -- the author-facing factory for SelectNode.
//
//   select({ key, open, value, placeholder, options, onSelect, onOpenChange,
//            width, style })
//
// STRUCTURE (SelectWidget depends on it):
//   select node        style SELECT_TRIGGER (row, 34 high, padding [10,0])
//     ├─ [0] label text   the selected option's label, or the placeholder
//     └─ [1] dropdown box style DROP_SHEET (absolute; the widget writes its insets)
//              └─ one box + text per option
//
// THE DROPDOWN IS ALWAYS THE LAST CHILD, and the widget takes it from the end (the
// same contract dialog()/popover() keep) so no index constant can go stale.
//
// A SELECTED ROW CARRIES ITS OWN BACKGROUND. Unlike the menu -- whose selected index
// changes on a click that the author may not re-render -- a select's selection only
// moves through `onSelect`, and the author re-renders with the new `value`. So the
// highlight can be an ordinary style diff, and the row needs no painted band.
package asaot.ui
{
    import asaot.ui.style.Length;
    import asaot.ui.style.Size;
    import asaot.ui.style.StyleRefinement;

    public function select(opts:Object = null):Node
    {
        var n:SelectNode = new SelectNode();
        OptionSupport.applyOpts(n, opts);
        if (opts != null)
        {
            if (opts.open != null) n.open = Boolean(opts.open);
            if (opts.value != null) n.value = String(opts.value);
            if (opts.placeholder != null) n.placeholder = String(opts.placeholder);
            if (opts.options != null) n.options = OptionSupport.list(opts.options);
            if (opts.onSelect != null) n.onSelect = (opts.onSelect as Function);
            if (opts.onOpenChange != null) n.onOpenChange = (opts.onOpenChange as Function);
            if (opts.width != null) n.width = Number(opts.width);
        }

        var w:StyleRefinement = new StyleRefinement();
        w.size = Size.of(Length.px(n.width), null);
        n.style = (n.style == null ? new StyleRefinement() : n.style)
            .withPatch(OverlayChrome.SELECT_TRIGGER.withPatch(w));
        if (n.ariaName == null) n.ariaName = "select";

        var base:String = n.key == null ? "select" : String(n.key);
        var options:Array = n.options == null ? [] : n.options;

        // The visible label: the option whose value matches, else the placeholder.
        var shown:String = n.placeholder;
        var sel:int = -1;
        for (var i:int = 0; i < options.length; i++)
        {
            var v:String = OverlayList.valueOf(options[i], i);
            if (n.value != null && v == n.value) { sel = i; break; }
        }
        if (sel >= 0) shown = OverlayList.labelOf(options[sel]);

        n.addChild(text(shown, { key: base + ":label", style: OverlayChrome.SELECT_LABEL,
                                 ariaName: "" }));

        var dropStyle:StyleRefinement = new StyleRefinement();
        dropStyle.size = Size.of(Length.px(n.width), null);
        dropStyle.position = "absolute";
        var drop:Node = box({ key: base + ":drop", style: OverlayChrome.MENU_PANEL.withPatch(dropStyle),
                             ariaName: "", visible: n.open });

        for (var j:int = 0; j < options.length; j++)
        {
            var label:String = OverlayList.labelOf(options[j]);
            // The selected row's highlight is DECLARATIVE (see the header). The row
            // style is either the plain item or the item with a background, so a
            // selection change is a paint-only style diff.
            var rowStyle:StyleRefinement = OverlayChrome.MENU_ITEM;
            if (j == sel) rowStyle = OverlayChrome.MENU_ITEM_SEL;
            var rowNode:Node = box({ key: base + ":i" + j, style: rowStyle, ariaName: label });
            rowNode.addChild(text(label, { key: base + ":i" + j + ":t",
                                           style: OverlayChrome.MENU_TEXT, ariaName: "" }));
            drop.addChild(rowNode);
        }
        n.addChild(drop);
        return n;
    }
}
// asaot.ui.multiSelect -- the author-facing factory for MultiSelectNode.
//
//   multiSelect({ key, open, values: ["a"], options: ["Alpha", "Beta"],
//                 placeholder: "Pick some", width: 220,
//                 onToggle: function (i:int):void { ... },
//                 onOpenChange: function (o:Boolean):void { ... } })
//
// STRUCTURE (MultiSelectWidget depends on it, same shape as select):
//   node  style SELECT_TRIGGER (row 34, padding [10, 0])
//     ├─ [0] summary text   joined labels, or the placeholder
//     └─ [1] dropdown box   ABSOLUTE; the widget writes its insets
//              └─ one row + label per option, padding-left 26 for the check mark
//
// THE SUMMARY IS BUILT HERE, NOT IN THE WIDGET. A trigger label is a pure function of
// `values` + `options`, and the author re-renders when they change -- so the same
// "description is the projection" rule that makes `select` work applies unchanged.
// `Array.join` is not part of the kit's narrow String surface, so the separator is
// spelled with a loop.
package asaot.ui
{
    import asaot.ui.style.Length;
    import asaot.ui.style.Size;
    import asaot.ui.style.StyleRefinement;

    public function multiSelect(opts:Object = null):Node
    {
        var n:MultiSelectNode = new MultiSelectNode();
        OptionSupport.applyOpts(n, opts);
        if (n.ariaName == null || n.ariaName == "") n.ariaName = "multi select";
        if (opts != null)
        {
            if (opts.open != null) n.open = Boolean(opts.open);
            if (opts.values != null) n.values = OptionSupport.list(opts.values);
            if (opts.placeholder != null) n.placeholder = String(opts.placeholder);
            if (opts.options != null) n.options = OptionSupport.list(opts.options);
            if (opts.onToggle != null) n.onToggle = (opts.onToggle as Function);
            if (opts.onOpenChange != null) n.onOpenChange = (opts.onOpenChange as Function);
            if (opts.width != null) n.width = Number(opts.width);
        }

        var w:StyleRefinement = new StyleRefinement();
        w.size = Size.of(Length.px(n.width), null);
        n.style = (n.style == null ? new StyleRefinement() : n.style)
            .withPatch(OverlayChrome.SELECT_TRIGGER.withPatch(w));

        var base:String = n.key == null ? "multi" : String(n.key);
        var options:Array = n.options == null ? [] : n.options;
        var values:Array = n.values == null ? [] : n.values;

        // The summary: the selected labels in OPTION ORDER (not in selection order),
        // so the trigger reads the same as the list it came from.
        var summary:String = "";
        var picked:int = 0;
        for (var i:int = 0; i < options.length; i++)
        {
            var v:String = OverlayList.valueOf(options[i], i);
            if (!MultiSelectNode.holds(values, v)) continue;
            if (picked > 0) summary = summary + ", ";
            summary = summary + OverlayList.labelOf(options[i]);
            picked = picked + 1;
        }
        if (picked == 0) summary = n.placeholder;

        n.addChild(text(summary, { key: base + ":label", style: OverlayChrome.SELECT_LABEL,
                                   ariaName: "" }));

        var dropStyle:StyleRefinement = new StyleRefinement();
        dropStyle.size = Size.of(Length.px(n.width), null);
        dropStyle.position = "absolute";
        var drop:Node = box({ key: base + ":drop", style: OverlayChrome.MENU_PANEL.withPatch(dropStyle),
                             ariaName: "", visible: n.open });

        for (var j:int = 0; j < options.length; j++)
        {
            var label:String = OverlayList.labelOf(options[j]);
            var ov:String = OverlayList.valueOf(options[j], j);
            var on:Boolean = MultiSelectNode.holds(values, ov);
            var rowStyle:StyleRefinement = on ? OverlayChrome.MENU_ITEM_SEL : OverlayChrome.MENU_ITEM;
            // The check mark is painted by the widget into this padding, so the row
            // style owns the space and the glyph never sits on top of the label.
            rowStyle = rowStyle.withPatch(StyleRefinement.from({ padding: [0, 0, 0, 26] }));
            var rowNode:Node = box({ key: base + ":i" + j, style: rowStyle, ariaName: label });
            rowNode.addChild(text(label, { key: base + ":i" + j + ":t",
                                           style: OverlayChrome.MENU_TEXT, ariaName: "" }));
            drop.addChild(rowNode);
        }
        n.addChild(drop);
        return n;
    }
}
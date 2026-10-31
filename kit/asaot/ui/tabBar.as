// asaot.ui.tabBar -- the author-facing factory for TabBarNode (see TabBarNode.as
// for why the file is lowercase and the class is not).
//
//   tabBar({ key: "tabs", selectedIndex: model.tab,
//            items: [ { key: "home", label: "Home", icon: "M4 20 V10 L12 4 L20 10 V20 Z" },
//                     { key: "search", label: "Search", icon: "M11 4 A7 7 0 1 1 10.99 4 Z" },
//                     { key: "me", label: "Me", icon: "M4 20 A8 8 0 0 1 20 20 Z" } ],
//            onSelect: function (i:int):void { model.tab = i; view.invalidate(Dirty.ALL); } })
//
// The bar's HEIGHT is `barHeight` (default 56) plus whatever the safe-area fold
// adds as padding: don't pass `style.height`, it would fight both.
//
// The cells are EQUAL WIDTH (`flexGrow: 1`), which is the phone convention and the
// reason `items` cannot be a variable-length label list -- a 5th tab makes every
// tab narrower rather than scrolling. A bar with too many tabs is an authoring
// mistake, not a state this widget can improve on.
package asaot.ui
{
    import asaot.ui.style.StyleRefinement;
    import asaot.ui.style.auto;
    import asaot.ui.style.pct;

    public function tabBar(opts:Object):Node
    {
        var n:TabBarNode = new TabBarNode();
        OptionSupport.applyOpts(n, opts);

        var rowH:Number = (opts != null && opts.barHeight != null)
            ? Number(opts.barHeight) : n.barHeight;
        if (isNaN(rowH) || rowH <= 0)
        {
            throw new Error("asaot.ui: tabBar barHeight must be a positive number (got "
                + rowH + ")");
        }
        n.barHeight = rowH;

        var list:Array = (opts != null && opts.items != null)
            ? OptionSupport.list(opts.items) : n.items;
        if (list == null) list = [];
        n.items = list;

        var sel:int = (opts != null && opts.selectedIndex != null)
            ? int(Number(opts.selectedIndex)) : n.selectedIndex;
        if (sel >= list.length) sel = -1;   // a model that outlived its list selects none
        if (sel < -1) sel = -1;
        n.selectedIndex = sel;

        var cb:Function = null;
        if (opts != null && opts.onSelect != null)
        {
            cb = opts.onSelect as Function;
            n.onSelect = cb;
        }

        var t:ThemeTokens = Theme.tokens();
        var base:StyleRefinement = StyleRefinement.from({
            flexDirection: "column", background: t.surface
        });
        n.style = n.style == null ? base : base.withPatch(n.style);
        if (n.ariaName == null || n.ariaName == "") n.ariaName = "tabs";

        // The tint is the SELECTED STATE: a text-style patch on the cell, inherited by
        // the label. It is applied to the cell rather than to the label so that
        // anything else the author puts in the cell (a badge, a custom Node) inherits
        // the same colour.
        var selTint:StyleRefinement = StyleRefinement.from({
            text: { color: t.accent, fontWeight: "bold" } });
        var offTint:StyleRefinement = StyleRefinement.from({
            text: { color: t.textMuted } });

        var strip:Node = row({ style: StyleRefinement.from({
            height: rowH, alignItems: "stretch" }) });

        for (var i:int = 0; i < list.length; i++)
        {
            var it:Object = list[i];
            if (it == null) throw new Error("asaot.ui: tabBar item " + i + " is not an Object");
            var label:String = it.label == null ? "" : String(it.label);
            var on:Boolean = (i == sel);

            var cellStyle:StyleRefinement = StyleRefinement.from({
                flexGrow: 1, alignItems: "center", justifyContent: "center", gap: 2
            }).withPatch(on ? selTint : offTint);

            var kids:Array = [];
            var ic:Object = it.icon;
            if (ic != null)
            {
                if (ic is Node) kids.push(ic as Node);   // the author's own colour wins
                else kids.push(icon(String(ic), {
                    size: [24, 24], color: on ? t.accent : t.textMuted }));
            }
            // The label is pinned to the CELL's width (and truncated by ellipsis) instead
            // of sizing to its text: a cell is a flex share, so an over-long label would
            // otherwise be laid out at its intrinsic width and paint OVER the neighbouring
            // tab (the cell does not clip). `pct(1)` resolves because the cell's width is
            // definite by then; `textAlign:"center"` keeps a short label centred.
            kids.push(text(label, { style: StyleRefinement.from({
                size: [pct(1), auto()],
                text: { fontSize: 11, textAlign: "center", textOverflow: "ellipsis" } })
                .withPatch(on ? selTint : offTint) }));

            var cellOpts:Object = {
                role: "tab", ariaName: label,
                onClick: OptionSupport.tapIndex(cb, i),
                style: cellStyle
            };
            if (it.key != null) cellOpts.key = String(it.key);
            strip.addChild(column(cellOpts, kids));
        }
        n.addChild(strip);
        return n;
    }
}

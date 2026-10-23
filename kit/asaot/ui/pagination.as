// asaot.ui.pagination -- the author-facing factory for PaginationNode (see
// PaginationNode.as for why the file is lowercase and the class is not).
//
//   pagination(3, 20, { key: "pg", pageSize: 7,
//                       onSelect: function(p:int):void { load(p); } })
//
// The visible numbers come from PaginationWidget.pageList(page, pageCount, size) --
// the SAME function the widget uses to map a click back to a page, so a rendered
// slot and a clicked slot are the same slot by construction.
//
// WHY THE CHIPS CARRY `role: "button"`: a page number IS a button, and the role is
// also the marker the widget uses to skip the ellipsis texts when it counts slots.
// The current page is the "info" chip TONE rather than something the widget paints,
// so changing page is a style change (re-resolve), not a repaint hook.
package asaot.ui
{
    import asaot.ui.kind.PaginationWidget;
    import asaot.ui.style.StyleRefinement;

    public function pagination(page:int, pageCount:int, opts:Object = null):Node
    {
        var n:PaginationNode = new PaginationNode();
        n.page = page < 1 ? 1 : page;
        n.pageCount = pageCount < 1 ? 1 : pageCount;
        if (n.page > n.pageCount) n.page = n.pageCount;
        OptionSupport.applyOpts(n, opts);
        if (n.ariaName == null || n.ariaName == "") n.ariaName = "pagination";
        if (opts != null)
        {
            if (opts.windowSize != null) n.windowSize = Number(opts.windowSize);
            if (opts.onSelect != null) n.onSelect = (opts.onSelect as Function);
            if (opts.page is Binding)
            {
                n.binding = Binding(opts.page);
                // `*`, NOT `Object`: an `Object` slot would box the value once per read.
                // Number() never depended on the G9 fix (阶段二四八) and the G14 Array-identity
                // hazard (阶段二百五十三) is closed too, so `*` is now purely the cheaper default.
                var v:* = n.binding.get();
                n.page = v == null ? 1 : Number(v);
            }
            else if (opts.page != null)
            {
                n.page = Number(opts.page);
                if (n.page < 1) n.page = 1;
                if (n.page > n.pageCount) n.page = n.pageCount;
            }
        }

        var cur:int = int(n.page);
        var pcs:int = int(n.pageCount);
        var list:Array = PaginationWidget.pageList(cur, pcs, int(n.windowSize));

        // The stepper is HORIZONTAL: pin the direction as a patch on top of whatever
        // the author set (the resolver's default is a column, which would stack the
        // chips). Patching, not replacing, keeps the author's size/padding.
        var dirRef:StyleRefinement = StyleRefinement.from({ flexDirection: "row" });
        // NOT a ternary here: `n.style == null ? dirRef : ...` has a null LITERAL in
        // the THEN slot, and that shape collapses to a constant null on this compiler
        // (compiler-gaps G16) -- the container would lose its style altogether.
        if (n.style == null) n.style = dirRef;
        else n.style = n.style.withPatch(dirRef);

        var navRef:StyleRefinement = StyleRefinement.from({ padding: [8, 10] });
        var kids:Array = [];
        kids.push(chip("<", { key: "prev", role: "button", ariaName: "previous page", style: navRef }));

        var slots:int = list.length;
        for (var i:int = 0; i < slots; i++)
        {
            var p:int = int(list[i]);
            if (p < 0)
            {
                // An ellipsis: NOT a button, so the widget's slot counter skips it.
                kids.push(text("...", { key: "gap" + i, style: navRef }));
            }
            else
            {
                kids.push(chip(String(p), { key: "pg" + p, role: "button", ariaName: "page " + p,
                                            tone: (p == cur ? "info" : "neutral"),
                                            style: navRef }));
            }
        }

        kids.push(chip(">", { key: "next", role: "button", ariaName: "next page", style: navRef }));
        OptionSupport.addChildren(n, kids);
        return n;
    }
}
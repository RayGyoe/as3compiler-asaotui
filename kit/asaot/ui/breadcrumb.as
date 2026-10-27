// asaot.ui.breadcrumb -- the author-facing factory for BreadcrumbNode (see
// BreadcrumbNode.as for why the file is lowercase and the class is not).
//
//   breadcrumb(["Library", "Data", "Raw"], { key: "bc", separator: "/",
//                                            onNavigate: onCrumb })
//
// ITEMS ARE PLAIN LABELS. A crumb that needs a key or a URL can carry it in the
// author's own `onNavigate(index)` closure -- the widget's contract is the INDEX,
// so the factory stays a pure "labels in, trail out" function.
//
// The crumb/separator styles are ONE pointer each for the whole pass (the resolver
// skips a style it has already resolved), and they tell the two kinds apart for the
// reader: links are blue, separators are muted, the current crumb is grey.
package asaot.ui
{
    import asaot.ui.style.StyleRefinement;

    public function breadcrumb(items:Array, opts:Object = null):Node
    {
        var n:BreadcrumbNode = new BreadcrumbNode();
        n.items = items == null ? [] : items;
        OptionSupport.applyOpts(n, opts);
        if (n.ariaName == null || n.ariaName == "") n.ariaName = "breadcrumb";
        if (opts != null)
        {
            if (opts.separator != null) n.separator = String(opts.separator);
            if (opts.onNavigate != null) n.onNavigate = (opts.onNavigate as Function);
            if (opts.currentIndex != null) n.currentIndex = Number(opts.currentIndex);
        }

        var count:int = n.items.length;
        var cur:int = n.currentIndex >= 0 ? int(n.currentIndex) : count - 1;

        // A trail is HORIZONTAL: pin the direction as a patch on top of whatever the
        // author set (the resolver's default is a column, which would stack the
        // crumbs). Patching, not replacing, keeps the author's size/padding.
        var dirRef:StyleRefinement = StyleRefinement.from({ flexDirection: "row" });
        // This used to be an if/else: `cond ? null : X` has a null LITERAL in its
        // THEN slot, and that shape collapsed to a constant null on this compiler
        // (compiler-gaps G16) -- the container lost the author's style altogether.
        // G16 is FIXED (compiler stage 266); the tripwire is the EMPTY AOT deviation
        // set of probes/g16-ternary-null, so the ternary is the safe shape again.
        n.style = n.style == null ? dirRef : n.style.withPatch(dirRef);

        var linkRef:StyleRefinement = StyleRefinement.from({ text: { color: Theme.tokens().accent } });
        var curRef:StyleRefinement = StyleRefinement.from({ text: { color: Theme.tokens().textMuted,
                                                                   fontWeight: "bold" } });
        var sepRef:StyleRefinement = StyleRefinement.from({ text: { color: Theme.tokens().neutral },
                                                            padding: [4, 0] });

        var kids:Array = [];
        for (var i:int = 0; i < count; i++)
        {
            var label:String = n.items[i] == null ? "" : String(n.items[i]);
            var s:StyleRefinement = i == cur ? curRef : linkRef;
            // role "link" is both the ARIA shape of a crumb and the marker the widget
            // uses to skip separators when it maps a click to an index.
            kids.push(text(label, { key: "c" + i, role: "link", ariaName: label, style: s }));
            if (i < count - 1)
            {
                kids.push(text(n.separator, { key: "s" + i, role: "separator",
                                              style: sepRef }));
            }
        }

        OptionSupport.addChildren(n, kids);
        return n;
    }
}
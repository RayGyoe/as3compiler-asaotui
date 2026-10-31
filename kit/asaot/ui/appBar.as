// asaot.ui.appBar -- the author-facing factory for AppBarNode (see AppBarNode.as
// for why the file is lowercase and the class is not).
//
//   appBar({ key: "bar", safeArea: "top",
//            leading: iconButton({ key: "back", icon: "M15 6l-6 6 6 6" }),
//            title: "Inbox",
//            trailing: [iconButton(...), iconButton(...)] })
//
//   ... and the large variant, driven by the page's own scroll position:
//
//   appBar({ key: "bar", title: "Inbox", large: true,
//            collapse: model.collapse })       // 0 = open, largeExtra = fully closed
//
// The bar's HEIGHT IS NOT THE AUTHOR'S TO SET: it is `barHeight` (default 56) plus
// the large area, so that the collapse arithmetic is one number in one place. A
// `style.height` would fight it; don't pass one.
//
// `safeArea: "top"` is the top inset (the notch) and it needs no new field: every
// Element already accepts `safeArea`, and the insets are folded into PADDING, so
// the bar's background still covers the notch while its row starts below it.
//
// A SLOT IS `Node` OR `Node[]`. Two actions on the right are the normal case, and
// the obvious spelling is a list; `opts.trailing as Node` alone silently DROPPED
// that list (measured on the gallery's own appBar page, whose example passes
// `trailing: [icon(...)]` -- the hamburger was simply not there). A list is wrapped
// in a row here, in the slot, so the three-slot layout stays three slots.
package asaot.ui
{
    import asaot.ui.style.StyleRefinement;

    public function appBar(opts:Object):Node
    {
        var n:AppBarNode = new AppBarNode();
        OptionSupport.applyOpts(n, opts);

        var rowH:Number = (opts != null && opts.barHeight != null)
            ? Number(opts.barHeight) : n.barHeight;
        var extra:Number = (opts != null && opts.largeExtra != null)
            ? Number(opts.largeExtra) : n.largeExtra;
        var coll:Number = (opts != null && opts.collapse != null)
            ? Number(opts.collapse) : n.collapse;
        if (isNaN(rowH) || rowH <= 0)
        {
            throw new Error("asaot.ui: appBar barHeight must be a positive number (got "
                + rowH + ")");
        }
        if (isNaN(extra) || extra < 0)
        {
            throw new Error("asaot.ui: appBar largeExtra must be >= 0 (got " + extra + ")");
        }
        // `collapse` is a SCROLL POSITION, so it is clamped rather than rejected: a
        // list can overscroll, and a bar that threw an Error mid-gesture would take
        // the frame down. Bounded to the area that actually exists.
        if (isNaN(coll) || coll < 0) coll = 0;
        if (coll > extra) coll = extra;
        n.barHeight = rowH;
        n.largeExtra = extra;
        n.collapse = coll;
        n.large = opts != null && opts.large != null && Boolean(opts.large);

        // ONE slot accepts ONE Node -- so a list is folded here rather than leaking
        // "some slots are rows" into the three-slot model above. A list is wrapped in
        // a row with the bar's own gap, which is what an author would have written.
        var slot = function (v:Object, name:String):Node
        {
            if (v == null) return null;
            if (v is Node) return v as Node;
            var arr:Array = OptionSupport.list(v);
            if (arr == null) return null;
            for (var k:int = 0; k < arr.length; k++)
            {
                if (!(arr[k] is Node))
                {
                    throw new Error("asaot.ui: appBar " + name + "[" + k + "] is not a Node");
                }
            }
            if (arr.length == 0) return null;
            if (arr.length == 1) return arr[0] as Node;
            return row({ style: StyleRefinement.from({ alignItems: "center", gap: 8 }) }, arr);
        };
        if (opts != null)
        {
            n.leading = slot(opts.leading, "leading");
            n.trailing = slot(opts.trailing, "trailing");
            var t:Object = opts.title;
            if (t is Node) n.title = t as Node;
            else if (t != null) n.title = null;   // wrapped below, after the sizes are known
        }

        var t2:ThemeTokens = Theme.tokens();
        // The bar stacks its rows as a COLUMN; `padding` here is the safe-area
        // fold's slot, which is why no row may set a horizontal padding on the node
        // itself. (Padding tuples are [horizontal, vertical] in this kit.)
        var base:StyleRefinement = StyleRefinement.from({
            flexDirection: "column", background: t2.surface
        });
        n.style = n.style == null ? base : base.withPatch(n.style);
        if (n.ariaName == null || n.ariaName == "") n.ariaName = "toolbar";

        // The two title sizes. A String title becomes TWO text nodes (compact and
        // large) because a node cannot be in two places; only one is ever mounted.
        // An explicit Node title is mounted as-is in whichever slot applies.
        var tSmall:Node = null;
        var tBig:Node = null;
        if (opts != null && opts.title != null)
        {
            if (opts.title is Node)
            {
                tSmall = opts.title as Node;
                tBig = tSmall;
            }
            else
            {
                var label:String = String(opts.title);
                tSmall = text(label, { style: StyleRefinement.from({
                    text: { fontSize: 17, fontWeight: "bold", color: t2.textStrong } }) });
                tBig = text(label, { style: StyleRefinement.from({
                    text: { fontSize: 26, fontWeight: "bold", color: t2.textStrong } }) });
            }
            n.title = tSmall;   // the description carries the compact one
        }

        var closed:Boolean = !n.large || coll >= extra;
        var showBig:Boolean = n.large && coll < extra;

        // `row(...)`, NOT `box({ flexDirection: "row" })`: a box's axis is
        // `BoxNode.direction`, which the BoxWidget mirrors while the style's
        // `flexDirection` is ignored for that kind -- the bar would silently stack
        // its slots as a column (measured: lead and trailing both centred, one above
        // the other).
        var bar:Node = row({ style: StyleRefinement.from({
            alignItems: "center", gap: 8,
            height: rowH, padding: [12, 0] }) });
        if (n.leading != null) bar.addChild(n.leading);
        // The centre slot exists even with no title: it is the flexible space that
        // keeps `trailing` on the right edge.
        var mid:Node = row({ style: StyleRefinement.from({
            alignItems: "center", flexGrow: 1,
            justifyContent: n.large ? "flex-start" : "center" }) });
        if (closed && tSmall != null) mid.addChild(tSmall);
        bar.addChild(mid);
        if (n.trailing != null) bar.addChild(n.trailing);
        n.addChild(bar);

        if (showBig && tBig != null)
        {
            // The row SHRINKS with `collapse`; the title keeps its own size and is
            // cut by the bar's clip once it is taller than the row.
            n.addChild(row({ style: StyleRefinement.from({
                alignItems: "flex-start",
                height: extra - coll, padding: [12, 0] }) }, [tBig]));
        }
        return n;
    }
}

// asaot.ui.skeleton -- the author-facing factory for SkeletonNode (see
// SkeletonNode.as for why the file is lowercase and the class is not).
//
//   skeleton({ key: "sk", lines: 3, barHeight: 8, gap: 6 })
//   skeleton({ variant: "circle", size: [40, 40] })
//   skeleton({ variant: "rect", style: { size: [200, 80], cornerRadii: 6 } })
//
// A "text" skeleton leaves its WIDTH auto on purpose: in a column that means the
// engine stretches it to the parent's content width, which is what a paragraph
// placeholder should do. Give an explicit `size` when you need it pinned.
package asaot.ui
{
    public function skeleton(opts:Object = null):Node
    {
        var n:SkeletonNode = new SkeletonNode();
        OptionSupport.applyOpts(n, opts);
        if (n.ariaName == null || n.ariaName == "") n.ariaName = "loading placeholder";
        if (opts != null)
        {
            if (opts.variant != null) n.variant = String(opts.variant);
            if (opts.lines != null) n.lines = int(opts.lines);
            if (opts.barHeight != null) n.barHeight = Number(opts.barHeight);
            if (opts.gap != null) n.gap = Number(opts.gap);
            if (opts.tone != null) n.tone = Number(opts.tone);
        }
        return n;
    }
}

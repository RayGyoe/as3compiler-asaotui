// asaot.ui.splitPane -- the author-facing factory for SplitPaneNode.
//
//   splitPane(leftNode, rightNode, {
//       key: "edit",
//       direction: "row",        // "row" = side by side, "column" = stacked
//       ratio: 0.35,             // share of the FIRST pane
//       minSize: 120,
//       dividerSize: 6,
//       onResize: function (r:Number):void { model.ratio = r; view.invalidate(Dirty.ALL); }
//   })
//
// THE DIVIDER IS AN ORDINARY CHILD NODE, painted as a bar. It is not a special
// display object: a child with drawing content is what makes the grip hit-testable
// (as_pick_hit only hits Sprites that actually drew something -- the same reason
// the tree rows carry an alpha-0 fill), and it means the divider inherits the
// engine's geometry instead of being positioned by hand.
//
// BOTH PANES ARE THE AUTHOR'S NODES, unchanged. The widget overrides their
// MAIN-AXIS size (that is what a splitter is), and leaves the cross axis to the
// container's `alignItems: stretch`. Anything the author set as `flexGrow` on a
// pane is therefore ignored while it is inside a splitPane -- deliberate, and the
// reason this is a kind rather than a recipe.
package asaot.ui
{
    import asaot.ui.style.Length;
    import asaot.ui.style.Size;
    import asaot.ui.style.StyleRefinement;

    public function splitPane(first:Node, second:Node, opts:Object = null):Node
    {
        if (first == null || second == null)
            throw new Error("asaot.ui.splitPane: both panes are required (got "
                + (first == null ? "a null first pane" : "a null second pane")
                + "). A one-pane split is a plain container -- say so explicitly.");

        var n:SplitPaneNode = new SplitPaneNode();
        OptionSupport.applyOpts(n, opts);
        if (opts != null)
        {
            if (opts.direction != null) n.direction = String(opts.direction);
            if (opts.ratio != null) n.ratio = Number(opts.ratio);
            if (opts.minSize != null) n.minSize = Number(opts.minSize);
            if (opts.dividerSize != null) n.dividerSize = Number(opts.dividerSize);
            if (opts.onResize != null) n.onResize = (opts.onResize as Function);
        }

        // Refuse, never reinterpret: "horizontal" reads BOTH ways (a horizontal
        // divider stacks the panes; a horizontal split puts them side by side), so a
        // wrong guess would be invisible until the layout came out rotated.
        if (n.direction != "row" && n.direction != "column")
            throw new Error("asaot.ui.splitPane: `direction` must be \"row\" (panes side by side)"
                + " or \"column\" (panes stacked), got \"" + n.direction + "\".");

        // A ratio outside 0..1 is a model error, not something to clamp: clamping
        // would make a typo look like it worked, and the panes would sit at an edge
        // the author never asked for.
        if (isNaN(n.ratio) || n.ratio < 0 || n.ratio > 1)
            throw new Error("asaot.ui.splitPane: `ratio` is the FIRST pane's share and must be"
                + " within 0..1, got " + n.ratio + ".");
        if (isNaN(n.minSize) || n.minSize < 0)
            throw new Error("asaot.ui.splitPane: `minSize` must be >= 0, got " + n.minSize + ".");
        if (!(n.dividerSize > 0))
            throw new Error("asaot.ui.splitPane: `dividerSize` must be positive, got "
                + n.dividerSize + ".");

        var row:Boolean = n.direction == "row";
        var base:String = n.key == null ? "split" : String(n.key);

        // The container itself: the engine's own direction, no gap (the divider is
        // the gap, and a real gap would make the arithmetic depend on two numbers).
        var self:StyleRefinement = new StyleRefinement();
        self.flexDirection = n.direction;
        n.style = (n.style == null ? new StyleRefinement() : n.style).withPatch(self);
        if (n.ariaName == null || n.ariaName == "") n.ariaName = "split pane";

        // The grip. `size` here only matters on the very first frame, before the
        // widget has read a solved container size; after that the widget writes the
        // main-axis basis itself.
        var dv:Number = n.dividerSize;
        var grip:StyleRefinement = StyleRefinement.from({
            size: row ? [dv, null] : [null, dv],
            background: 0xE5E7EB
        });
        var div:Node = box({ key: base + ":div", style: grip, ariaName: "splitter" });

        n.addChild(first);
        n.addChild(div);
        n.addChild(second);
        return n;
    }
}
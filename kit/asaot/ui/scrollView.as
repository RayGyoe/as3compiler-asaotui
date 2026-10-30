// asaot.ui.scrollView -- the author-facing factory for ScrollViewNode (see
// ScrollViewNode.as for why the file is lowercase, the class is not, and what the
// offset request means).
//
//   scrollView({ key: "sv", size: [280, 60], offset: [0, 0] }, [
//       box({ style: { height: 40, background: 0xEE1111 } }),
//       box({ style: { height: 40, background: 0x11EE11 } })
//   ])
//
// Scrollbars are on by default (`scrollbarX`/`scrollbarY`: "auto"). They are drawn
// over the viewport, so they do not change any rect this node is laid out in.
//
// A finger can scroll it (MOBILE.md S1) and coasts after the lift unless
// `momentum: false`; `decelerationRate` (default 0.95, a fraction in (0,1)) sets how
// quickly the coast dies. Both are read at glide time, so a render() that changes
// them mid-flight is honoured.
//
// Give it an explicit size: a viewport has no meaningful intrinsic size, so an
// auto axis falls back to 200x150 (ScrollViewWidget.DEFAULT_W/H) rather than
// collapsing to zero.
package asaot.ui
{
    public function scrollView(opts:Object = null, children:Array = null):Node
    {
        var n:ScrollViewNode = new ScrollViewNode();
        OptionSupport.applyOpts(n, opts);
        if (n.ariaName == null || n.ariaName == "") n.ariaName = "scrollable region";
        if (opts != null)
        {
            if (opts.offset != null)
            {
                var o:Array = opts.offset as Array;
                if (o != null && o.length >= 2)
                {
                    n.offsetX = Number(o[0]);
                    n.offsetY = Number(o[1]);
                }
            }
            if (opts.offsetX != null) n.offsetX = Number(opts.offsetX);
            if (opts.offsetY != null) n.offsetY = Number(opts.offsetY);
            if (opts.wheelStep != null) n.wheelStep = Number(opts.wheelStep);
            if (opts.stickToBottom != null) n.stickToBottom = Boolean(opts.stickToBottom);
            if (opts.momentum != null) n.momentum = Boolean(opts.momentum);
            if (opts.decelerationRate != null)
                n.decelerationRate = ScrollViewNode.decelRate(opts.decelerationRate, "decelerationRate");
            if (opts.onScroll != null) n.onScroll = opts.onScroll;
            // The bar modes are validated HERE, at factory time: an unknown string
            // that silently became "auto" is exactly the fallback AGENTS.md 2.5
            // forbids, and the call site is the only place that can name the
            // offending option.
            if (opts.scrollbarX != null) n.scrollbarX = ScrollViewNode.barMode(opts.scrollbarX, "scrollbarX");
            if (opts.scrollbarY != null) n.scrollbarY = ScrollViewNode.barMode(opts.scrollbarY, "scrollbarY");
            if (opts.barThickness != null) n.barThickness = Number(opts.barThickness);
            if (opts.barColor != null) n.barColor = uint(opts.barColor);
            if (opts.barHoverColor != null) n.barHoverColor = uint(opts.barHoverColor);
            if (opts.trackColor != null) n.trackColor = uint(opts.trackColor);
        }
        OptionSupport.addChildren(n, children);
        return n;
    }
}

// asaot.ui.scrollView -- the author-facing factory for ScrollViewNode (see
// ScrollViewNode.as for why the file is lowercase, the class is not, and what the
// offset request means).
//
//   scrollView({ key: "sv", size: [280, 60], offset: [0, 0] }, [
//       box({ style: { height: 40, background: 0xEE1111 } }),
//       box({ style: { height: 40, background: 0x11EE11 } })
//   ])
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
            if (opts.onScroll != null) n.onScroll = opts.onScroll;
        }
        OptionSupport.addChildren(n, children);
        return n;
    }
}

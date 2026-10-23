// asaot.ui.popover -- the author-facing factory for PopoverNode.
//
//   popover({ key, open, anchorKey, placement, offset, width, closeOnOutside,
//             onClose, style }, [ content nodes... ])
//
// The node is the PANEL (see PopoverNode's header). Its children are ordinary flow
// children, so the panel's height comes from its content and the author never
// computes a size.
//
// `anchorKey` is a plain key string, resolved through `UiApp.findByKey` at measure
// time -- i.e. the anchor is looked up in the LIVE tree, not captured as a node
// reference. That is what makes the popover survive a reconcile: the retained tree
// keeps its pointers across frames, but a fresh descriptor tree is built every
// frame, so capturing a Node would point at a description that is about to be
// thrown away.
package asaot.ui
{
    import asaot.ui.style.Length;
    import asaot.ui.style.Size;
    import asaot.ui.style.StyleRefinement;

    public function popover(opts:Object = null, children:Array = null):Node
    {
        var n:PopoverNode = new PopoverNode();
        OptionSupport.applyOpts(n, opts);
        if (opts != null)
        {
            if (opts.open != null) n.open = Boolean(opts.open);
            if (opts.anchorKey != null) n.anchorKey = String(opts.anchorKey);
            if (opts.placement != null) n.placement = String(opts.placement);
            if (opts.offset != null) n.offset = Number(opts.offset);
            if (opts.width != null) n.width = Number(opts.width);
            if (opts.closeOnOutside != null) n.closeOnOutside = Boolean(opts.closeOnOutside);
            if (opts.onClose != null) n.onClose = (opts.onClose as Function);
        }
        n.visible = n.open;

        var w:StyleRefinement = new StyleRefinement();
        w.size = Size.of(Length.px(n.width), null);
        w.position = "absolute";
        n.style = (n.style == null ? new StyleRefinement() : n.style)
            .withPatch(OverlayChrome.POPOVER_PANEL.withPatch(w));
        if (n.ariaName == null) n.ariaName = "popover";

        if (children != null)
        {
            for (var i:int = 0; i < children.length; i++) n.addChild(Node(children[i]));
        }
        return n;
    }
}
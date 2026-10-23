// asaot.ui.drawer -- the author-facing factory for DrawerNode.
//
//   drawer({ key, open, side, size, title, scrim, closeOnScrim, onClose, style },
//          [ body nodes... ])
//
// `side` picks the layer style (see DrawerNode's header) and the axis the `size`
// number applies to; a bad value THROWS rather than silently falling back to
// "left", because a sheet that appears on the wrong edge is a bug nobody reads in
// a log (compiler-gaps.md discipline: no silent fallback).
//
// The panel is ALWAYS THE LAST CHILD, same contract as dialog() -- the widget's
// outside-click test reads it from the end.
package asaot.ui
{
    import asaot.ui.style.Length;
    import asaot.ui.style.Size;
    import asaot.ui.style.StyleRefinement;

    public function drawer(opts:Object = null, children:Array = null):Node
    {
        var n:DrawerNode = new DrawerNode();
        OptionSupport.applyOpts(n, opts);
        if (opts != null)
        {
            if (opts.open != null) n.open = Boolean(opts.open);
            if (opts.side != null) n.side = String(opts.side);
            if (opts.size != null) n.size = Number(opts.size);
            if (opts.title != null) n.title = String(opts.title);
            if (opts.scrim != null) n.scrim = Boolean(opts.scrim);
            if (opts.closeOnScrim != null) n.closeOnScrim = Boolean(opts.closeOnScrim);
            if (opts.onClose != null) n.onClose = (opts.onClose as Function);
        }
        n.visible = n.open;

        var layer:StyleRefinement = OverlayChrome.LAYER_ROW_START;
        var horizontal:Boolean = true;
        if (n.side == "left") { layer = OverlayChrome.LAYER_ROW_START; horizontal = true; }
        else if (n.side == "right") { layer = OverlayChrome.LAYER_ROW_END; horizontal = true; }
        else if (n.side == "top") { layer = OverlayChrome.LAYER_COL_START; horizontal = false; }
        else if (n.side == "bottom") { layer = OverlayChrome.LAYER_COL_END; horizontal = false; }
        else throw new Error("asaot.ui.drawer: unknown side '" + n.side
            + "' (accepted: left | right | top | bottom)");

        n.style = (n.style == null ? new StyleRefinement() : n.style).withPatch(layer);
        // THE LAYER IS THE WINDOW, and `size` is BOTH this control's option and a
        // style shorthand -- `OptionSupport.applyOpts` therefore turned
        // `drawer({size: 100})` into `size: [100,100]` on the layer, which beat the
        // `inset` and made the layer 100x100 instead of window-sized (measured:
        // the bottom sheet collapsed to a 100x100 box in the top-left corner).
        // The sheet's own dimension is applied to `dim` below.
        n.style.size = null;
        if (n.ariaName == null) n.ariaName = n.title != null ? n.title : "drawer";

        var base:String = n.key == null ? "drawer" : String(n.key);

        if (n.scrim)
        {
            n.addChild(box({ key: base + ":scrim", style: OverlayChrome.SCRIM_BOX, ariaName: "" }));
        }

        // Only the MAIN dimension is set; the cross axis stays AUTO so that the
        // layer's `align-items: stretch` fills it (a fixed height on a left sheet
        // would leave a gap under the panel).
        var dim:StyleRefinement = new StyleRefinement();
        dim.size = horizontal ? Size.of(Length.px(n.size), null) : Size.of(null, Length.px(n.size));
        var panel:Node = box({ key: base + ":panel",
                              style: OverlayChrome.DRAWER_PANEL.withPatch(dim), ariaName: "" });

        if (n.title != null)
        {
            panel.addChild(text(n.title, { key: base + ":title", style: OverlayChrome.TITLE }));
        }
        if (children != null)
        {
            for (var i:int = 0; i < children.length; i++) panel.addChild(Node(children[i]));
        }

        n.addChild(panel);
        return n;
    }
}
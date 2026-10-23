// asaot.ui.dialog -- the author-facing factory for DialogNode.
//
//   dialog({ key, open, title, width, scrim, closeOnScrim, onClose, style },
//          [ body nodes... ])
//
// `open` is AUTHOR-OWNED (see DialogNode's header). `onClose` is called when the
// scrim is clicked with `closeOnScrim: true`; it is the author's job to set
// `open = false` and invalidate. Nothing here mutates state behind the author's
// back, which is what keeps `render()` a pure function of the model.
//
// The panel is ALWAYS THE LAST CHILD (DialogWidget depends on it -- see the node's
// header for why an index constant would break with `scrim: false`).
package asaot.ui
{
    import asaot.ui.style.Length;
    import asaot.ui.style.Size;
    import asaot.ui.style.StyleRefinement;

    public function dialog(opts:Object = null, children:Array = null):Node
    {
        var n:DialogNode = new DialogNode();
        OptionSupport.applyOpts(n, opts);
        var footer:Array = null;
        if (opts != null)
        {
            if (opts.open != null) n.open = Boolean(opts.open);
            if (opts.title != null) n.title = String(opts.title);
            if (opts.width != null) n.width = Number(opts.width);
            if (opts.scrim != null) n.scrim = Boolean(opts.scrim);
            if (opts.closeOnScrim != null) n.closeOnScrim = Boolean(opts.closeOnScrim);
            if (opts.onClose != null) n.onClose = (opts.onClose as Function);
            if (opts.footer != null) footer = OptionSupport.list(opts.footer);
        }
        // Closed is `visible: false`, not "absent": the node keeps its place in
        // the tree (so hover/scroll state survives), draws nothing, and -- the
        // part that matters -- is not hit-testable, because this engine's pick
        // walk returns early for an invisible object (src/emit.ts
        // as_pick_hit_m: `if (!o->visible) return NULL`). A closed dialog
        // therefore cannot eat the clicks of the page behind it.
        n.visible = n.open;
        n.style = (n.style == null ? new StyleRefinement() : n.style).withPatch(OverlayChrome.LAYER_CENTER);
        // THE LAYER IS THE WINDOW, so an explicit size on it is always wrong.
        // `OptionSupport.applyOpts` reads the shorthand style keys out of `opts`,
        // and this control's own option is ALSO called `width` -- so
        // `dialog({width: 300})` had silently turned into `size.width = 300` on the
        // layer, and an explicit size BEATS `inset` in a flex solve: the layer
        // shrank to 300 and the centring collapsed (measured: layer 300x460, panel
        // at x=0). The panel below gets its width from `n.width` instead.
        n.style.size = null;
        if (n.ariaName == null) n.ariaName = n.title != null ? n.title : "dialog";

        var base:String = n.key == null ? "dialog" : String(n.key);

        if (n.scrim)
        {
            n.addChild(box({ key: base + ":scrim", style: OverlayChrome.SCRIM_BOX, ariaName: "" }));
        }

        // The panel's width is a px Length and its height stays AUTO (null), so
        // the box grows with its content. Feeding `[w]` to Size instead would make
        // it a square (Size.fromArray's 1-element form).
        var w:StyleRefinement = new StyleRefinement();
        w.size = Size.of(Length.px(n.width), null);
        var panel:Node = box({ key: base + ":panel", style: OverlayChrome.DIALOG_PANEL.withPatch(w),
                              ariaName: "" });

        if (n.title != null)
        {
            panel.addChild(text(n.title, { key: base + ":title", style: OverlayChrome.TITLE }));
        }
        if (children != null)
        {
            for (var i:int = 0; i < children.length; i++) panel.addChild(Node(children[i]));
        }
        if (footer != null && footer.length > 0)
        {
            var frow:Node = row({ key: base + ":footer", style: OverlayChrome.FOOTER_ROW, ariaName: "" });
            for (var j:int = 0; j < footer.length; j++) frow.addChild(Node(footer[j]));
            panel.addChild(frow);
        }

        n.addChild(panel);
        return n;
    }
}
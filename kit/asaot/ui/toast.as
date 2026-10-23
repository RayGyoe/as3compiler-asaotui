// asaot.ui.toast -- the author-facing factory for ToastNode.
//
//   toast({ key, open, message, tone, duration, onClose, width, style })
//
// The tone picks a STATIC box style (default / success / danger) rather than being
// painted from a variable, so a tone change is an ordinary style diff.
//
// A toast never takes the pointer: it has no click behaviour and no `wantsPress`,
// and its bounding box is small and in a corner, so it does not block the page.
package asaot.ui
{
    import asaot.ui.style.Length;
    import asaot.ui.style.Size;
    import asaot.ui.style.StyleRefinement;

    public function toast(opts:Object = null):Node
    {
        var n:ToastNode = new ToastNode();
        OptionSupport.applyOpts(n, opts);
        var width:Number = 220;
        if (opts != null)
        {
            if (opts.open != null) n.open = Boolean(opts.open);
            if (opts.message != null) n.message = String(opts.message);
            if (opts.tone != null) n.tone = String(opts.tone);
            if (opts.duration != null) n.duration = Number(opts.duration);
            if (opts.onClose != null) n.onClose = (opts.onClose as Function);
            if (opts.width != null) width = Number(opts.width);
        }
        n.visible = n.open;

        var boxStyle:StyleRefinement = OverlayChrome.TOAST_BOX;
        if (n.tone == "success") boxStyle = OverlayChrome.TOAST_BOX_OK;
        else if (n.tone == "danger") boxStyle = OverlayChrome.TOAST_BOX_ERR;
        else if (n.tone != "default")
            throw new Error("asaot.ui.toast: unknown tone '" + n.tone
                + "' (accepted: default | success | danger)");

        // [w] sets BOTH axes (Size.fromArray's 1-element form is a square), so the
        // height stays AUTO explicitly.
        var w:StyleRefinement = new StyleRefinement();
        w.size = Size.of(Length.px(width), null);
        n.style = (n.style == null ? new StyleRefinement() : n.style).withPatch(boxStyle.withPatch(w));
        if (n.ariaName == null) n.ariaName = n.message;

        n.addChild(text(n.message, { key: (n.key == null ? "toast" : String(n.key)) + ":t",
                                   style: OverlayChrome.TOAST_TEXT, ariaName: "" }));
        return n;
    }
}
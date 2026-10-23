// asaot.ui.toastHost -- the bottom-right stack toasts drop into.
//
// It is a PLAIN BOX, not a new kind: the entire behaviour is the `TOAST_LAYER`
// style (absolute, inset 0, column, justify flex-end, align flex-end, 16px padding,
// 8px gap). Toasts are then ordinary flow children of it, so the stack grows in the
// right direction with no per-toast positioning -- and closing one re-flows the
// rest for free, which is the part a hand-positioned stack always gets wrong.
//
// IT HAS NO BACKGROUND, SO IT CANNOT EAT CLICKS. This engine's pick test needs real
// path geometry (src/emit.ts as_shape_region_hit), and a transparent stack draws
// nothing, so every click passes straight through to the page behind.
package asaot.ui
{
    import asaot.ui.style.StyleRefinement;

    public function toastHost(opts:Object = null, children:Array = null):Node
    {
        var n:BoxNode = new BoxNode();
        OptionSupport.applyOpts(n, opts);
        n.style = (n.style == null ? new StyleRefinement() : n.style)
            .withPatch(OverlayChrome.TOAST_LAYER);
        if (n.ariaName == null) n.ariaName = "notifications";
        OptionSupport.addChildren(n, children);
        return n;
    }
}
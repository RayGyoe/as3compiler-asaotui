// asaot.ui.overlay -- the ROOT of the floating layer (see View.renderOverlay).
//
// A plain box that fills the WINDOW, used as the top-level node of the second
// retained tree. It has no background, so it is not hit-testable itself: only its
// children are. Everything the author wants to float is a child of it, and each
// such child takes itself out of flow with `position: "absolute"`.
//
// SHAPE AND ORDER
//   overlay([ dialog(...), toastStack([...]) ])
// Children are stacked in DISPLAY ORDER: the last one is painted last and wins a
// hit test where they overlap. There is no z-index in this engine (Style has no
// such field, deliberately), so the list order IS the stacking order -- the same
// rule as plain CSS without z-index.
//
// WHY size 100% AND NOT position:absolute: this node is a ROOT, so it has no
// parent to be absolute against; it is the coordinate space the absolute children
// resolve their insets against. Percent rather than px because it must follow a
// window resize, and the engine resolves percentages against the availW/availH
// handed to `calculate()`.
package asaot.ui
{
    import asaot.ui.style.StyleRefinement;

    public function overlay(children:Array = null, opts:Object = null):Node
    {
        var n:BoxNode = new BoxNode();
        OptionSupport.applyOpts(n, opts);
        // The host is forced, never authored: a window-sized, flow-transparent
        // space. Authoring `size` here would silently break window resizing.
        n.style = (n.style == null ? new StyleRefinement() : n.style).withPatch(OverlayChrome.HOST);
        n.direction = "column";
        if (n.key == null) n.key = "overlay";
        if (n.ariaName == null) n.ariaName = "overlay";
        OptionSupport.addChildren(n, children);
        return n;
    }
}
// asaot.ui.ScrollViewNode -- a CLIPPED, SCROLLABLE viewport.
//
// Copy of the ChipNode recipe: class `ScrollViewNode`, lowercase factory
// `scrollView.as` (compiler-gaps.md G7), `role` mandatory, self-registration once.
//
// It is a CONTAINER (role "group", like box/card): its children are ordinary
// UiNodes the layout engine positions inside it, and the viewport clips them.
//
// TWO DIFFERENT THINGS ARE CALLED "THE OFFSET" HERE, and keeping them apart is the
// whole design:
//
//   * `offsetY` (this class, author-owned) is the POSITION REQUEST -- the initial
//     scroll and the value the author sets to scroll programmatically;
//   * the LIVE position belongs to the node (it must survive a re-render that
//     rebuilds the description from an unchanged model).
//
// The rule the widget implements: if the description's offset CHANGES between
// frames it moves the view; if it is unchanged the view keeps where the user
// scrolled it. So both authoring styles work --
//
//   A) rebuild the description every render(): keep the offset in your model and
//      update it from `onScroll`, or the next render simply re-passes the old value
//      (which is unchanged, so it does not fight the wheel);
//   B) build the description once and mutate it: the wheel handler writes back into
//      `offsetY` itself, so this class is always the author's live handle.
//
// `contentW/H` and `maxOffsetX/Y` are OUTPUTS, written during paint from the
// engine's solved child rects.
package asaot.ui
{
    import asaot.ui.kind.ScrollViewWidget;

    public class ScrollViewNode extends Element
    {
        public var offsetX:Number;      // request (see the header)
        public var offsetY:Number;
        public var wheelStep:Number;    // px per wheel delta unit
        public var contentW:Number;     // out: the content's extent
        public var contentH:Number;
        public var maxOffsetX:Number;   // out: content - viewport, floored at 0
        public var maxOffsetY:Number;
        public var onScroll:Function;   // (offsetX:Number, offsetY:Number)

        private static var registered:Boolean = false;

        public function ScrollViewNode():void
        {
            super("scrollView");
            if (!registered) { registered = true; Widgets.register("scrollView", new ScrollViewWidget()); }
            this.role = "group";
            this.offsetX = 0;
            this.offsetY = 0;
            this.wheelStep = 24;
            this.contentW = 0;
            this.contentH = 0;
            this.maxOffsetX = 0;
            this.maxOffsetY = 0;
            this.onScroll = null;
        }
    }
}

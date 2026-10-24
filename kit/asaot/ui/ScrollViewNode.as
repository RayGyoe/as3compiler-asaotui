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
//
// SCROLLBARS. `scrollbarX`/`scrollbarY` are "auto" (the default: the bar is
// there when the content overflows on that axis), "always" (the author asked for
// the bar even when there is nothing to scroll) or "never". The bars are OVERLAY
// chrome, not layout: showing one does not narrow the content, because a viewport
// whose content width depends on whether a bar is showing is the scrollbar-gutter
// feedback loop. The geometry is the widget's; `barThickness` and the three
// colours are yours.
//
// The wheel scrolls the vertical axis when it can and falls back to the
// horizontal one otherwise (a film strip should still respond to a wheel). A
// shift-wheel is NOT available: the runtime's wheel event carries no modifier
// (see Stage_dispatchWheel in the compiler).
//
// STICK TO BOTTOM (`stickToBottom`) is for logs, chats and consoles: the view keeps
// following the END of the content while it grows, and stops following the moment the
// reader scrolls away from the bottom. The whole rule is one comparison per frame
// against the PREVIOUS frame's `maxOffsetY` (see ScrollViewWidget.paint) -- "was I at
// the end?" cannot be answered after `maxOffsetY` has already grown, because then
// every position looks "not at the end" and the view would never follow.
//
//   * a fresh view (nothing scrolled yet) counts as at-the-end, so a log opens on its
//     newest line rather than at the top;
//   * one pixel off the end is enough to detach: `maxOffsetY - 1` is a reader who
//     scrolled up, not a rounding error, and 0.5px of slack absorbs the fractional
//     offsets the bar drag produces;
//   * scrolling back DOWN to the end re-attaches it, because the test is re-evaluated
//     from the live offset every frame -- there is no separate "stuck" flag to reset;
//   * the auto-scroll is a REAL move: `onScroll` fires and `offsetY` is written back,
//     so an author's model never disagrees with what is on screen.
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
        public var stickToBottom:Boolean;   // follow content growth while at the end
        public var onScroll:Function;   // (offsetX:Number, offsetY:Number)

        public var scrollbarX:String;   // "auto" | "always" | "never"
        public var scrollbarY:String;
        public var barThickness:Number; // px, the overlay bar's width
        public var barColor:uint;       // thumb, resting
        public var barHoverColor:uint;  // thumb, hovered or dragged
        public var trackColor:uint;     // the groove behind the thumb

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
            this.stickToBottom = false;
            this.onScroll = null;
            this.scrollbarX = "auto";
            this.scrollbarY = "auto";
            this.barThickness = 10;
            this.barColor = 0xB9C2D0;
            this.barHoverColor = 0x8A97AB;
            this.trackColor = 0xE8EDF5;
        }

        // "auto" | "always" | "never", anything else THROWS. A static on the NODE
        // class rather than a second top-level function in scrollView.as: the
        // toolkit's convention is one public top-level definition per file
        // (compiler-gaps G7 -- AIR enforces it, we do not), and this keeps the
        // factory and the payloadable value in one vocabulary.
        public static function barMode(v:Object, opt:String):String
        {
            var s:String = String(v);
            if (s == "auto" || s == "always" || s == "never") return s;
            throw new Error("asaot.ui.scrollView: " + opt + " must be \"auto\", \"always\""
                + " or \"never\", got '" + s + "'");
        }
    }
}

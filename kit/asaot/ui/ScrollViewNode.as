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
//   * the LIVE position belongs to the node: a re-render does not move the viewport
//     unless the description asks it to, and moving never re-runs layout.
//
// The rule the widget implements: the description's offset is compared against the
// LIVE position; a difference is a request to move. So both authoring styles work --
//
//   A) rebuild the description every render(): keep the offset in your model and
//      MIRROR it from `onScroll`. Mirroring is not optional in this style: a
//      description that still carries the value from before the user scrolled says
//      "go back there", so a re-render for any other reason would snap the viewport
//      back (the widget cannot tell a stale copy from a deliberate "back to top");
//   B) build the description once and mutate it: the wheel and drag handlers write
//      back into `offsetY` itself, so this class is always the author's live handle.
//
// A request is the only way to scroll programmatically, which means the same value
// cannot be requested twice in a row while it is already the live position: the
// usual "back to top" button works because it differs from where the user is.
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
// TOUCH (MOBILE.md S1/S2). A finger inside the viewport scrolls it 1:1 and, unless
// `momentum` is false, keeps going after it lifts:
//
//   * `momentum` (default `true`) is the author's "no coasting" switch -- a form
//     whose list must stop the instant the finger lifts sets it false;
//   * `decelerationRate` (default 0.95) is the share of the velocity that survives
//     ONE 60Hz frame; the widget corrects it for the real frame time, so the curve is
//     the same at 30/60/120 Hz. Smaller = stops sooner. It is validated at factory
//     time like the bar modes: a rate of 1.5 ("it accelerates") or 0 ("it stops dead
//     every frame") is a typo, not a style.
//
// Momentum is deliberately NOT here as a per-frame tick: the widget runs it inside
// `paint` and asks for its own next frame (markPaint), so coasting never re-solves
// layout. That is also why `decelerationRate` is read at glide time from the
// description: a theme or a model that changes it mid-glide is honoured.
//
// OVERSCROLL (MOBILE.md S3). `overscroll` is "rubber" (the default: a finger that
// drags past an end stretches the content against a damped resistance and it springs
// back when released) or "none" (the drag simply stops at the end). THE STRETCH IS
// NOT THE OFFSET: `offsetX`/`offsetY` stay clamped to the range at all times, so an
// author's model never sees a negative offset and `offsetY == maxOffsetY` still means
// "at the end". The stretch is published separately as `overscrollX`/`overscrollY`
// (outputs, signed px, 0 when at rest) -- that is what the clip is drawn at, and what
// a probe can assert.
//
// Only a FINGER can overscroll: a wheel notch and a scrollbar drag both clamp (they
// are discrete moves, and a desktop user expects the wall to be a wall). So
// `overscroll` is opt-out for the mobile case, not a desktop behaviour change.
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

        public var momentum:Boolean;        // touch fling keeps going after the lift
        public var decelerationRate:Number; // velocity multiplier per 60Hz frame, (0,1)

        public var overscroll:String;   // "rubber" | "none"
        public var overscrollX:Number;  // out: current stretch, signed px (0 at rest)
        public var overscrollY:Number;  // out

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
            this.momentum = true;
            this.decelerationRate = 0.95;
            this.overscroll = "rubber";
            this.overscrollX = 0;
            this.overscrollY = 0;
            this.scrollbarX = "auto";
            this.scrollbarY = "auto";
            this.barThickness = 10;
            // From the palette, read here rather than stored as a const: the node is
            // rebuilt by the factory on every render pass, so the ctor is the one
            // place where "the default" is evaluated against the CURRENT theme. An
            // author who assigns `barColor` (opts or by hand) still wins.
            var pal:ThemeTokens = Theme.tokens();
            this.barColor = pal.scrollBar;
            this.barHoverColor = pal.scrollBarHover;
            this.trackColor = pal.scrollTrack;
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

        // "rubber" | "none", anything else THROWS. Same reasoning as barMode: a typo
        // (`overscroll: true`) must not silently mean "whatever the default was".
        public static function overMode(v:Object, opt:String):String
        {
            var s:String = String(v);
            if (s == "rubber" || s == "none") return s;
            throw new Error("asaot.ui.scrollView: " + opt + " must be \"rubber\" or"
                + " \"none\", got '" + v + "'");
        }

        // The share of the velocity surviving one 60Hz frame, anything outside (0,1)
        // THROWS. Same reasoning as barMode: an out-of-range rate is a typo
        // (`decelerationRate: 0.95` written as `95`), and a silent fallback would
        // make a list that stops dead look like "momentum is broken".
        public static function decelRate(v:Object, opt:String):Number
        {
            var n:Number = Number(v);
            if (isNaN(n) || n <= 0 || n >= 1)
            {
                throw new Error("asaot.ui.scrollView: " + opt
                    + " must be a fraction in (0,1) -- the share of velocity that"
                    + " survives one 60Hz frame, got '" + v + "'");
            }
            return n;
        }
    }
}

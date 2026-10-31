// asaot.ui.NavStackNode -- a phone-style navigation stack: N pages, one on top.
//
// Same recipe as ChipNode (the reference trio): class `NavStackNode`, lowercase
// factory `navStack.as` (compiler-gaps G7), `role` mandatory, self-registration
// once from the ctor.
//
// THE MODEL IS THE AUTHOR'S ARRAY. `pages` is the WHOLE stack, back-most first, and
// `activeIndex` names the page on top (-1 or an out-of-range index means "the last
// page", i.e. the top of the stack). Pushing is appending to that array; popping is
// removing from it. The widget never mutates `pages` -- there is no `push()` method
// and no hidden history, because a second copy of the stack would eventually
// disagree with the author's (the same rule every other kind in this kit follows:
// the description is the state, a callback is the intent).
//
// INTENT: `onBack()` is raised when the platform's BACK key arrives (Keyboard.BACK,
// code 0x01000016). What back MEANS is the author's call -- usually `pages.pop()`
// with `activeIndex` following -- so a one-page stack still gets a callback and the
// author can decide to leave the screen entirely.
//
// EVERY PAGE STAYS MOUNTED, and that is what "page state is kept" means here: the
// pages are absolute inset-0 wrappers, only the active one is `visible`, and a
// hidden node neither paints nor picks (UiApp.pickAt rejects an invisible node).
// So a scrollView keeps its offset and an input keeps its text while another page
// is on top -- the reason pages are mounted rather than rebuilt on demand.
// The cost is honest: hidden pages still measure and arrange every pass. That is
// fine for the handful of pages a phone screen has; it is not a router for a
// hundred.
//
// STILL DOES NOT DO (deliberate, each one a separate decision):
//   * NO slide transition. The page swap is instant. A slide needs two pages drawn
//     at once with an animated x offset, i.e. the OverlayMotion machinery, not the
//     layout engine; it is not part of the "does the stack work" contract (MOBILE.md
//     M3 asserts push/pop/back/state, not animation).
//   * NO edge-swipe back. The system back key is the only back intent expressed
//     here; a left-edge drag would need the pointer router to claim a gesture that
//     starts inside a page's own scroll view (S5, not built yet).
//   * NO header. A page's app bar is `appBar()`, composed by the author INSIDE the
//     page, so a page can choose not to have one (a splash or a full-bleed map).
package asaot.ui
{
    import asaot.ui.kind.NavStackWidget;

    public class NavStackNode extends Element
    {
        // Array of { key:String, page:Node } -- see navStack.as (the factory wraps).
        public var pages:Array;
        public var activeIndex:int;   // -1 or out of range = the top page
        public var onBack:Function;   // function():void -- the platform back key

        private static var registered:Boolean = false;

        public function NavStackNode():void
        {
            super("navStack");
            if (!registered) { registered = true; Widgets.register("navStack", new NavStackWidget()); }
            this.role = "group";
            this.pages = null;
            this.activeIndex = -1;
            this.onBack = null;
        }

        // The ONE place "which page is on top" is decided. The factory (which mounts
        // and toggles `visible`) and the widget (which reports the depth) must agree,
        // so the rule is a static function rather than a copy of the clamp in both.
        // Out-of-range is NOT an error: `activeIndex` is author data that outlives a
        // page being popped, and a stale index must not blank the whole stack.
        public static function topIndex(count:int, want:int):int
        {
            if (count <= 0) return -1;
            if (want < 0 || want >= count) return count - 1;
            return want;
        }
    }
}

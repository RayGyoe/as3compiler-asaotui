// asaot.ui.Dirty -- the notification GRANULARITY, not an event kind.
//
// WHY NOT EventDispatcher (design doc section 5.1)
// ------------------------------------------------
// `notify()` is "tell the scheduler I changed", the same idea as GPUI's
// `Context::notify` (asaotui/gpui-src/crates/gpui/src/app/context.rs:221). It is
// NOT a display-list broadcast: routing it through `addEventListener` would run
// AS3's capture/target/bubble phases for a business object that is not on the
// display list, and would allocate an `Event` per notify -- a per-frame
// allocation, which section 7 forbids. So `Observable` carries its own small
// synchronous subscription list and these four bits.
package asaot.ui
{
    public final class Dirty
    {
        public static const VALUE:int = 1;       // a data value changed
        public static const DECOR:int = 2;       // decoration only
        public static const STRUCTURE:int = 4;   // children/keys changed
        public static const THEME:int = 8;       // re-resolve the whole tree
        public static const ALL:int = 15;

        // Per-UiNode pass bits (design doc section 3.3). Kept here so the
        // dirty-propagation table has one vocabulary in one file.
        public static const M_MEASURE:int = 16;
        public static const M_ARRANGE:int = 32;
        public static const M_PAINT:int = 64;

        public function Dirty() { }
    }
}

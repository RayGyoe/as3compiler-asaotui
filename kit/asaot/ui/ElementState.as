// asaot.ui.ElementState -- the TRANSIENT per-node state (design doc section 3.2).
//
// Borrowed from GPUI's `Element::PrepaintState` (asaotui/gpui-src/crates/gpui/
// src/element.rs:17: "some state is too simple and voluminous to store in every
// view that needs it, e.g. whether a hover has been started"). It lives INLINE
// in the retained UiNode, so hover / scroll / measurement survive a reconcile by
// the node pointer alone -- no external map, no hashing, no cross-frame lookup.
//
// Every field is an int or Number: no string, no array, no object. That is what
// keeps it off the GC heap and makes a state flip allocation-free.
package asaot.ui
{
    public class ElementState
    {
        public var hover:int;
        public var pressed:int;
        public var focused:int;
        public var disabled:int;

        public var scrollX:Number;
        public var scrollY:Number;

        public var measuredW:Number;      // intrinsic size cache (measure pass)
        public var measuredH:Number;
        public var measureValid:int;      // bit 1 = W valid, bit 2 = H valid

        public var arrangedX:Number;      // last final rect (hit test reuse)
        public var arrangedY:Number;
        public var arrangedW:Number;
        public var arrangedH:Number;
        public var hitValid:int;

        public function ElementState():void
        {
            this.hover = 0;
            this.pressed = 0;
            this.focused = 0;
            this.disabled = 0;
            this.scrollX = 0;
            this.scrollY = 0;
            this.measuredW = 0;
            this.measuredH = 0;
            this.measureValid = 0;
            this.arrangedX = 0;
            this.arrangedY = 0;
            this.arrangedW = 0;
            this.arrangedH = 0;
            this.hitValid = 0;
        }
    }
}
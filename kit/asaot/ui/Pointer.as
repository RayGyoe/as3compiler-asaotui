// asaot.ui.Pointer -- ONE pointer's state, normalized across touch, pen and mouse
// (MOBILE.md 6.2 / P1).
//
// The instance is MUTABLE ON PURPOSE: a touch move is the hottest input path the library
// has (AGENTS.md 2.4's GC red line, MOBILE.md P7). PointerRouter keeps one Pointer per
// touch id and updates x/y/phase in place, so the ROUTER's own bookkeeping allocates
// nothing as the finger moves. What still allocates is the compatibility layer: it
// constructs one MouseEvent per phase it dispatches, which is the same order as the
// engine's own real event and is not something this class can avoid.
//
// Reading a field is the whole public API -- a copy would hand out a second answer to
// "where is the pointer", which is how two subsystems start disagreeing.
package asaot.ui
{
    public class Pointer
    {
        public var id:int;

        // ROOT coordinates (stage space), the only space a router can compare across
        // nodes without asking the display list for a transform.
        public var x:Number;
        public var y:Number;

        // "down" | "move" | "up" | "cancel"
        public var phase:String;

        public var isPrimary:Boolean;

        // Devices that cannot report pressure report 0.5 (a finger resting on glass),
        // never 0 -- 0 is indistinguishable from "this pointer does not exist".
        public var pressure:Number;

        // The press anchor. Not in MOBILE.md's listed shape, but "did this series leave
        // the slop?" cannot be answered from the current x/y alone, and recomputing it
        // from the touch events would be a second rule.
        public var startX:Number;
        public var startY:Number;

        // The node the press started on (null when nothing was under the pointer). Kept
        // per pointer so a drag can be routed to the node that owns it rather than to
        // whatever happens to be under the finger now.
        public var node:UiNode;

        public function Pointer(id:int, x:Number, y:Number, isPrimary:Boolean, pressure:Number):void
        {
            this.id = id;
            this.x = x;
            this.y = y;
            this.startX = x;
            this.startY = y;
            this.phase = "down";
            this.isPrimary = isPrimary;
            this.pressure = (pressure != pressure) ? 0.5 : pressure;
            this.node = null;
        }
    }
}

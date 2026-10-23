// asaot.ui.SpinnerNode -- an indeterminate activity ring.
//
// Copy of the ChipNode recipe: class `SpinnerNode`, lowercase factory `spinner.as`
// (compiler-gaps.md G7), `role` mandatory, self-registration once from the ctor.
//
// WHY `phase` IS AN OPTION AND NOT PRIVATE STATE
// ---------------------------------------------
// A spinner is the one widget whose whole point is being different every frame,
// which makes it the one widget a pixel probe cannot nail down. So the ROTATION is
// expressed as a number (`phase`, 0..1 of a turn) that the caller can PIN, and
// `spin` decides whether that number is used or derived from the frame clock:
//
//   spin = false, phase = 0    -> a still picture, byte-identical every run
//   spin = true  (default)     -> phase follows UiApp.enterFrameTicks
//
// The widget keeps itself repainting while `spin` is true (it calls
// `markPaint` at the end of its own paint). That is a PAINT-ONLY loop by
// construction: it never touches a layout bit, so a spinning spinner costs no
// re-solve -- which is the property the probe asserts.
package asaot.ui
{
    import asaot.ui.kind.SpinnerWidget;

    public class SpinnerNode extends Element
    {
        public var diameter:Number;    // the ring's outside diameter (px)
        public var thickness:Number;   // stroke width (px)
        public var tone:String;        // "info" | "neutral" | "danger"
        public var spin:Boolean;       // derive `phase` from the frame clock
        public var phase:Number;       // 0..1 of a turn; 0 = the arc starts at 12 o'clock

        private static var registered:Boolean = false;

        public function SpinnerNode():void
        {
            super("spinner");
            if (!registered) { registered = true; Widgets.register("spinner", new SpinnerWidget()); }
            this.role = "status";
            this.diameter = 20;
            this.thickness = 2;
            this.tone = "info";
            this.spin = true;
            this.phase = 0;
        }
    }
}

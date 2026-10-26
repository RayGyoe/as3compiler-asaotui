// asaot.ui.TooltipNode -- a dark bubble with an optional arrow.
//
// Copy of the ChipNode recipe: class `TooltipNode`, lowercase factory `tooltip.as`
// (compiler-gaps.md G7), `role` mandatory, self-registration once from the ctor.
//
// WHERE IT GOES IS THE AUTHOR'S JOB, and that is now a CHOICE rather than the only
// option: the library HAS a second retained tree (`View.renderOverlay()` + the six
// overlay kinds), so a bubble that follows a target by key is `popover({ anchorKey })`
// in the overlay. A tooltip stays an ordinary node on purpose -- a hover bubble that
// the author places has no anchor to find, no flip to compute and no layer to tear
// down, and this is the shape the docs demos and the probes use. Placed either in
// flow or with the absolute positioning the engine already supports:
//
//   tooltip("Saved", { style: { position: "absolute", inset: [40, 8, 0, 0] } })
//
// Declaring that here matters, because "tooltip" in a component library usually
// means the floating kind, and quietly pretending otherwise would be the kind of
// silent difference AGENTS.md section 2.5 forbids.
package asaot.ui
{
    import asaot.ui.kind.TooltipWidget;

    public class TooltipNode extends Element
    {
        public var text:String;
        // "up" | "down" | "left" | "right" | "none". "up" means the arrow points
        // UP out of the bubble's top edge (so the bubble hangs below its target).
        public var arrow:String;
        public var tone:Number;   // the bubble fill

        private static var registered:Boolean = false;

        public function TooltipNode():void
        {
            super("tooltip");
            if (!registered) { registered = true; Widgets.register("tooltip", new TooltipWidget()); }
            this.role = "tooltip";
            this.text = "";
            this.arrow = "up";
            this.tone = 0x1F2937;
        }
    }
}

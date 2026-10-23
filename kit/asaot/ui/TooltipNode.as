// asaot.ui.TooltipNode -- a dark bubble with an optional arrow.
//
// Copy of the ChipNode recipe: class `TooltipNode`, lowercase factory `tooltip.as`
// (compiler-gaps.md G7), `role` mandatory, self-registration once from the ctor.
//
// WHERE IT GOES IS THE AUTHOR'S JOB. This library has no overlay layer yet
// (STATUS.md section 2.1), so a tooltip is not a floating window that anchors
// itself to a target: it is an ordinary node that takes part in the layout like
// every other node, and it is placed either in flow or with the absolute
// positioning the engine already supports:
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

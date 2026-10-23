// asaot.ui.SkeletonNode -- a placeholder for content that has not arrived.
//
// Copy of the ChipNode recipe: class `SkeletonNode`, lowercase factory
// `skeleton.as` (compiler-gaps.md G7), `role` mandatory, self-registration once.
//
// DELIBERATELY STATIC. A shimmer would be nice, but a shimmer is an animation,
// and this library ships no animation a test cannot freeze (see SpinnerNode for
// the one place that rule was bent, and how). A static grey block is the honest
// 90% of a skeleton's value: it reserves the space and reads as "loading" without
// pretending to be busy.
package asaot.ui
{
    import asaot.ui.kind.SkeletonWidget;

    public class SkeletonNode extends Element
    {
        public var variant:String;      // "text" | "rect" | "circle"
        public var lines:int;           // text variant only
        public var barHeight:Number;    // a line's thickness (px)
        public var gap:Number;          // between lines (px)
        public var tone:Number;         // the bar colour

        private static var registered:Boolean = false;

        public function SkeletonNode():void
        {
            super("skeleton");
            if (!registered) { registered = true; Widgets.register("skeleton", new SkeletonWidget()); }
            this.role = "status";
            this.variant = "text";
            this.lines = 3;
            this.barHeight = 8;
            this.gap = 6;
            this.tone = 0xE5E7EB;
        }
    }
}

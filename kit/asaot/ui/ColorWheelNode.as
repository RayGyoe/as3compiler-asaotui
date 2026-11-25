// asaot.ui.ColorWheelNode -- a hue-ring colour wheel (shadows/mid/highlights style).
// Generic colour-picker primitive: a conic hue ring, an inner disc, and a draggable
// dot. `value` is the hue angle 0..1; `spread` is the dot's radius fraction 0..1.
package asaot.ui
{
    import asaot.ui.kind.ColorWheelWidget;

    public class ColorWheelNode extends Control
    {
        public var label:String;
        public var value:Number;    // 0..1 hue angle
        public var spread:Number;   // 0..1 dot radius fraction
        public var onChange:Function;

        private static var registered:Boolean = false;

        public function ColorWheelNode(l:String):void
        {
            super("colorWheel");
            if (!registered) { registered = true; Widgets.register("colorWheel", new ColorWheelWidget()); }
            this.role = "slider";
            this.label = l;
            this.value = 0;
            this.spread = 0.15;
        }
    }
}
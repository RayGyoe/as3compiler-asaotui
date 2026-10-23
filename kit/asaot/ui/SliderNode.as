// asaot.ui.SliderNode -- a horizontal 0..1 slider.
//
// See RadioNode/ChipNode for the naming rules. `value` is a Number in 0..1
// (clamped both by the factory and by the widget). `binding` (optional) is read
// for the value and written on interaction, exactly like textField/checkbox.
package asaot.ui
{
    import asaot.ui.kind.SliderWidget;

    public class SliderNode extends Control
    {
        public var label:String;
        public var value:Number;      // 0..1
        public var binding:Binding;   // optional: value read from / written to
        public var onChange:Function;

        private static var registered:Boolean = false;

        public function SliderNode(l:String):void
        {
            super("slider");
            if (!registered) { registered = true; Widgets.register("slider", new SliderWidget()); }
            this.role = "slider";
            this.label = l;
            this.value = 0;
            this.binding = null;
            this.onChange = null;
        }
    }
}
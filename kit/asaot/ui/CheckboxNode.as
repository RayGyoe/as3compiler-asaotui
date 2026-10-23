// asaot.ui.CheckboxNode -- the description node for a checkbox (design doc
// section 4.2). See BoxNode for why the class has the `Node` suffix while the
// factory is still `checkbox(...)`.
package asaot.ui
{
    import asaot.ui.kind.CheckboxWidget;

    public class CheckboxNode extends Control
    {
        public var label:String;
        public var checked:Boolean;
        public var binding:Binding;       // optional: checked read from / written to
        public var onChange:Function;

        private static var registered:Boolean = false;

        public function CheckboxNode(l:String):void
        {
            super("checkbox");
            if (!registered) { registered = true; Widgets.register("checkbox", new CheckboxWidget()); }
            this.role = "checkBox";
            this.label = l;
            this.checked = false;
            this.binding = null;
            this.onChange = null;
        }
    }
}
// asaot.ui.SwitchNode -- an on/off toggle (a "switch"/"toggle" control).
//
// See RadioNode/ChipNode for the naming rules. NOTE the factory file is
// `toggle.as` and the factory function is `toggle(...)`: `switch` is a reserved
// AS3 keyword (see CONTRIBUTING-widget.md section 4.4, where `with` had to
// become `withPatch`), so it cannot be a definition name. The KIND string is
// still "switch" and the ARIA role is "switch".
package asaot.ui
{
    import asaot.ui.kind.SwitchWidget;

    public class SwitchNode extends Control
    {
        public var label:String;
        public var checked:Boolean;
        public var binding:Binding;   // optional: checked read from / written to
        public var onChange:Function;

        private static var registered:Boolean = false;

        public function SwitchNode(l:String):void
        {
            super("switch");
            if (!registered) { registered = true; Widgets.register("switch", new SwitchWidget()); }
            this.role = "switch";
            this.label = l;
            this.checked = false;
            this.binding = null;
            this.onChange = null;
        }
    }
}
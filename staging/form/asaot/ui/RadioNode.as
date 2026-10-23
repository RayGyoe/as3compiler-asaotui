// asaot.ui.RadioNode -- a labelled radio option.
//
// Copy of the ChipNode trio recipe (asaotui/CONTRIBUTING-widget.md): the class
// is `RadioNode` while the author-facing factory file is lowercase `radio.as`
// (case-insensitive filesystem + one externally-visible definition per file,
// compiler-gaps G7), `role` is mandatory, and the kind registers itself once
// from the constructor.
//
// `group`/`value` are carried on the description node as payload metadata for a
// future radio-GROUP manager; there is no cross-sibling coordination today (see
// the report's "not done" section), so clicking only sets THIS node selected.
package asaot.ui
{
    import asaot.ui.kind.RadioWidget;

    public class RadioNode extends Control
    {
        public var label:String;
        public var selected:Boolean;
        public var group:String;      // optional mutual-exclusion group id
        public var value:String;      // optional value for the group
        public var binding:Binding;   // optional: selected read from / written to
        public var onChange:Function;

        private static var registered:Boolean = false;

        public function RadioNode(l:String):void
        {
            super("radio");
            if (!registered) { registered = true; Widgets.register("radio", new RadioWidget()); }
            this.role = "radio";
            this.label = l;
            this.selected = false;
            this.group = null;
            this.value = null;
            this.binding = null;
            this.onChange = null;
        }
    }
}
// asaot.ui.ComboBoxNode -- a select whose trigger is a real text field, so the author
// can filter the options by typing.
//
// FILTERING IS THE FACTORY'S JOB. The widget reports the typed text through
// `onQuery(text)`; the author writes it into the model and re-renders with whatever
// `options` are left. So the dropdown is still a pure projection of the description
// (same contract as SelectNode) and this node holds no matching logic at all -- which
// is also why the widget never has to re-filter on its own: there is nothing to keep
// in sync.
//
// THE FIELD IS THE FOCUS TARGET, not this node: typing has to reach a TextField for
// the runtime to insert characters at all. That makes the key path different from
// every other widget -- see ComboBoxWidget's header.
package asaot.ui
{
    import asaot.ui.kind.ComboBoxWidget;

    public class ComboBoxNode extends Element
    {
        public var open:Boolean;
        public var query:String;           // the text in the trigger's field
        public var placeholder:String;
        public var options:Array;          // already FILTERED by the author/factory
        public var onSelect:Function;      // Function(index:int) -- index into `options`
        public var onQuery:Function;       // Function(text:String) -- every keystroke
        public var onOpenChange:Function;  // Function(open:Boolean)
        public var width:Number;

        private static var registered:Boolean = false;

        public function ComboBoxNode():void
        {
            super("combo");
            if (!registered) { registered = true; Widgets.register("combo", new ComboBoxWidget()); }
            this.role = "combobox";
            this.open = false;
            this.query = "";
            this.placeholder = "";
            this.options = [];
            this.onSelect = null;
            this.onQuery = null;
            this.onOpenChange = null;
            this.width = 200;
        }
    }
}
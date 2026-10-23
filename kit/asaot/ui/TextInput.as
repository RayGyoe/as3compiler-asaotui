// asaot.ui.TextInput -- a single-line editable field (design doc section
// 4.2/4.4). The editing text object is a REAL flash.text.TextField with
// type="input", so caret, selection, IME-adjacent and password masking are all
// the existing, adl-calibrated behaviour -- we do not write a second text
// pipeline (section 4.4 explicitly forbids it).
package asaot.ui
{
    import asaot.ui.kind.InputWidget;

    public class TextInput extends Control
    {
        public var value:String;
        public var binding:Binding;      // optional: value read from / written to
        public var placeholder:String;
        public var password:Boolean;
        public var onCommit:Function;

        private static var registered:Boolean = false;

        public function TextInput():void
        {
            super("textInput");
            if (!registered) { registered = true; Widgets.register("textInput", new InputWidget()); }
            this.role = "textField";
            this.value = "";
            this.binding = null;
            this.placeholder = "";
            this.password = false;
            this.onCommit = null;
        }
    }
}
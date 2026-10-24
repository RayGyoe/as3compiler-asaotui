// asaot.ui.TextAreaNode -- a MULTI-LINE editable field (design doc section 4.2).
//
// Same editing object as TextInput: a REAL flash.text.TextField with
// type="input", only `multiline`/`wordWrap` on and a fixed box instead of an
// intrinsic width. Caret, selection, IME-adjacent behaviour and CHANGE events are
// the existing, adl-calibrated text pipeline (section 4.4 forbids a second one).
//
// WHY A SEPARATE KIND RATHER THAN `textField({ multiline: true })`
// ---------------------------------------------------------------
// The two differ in more than a flag, and every difference is a CONTRACT:
//   * Enter. In a single-line field Enter COMMITS (InputWidget consumes 13). In a
//     multiline field Enter inserts a newline -- the runtime does that itself
//     (`keyCode == 13 && tf->multiline` in src/emit.ts) and only when the widget
//     did NOT consume the key. So the key contract is inverted, not extended.
//   * Height. A single-line field is 32pt when auto; a text area is `rows` lines.
//   * Escape still reverts to the last committed value in both.
// One class with a boolean that inverts its own keyboard contract is exactly the
// kind of "looks like it works" trap AGENTS.md 2.4 warns about.
package asaot.ui
{
    import asaot.ui.kind.TextAreaWidget;

    public class TextAreaNode extends Control
    {
        public var value:String;
        public var binding:Binding;      // optional: value read from / written to
        public var placeholder:String;
        // Intrinsic height in LINES when the style gives no height. Measured from
        // the resolved font's real line height, not from a hard-coded constant.
        public var rows:int;
        public var onCommit:Function;
        public var onChange:Function;    // every edit, like TextInput's

        private static var registered:Boolean = false;

        public function TextAreaNode():void
        {
            super("textArea");
            if (!registered) { registered = true; Widgets.register("textArea", new TextAreaWidget()); }
            this.role = "textArea";
            this.value = "";
            this.binding = null;
            this.placeholder = "";
            this.rows = 4;
            this.onCommit = null;
            this.onChange = null;
        }
    }
}
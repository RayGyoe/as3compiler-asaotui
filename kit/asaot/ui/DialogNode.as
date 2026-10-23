// asaot.ui.DialogNode -- a MODAL panel over a dimming scrim.
//
// Copy of the ChipNode recipe (compiler-gaps.md G7 for the file/class naming, the
// mandatory `role`, and the once-only self-registration).
//
// STRUCTURE the factory builds (and the widget relies on):
//
//   dialog node            style LAYER_CENTER  (absolute, inset 0, centres both axes)
//     ├─ [0] scrim   box   style SCRIM_BOX     (absolute, inset 0, translucent fill)
//     └─ [1] panel   box   style DIALOG_PANEL  (explicit width, auto height)
//            ├─ title text      (only when `title` is set)
//            ├─ the author's body children
//            └─ footer row      (only when `footer` is non-empty)
//
// THE PANEL IS ALWAYS THE LAST CHILD. The widget's click handler needs to know
// whether a click landed on the panel or on the scrim, so it takes the last child
// rather than counting: with `scrim: false` the panel is child 0, and an index
// constant would silently point at the panel's title instead.
//
// `open` IS AUTHOR-OWNED, like every other controlled control in this library
// (`page`, `selectedIndex`, `activeIndex`): clicking the scrim calls `onClose`,
// and the author's model decides whether the dialog actually closes. That keeps
// `render()` a pure function of the model, which is the whole design.
package asaot.ui
{
    import asaot.ui.kind.DialogWidget;

    public class DialogNode extends Element
    {
        public var open:Boolean;
        public var title:String;
        public var width:Number;          // panel width in px
        public var scrim:Boolean;         // dim + block what is behind
        public var closeOnScrim:Boolean;  // a scrim click calls onClose
        public var onClose:Function;

        private static var registered:Boolean = false;

        public function DialogNode():void
        {
            super("dialog");
            if (!registered) { registered = true; Widgets.register("dialog", new DialogWidget()); }
            this.role = "dialog";
            this.open = false;
            this.title = null;
            this.width = 360;
            this.scrim = true;
            this.closeOnScrim = true;
            this.onClose = null;
        }
    }
}
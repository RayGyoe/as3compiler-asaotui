// asaot.ui.ToastNode -- a transient notification.
//
// The node IS the bubble (like PopoverNode, not like DialogNode): a fixed-width box
// with one text child. WHERE it appears is not this node's business -- the app puts
// it in a `toastHost` stack (bottom-right), and the stack is a plain styled box.
// Splitting "the bubble" from "the corner" means a toast can also be dropped
// anywhere else (inline, in a form) without a second widget.
//
// `duration` IS THE ONE PIECE OF TIMER STATE in the whole library, and it is
// deliberately opt-in: 0 means "stay until the author closes me", which is what a
// demo/test wants (a timer that fires mid-assertion is untestable). Auto-dismiss
// only ever calls `onClose`; it never mutates `open` behind the author's back, so
// the model stays the single source of truth.
package asaot.ui
{
    import asaot.ui.kind.ToastWidget;

    public class ToastNode extends Element
    {
        public var open:Boolean;
        public var message:String;
        public var tone:String;           // "default" | "success" | "danger"
        public var duration:Number;       // ms until auto-dismiss; 0 == never
        public var onClose:Function;

        private static var registered:Boolean = false;

        public function ToastNode():void
        {
            super("toast");
            if (!registered) { registered = true; Widgets.register("toast", new ToastWidget()); }
            this.role = "status";
            this.open = false;
            this.message = "";
            this.tone = "default";
            this.duration = 0;
            this.onClose = null;
        }
    }
}
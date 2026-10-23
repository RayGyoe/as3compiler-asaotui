// asaot.ui.BadgeNode -- a small count/text pill (e.g. "3", "99+").
//
// Like ChipNode it is a status readout, not a focusable control. It extends
// Control (as ChipNode does) purely for the shared payload slots, with
// `tabEnabled = false` and no press behaviour. `tone` is a DECORATION: it only
// changes a colour, never the size, so the reconciler must not reflow for it.
package asaot.ui
{
    import asaot.ui.kind.BadgeWidget;

    public class BadgeNode extends Control
    {
        public var label:String;
        // "neutral" | "info" | "danger"
        public var tone:String;

        private static var registered:Boolean = false;

        public function BadgeNode(l:String):void
        {
            super("badge");
            if (!registered) { registered = true; Widgets.register("badge", new BadgeWidget()); }
            this.role = "status";
            this.tabEnabled = false;
            this.label = l;
            this.tone = "neutral";
        }
    }
}
// asaot.ui.ProgressNode -- a non-interactive 0..1 progress bar.
//
// See RadioNode/ChipNode for the naming rules. `value` is clamped to 0..1 and
// MUST paint correctly at both ends (0 shows only the track, 1 fills it). There
// is no Binding here: a progress bar is a readout of state owned elsewhere, so
// the author passes the current number each render.
package asaot.ui
{
    import asaot.ui.kind.ProgressWidget;

    public class ProgressNode extends Control
    {
        public var label:String;
        public var value:Number;      // 0..1

        private static var registered:Boolean = false;

        public function ProgressNode(l:String):void
        {
            super("progress");
            if (!registered) { registered = true; Widgets.register("progress", new ProgressWidget()); }
            this.role = "progressbar";
            this.tabEnabled = false;      // a readout is not focusable
            this.label = l;
            this.value = 0;
        }
    }
}
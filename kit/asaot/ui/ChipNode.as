// asaot.ui.ChipNode -- a small labelled pill.
//
// ★ REFERENCE IMPLEMENTATION of the Widget seam. Copy this trio (Node + factory +
// kind/<X>Widget) when adding a widget; the full recipe is in
// asaotui/CONTRIBUTING-widget.md. The three points worth noticing:
//
//   1. the class name is `<X>Node` while the author-facing factory file is
//      lowercase (`chip.as`) -- on a case-insensitive filesystem `chip.as` and
//      `Chip.as` are the SAME file, and mxmlc requires one externally-visible
//      definition per file, named after it (asaotui/compiler-gaps.md G7);
//   2. `role` is mandatory and non-null -- the Reconciler throws without it;
//   3. `Widgets.register` runs here, once, from the constructor.
package asaot.ui
{
    import asaot.ui.kind.ChipWidget;

    public class ChipNode extends Control
    {
        public var label:String;
        // "neutral" | "info" | "danger" -- a DECORATION, so it never reflows.
        public var tone:String;

        private static var registered:Boolean = false;

        public function ChipNode(l:String):void
        {
            super("chip");
            if (!registered) { registered = true; Widgets.register("chip", new ChipWidget()); }
            // A chip is a status readout, not a focusable control.
            this.role = "status";
            this.tabEnabled = false;
            this.label = l;
            this.tone = "neutral";
        }
    }
}
// asaot.ui.TabsNode -- a horizontal segmented control.
//
// Copy of the ChipNode trio recipe (asaotui/CONTRIBUTING-widget.md): the class
// is `TabsNode` while the author-facing factory file is lowercase `tabs.as`
// (case-insensitive filesystem + one externally-visible definition per file,
// compiler-gaps G7), `role` is mandatory, and the kind registers itself once
// from the constructor.
//
// TWO STATE KINDS, and they are NOT the same (the contract the probe pins):
//   * `selectedIndex` is a DECORATION -- changing which segment is active only
//     repaints, so TabsWidget.payload returns FALSE for it;
//   * the `labels` ARRAY changes how many segments there are and how wide each
//     is measured, so a labels change is a STRUCTURE change and payload returns
//     TRUE (re-measure).
//
// `selectedIndex` accepts a Number OR an `asaot.ui.Binding` (the slider
// convention, see slider.as): a Binding is stored on the node and read/written
// through, so a click reaches the model via `Binding.set` -> `Observable.notify`.
//
// `gap` is the space between segments. It is carried as its OWN field (not only
// as the style `gap`) because a caller that passes an explicit `style` refinement
// would otherwise lose the shorthand -- OptionSupport.applyOpts takes either
// `opts.style` OR the shorthand keys, never both (see OptionSupport.applyOpts).
//
// Keyboard: there is NO focus/Tab layer in the toolkit (STATUS.md section 3.1),
// so this control is deliberately tabEnabled = false and the widget does not
// pretend to read arrow keys.
package asaot.ui
{
    import asaot.ui.kind.TabsWidget;

    public class TabsNode extends Control
    {
        public var labels:Array;
        public var selectedIndex:Number;
        public var gap:Number;        // space between segments; NaN = use style gap
        public var binding:Binding;   // optional: selectedIndex read from / written to
        public var onChange:Function; // called with the new index on a click

        private static var registered:Boolean = false;

        public function TabsNode()
        {
            super("tabs");
            if (!registered) { registered = true; Widgets.register("tabs", new TabsWidget()); }
            this.role = "tablist";
            this.tabEnabled = false;   // no keyboard layer exists; see the file header
            this.labels = [];
            this.selectedIndex = 0;
            this.gap = NaN;
            this.binding = null;
            this.onChange = null;
        }
    }
}
// asaot.ui.SplitPaneNode -- two panes and a draggable divider between them.
//
// WHY `direction` AND NOT `orientation`: "horizontal split" means opposite things
// to opposite people (a horizontal DIVIDER gives two stacked panes; a horizontal
// SPLIT gives two side-by-side panes). The engine's own vocabulary is unambiguous,
// so this kind borrows it: `row` = panes side by side, `column` = panes stacked.
// Any other value THROWS instead of picking one of the two readings.
//
// WHAT IS AUTHOR-OWNED: `ratio`. The drag REPORTS a new ratio through `onResize`
// and never writes this field -- the same contract `table` uses for column widths,
// for the same reason (`ratio` usually lives in a model that is rebuilt every
// render). A drag whose callback is ignored therefore moves nothing, which is the
// controlled-component contract rather than a bug.
//
// WHY minSize IS ENFORCED TWICE: in `measure` so a hand-written ratio cannot
// produce a zero-width pane, and in the drag so the pointer cannot drag one there.
// They are the same number applied at the two places that can violate it.
package asaot.ui
{
    import asaot.ui.kind.SplitPaneWidget;

    public class SplitPaneNode extends Element
    {
        // "row" (side by side) | "column" (stacked)
        public var direction:String;
        public var ratio:Number;        // share of the FIRST pane, 0..1
        public var minSize:Number;      // narrowest either pane may become, px
        public var dividerSize:Number;  // thickness of the grip, px
        public var onResize:Function;   // Function(ratio:Number) -- every drag move

        private static var registered:Boolean = false;

        public function SplitPaneNode():void
        {
            super("splitPane");
            if (!registered) { registered = true; Widgets.register("splitPane", new SplitPaneWidget()); }
            this.role = "group";
            this.direction = "row";
            this.ratio = 0.5;
            this.minSize = 40;
            this.dividerSize = 6;
            this.onResize = null;
        }
    }
}
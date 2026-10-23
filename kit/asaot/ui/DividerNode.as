// asaot.ui.DividerNode -- a 1px rule between two pieces of content.
//
// A separator is NOT a focusable control (role "separator", no press), so it
// extends Element rather than Control. The `orientation` decides which axis is
// the 1px one; because that changes the node's INTRINSIC size it is a layout
// input, not a decoration (contrast with a colour, which would be paint-only).
package asaot.ui
{
    import asaot.ui.kind.DividerWidget;

    public class DividerNode extends Element
    {
        // "horizontal" | "vertical"
        public var orientation:String;

        private static var registered:Boolean = false;

        public function DividerNode():void
        {
            super("divider");
            if (!registered) { registered = true; Widgets.register("divider", new DividerWidget()); }
            this.role = "separator";
            this.orientation = "horizontal";
        }
    }
}

// asaot.ui.DrawerNode -- an edge-anchored panel (the dialog's side-sheet sibling).
//
// Same shape as DialogNode (copy of the ChipNode recipe), with ONE difference that
// drives the whole layout: the panel is pinned to an EDGE and stretched across the
// other axis, so the layer's flex settings do the work:
//
//   side "left"   LAYER_ROW_START  row, justify flex-start, align stretch  -> full height
//   side "right"  LAYER_ROW_END    row, justify flex-end,   align stretch  -> full height
//   side "top"    LAYER_COL_START  col, justify flex-start, align stretch  -> full width
//   side "bottom" LAYER_COL_END    col, justify flex-end,   align stretch  -> full width
//
// `align-items: stretch` only stretches a child whose cross size is AUTO, which is
// exactly what the factory leaves it: `size` sets the MAIN dimension (width for a
// side sheet, height for a sheet) and nothing else.
//
// `size` is the sheet's own thickness (width for left/right, height for top/bottom).
// Naming it `size` rather than `width` is deliberate: one number means different
// axes depending on `side`, and calling it `width` for a top sheet would be a lie.
package asaot.ui
{
    import asaot.ui.kind.DrawerWidget;

    public class DrawerNode extends Element
    {
        public var open:Boolean;
        public var side:String;           // "left" | "right" | "top" | "bottom"
        public var size:Number;           // thickness in px along the sheet's main axis
        public var title:String;
        public var scrim:Boolean;
        public var closeOnScrim:Boolean;
        public var onClose:Function;

        private static var registered:Boolean = false;

        public function DrawerNode():void
        {
            super("drawer");
            if (!registered) { registered = true; Widgets.register("drawer", new DrawerWidget()); }
            this.role = "dialog";
            this.open = false;
            this.side = "left";
            this.size = 280;
            this.title = null;
            this.scrim = true;
            this.closeOnScrim = true;
            this.onClose = null;
        }
    }
}
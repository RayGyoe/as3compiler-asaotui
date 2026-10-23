// asaot.ui.PopoverNode -- an anchored floating panel.
//
// UNLIKE dialog/drawer THIS NODE **IS** THE PANEL, not a window-sized layer. Three
// consequences, all deliberate:
//
//   * it is positioned by INSETS (absolute), so the widget can move it to its
//     anchor every measure without touching the flow of its siblings;
//   * it can paint into its own shapeA and have children on top of that paint --
//     which is what the menu needs for its selection band;
//   * it does NOT swallow the window, so it does not need a scrim or a catcher.
//
// CLOSE-ON-OUTSIDE is therefore a STAGE listener, not a captured click: when a
// click bubbles to the stage and the event's target is not inside this node, the
// popover calls `onClose`. The trade-off is real and documented: the click is NOT
// swallowed, so the control underneath still sees it. That is the usual popover
// behaviour, and it is why modal surfaces use dialog() instead.
//
// `placement` is which side of the anchor the panel sits on. `top`/`left` are
// expressed with the TRAILING inset (bottom/right) rather than as
// `anchor.y - panelHeight`, so the panel does not have to know its own height
// before it has been measured -- the engine resolves the trailing inset, we do not.
package asaot.ui
{
    import asaot.ui.kind.PopoverWidget;

    public class PopoverNode extends Element
    {
        public var open:Boolean;
        public var anchorKey:String;      // key of the node to hang off
        public var placement:String;      // "bottom" | "top" | "right" | "left"
        public var offset:Number;         // gap between the anchor and the panel
        public var width:Number;          // panel width in px
        public var closeOnOutside:Boolean;
        public var onClose:Function;

        private static var registered:Boolean = false;

        public function PopoverNode():void
        {
            super("popover");
            if (!registered) { registered = true; Widgets.register("popover", new PopoverWidget()); }
            this.role = "group";
            this.open = false;
            this.anchorKey = null;
            this.placement = "bottom";
            this.offset = 6;
            this.width = 200;
            this.closeOnOutside = true;
            this.onClose = null;
        }
    }
}
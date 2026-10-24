// asaot.ui.MenuNode -- an anchored list of selectable rows (the popup behind a
// "..." button, and the surface a `select` dropdown is built from).
//
// EXTENDS PopoverNode because it IS a popover with rows in it: same anchoring, same
// placement, same close-on-outside. Inheritance here is not decoration -- it is
// what lets MenuWidget extend PopoverWidget and keep exactly one copy of the
// "where does the panel go" and "when does it close" logic (which is how the two
// kinds stay in step).
//
// THE ROWS ARE CHILD NODES but the SELECTION BAND IS NOT PAINTED ON THEM. The rows
// are transparent boxes and this node's own shapeA (behind every child) carries the
// band -- the same split TableWidget uses for its stripes and selection. Painting
// the band onto a row's shapeA would not work: a box clears its shape on every
// paint, and a child paints AFTER its parent.
package asaot.ui
{
    import asaot.ui.kind.MenuWidget;

    public class MenuNode extends PopoverNode
    {
        public var items:Array;           // [ "Label", ... ] or [ { label, value }, ... ]
        public var selectedIndex:int;     // -1 == none
        // Which item's SUBMENU is open (-1 = none). Author-owned like every other
        // overlay `open`, so render() stays a pure function of the model: the author
        // sets it from onSelect when the activated row has a submenu.
        public var submenuIndex:int;
        public var onSelect:Function;     // Function(index:int)

        private static var menuRegistered:Boolean = false;

        public function MenuNode():void
        {
            super();
            if (!menuRegistered) { menuRegistered = true; Widgets.register("menu", new MenuWidget()); }
            this.kind = "menu";
            this.role = "menu";
            this.items = [];
            this.selectedIndex = -1;
            this.submenuIndex = -1;
            this.onSelect = null;
            this.width = 160;
        }
    }
}
// asaot.ui.ListNode -- a real scroll-free column of rows.
//
// Copy of the ChipNode recipe: class `ListNode`, lowercase factory `list.as`
// (compiler-gaps G7), `role` mandatory, self-registration once from the ctor.
//
// This node IS a container: its description children are the rows (plus optional
// dividers) the factory produced, and the layout ENGINE places them -- the widget
// never hand-positions a row. See list.as for how the children are built.
//
// INTERACTION: `selectedIndex` accepts a Number OR a Binding, exactly like
// checkbox/radio/slider. A click on row i selects it, writes back through the
// Binding, and calls `onSelect(i)`.
//
// KEYBOARD: the list is a single TAB STOP (tabEnabled, the ARIA listbox model) and
// Up/Down/Home/End move the selection -- see ListWidget.onKey. Which is also why
// `tabEnabled` is true: the Tab ring is how a node receives keys at all (UiApp owns
// the ring and hands the focused node's widget every unconsumed KEY_DOWN).
//
// OUT OF SCOPE (registered in STATUS.md section 3.1, not silently stubbed):
// virtualised scrolling and viewport clipping. Every item becomes a real UiNode
// and every row is laid out, so a 10k-item list would build 10k nodes. That is
// the documented boundary of this widget, not a bug.
package asaot.ui
{
    import asaot.ui.kind.ListWidget;

    public class ListNode extends Control
    {
        public var items:Array;
        public var builder:Function;     // function(item:Object, index:int):Node
        public var separator:Boolean;
        public var itemHeight:Number;    // 0 = unset (rows size themselves)
        public var selectedIndex:Number; // number OR bound through `binding`
        public var binding:Binding;
        public var onSelect:Function;

        private static var registered:Boolean = false;

        public function ListNode()
        {
            super("list");
            if (!registered) { registered = true; Widgets.register("list", new ListWidget()); }
            this.role = "list";
            this.tabEnabled = true;    // one stop for the whole list; arrows walk the rows
            this.items = null;
            this.builder = null;
            this.separator = false;
            this.itemHeight = 0;
            this.selectedIndex = 0;
            this.binding = null;
            this.onSelect = null;
        }
    }
}
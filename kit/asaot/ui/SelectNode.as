// asaot.ui.SelectNode -- a trigger plus a dropdown list.
//
// THE ONE OVERLAY CONTROL THAT IS **NOT** IN THE FLOATING LAYER. Its dropdown is an
// absolutely-positioned CHILD of this node, so it inherits the trigger's coordinate
// space and needs no anchoring/portal machinery at all.
//
// THE COST OF THAT CHOICE IS REAL AND DOCUMENTED: the dropdown lives in this node's
// backing, so any LATER SIBLING of the select is painted above it, and an ancestor
// with a real clip would cut it off (`overflow` is stored but not applied on this
// backend, so clipping does not actually happen today -- see compiler-gaps.md). The
// gallery keeps the select LAST in its column for exactly this reason.
//
// `open` IS AUTHOR-OWNED (like dialog/popover): clicking the trigger calls
// `onOpenChange(!open)` and the author decides. It has to be -- the dropdown's
// visibility is a property of the descriptor tree the author builds each frame, so
// state the widget kept privately would be overwritten by the next render.
package asaot.ui
{
    import asaot.ui.kind.SelectWidget;

    public class SelectNode extends Element
    {
        public var open:Boolean;
        public var value:String;
        public var placeholder:String;
        public var options:Array;          // [ "Label", ... ] or [ { label, value }, ... ]
        public var onSelect:Function;      // Function(index:int)
        public var onOpenChange:Function;  // Function(open:Boolean)
        public var width:Number;

        private static var registered:Boolean = false;

        public function SelectNode():void
        {
            super("select");
            if (!registered) { registered = true; Widgets.register("select", new SelectWidget()); }
            this.role = "combobox";
            this.open = false;
            this.value = null;
            this.placeholder = "Select...";
            this.options = [];
            this.onSelect = null;
            this.onOpenChange = null;
            this.width = 200;
        }
    }
}
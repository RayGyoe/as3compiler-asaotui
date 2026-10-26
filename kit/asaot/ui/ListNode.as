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
// VIRTUAL MODE (`virtual: true`, added 2026-10-26): the same contract virtualList
// and `table.virtual` already use -- the AUTHOR holds the model, the kit mounts only
// the window, and `onScroll(y)` reports a row-aligned offset the author writes back
// before re-rendering. Without it every item becomes a real UiNode, which is the
// right boundary for a settings panel and a hard wall for a log viewer.
//
// WHAT VIRTUAL MODE REFUSES, AND WHY: `separator: true` (the window arithmetic is
// row-granular; a hairline between rows changes the pitch the offset is measured in,
// so a virtualised list with separators would drift by one row per screen) and a
// viewport height that is not an explicit point value (the window has to know how
// many rows fit BEFORE layout runs). Both throw in list.as rather than approximating.
package asaot.ui
{
    import asaot.ui.kind.ListWidget;
    import asaot.ui.kind.VirtualListWidget;
    import asaot.ui.style.StyleRefinement;

    public class ListNode extends Control
    {
        public var items:Array;
        public var builder:Function;     // function(item:Object, index:int):Node
        public var separator:Boolean;
        public var itemHeight:Number;    // 0 = unset (rows size themselves)
        public var selectedIndex:Number; // number OR bound through `binding`
        public var binding:Binding;
        public var onSelect:Function;

        // ---- virtual mode (see the header) ----------------------------------
        public var virtual:Boolean;      // mount only the visible window
        public var offsetY:Number;       // row-granular; the factory snaps it
        public var onScroll:Function;    // function (offsetY:Number)
        public var count:int;            // TOTAL rows (not mounted rows)
        public var firstIndex:int;       // published by the factory for probes/authors
        public var lastIndex:int;
        public var visibleCount:int;     // rows that fit, ignoring the +1 partial row

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
            this.virtual = false;
            this.offsetY = 0;
            this.onScroll = null;
            this.count = 0;
            this.firstIndex = 0;
            this.lastIndex = -1;
            this.visibleCount = 0;
        }

        // ---- the virtual window ------------------------------------------------
        // Mount only [first, last]. The +1 row is the PARTIAL row a viewport whose
        // height is not a multiple of itemHeight shows -- it is real, and omitting it
        // leaves a blank strip at the bottom of every virtualised list.
        //
        // BOTH `height` and `minSize.height` are pinned, for the reason virtualList.as
        // records from the other side: `height` alone is overridden by the flexbox
        // solve when the window overflows the viewport, and `flexShrink: 0` encodes as
        // "flex: 1 with a zero basis" in this engine and collapses every row to 0.
        public static function mountWindow(n:ListNode, items:Array, builder:Function, count:int):void
        {
            var rh:Number = n.itemHeight;
            if (!(rh > 0))
            {
                throw new Error("asaot.ui.list: `virtual: true` needs a positive `itemHeight` (got "
                    + rh + "). The window is row-granular: without a row height there is no"
                    + " definition of which rows are visible.");
            }
            if (n.separator)
            {
                throw new Error("asaot.ui.list: `separator: true` cannot be combined with"
                    + " `virtual: true`. The window arithmetic is row-granular, and a hairline"
                    + " between rows changes the pitch the offset is measured in -- the list"
                    + " would drift by one row per screen. Give the row a border instead.");
            }
            var vh:Number = VirtualListWidget.viewportHeight(n.style);
            if (!(vh > 0))
            {
                throw new Error("asaot.ui.list: `virtual: true` needs an explicit point height"
                    + " on the list (style.size/height, e.g. size: [280, 200]). The window has"
                    + " to know how many rows fit before layout runs, and an auto height is"
                    + " decided by the rows that would have been mounted.");
            }

            var fit:int = int(Math.ceil(vh / rh));
            if (fit < 1) fit = 1;
            var maxFirst:int = count - fit;
            if (maxFirst < 0) maxFirst = 0;
            var off:Number = isNaN(n.offsetY) ? 0 : n.offsetY;
            var first:int = int(Math.round(off / rh));
            if (first > maxFirst) first = maxFirst;
            if (first < 0) first = 0;
            n.offsetY = first * rh;
            n.firstIndex = first;
            n.visibleCount = fit;

            var last:int = first + fit;      // +1: the partial row
            if (last > count - 1) last = count - 1;
            n.lastIndex = last;

            var base:String = n.key == null ? "list" : String(n.key);
            var patch:StyleRefinement = StyleRefinement.from({ height: rh, minSize: [null, rh] });
            var kids:Array = [];
            for (var i:int = first; i <= last; i++)
            {
                var row:Node = builder(items[i], i);
                if (row == null)
                {
                    throw new Error("asaot.ui.list: the row builder returned null for index "
                        + i + "; every mounted row must be a Node.");
                }
                if (row.key == null) row.key = base + ":r" + i;
                row.style = (row.style == null ? new StyleRefinement() : row.style).withPatch(patch);
                kids.push(row);
            }
            OptionSupport.addChildren(n, kids);
        }
    }
}
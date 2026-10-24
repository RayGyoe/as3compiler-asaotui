// asaot.ui.VirtualListNode -- a viewport that mounts only the rows it can show.
//
// WHY THIS EXISTS AT ALL. `list` (ListNode) says it plainly in its own header:
// every item becomes a real UiNode, so a 10k-item list builds 10k nodes. That is a
// fine boundary for a settings panel and a hard wall for a log viewer. This node is
// the other half of that sentence: the AUTHOR decides which slice exists, because
// `render()` is a pure function of the author's model -- `offsetY` included.
//
// THE MODEL IS THE WINDOW. `virtualList` mounts rows [firstIndex, lastIndex] and
// nothing else, and `firstIndex` is derived from `offsetY` (see virtualList.as).
// The widget therefore never mounts or unmounts anything: it reports a scroll
// (onScroll) and the author re-renders with the new offset. That is the same
// contract `select` uses for `open` and `dialog` uses for `open` -- the retained
// tree stays a pure projection of the description.
//
// ROW-GRANULAR, DELIBERATELY. There is no sub-row offset: `offsetY` is snapped to
// a whole number of rows in the factory. A half row at the top of a virtualised
// list buys nothing the author cannot get from a smaller rowHeight, and it costs a
// translated content box whose position fights the layout engine every frame.
//
// The clip is `backing.scrollRect` and it is a PURE clip here, not a slide:
// ScrollViewWidget assigns Rectangle(0, offsetY, w, h) to slide its content, while
// this widget assigns Rectangle(0, 0, w, h) -- the rows are already positioned
// inside the viewport because only the visible slice was mounted. Getting that
// backwards is exactly how the last row would paint below the viewport.
package asaot.ui
{
    import asaot.ui.kind.VirtualListWidget;

    public class VirtualListNode extends Control
    {
        public var count:int;        // total items (not mounted items)
        public var rowHeight:Number;
        public var offsetY:Number;   // row-granular; the factory snaps it
        public var overscan:int;     // extra rows above and below the window
        public var renderRow:Function;   // function(index:int):Node
        public var onScroll:Function;    // function(offsetY:Number):void

        // Published by the factory so an author (or a probe) can assert what got
        // mounted WITHOUT walking children: the window is the whole point.
        public var firstIndex:int;
        public var lastIndex:int;
        public var visibleCount:int;   // rows that fit in the viewport, ignoring overscan

        private static var registered:Boolean = false;

        public function VirtualListNode()
        {
            super("vlist");
            if (!registered) { registered = true; Widgets.register("vlist", new VirtualListWidget()); }
            this.role = "list";
            // Focusable so the widget's arrow/Page keys can arrive through UiApp's
            // WidgetKeys dispatch (see WidgetKeys). A list that cannot be scrolled
            // without a mouse is not a finished control.
            this.tabEnabled = true;
            this.count = 0;
            this.rowHeight = 0;
            this.offsetY = 0;
            this.overscan = 0;
            this.renderRow = null;
            this.onScroll = null;
            this.firstIndex = 0;
            this.lastIndex = -1;
            this.visibleCount = 0;
        }
    }
}
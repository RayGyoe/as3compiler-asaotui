// asaot.ui.TreeNode -- a flattened, expandable tree of rows.
//
// FLATTENING IS THE FACTORY'S JOB, NOT THE WIDGET'S. `tree()` walks the nested
// `items` once per frame and produces a FLAT list of rows for the branches that are
// open -- so every row is an ordinary direct child of this node, the layout engine
// places them, and the widget never indents or positions anything. Depth survives
// only as a left padding on the row plus the `depth` field below.
//
// WHY THAT MATTERS: the retained tree stays a pure projection of the description
// (same contract as `select.open` and `dialog.open`). An expanded branch is a key in
// `expanded`; the author owns that array and re-renders. Nothing about a tree's state
// hides inside a widget where the next render would overwrite it.
//
// `rows` IS WRITTEN BY THE FACTORY and read by TreeWidget: it is the only place that
// knows which row index means which item key, and routing a click back to a key
// needs exactly that. Each entry is a plain object { key, label, depth, branch, open }.
//
// VIRTUAL MODE (2026-10-26). The rows list is ALWAYS the full flattened subtree; only
// the MOUNTED children are a window of it. That split is what makes the widget's
// absolute row index possible (click/keys index `rows`, the mounted slice is
// `rows[firstRow ..]`), and it is why `firstRow`/`visibleRows` are published here
// rather than kept inside the widget.
package asaot.ui
{
    import asaot.ui.kind.TreeWidget;

    public class TreeNode extends Control
    {
        public var items:Array;         // [ { key, label, children: [...] }, ... ] (nested)
        public var rows:Array;          // OUT: the flattened visible rows (see header)
        public var expanded:Array;      // keys of the open branches
        public var selectedKey:String;
        public var onToggle:Function;   // Function(key:String)  -- the author flips `expanded`
        public var onSelect:Function;   // Function(key:String)
        public var rowHeight:Number;    // 0 = rows size themselves

        // ---- virtual mode (see the header) ----------------------------------
        public var virtual:Boolean;
        public var offsetY:Number;      // row-granular; the factory snaps it
        public var onScroll:Function;   // function (offsetY:Number)
        public var firstRow:int;        // index into `rows` of the first MOUNTED row
        public var visibleRows:int;     // rows that fit, ignoring the +1 partial row
        public var rowCount:int;        // rows.length, published for probes

        private static var registered:Boolean = false;

        public function TreeNode():void
        {
            super("tree");
            if (!registered) { registered = true; Widgets.register("tree", new TreeWidget()); }
            this.role = "tree";
            this.tabEnabled = true;
            this.items = [];
            this.rows = [];
            this.expanded = [];
            this.selectedKey = null;
            this.onToggle = null;
            this.onSelect = null;
            this.rowHeight = 0;
            this.virtual = false;
            this.offsetY = 0;
            this.onScroll = null;
            this.firstRow = 0;
            this.visibleRows = 0;
            this.rowCount = 0;
        }

        // Is `key` in the key list? A tiny linear scan instead of an object map:
        // tree sizes are in the dozens, and a plain Array keeps `expanded: ["a","b"]`
        // in the author's own description, which is what the docs show.
        public static function holds(keys:Array, key:String):Boolean
        {
            if (keys == null) return false;
            for (var i:int = 0; i < keys.length; i++)
            {
                if (String(keys[i]) == key) return true;
            }
            return false;
        }
    }
}
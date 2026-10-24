// asaot.ui.TableNode -- a real column of header + body ROWS.
//
// Same recipe as ListNode: class `TableNode`, lowercase factory `table.as`
// (compiler-gaps G7), `role` mandatory, self-registration once from the ctor.
//
// This node IS a container: its description children are the header row and the
// body rows the factory built, and the layout ENGINE places them -- the widget
// never hand-positions a cell. Column alignment is therefore a LAYOUT property,
// not widget arithmetic: every cell of column c gets the same flex basis, so the
// engine gives every column the same width in every row.
//
// INTERACTION: `selectedIndex` accepts a Number OR a Binding, exactly like
// list/checkbox/radio/slider. A click on body row i selects it, writes back
// through the Binding, and calls `onSelect(i)` (-1 = no row selected).
//
// SORTING is the AUTHOR'S, not the widget's. A header click only decides WHAT to
// ask for (`onSort(columnKey, descending)`); the state lives in the author's model
// and comes back as `sortColumn`/`sortDescending` on the next render, where the
// factory sorts a COPY of `rows` -- never the author's array, which stays the
// caller's data. `sortColumn` is the only thing that sorts: passing -1 (the default)
// means "the model's own order", and an author who keeps their data sorted
// themselves never opts in. The cycle is the browser's: another column -> ascending,
// same column -> descending, same column again -> unsorted.
//
// SORTED-ORDER INDICES: `selectedIndex` and `onSelect(i)` are positions in the
// DISPLAYED (sorted) order, and with `virtual` that is also the absolute row
// position -- a windowed table reports row 4, not "the second mounted row". An
// author who needs the row's identity rather than its position should compare a key
// column, because a sort changes every position by definition.
//
// VIRTUALISATION (`virtual: true` + `rowHeight` + `onScroll`): same contract as
// virtualList -- the DESCRIPTION carries the window, the widget only reports
// `onScroll(offsetY)` and the author re-renders. There is exactly one difference:
// the header row is always mounted and never scrolls, so the visible body height is
// `height - rowHeight`. A windowed table must therefore have a POINT height (a
// percentage height is unresolved when the factory runs -- same boundary
// ScrollViewWidget documents).
//
// COLUMN RESIZE (`resizable: true`): drag a column boundary in the header and the
// widget calls `onColumnResize(index, width)` on release. It does NOT write the
// width into `columns` itself: the columns array is the author's model (often an
// inline literal rebuilt every render), so a width written there would be lost on
// the next pass. While dragging, the only feedback is a 1px preview line -- the
// engine owns the cell geometry, so a live resize would need a full reflow per
// pointer move.
//
// OUT OF SCOPE (stated, not silently stubbed):
//   * cell content is CLIPPED nowhere -- a cell wider than its column simply
//     overlaps the next one. Use `cellText` to shorten it, or give the column a
//     width.
//   * no horizontal scrolling and no sticky first column.
//   * the sort is stable only because `sortRows` breaks ties on the original index;
//     it does not understand collation (no `localeCompare` in this dialect), so
//     "a" < "B" because that is what code-unit comparison says.
package asaot.ui
{
    import asaot.ui.kind.TableWidget;

    public class TableNode extends Control
    {
        // ---- the table's palette -------------------------------------------
        // Declared HERE, not in the factory or the widget, because both need it:
        // the factory styles the header cells, the widget paints the grid. Two
        // copies would drift. (A package-level `const` in table.as would be a
        // SECOND externally-visible definition in a file named after the factory
        // -- compiler-gaps G7, an mxmlc hard error.)
        public static const HEAD_BG:uint = 0xF3F4F6;    // header row fill
        public static const HEAD_TEXT:uint = 0x374151;  // header cell colour
        public static const GRID_LINE:uint = 0xE5E7EB;  // hairline colour
        public static const STRIPE_BG:uint = 0xF9FAFB;  // zebra fill
        public static const SEL_BG:uint = 0xDBEAFE;     // selected-row fill
        public static const CELL_PAD:Number = 6;        // horizontal cell padding

        // Array of { key:String, title:String, width:Number, style:StyleRefinement }
        // (`width` 0/absent = the column shares the leftover width equally).
        public var columns:Array;
        public var rows:Array;           // Array of Objects, read as row[column.key]
        public var cellText:Function;    // function(value:Object, rowIndex:int, colIndex:int):String
        public var header:Boolean;
        public var stripes:Boolean;      // zebra body rows
        public var grid:Boolean;         // hairlines between rows/columns
        public var rowHeight:Number;     // 0 = unset (rows size themselves)
        public var selectedIndex:Number; // number OR bound through `binding`; -1 = none
        public var binding:Binding;
        public var onSelect:Function;

        // ---- sorting (see the header: the AUTHOR owns the state) --------------
        public var sortColumn:int;          // -1 = model order; else the displayed column index
        public var sortDescending:Boolean;
        public var onSort:Function;         // function(columnKey:String, descending:Boolean):void

        // ---- column resize ---------------------------------------------------
        public var resizable:Boolean;
        public var onColumnResize:Function; // function(columnIndex:int, width:Number):void

        // ---- virtualisation (same contract as VirtualListNode) ---------------
        public var virtual:Boolean;
        public var offsetY:Number;          // row-granular; snapped by the factory
        public var onScroll:Function;       // function(offsetY:Number):void

        // Published by the FACTORY so a probe (or an author) can read the window
        // without walking 10k rows. `rowCount` is the number of rows that EXIST
        // (after sorting), not the number that got mounted.
        public var rowCount:int;
        public var firstRow:int;
        public var visibleRows:int;

        private static var registered:Boolean = false;

        public function TableNode()
        {
            super("table");
            if (!registered) { registered = true; Widgets.register("table", new TableWidget()); }
            this.role = "table";
            this.tabEnabled = false;
            this.columns = null;
            this.rows = null;
            this.cellText = null;
            this.header = true;
            this.stripes = false;
            this.grid = true;
            this.rowHeight = 0;
            this.selectedIndex = -1;
            this.binding = null;
            this.onSelect = null;
            this.sortColumn = -1;
            this.sortDescending = false;
            this.onSort = null;
            this.resizable = false;
            this.onColumnResize = null;
            this.virtual = false;
            this.offsetY = 0;
            this.onScroll = null;
            this.rowCount = 0;
            this.firstRow = 0;
            this.visibleRows = 0;
        }

        // A STABLE ascending sort of row objects by one key. Returns a NEW array: the
        // caller's data belongs to the caller, and a table that reordered it would
        // change the author's model as a side effect of drawing.
        //
        // Stability is enforced by the second comparison term, not by the sort
        // implementation (as_array_sort_impl is a plain qsort, i.e. UNSTABLE): equal
        // keys keep their original relative order because the tie-break is the index.
        //
        // Comparison rules, in the order they are applied (there is no `localeCompare`
        // in this dialect, so string order is code-unit order, and numbers are
        // compared as numbers even when the model stores them as strings):
        //   * both sides numeric (Number, or a String that parses as a number)
        //     -> numeric compare, so "10" > "9";
        //   * null/undefined sorts BEFORE everything (an empty cell at the top), and
        //     two nulls tie;
        //   * otherwise the String forms are compared with `<` / `>`.
        public static function sortRows(rows:Array, key:String, desc:Boolean):Array
        {
            var n:int = rows.length;
            var idx:Array = new Array();
            var i:int;
            for (i = 0; i < n; i++) idx.push(i);

            var cmp:Function = function (ia:Object, ib:Object):int
            {
                var a:Object = rows[int(ia)];
                var b:Object = rows[int(ib)];
                // Dynamic index, exactly like table.as reads a cell: `row[key]`, not
                // `Reflect.field` (the kit does not depend on `flash.utils` reflection).
                var va:Object = a == null ? null : a[key];
                var vb:Object = b == null ? null : b[key];
                var r:int = compareValues(va, vb);
                if (desc) r = -r;
                // Tie-break on the ORIGINAL index: this is what makes the sort stable
                // (and it must be added AFTER the direction flip, otherwise a
                // descending sort would reverse equal keys too).
                if (r == 0) r = int(ia) < int(ib) ? -1 : (int(ia) > int(ib) ? 1 : 0);
                return r;
            };
            idx.sort(cmp);

            var out:Array = new Array();
            for (i = 0; i < n; i++) out.push(rows[int(idx[i])]);
            return out;
        }

        // The value comparison half of sortRows, exposed because "why did my numbers
        // sort as text" is the question this answers.
        public static function compareValues(va:Object, vb:Object):int
        {
            var na:Boolean = isNumeric(va);
            var nb:Boolean = isNumeric(vb);
            if (na && nb)
            {
                var da:Number = Number(va);
                var db:Number = Number(vb);
                if (da < db) return -1;
                if (da > db) return 1;
                return 0;
            }
            if (va == null && vb == null) return 0;
            if (va == null) return -1;
            if (vb == null) return 1;
            var sa:String = String(va);
            var sb:String = String(vb);
            if (sa < sb) return -1;
            if (sa > sb) return 1;
            return 0;
        }

        private static function isNumeric(v:Object):Boolean
        {
            if (v == null) return false;
            if (v is Number) return !isNaN(Number(v));
            if (v is String)
            {
                // Trim first: " 7" must not become NaN (which would make the whole
                // column fall back to text order for one stray space).
                var s:String = String(v);
                if (s.length == 0) return false;
                if (s == " ") return false;
                var d:Number = Number(s);
                return !isNaN(d);
            }
            return false;
        }
    }
}
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
// OUT OF SCOPE (stated, not silently stubbed):
//   * cell content is CLIPPED nowhere -- a cell wider than its column simply
//     overlaps the next one. Use `cellText` to shorten it, or give the column a
//     width.
//   * no sorting, no column resize, no virtualisation: every row is a real UiNode
//     (same boundary as ListNode, STATUS.md section 3.1).
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
        }
    }
}
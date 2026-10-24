// asaot.ui.DatePickerNode -- a trigger plus a month grid, in the select mould.
//
// Same shape as SelectNode/ComboBoxNode: the panel is an absolutely-positioned CHILD,
// so it inherits the trigger's coordinate space and needs no anchoring machinery (and
// inherits select's documented cost -- a later sibling paints above it).
//
// `year`/`month`/`value` ARE AUTHOR-OWNED. Clicking a day reports `onSelect(iso)`;
// clicking the month arrows reports `onMonthChange(year, month)`. Neither is applied
// here: the author re-renders, and the grid the user sees is always the description's.
//
// `days` IS WRITTEN BY THE FACTORY (like TreeNode.rows): 42 entries, one per cell of
// the 6x7 grid, { key, day, muted } where day == 0 means "a cell of the previous or
// next month" and is not clickable. The widget routes a click back to a day by
// matching the hit node's key against this array -- no string parsing anywhere.
package asaot.ui
{
    import asaot.ui.kind.DatePickerWidget;

    public class DatePickerNode extends Control
    {
        public var open:Boolean;
        public var value:String;          // "YYYY-MM-DD" or null
        public var placeholder:String;
        public var year:int;              // the month ON SCREEN (not the selected date)
        public var month:int;             // 1..12
        public var days:Array;            // OUT: 42 cells, see the header
        public var onSelect:Function;     // Function(iso:String)
        public var onMonthChange:Function;// Function(year:int, month:int)
        public var onOpenChange:Function; // Function(open:Boolean)
        public var width:Number;

        private static var registered:Boolean = false;

        public function DatePickerNode():void
        {
            super("datepicker");
            if (!registered) { registered = true; Widgets.register("datepicker", new DatePickerWidget()); }
            this.role = "combobox";
            this.tabEnabled = true;
            this.open = false;
            this.value = null;
            this.placeholder = "Pick a date";
            this.year = 1970;
            this.month = 1;
            this.days = [];
            this.onSelect = null;
            this.onMonthChange = null;
            this.onOpenChange = null;
            this.width = 200;
        }
    }
}
// asaot.ui.MultiSelectNode -- a dropdown where several options can be on.
//
// THE STORED VALUES ARE THE OPTIONS' `value`s, NOT ROW INDICES. An index is a
// position in an array the author rebuilds every render; the moment an option is
// filtered out or inserted, "selected row 2" points at a different thing. The value
// is stable across that, and it is also what the author's model already holds.
//
// `onToggle(index)` reports the ROW the click landed on, because that is the only
// identity a row has at click time (a value would have to be looked up first, and the
// widget would then be guessing which of two options with the same value was meant).
// The author flips membership in their own array; the dropdown stays OPEN, because
// closing after every pick is what makes a multi-select useless for picking three
// things.
//
// `values` is an Array of Strings and it is READ-ONLY here: the widget never mutates
// it. Mutating an author's array in place would work until they memoised it.
package asaot.ui
{
    import asaot.ui.kind.MultiSelectWidget;

    public class MultiSelectNode extends Control
    {
        public var open:Boolean;
        public var values:Array;         // selected option VALUES (Strings)
        public var placeholder:String;
        public var options:Array;        // Strings or { label, value }
        public var onToggle:Function;    // function (index:int)
        public var onOpenChange:Function; // function (open:Boolean)
        public var width:Number;

        private static var registered:Boolean = false;

        public function MultiSelectNode():void
        {
            super("multiSelect");
            if (!registered) { registered = true; Widgets.register("multiSelect", new MultiSelectWidget()); }
            this.role = "combobox";
            this.tabEnabled = true;
            this.open = false;
            this.values = [];
            this.placeholder = "Select";
            this.options = [];
            this.onToggle = null;
            this.onOpenChange = null;
            this.width = 200;
        }

        // Is `v` selected? A linear scan: option lists are dozens long, and a Set-like
        // object would have to be rebuilt on every render anyway.
        public static function holds(values:Array, v:String):Boolean
        {
            if (values == null) return false;
            for (var i:int = 0; i < values.length; i++)
            {
                if (String(values[i]) == v) return true;
            }
            return false;
        }
    }
}
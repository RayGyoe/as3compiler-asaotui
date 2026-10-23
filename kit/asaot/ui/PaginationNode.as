// asaot.ui.PaginationNode -- a page stepper: prev, page numbers, next.
//
// Same recipe as ChipNode (the reference trio): class `PaginationNode`, lowercase
// factory `pagination.as` (compiler-gaps G7), `role` mandatory, self-registration
// once from the ctor.
//
// PAGES ARE 1-BASED: `page` is the page a human would see in the URL, and
// `onSelect` receives a 1-based page. That is the one place this library does not
// use 0-based indices, and it is deliberate -- a caller formatting "page N of M"
// would otherwise convert twice.
//
// STRUCTURE (built by the factory, placed by the engine): one `chip` child for
// prev, one per visible page number, one `text` child per ellipsis, one `chip` for
// next. WHICH numbers are visible is decided by `PaginationWidget.pageList`, a
// pure static shared by the factory (which renders it) and the widget (which maps a
// click back through it), so the two can never disagree about a slot.
//
// INTERACTION: `page` accepts a Number OR a Binding. A click on a number selects
// that page; prev/next step by one and stop at the ends (a click that would not
// move the page reports nothing at all -- no callback, no binding write).
package asaot.ui
{
    import asaot.ui.kind.PaginationWidget;

    public class PaginationNode extends Control
    {
        public var page:Number;        // 1-based current page
        public var pageCount:Number;   // total pages (>= 1)
        public var windowSize:Number;  // max number slots (>= 5; ellipses may add 2)
        public var binding:Binding;
        public var onSelect:Function;  // function(page:int):void

        private static var registered:Boolean = false;

        public function PaginationNode():void
        {
            super("pagination");
            if (!registered) { registered = true; Widgets.register("pagination", new PaginationWidget()); }
            this.role = "navigation";
            this.tabEnabled = false;
            this.page = 1;
            this.pageCount = 1;
            this.windowSize = 7;
            this.binding = null;
            this.onSelect = null;
        }
    }
}
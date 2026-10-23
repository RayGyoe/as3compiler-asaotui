// asaot.ui.BreadcrumbNode -- a trail of labels, last one current.
//
// Same recipe as ChipNode (the reference trio): class `BreadcrumbNode`, lowercase
// factory `breadcrumb.as` (compiler-gaps G7), `role` mandatory, self-registration
// once from the ctor.
//
// STRUCTURE (built by the factory, placed by the engine): one `text` child per
// crumb plus a `text` separator between them. The crumb labels carry
// `role: "link"` and the separators `role: "separator"` -- the ARIA shape of a
// breadcrumb, and at the same time the marker the widget uses to tell a crumb from
// a separator (no key parsing).
//
// INTERACTION: clicking a crumb calls `onNavigate(index)` with the CRUMB index
// (separators do not count). The current crumb is not navigable -- by default the
// LAST one, or `currentIndex` if the author sets it (a trail rendered mid-flight,
// e.g. while a child page is open).
//
// The visible state of "which crumb is current" is a style difference chosen by the
// factory (muted vs link colour), not something the widget paints, so a
// `currentIndex` change costs a re-resolve, never a reflow.
package asaot.ui
{
    import asaot.ui.kind.BreadcrumbWidget;

    public class BreadcrumbNode extends Control
    {
        // ---- the palette (see TableNode for why it lives on the node) ------
        public static const LINK_TEXT:uint = 0x2563EB;
        public static const CURRENT_TEXT:uint = 0x6B7280;
        public static const SEP_TEXT:uint = 0x9CA3AF;

        public var items:Array;         // Array of labels (String)
        public var separator:String;    // between crumbs
        public var currentIndex:Number; // -1 = the last crumb
        public var onNavigate:Function; // function(crumbIndex:int):void

        private static var registered:Boolean = false;

        public function BreadcrumbNode():void
        {
            super("breadcrumb");
            if (!registered) { registered = true; Widgets.register("breadcrumb", new BreadcrumbWidget()); }
            this.role = "navigation";
            this.tabEnabled = false;
            this.items = null;
            this.separator = "/";
            this.currentIndex = -1;
            this.onNavigate = null;
        }
    }
}
// asaot.ui.AccordionNode -- a stack of collapsible sections.
//
// Same recipe as ChipNode (the reference trio): class `AccordionNode`, lowercase
// factory `accordion.as` (compiler-gaps G7), `role` mandatory, self-registration
// once from the ctor.
//
// STRUCTURE (built by the factory, placed by the engine -- the widget positions
// nothing): one header `row` per section, and the PANEL of the open section only.
// A collapsed panel is left out of the children entirely, because a collapsed
// section must take no layout space -- and `Element.visible` is
// `visibility:hidden` (a node that is not drawn but still occupies space), not
// `display:none`, so hiding the panel would leave its height behind.
//
// INTERACTION: `activeIndex` accepts a Number OR a Binding (Number(Number) like
// list/tabs/slider). Clicking a header opens that section and closes the other;
// clicking the open header closes it, so -1 means "all closed". Single-open is the
// only mode, and that is a stated boundary, not an accident:
//   * `mode: "multi"` is NOT implemented (it would need an Array slot plus a
//     per-section boolean, and the design doc does not pin the author spelling);
//   * collapsing/expanding REBUILDS the panel's UiNode, so live state that only
//     lives on that node (e.g. a scrollView's offset) resets on collapse. Author
//     state that lives in the descriptor (like this `activeIndex`) survives.
package asaot.ui
{
    import asaot.ui.kind.AccordionWidget;

    public class AccordionNode extends Control
    {
        // ---- the palette ---------------------------------------------------
        // Declared here because both the factory (the header row's resting fill and
        // its text colour) and the widget (the open header's fill) need it, and two
        // copies would drift. See TableNode for why this is not a package const.
        public static const HEADER_BG:uint = 0xF3F4F6;
        public static const OPEN_BG:uint = 0xDBEAFE;
        public static const HEADER_TEXT:uint = 0x111827;
        public static const RULE:uint = 0xE5E7EB;
        public static const HEADER_PAD_H:Number = 12;
        public static const HEADER_PAD_V:Number = 10;

        // Array of { title:String, content:Node, key:String }
        public var sections:Array;
        public var activeIndex:Number;   // -1 = all closed; number OR bound through `binding`
        public var binding:Binding;
        public var onToggle:Function;    // function(index:int):void

        private static var registered:Boolean = false;

        public function AccordionNode():void
        {
            super("accordion");
            if (!registered) { registered = true; Widgets.register("accordion", new AccordionWidget()); }
            this.role = "group";
            this.tabEnabled = false;
            this.sections = null;
            this.activeIndex = -1;
            this.binding = null;
            this.onToggle = null;
        }
    }
}
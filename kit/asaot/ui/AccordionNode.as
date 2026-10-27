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
// clicking the open header closes it, so -1 means "all closed".
//
// TWO MODES (2026-10-26):
//   mode: "single" (default) -- at most ONE panel open, state in `activeIndex`.
//   mode: "multi"            -- ANY number open, state in `openIndices` (an Array
//                               of section indices, or a Binding whose value is
//                               one). `onToggle(i)` still reports the ONE section
//                               whose state changed, so the author never has to
//                               diff two arrays to find out what the user did.
//
// The two spellings are exclusive ON PURPOSE: `activeIndex` in multi mode would be
// a second, silently ignored source of truth, so the factory REFUSES the
// combination instead of picking one (AGENTS.md 2.5).
//
// Both modes keep the same rule: collapsing/expanding REBUILDS the panel's UiNode,
// so live state that only lives on that node (e.g. a scrollView's offset) resets on
// collapse. Author state that lives in the descriptor (activeIndex/openIndices)
// survives.
package asaot.ui
{
    import asaot.ui.kind.AccordionWidget;

    public class AccordionNode extends Control
    {
        // ---- the geometry --------------------------------------------------
        // Colours come from `Theme.tokens()` (see TableNode's note: a `const` cannot
        // follow a theme switch). Only spacing lives here.
        public static const HEADER_PAD_H:Number = 12;
        public static const HEADER_PAD_V:Number = 10;

        // Array of { title:String, content:Node, key:String }
        public var sections:Array;
        public var mode:String;          // "single" (default) | "multi"
        public var activeIndex:Number;   // single: -1 = all closed; number OR bound through `binding`
        public var openIndices:Array;    // multi: the open section indices; array OR bound through `binding`
        public var binding:Binding;      // single: a Number; multi: the Array
        public var onToggle:Function;    // function(index:int):void -- the section that changed

        private static var registered:Boolean = false;

        public function AccordionNode():void
        {
            super("accordion");
            if (!registered) { registered = true; Widgets.register("accordion", new AccordionWidget()); }
            this.role = "group";
            this.tabEnabled = false;
            this.sections = null;
            this.mode = "single";
            this.activeIndex = -1;
            this.openIndices = null;
            this.binding = null;
            this.onToggle = null;
        }

        // Membership test for multi mode: the FACTORY (which decides which panels to
        // mount) and the WIDGET (which decides which headers to fill) must agree, so
        // the rule lives in one place. Out-of-range indices are IGNORED, not clamped
        // and not an error: `openIndices` is author data that can outlive a section
        // being removed, and refusing to draw over a stale index would turn a data
        // edit into a broken window.
        // The open set arrives either as an Array literal or as the value a Binding
        // returns, i.e. typed `*`. `Array(x)` is NOT a cast: AS3's constructor treats a
        // single non-Number argument as ONE ELEMENT, so `Array([0,2])` is `[[0,2]]` --
        // which isOpen then reads as "index 0 open, everything else closed", because
        // `Number([0,2])` is NaN and `int(NaN)` is 0. That is exactly how the first
        // version of multi mode lost its second panel (probes/widgets/accordion), and
        // the failure was silent. Anything that is not an Array is refused.
        public static function asIndices(v:*):Array
        {
            if (v == null) return [];
            if (v is Array) return v as Array;
            throw new Error("asaot.ui: accordion openIndices must be an Array of section indices");
        }

        public static function isOpen(list:Array, i:int):Boolean
        {
            if (list == null) return false;
            for (var k:int = 0; k < list.length; k++)
            {
                if (list[k] == null) continue;
                if (int(Number(list[k])) == i) return true;
            }
            return false;
        }
    }
}
// asaot.ui.TabBarNode -- the phone's first-level navigation: one bar of tabs at the
// bottom of the screen, exactly one of them current.
//
// Copy of the ChipNode recipe: class `TabBarNode`, lowercase factory `tabBar.as`
// (compiler-gaps.md G7), `role` mandatory, self-registration once.
//
// ONE LEVEL, NOT A HIERARCHY. `items` is the author's array and `selectedIndex` is
// the author's model: tapping a tab reports the INDEX through `onSelect` and the
// author decides what the next render looks like. Nothing here swaps pages -- a
// tabBar that mounted its own content would be a second navStack, and the two
// have different histories (tabs REPLACE, a stack PUSHES). Compose them: a
// tabBar selects which navStack is mounted.
//
// A TAP ON THE CURRENT TAB IS STILL REPORTED. It is not a no-op: re-tapping the
// tab you are on is how an app says "take me back to the top of this section", and
// swallowing the event would make that impossible to express.
//
// `items[i]` is `{ key:String, label:String, icon:String|Node }`:
//
//   * `icon` as a STRING is SVG path data and the bar owns its colour -- the tab's
//     tint is the selected/unselected state, and a glyph the author tinted by hand
//     could not follow it. `icon` as a NODE is mounted as the author built it (their
//     colour wins; the bar does not recolour a node it did not build);
//   * `label` is text, and it follows the same tint.
//
// The tint is a TEXT-STYLE patch on the cell, so it is inherited by the label --
// and by anything else the author puts in a cell that reads the inherited text
// colour. There is no indicator pill/underline in this version (MOBILE.md C3 asks
// for the selected state, not for Material's exact indicator); the tint is the
// state.
//
// `safeArea: "bottom"` is the home-indicator inset, and it needs no field: every
// Element accepts `safeArea`, and insets are folded into PADDING, so the bar grows
// and its own background still covers the inset.
package asaot.ui
{
    import asaot.ui.kind.TabBarWidget;

    public class TabBarNode extends Element
    {
        public var items:Array;          // [{ key, label, icon }], back-most first
        public var selectedIndex:int;    // -1 = nothing selected
        public var onSelect:Function;    // (index:int)
        public var barHeight:Number;     // the row of tabs

        private static var registered:Boolean = false;

        public function TabBarNode():void
        {
            super("tabBar");
            if (!registered) { registered = true; Widgets.register("tabBar", new TabBarWidget()); }
            this.role = "tablist";
            this.items = [];
            this.selectedIndex = -1;
            this.onSelect = null;
            this.barHeight = 56;
        }
    }
}

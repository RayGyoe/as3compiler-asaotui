// asaot.ui.AppBarNode -- the head of a page: a bar with leading / title / trailing
// slots and an OPTIONAL large title that the author scrolls away.
//
// Copy of the ChipNode recipe: class `AppBarNode`, lowercase factory `appBar.as`
// (compiler-gaps.md G7), `role` mandatory, self-registration once.
//
// THREE SLOTS, NOT FIVE. `leading` and `trailing` are ordinary Nodes (a back
// button, a menu button, an avatar), `title` is a Node or a plain String. Nothing
// is positioned by magic: the factory builds one row and the slots are its
// children, so the bar's geometry is the layout engine's, not the widget's.
//
// THE TITLE IS CENTRED IN WHAT IS LEFT, NOT IN THE BAR. Centring it in the bar
// would require taking it out of the row (absolute positioning) and then a long
// title would run under the trailing actions. The bar is 320px wide in the probe
// with a 40px leading and a 60px trailing: the title box is the 180px between
// them, and "centred" means centred there (x = 150, not the bar's 160). Stated
// because it is a choice, and the probe asserts the number.
//
// A LARGE bar LEFT-ALIGNS the title in both states -- big while the area is open,
// compact once it has collapsed -- because that is what the variant is for (a
// home-screen header whose title grows out of the left edge). So `large` also
// changes the alignment of the collapsed title, and the probe pins both numbers
// (150 compact, 95 collapsed-large).
//
// `large` IS THE LARGE-TITLE VARIANT, and it is driven by the AUTHOR, not by a
// hidden scroll coupling: the bar cannot know which viewport belongs to it. The
// author feeds `collapse` (px, 0..largeExtra) from their list's `onScroll`, exactly
// as they feed any other value back into the model.
//
//   * `largeExtra` (default 48) is the height of the extra area when nothing has
//     been collapsed; the bar's total height is `barHeight + largeExtra - collapse`;
//   * at `collapse >= largeExtra` the extra area is not mounted at all and the
//     compact title moves into the bar row -- ONE node either way, never two.
//
// The extra area SHRINKS FROM THE BOTTOM (the title's top stays put, the box's
// bottom edge rides up) rather than translating the title out of the top. That is
// a real difference from a Material header and it is why the bar clips itself:
// while the area is between 0 and largeExtra the title can be taller than its box
// and must be cut, not spilled over the page below (AppBarWidget sets the
// scrollRect; the appBar probe samples the pixels under the bar to prove it).
package asaot.ui
{
    import asaot.ui.kind.AppBarWidget;

    public class AppBarNode extends Element
    {
        public var leading:Node;      // left slot, or null
        public var title:Node;        // centre slot (the factory wraps a String), or null
        public var trailing:Node;     // right slot, or null

        public var large:Boolean;     // false = the compact bar only
        public var largeExtra:Number; // extra height of the large title area when shown
        public var barHeight:Number;  // the always-visible row
        public var collapse:Number;   // how much of largeExtra the author has scrolled away

        private static var registered:Boolean = false;

        public function AppBarNode():void
        {
            super("appBar");
            if (!registered) { registered = true; Widgets.register("appBar", new AppBarWidget()); }
            this.role = "banner";
            this.leading = null;
            this.title = null;
            this.trailing = null;
            this.large = false;
            this.largeExtra = 48;
            this.barHeight = 56;
            this.collapse = 0;
        }
    }
}

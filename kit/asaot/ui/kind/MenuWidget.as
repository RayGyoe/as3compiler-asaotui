// asaot.ui.kind.MenuWidget -- the anchored row list for MenuNode.
//
// EXTENDS PopoverWidget: anchoring and dismissal are inherited verbatim (see that
// file for the reasoning). This class adds exactly two things a popover does not
// have -- a selection band and a row click.
//
// THE BAND IS PAINTED ON THIS NODE'S shapeA, behind every child (the TableWidget
// split): the row boxes are transparent on purpose, so nothing clears it.
//
// A CLICK IS CONSUMED ONLY WHEN IT LANDED ON A ROW. `click()` reports that, so a
// click in the panel's 4px padding falls through to the author's onClick instead of
// silently doing nothing -- the same contract TableWidget's container uses.
package asaot.ui.kind
{
    import asaot.ui.Dirty;
    import asaot.ui.MenuNode;
    import asaot.ui.Node;
    import asaot.ui.OverlayChrome;
    import asaot.ui.OverlayList;
    import asaot.ui.UiNode;

    import flash.events.MouseEvent;

    public class MenuWidget extends PopoverWidget
    {
        private static const SEL_KEY:String = "sel";
        private static const HIT_KEY:String = "hitRow";

        override public function build(n:UiNode):void
        {
            super.build(n);
            // super.build creates shapeA (child index 0) and wires the scrim/
            // outside-close plumbing. That ONE shape carries both the MENU_PANEL
            // background and OverlayList.band -- rows are transparent on purpose, so
            // nothing clears the band. (Both painters null-guard shapeA, which is why
            // a missing shape showed a correctly laid out menu that painted nothing.)
            n.extra[SEL_KEY] = -1;
            n.extra[HIT_KEY] = 0;
            var self:MenuWidget = this;
            n.backing.addEventListener(MouseEvent.CLICK,
                function (e:MouseEvent):void { self.onRowClick(n, e); });
        }

        override public function payload(n:UiNode, desc:Node):Boolean
        {
            var m:MenuNode = MenuNode(desc);
            var relayout:Boolean = super.payload(n, desc);
            n.onChange = m.onSelect;
            var prev:Object = n.extra[SEL_KEY];
            if (prev == null || int(Number(prev)) != m.selectedIndex)
            {
                n.extra[SEL_KEY] = m.selectedIndex;
                // A selection change DECORATES only (same rule as tabs/list/table):
                // the band is painted, nothing is measured.
                n.dirty |= Dirty.M_PAINT;
            }
            // Rows are child nodes; the reconciler diffs them, so an items change
            // re-measures through the tree, not through this node.
            return relayout;
        }

        override public function wantsPress():Boolean { return true; }

        override public function paint(n:UiNode):void
        {
            super.paint(n);
            OverlayList.band(n, int(Number(n.extra[SEL_KEY])), OverlayChrome.ITEM_SELECTED);
        }

        override public function click(n:UiNode):Boolean
        {
            return Number(n.extra[HIT_KEY]) != 0;
        }

        private function onRowClick(n:UiNode, e:MouseEvent):void
        {
            n.extra[HIT_KEY] = 0;
            // e.localY is TARGET-relative (a row click reports row-local y) -- see
            // OverlayList.localYIn.
            var row:int = OverlayList.rowAt(n, OverlayList.localYIn(n, e));
            if (row < 0) return;
            n.extra[HIT_KEY] = 1;
            // Do NOT write SEL_KEY: payload must observe the change (same reason as
            // TableWidget.onClickY).
            n.app.markPaint(n);
            if (n.onChange != null) n.onChange(row);
        }
    }
}
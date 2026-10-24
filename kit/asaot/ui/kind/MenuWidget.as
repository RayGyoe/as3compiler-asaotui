// asaot.ui.kind.MenuWidget -- the anchored row list for MenuNode.
//
// EXTENDS PopoverWidget: anchoring, dismissal, the overflow flip and the entrance
// animation are inherited verbatim (see that file for the reasoning). This class
// adds exactly four things a popover does not have:
//
//   1. a SELECTION band and a HOVER band, painted on this node's own shapeA behind
//      every child (the TableWidget split) -- the row boxes are transparent on
//      purpose, so nothing clears them;
//   2. ROW KEYBOARD NAVIGATION (Up/Down/Enter/Escape) -- active row moved by the
//      arrows, activated by Enter, menu dismissed by Escape;
//   3. SUBMENU-COLLISION-FREE CLICK ROUTING: a nested `menu` child (built by
//      menu.as for an item that carries `submenu`) is an ordinary ANCHORED popover
//      whose anchorKey is its own row, so it needs no placement code here -- but a
//      click inside it must not be read as a click on the parent row that happens
//      to sit at the same height.
//   4. ROW CLICK ROUTING that also knows about submenus: a click inside a child
//      menu is that menu's business, not this one's.
//
// A CLICK IS CONSUMED ONLY WHEN IT LANDED ON A ROW. `click()` reports that, so a
// click in the panel's 4px padding falls through to the author's onClick instead of
// silently doing nothing -- the same contract TableWidget's container uses.
package asaot.ui.kind
{
    import asaot.ui.Dirty;
    import asaot.ui.LayoutConstants;
    import asaot.ui.LayoutEngine;
    import asaot.ui.MenuNode;
    import asaot.ui.Node;
    import asaot.ui.OverlayChrome;
    import asaot.ui.OverlayList;
    import asaot.ui.PaintKit;
    import asaot.ui.UiNode;
    import asaot.ui.WidgetKeys;

    import flash.events.MouseEvent;

    public class MenuWidget extends PopoverWidget implements WidgetKeys
    {
        private static const SEL_KEY:String = "sel";
        private static const HIT_KEY:String = "hitRow";
        private static const HOV_KEY:String = "hoverRow";
        private static const ACT_KEY:String = "activeRow";

        override public function build(n:UiNode):void
        {
            super.build(n);
            // super.build creates shapeA (child index 0) and wires the outside-close
            // plumbing. That ONE shape carries the MENU_PANEL background, the
            // selection band and the hover band -- rows are transparent on purpose,
            // so nothing clears them. (Both painters null-guard shapeA, which is why
            // a missing shape showed a correctly laid out menu that painted nothing.)
            n.extra[SEL_KEY] = -1;
            n.extra[HIT_KEY] = 0;
            n.extra[HOV_KEY] = -1;
            n.extra[ACT_KEY] = -1;
            var self:MenuWidget = this;
            n.backing.addEventListener(MouseEvent.CLICK,
                function (e:MouseEvent):void { self.onRowClick(n, e); });
            // Row hover. MOUSE_MOVE on the panel (rather than MOUSE_OVER per row) is
            // one listener for any number of rows, and it re-derives the row from the
            // pointer's own position -- which is also what makes the band land on the
            // row the engine solved, not on a row the painter guessed.
            n.backing.addEventListener(MouseEvent.MOUSE_MOVE,
                function (e:MouseEvent):void { self.onMove(n, e); });
            n.backing.addEventListener(MouseEvent.MOUSE_OUT,
                function (e:MouseEvent):void { self.setHoverRow(n, -1); });
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
                // Keyboard navigation starts where the selection is, so the first
                // Down moves to the row AFTER the selected one instead of jumping
                // to the top of the list.
                n.extra[ACT_KEY] = m.selectedIndex;
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
            // HOVER FIRST, SELECTION ON TOP: a menu always shows where the pointer
            // is, and the selected row must stay visible under it.
            OverlayList.band(n, int(Number(n.extra[HOV_KEY])), OverlayChrome.ITEM_HOVER);
            OverlayList.band(n, int(Number(n.extra[SEL_KEY])), OverlayChrome.ITEM_SELECTED);
            // The keyboard's active row is shown with the same hover colour, so a
            // menu driven by keys and one driven by the pointer look alike.
            var act:int = int(Number(n.extra[ACT_KEY]));
            if (act != int(Number(n.extra[SEL_KEY]))) OverlayList.band(n, act, OverlayChrome.ITEM_HOVER);
        }

        override public function click(n:UiNode):Boolean
        {
            return Number(n.extra[HIT_KEY]) != 0;
        }

        // ---- keyboard ------------------------------------------------------
        public function onKey(n:UiNode, keyCode:int, shift:Boolean):Boolean
        {
            var rows:int = this.rowCount(n);
            if (keyCode == 27)
            {
                var close:Function = n.extra[FN_KEY];
                if (close != null) close();
                return true;
            }
            if (rows == 0) return false;
            var act:int = int(Number(n.extra[ACT_KEY]));
            if (keyCode == 40)      // Down
            {
                act = act < 0 || act >= rows - 1 ? 0 : act + 1;
                this.setActiveRow(n, act);
                return true;
            }
            if (keyCode == 38)      // Up
            {
                act = act <= 0 ? rows - 1 : act - 1;
                this.setActiveRow(n, act);
                return true;
            }
            if (keyCode == 13 || keyCode == 32)   // Enter / Space
            {
                if (act < 0) return true;
                n.app.markPaint(n);
                if (n.onChange != null) n.onChange(act);
                return true;
            }
            return false;
        }

        private function setActiveRow(n:UiNode, row:int):void
        {
            if (int(Number(n.extra[ACT_KEY])) == row) return;
            n.extra[ACT_KEY] = row;
            n.app.markPaint(n);
        }

        // Every child that is NOT a submenu is a row (menu.as appends rows first and
        // submenus after them, so a row's index IS its child index and
        // OverlayList.band's index arithmetic stays exact).
        private function rowCount(n:UiNode):int
        {
            var c:int = 0;
            for (var i:int = 0; i < n.children.length; i++)
            {
                if (n.children[i].kind != "menu") c++;
            }
            return c;
        }

        // ---- pointer -------------------------------------------------------
        private function onMove(n:UiNode, e:MouseEvent):void
        {
            var row:int = OverlayList.rowAt(n, OverlayList.localYIn(n, e));
            this.setHoverRow(n, row);
        }

        private function setHoverRow(n:UiNode, row:int):void
        {
            if (int(Number(n.extra[HOV_KEY])) == row) return;
            n.extra[HOV_KEY] = row;
            n.app.markPaint(n);
        }

        private function onRowClick(n:UiNode, e:MouseEvent):void
        {
            n.extra[HIT_KEY] = 0;
            // A click that landed inside a SUBMENU belongs to that menu: it has its
            // own handler, and this one would otherwise read the same point in
            // THIS node's space and activate whatever parent row happens to sit at
            // that height.
            for (var i:int = 0; i < n.children.length; i++)
            {
                var c:UiNode = n.children[i];
                if (c.kind != "menu" || c.backing == null) continue;
                if (OverlayList.isInside(c.backing, e.target)) return;
            }
            // e.localY is TARGET-relative (a row click reports row-local y) -- see
            // OverlayList.localYIn.
            var row:int = OverlayList.rowAt(n, OverlayList.localYIn(n, e));
            if (row < 0) return;
            n.extra[HIT_KEY] = 1;
            n.extra[ACT_KEY] = row;
            // Do NOT write SEL_KEY: payload must observe the change (same reason as
            // TableWidget.onClickY).
            n.app.markPaint(n);
            if (n.onChange != null) n.onChange(row);
        }
    }
}
// asaot.ui.kind.DatePickerWidget -- click routing, month paging and keyboard for
// DatePickerNode.
//
// ROUTING IS DEEP, NOT ROW-BASED. A day cell is three levels below the trigger
// (dp > panel > week > cell), so `OverlayList.rowAt` is the wrong tool; the widget asks
// `OverlayList.atPoint` for the deepest node under the click and then matches that
// node's key against `desc.days`. The factory owns the key scheme, so the two agree by
// construction and nothing parses "2026-10-05" out of a string.
//
// TRIGGER vs PANEL BY GEOMETRY: the panel hangs directly BELOW the trigger (its top
// inset is the trigger's own solved height, written in measure), so `ly < absH` means
// the trigger and anything lower is the panel. That is exact for the pinned layout and
// is why this kind does not implement the flip/portal machinery the overlay layer has.
package asaot.ui.kind
{
    import asaot.ui.DateMath;
    import asaot.ui.DatePickerNode;
    import asaot.ui.Dirty;
    import asaot.ui.LayoutConstants;
    import asaot.ui.Node;
    import asaot.ui.OverlayChrome;
    import asaot.ui.OverlayList;
    import asaot.ui.OverlayMotion;
    import asaot.ui.PaintKit;
    import asaot.ui.UiNode;
    import asaot.ui.Widget;
    import asaot.ui.WidgetKeys;
    import flash.display.Shape;
    import flash.events.MouseEvent;

    public class DatePickerWidget implements Widget, WidgetKeys
    {
        private static const OPEN_KEY:String = "open";
        private static const SEL_FN:String = "onSelect";
        private static const MONTH_FN:String = "onMonthChange";
        private static const OPEN_FN:String = "onOpenChange";
        private static const DAYS_KEY:String = "days";
        private static const Y_KEY:String = "year";
        private static const M_KEY:String = "month";
        private static const BASE_KEY:String = "base";
        private static const ACT_KEY:String = "actDay";
        private static const BAND_KEY:String = "bandShape";

        public function build(n:UiNode):void
        {
            n.extra[OPEN_KEY] = false;
            n.extra[SEL_FN] = null;
            n.extra[MONTH_FN] = null;
            n.extra[OPEN_FN] = null;
            n.extra[DAYS_KEY] = null;
            n.extra[Y_KEY] = 1970;
            n.extra[M_KEY] = 1;
            n.extra[BASE_KEY] = "datepicker";
            n.extra[ACT_KEY] = 1;
            n.shapeA = new Shape();
            n.backing.addChild(n.shapeA);
            var self:DatePickerWidget = this;
            n.listen(n.backing, MouseEvent.CLICK,
                function (e:MouseEvent):void { self.onClickAt(n, e); });
        }

        public function payload(n:UiNode, desc:Node):Boolean
        {
            var d:DatePickerNode = DatePickerNode(desc);
            n.extra[SEL_FN] = d.onSelect;
            n.extra[MONTH_FN] = d.onMonthChange;
            n.extra[OPEN_FN] = d.onOpenChange;
            n.extra[DAYS_KEY] = d.days;
            n.extra[Y_KEY] = d.year;
            n.extra[M_KEY] = d.month;
            n.extra[BASE_KEY] = n.key == null ? "datepicker" : String(n.key);
            n.onChange = d.onSelect;
            var wasOpen:Boolean = Boolean(n.extra[OPEN_KEY]);
            n.extra[OPEN_KEY] = d.open;
            if (!wasOpen && d.open) OverlayMotion.start(n);
            this.liftForPopup(n, wasOpen, d.open);
            // The active day follows the SELECTED date, so opening the picker puts the
            // keyboard where the eye already is. Only on open -- otherwise an arrow key
            // would be undone by the next render.
            if (!wasOpen && d.open)
            {
                n.extra[ACT_KEY] = this.dayOf(d.value, d.year, d.month);
            }
            return false;
        }

        // The day-of-month of `value` when it belongs to the month on screen, else 1.
        private function dayOf(value:String, y:int, m:int):int
        {
            if (value == null || value.length < 10) return 1;
            if (value.substring(0, 7) != DateMath.iso(y, m, 1).substring(0, 7)) return 1;
            var d:int = int(value.substring(8, 10));
            return d < 1 ? 1 : d;
        }


        // THE OPEN POPUP ESCAPES THE FLOW (see UiNode.lifted). The dropdown/panel
        // is the node's LAST CHILD -- i.e. a child of this card -- and a child can
        // never paint above a sibling that its own parent renders later, which is
        // the "the list opens UNDER the widget below it" defect. While open this
        // node is hoisted onto the stage container (positioned at its ABSOLUTE
        // rect) so it wins the stacking order; closing puts it straight back.
        // Layout, keys, focus and events are untouched: only the display object
        // moves, because an open popup is exactly what a floating layer is for.
        private function liftForPopup(n:UiNode, wasOpen:Boolean, open:Boolean):void
        {
            if (wasOpen == open) return;
            n.lifted = open;
            n.app.markPaint(n);
        }

        public function wantsPress():Boolean { return true; }

        public function measure(n:UiNode):void
        {
            if (n.engineNode == null || n.children.length == 0) return;
            var panel:UiNode = n.children[n.children.length - 1];
            if (panel.engineNode == null) return;
            var eng:* = n.app.engine;
            var e:* = panel.engineNode;
            var h:Number = n.absH > 0 ? n.absH : 34;
            eng.setPosition(e, LayoutConstants.EDGE_LEFT, 0, LayoutConstants.UNIT_POINT);
            eng.setPosition(e, LayoutConstants.EDGE_TOP, h, LayoutConstants.UNIT_POINT);
            eng.setPosition(e, LayoutConstants.EDGE_RIGHT, 0, LayoutConstants.UNIT_UNDEFINED);
            eng.setPosition(e, LayoutConstants.EDGE_BOTTOM, 0, LayoutConstants.UNIT_UNDEFINED);
        }

        public function arrange(n:UiNode):void { }

        public function paint(n:UiNode):void
        {
            PaintKit.paintBox(n, n.resolved, PaintKit.w1(n), PaintKit.h1(n));
            var panel:UiNode = n.children.length > 0 ? n.children[n.children.length - 1] : null;
            if (panel != null)
            {
                this.paintActiveBand(n, panel);
                if (panel.backing != null) OverlayMotion.apply(n, panel, panel, 0, 6);
            }
            if (n.shapeA == null) return;
            var w:Number = PaintKit.w1(n);
            var h:Number = PaintKit.h1(n);
            var cx:Number = w - 10 - 4;
            var cy:Number = Math.floor(h / 2);
            var g:Object = n.shapeA.graphics;
            g.beginFill(OverlayChrome.SELECT_CARET, 1.0);
            g.moveTo(cx - 4, cy - 2);
            g.lineTo(cx + 4, cy - 2);
            g.lineTo(cx, cy + 3);
            g.lineTo(cx - 4, cy - 2);
            g.endFill();
        }

        public function click(n:UiNode):Boolean
        {
            return true;
        }

        // ---- keyboard ------------------------------------------------------
        public function onKey(n:UiNode, keyCode:int, shift:Boolean):Boolean
        {
            var open:Boolean = Boolean(n.extra[OPEN_KEY]);
            if (keyCode == 27)
            {
                if (!open) return false;
                this.report(n, false);
                return true;
            }
            if (!open)
            {
                if (keyCode == 13 || keyCode == 32 || keyCode == 40)
                {
                    this.report(n, true);
                    return true;
                }
                return false;
            }
            var y:int = int(n.extra[Y_KEY]);
            var m:int = int(n.extra[M_KEY]);
            var total:int = DateMath.daysInMonth(y, m);
            var act:int = int(n.extra[ACT_KEY]);
            if (act < 1 || act > total) act = 1;

            if (keyCode == 37 || keyCode == 39)
            {
                act = keyCode == 39 ? (act >= total ? 1 : act + 1)
                                    : (act <= 1 ? total : act - 1);
                n.extra[ACT_KEY] = act;
                n.app.markPaint(n);
                return true;
            }
            if (keyCode == 38 || keyCode == 40)
            {
                act = keyCode == 40 ? act + 7 : act - 7;
                if (act > total) act = total;
                if (act < 1) act = 1;
                n.extra[ACT_KEY] = act;
                n.app.markPaint(n);
                return true;
            }
            if (keyCode == 36 || keyCode == 35)
            {
                n.extra[ACT_KEY] = keyCode == 36 ? 1 : total;
                n.app.markPaint(n);
                return true;
            }
            if (keyCode == 33 || keyCode == 34)   // PageUp / PageDown: one month
            {
                this.page(n, keyCode == 34 ? 1 : -1);
                return true;
            }
            if (keyCode == 13 || keyCode == 32)
            {
                var f:Function = n.extra[SEL_FN];
                if (f != null) f(DateMath.iso(y, m, act));
                return true;
            }
            return false;
        }

        private function page(n:UiNode, delta:int):void
        {
            var f:Function = n.extra[MONTH_FN];
            if (f == null) return;
            var r:Object = DateMath.addMonths(int(n.extra[Y_KEY]), int(n.extra[M_KEY]), delta);
            f(int(r.year), int(r.month));
        }

        private function report(n:UiNode, open:Boolean):void
        {
            var f:Function = n.extra[OPEN_FN];
            if (f != null) f(open);
        }

        // The active day's band, inside the PANEL and below its cells (the same slot
        // SelectWidget/ComboBoxWidget use for their dropdown band).
        private function paintActiveBand(n:UiNode, panel:UiNode):void
        {
            if (panel.backing == null) return;
            var raw:Object = panel.extra[BAND_KEY];
            var sh:Shape;
            if (raw == null)
            {
                sh = new Shape();
                panel.backing.addChildAt(sh, panel.internalCount);
                panel.internalCount = panel.internalCount + 1;
                panel.extra[BAND_KEY] = sh;
            }
            else sh = Shape(raw);
            sh.graphics.clear();
            if (!Boolean(n.extra[OPEN_KEY])) return;
            var act:int = int(n.extra[ACT_KEY]);
            var key:String = String(n.extra[BASE_KEY]) + ":d" + DateMath.pad2(act);
            var cell:UiNode = this.findKey(panel, key);
            if (cell == null) return;
            sh.graphics.beginFill(OverlayChrome.ITEM_HOVER, 1.0);
            sh.graphics.drawRect(cell.absX - panel.absX, cell.absY - panel.absY,
                                 cell.absW, cell.absH);
            sh.graphics.endFill();
        }

        private function findKey(n:UiNode, key:String):UiNode
        {
            if (n.key != null && String(n.key) == key) return n;
            for (var i:int = 0; i < n.children.length; i++)
            {
                var hit:UiNode = this.findKey(n.children[i], key);
                if (hit != null) return hit;
            }
            return null;
        }

        private function onClickAt(n:UiNode, e:MouseEvent):void
        {
            var open:Boolean = Boolean(n.extra[OPEN_KEY]);
            var ly:Number = OverlayList.localYIn(n, e);
            var lx:Number = OverlayList.localXIn(n, e);
            if (!open)
            {
                this.report(n, true);
                return;
            }
            // Above the trigger's own height: the trigger itself -> close.
            if (ly < n.absH)
            {
                this.report(n, false);
                return;
            }
            var panel:UiNode = n.children.length > 0 ? n.children[n.children.length - 1] : null;
            if (panel == null) { this.report(n, false); return; }
            var hit:UiNode = OverlayList.atPoint(panel, lx - (panel.absX - n.absX),
                                                 ly - (panel.absY - n.absY));
            if (hit == null) return;
            var base:String = String(n.extra[BASE_KEY]);
            var days:Array = n.extra[DAYS_KEY] as Array;
            // WALK UP FROM THE DEEPEST HIT. `atPoint` answers with the innermost node,
            // and a click on a day number lands on the cell's TEXT child (`dp:d15:t`),
            // not on the cell. Testing every ancestor up to the panel means both a click
            // on the glyph and a click on the cell's empty margin do the same thing --
            // and it keeps the key scheme the factory's business.
            var node:UiNode = hit;
            while (node != null)
            {
                if (node.key != null)
                {
                    var k:String = String(node.key);
                    if (k == base + ":prev") { this.page(n, -1); return; }
                    if (k == base + ":next") { this.page(n, 1); return; }
                    if (days != null)
                    {
                        for (var i:int = 0; i < days.length; i++)
                        {
                            var d:Object = days[i];
                            if (String(d.key) != k) continue;
                            var day:int = int(d.day);
                            if (day <= 0) return;   // a cell of the neighbouring month
                            n.extra[ACT_KEY] = day;
                            n.app.markPaint(n);
                            var f:Function = n.extra[SEL_FN];
                            if (f != null)
                            {
                                f(DateMath.iso(int(n.extra[Y_KEY]), int(n.extra[M_KEY]), day));
                            }
                            return;
                        }
                    }
                }
                if (node == panel) return;
                node = node.parent;
            }
        }
    }
}
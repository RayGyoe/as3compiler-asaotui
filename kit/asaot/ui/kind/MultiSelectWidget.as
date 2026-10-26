// asaot.ui.kind.MultiSelectWidget -- the trigger + checklist dropdown for
// MultiSelectNode.
//
// It is deliberately SelectWidget's twin, minus two things and plus two:
//
//   * MINUS "close after choosing" and MINUS the single-value label. A multi-select
//     that closes on every pick costs a click per option; the summary label is the
//     factory's job (a pure function of values + options).
//   * PLUS a check mark per selected row and PLUS the active-row band, which is what
//     makes a keyboard user able to see where Enter will land before pressing it.
//
// CLICKS ARE ROUTED BY GEOMETRY, NOT BY TARGET. A click on a row bubbles up through
// the dropdown to this node's backing, exactly like a click on the label, so
// `e.target` cannot tell them apart. Testing the point against the dropdown's own
// child rects can -- rows first, then the trigger.
//
// THE CHECK MARK LIVES ON A SHAPE INSIDE THE DROPDOWN, at `drop.internalCount` (the
// slot the reconciler treats as "before the UiNode children"). Drawing it into this
// node's shapeA would put it UNDER the dropdown's opaque panel, and drawing into
// `drop.shapeA` from here is undone by the dropdown's own paint, which runs after its
// parent's. Same reasoning as SelectWidget.paintActiveBand.
package asaot.ui.kind
{
    import asaot.ui.Dirty;
    import asaot.ui.LayoutConstants;
    import asaot.ui.MultiSelectNode;
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

    public class MultiSelectWidget implements Widget, WidgetKeys
    {
        private static const OPEN_KEY:String = "open";
        private static const TOGGLE_FN:String = "onToggle";
        private static const OPEN_FN:String = "onOpenChange";
        private static const HIT_KEY:String = "hit";
        private static const ACT_KEY:String = "actRow";
        private static const CHROME_KEY:String = "mChrome";   // band + check marks
        private static const VALUES_KEY:String = "mValues";
        private static const OPTS_KEY:String = "mOptions";
        private static const CHECK:uint = 0x2563EB;

        public function build(n:UiNode):void
        {
            n.extra[OPEN_KEY] = false;
            n.extra[TOGGLE_FN] = null;
            n.extra[OPEN_FN] = null;
            n.extra[HIT_KEY] = 0;
            n.extra[ACT_KEY] = -1;
            n.extra[CHROME_KEY] = null;
            n.extra[VALUES_KEY] = null;
            n.extra[OPTS_KEY] = null;
            n.shapeA = new Shape();   // trigger background + caret (child 0)
            n.backing.addChild(n.shapeA);
            var self:MultiSelectWidget = this;
            n.listen(n.backing, MouseEvent.CLICK,
                function (e:MouseEvent):void { self.onClickAt(n, e); });
        }

        public function payload(n:UiNode, desc:Node):Boolean
        {
            var m:MultiSelectNode = MultiSelectNode(desc);
            n.extra[TOGGLE_FN] = m.onToggle;
            n.extra[OPEN_FN] = m.onOpenChange;
            n.extra[VALUES_KEY] = m.values;
            n.extra[OPTS_KEY] = m.options;
            var wasOpen:Boolean = Boolean(n.extra[OPEN_KEY]);
            n.extra[OPEN_KEY] = m.open;
            if (!wasOpen && m.open) OverlayMotion.start(n);
            if (wasOpen != m.open)
            {
                n.lifted = m.open;
                n.app.markPaint(n);
            }
            // The dropdown's visibility rides on its own child; the check marks depend
            // on `values`, and the values array is usually a NEW array each render, so
            // a paint is always owed here when the panel is open.
            if (m.open) n.dirty |= Dirty.M_PAINT;
            return false;
        }

        public function wantsPress():Boolean { return true; }

        public function measure(n:UiNode):void
        {
            if (n.engineNode == null || n.children.length == 0) return;
            var drop:UiNode = n.children[n.children.length - 1];
            if (drop.engineNode == null) return;
            var eng:* = n.app.engine;
            var e:* = drop.engineNode;
            var h:Number = n.absH > 0 ? n.absH : 34;
            eng.setPosition(e, LayoutConstants.EDGE_LEFT, 0, LayoutConstants.UNIT_POINT);
            eng.setPosition(e, LayoutConstants.EDGE_TOP, h, LayoutConstants.UNIT_POINT);
            eng.setPosition(e, LayoutConstants.EDGE_RIGHT, 0, LayoutConstants.UNIT_UNDEFINED);
            eng.setPosition(e, LayoutConstants.EDGE_BOTTOM, 0, LayoutConstants.UNIT_UNDEFINED);
            eng.setSize(e, LayoutConstants.AXIS_WIDTH,
                        n.absW > 0 ? n.absW : 200, LayoutConstants.UNIT_POINT);
        }

        public function arrange(n:UiNode):void { }

        public function paint(n:UiNode):void
        {
            PaintKit.paintBox(n, n.resolved, PaintKit.w1(n), PaintKit.h1(n));
            this.paintChrome(n);
            if (n.children.length > 0)
            {
                var drop:UiNode = n.children[n.children.length - 1];
                if (drop.backing != null) OverlayMotion.apply(n, drop, drop, 0, 6);
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
            return Number(n.extra[HIT_KEY]) != 0;
        }

        // ---- keyboard --------------------------------------------------------
        // Arrows move the ACTIVE row (wrap: a list of options is a ring for the cursor,
        // exactly like menu/select). Enter/Space TOGGLE it and keep the panel open --
        // closing is Escape or a click on the trigger.
        public function onKey(n:UiNode, keyCode:int, shift:Boolean):Boolean
        {
            var open:Boolean = Boolean(n.extra[OPEN_KEY]);
            var drop:UiNode = n.children.length > 0 ? n.children[n.children.length - 1] : null;
            var rows:int = drop == null ? 0 : drop.children.length;

            if (keyCode == 27)
            {
                if (!open) return false;
                this.close(n, false);
                return true;
            }
            if (keyCode == 13 || keyCode == 32)
            {
                if (!open) { this.close(n, true); return true; }
                var act:int = int(Number(n.extra[ACT_KEY]));
                if (act >= 0 && act < rows) this.toggle(n, act);
                return true;
            }
            if (keyCode == 40 || keyCode == 38)
            {
                if (!open)
                {
                    if (keyCode == 40) this.close(n, true);
                    return true;
                }
                if (rows == 0) return true;
                var a:int = int(Number(n.extra[ACT_KEY]));
                if (a < 0) a = 0;
                else a = keyCode == 40 ? (a + 1) % rows : (a - 1 + rows) % rows;
                n.extra[ACT_KEY] = a;
                n.app.markPaint(n);
                return true;
            }
            return false;
        }

        private function toggle(n:UiNode, row:int):void
        {
            var f:Function = n.extra[TOGGLE_FN];
            if (f != null) f(row);
            n.app.markPaint(n);
        }

        private function close(n:UiNode, open:Boolean):void
        {
            n.extra[ACT_KEY] = -1;
            var f:Function = n.extra[OPEN_FN];
            if (f != null) f(open);
            n.app.markPaint(n);
        }

        // The band + one check mark per selected row, on a shape inside the dropdown.
        private function paintChrome(n:UiNode):void
        {
            var drop:UiNode = n.children.length > 0 ? n.children[n.children.length - 1] : null;
            if (drop == null || drop.backing == null) return;
            var raw:Object = drop.extra[CHROME_KEY];
            var sh:Shape;
            if (raw == null)
            {
                sh = new Shape();
                drop.backing.addChildAt(sh, drop.internalCount);
                drop.internalCount = drop.internalCount + 1;
                drop.extra[CHROME_KEY] = sh;
            }
            else sh = Shape(raw);
            sh.graphics.clear();
            if (!Boolean(n.extra[OPEN_KEY])) return;

            var act:int = int(Number(n.extra[ACT_KEY]));
            if (act >= 0 && act < drop.children.length)
            {
                var ar:UiNode = drop.children[act];
                sh.graphics.beginFill(OverlayChrome.ITEM_HOVER, 1.0);
                sh.graphics.drawRect(ar.absX - drop.absX, ar.absY - drop.absY, ar.absW, ar.absH);
                sh.graphics.endFill();
            }

            var values:Array = n.extra[VALUES_KEY] as Array;
            var options:Array = n.extra[OPTS_KEY] as Array;
            if (values == null || options == null) return;
            sh.graphics.lineStyle(2, CHECK, 1.0);
            for (var i:int = 0; i < drop.children.length && i < options.length; i++)
            {
                var ov:String = OverlayList.valueOf(options[i], i);
                if (!MultiSelectNode.holds(values, ov)) continue;
                var r:UiNode = drop.children[i];
                var x0:Number = r.absX - drop.absX + 9;
                var y0:Number = r.absY - drop.absY + Math.floor(r.absH / 2);
                sh.graphics.moveTo(x0, y0);
                sh.graphics.lineTo(x0 + 4, y0 + 4);
                sh.graphics.lineTo(x0 + 10, y0 - 5);
            }
        }

        private function onClickAt(n:UiNode, e:MouseEvent):void
        {
            n.extra[HIT_KEY] = 0;
            var open:Boolean = Boolean(n.extra[OPEN_KEY]);
            var drop:UiNode = n.children.length > 0 ? n.children[n.children.length - 1] : null;

            if (open && drop != null)
            {
                var row:int = OverlayList.rowAt(drop, OverlayList.localYIn(drop, e));
                if (row >= 0)
                {
                    n.extra[HIT_KEY] = 1;
                    this.toggle(n, row);
                    return;
                }
            }
            n.extra[HIT_KEY] = 1;
            var f:Function = n.extra[OPEN_FN];
            if (f != null) f(!open);
            n.app.markPaint(n);
        }
    }
}
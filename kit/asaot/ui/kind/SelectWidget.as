// asaot.ui.kind.SelectWidget -- the trigger + dropdown behaviour for SelectNode.
//
// The dropdown is a CHILD and its visibility comes from the descriptor, so this
// widget never hides or shows anything: `open` travels through the descriptor tree
// like every other property. What the widget owns is
//
//   1. the dropdown's INSETS -- flush under the trigger, as wide as the trigger,
//      written in measure from the trigger's own solved height (so a taller trigger
//      moves the dropdown with it and no constant goes stale);
//   2. the CARET -- a filled triangle in shapeA, i.e. behind the label child;
//   3. the HIT ROUTING -- a row click selects and closes, a trigger click toggles.
//
// CLICKS ARE ROUTED BY GEOMETRY, NOT BY TARGET. A click on a row bubbles up through
// the dropdown to this node's backing, exactly like a click on the label, so
// `e.target` cannot tell them apart. Testing the point against the dropdown's own
// child rects can (and does): rows first, then the trigger, then nothing.
package asaot.ui.kind
{
    import asaot.ui.LayoutConstants;
    import asaot.ui.Node;
    import asaot.ui.OverlayChrome;
    import asaot.ui.OverlayList;
    import asaot.ui.PaintKit;
    import asaot.ui.OverlayMotion;
    import asaot.ui.SelectNode;
    import asaot.ui.UiNode;
    import asaot.ui.WidgetKeys;
    import flash.display.Shape;
    import asaot.ui.Widget;

    import flash.events.MouseEvent;

    public class SelectWidget implements Widget, WidgetKeys
    {
        private static const OPEN_KEY:String = "open";
        private static const SEL_FN:String = "onSelect";
        private static const OPEN_FN:String = "onOpenChange";
        private static const HIT_KEY:String = "hit";
        private static const ACT_KEY:String = "actRow";
        private static const BAND_KEY:String = "bandShape";

        public function build(n:UiNode):void
        {
            n.extra[OPEN_KEY] = false;
            n.extra[SEL_FN] = null;
            n.extra[OPEN_FN] = null;
            // One Shape at child INDEX 0 holds the panel/trigger background;
            // PaintKit.paintBox draws nothing without it, so the surface used to
            // have a correct solved rect and paint nothing at all. Same layout as
            // BoxWidget: the shape is added in build(), before the reconciler
            // appends this node's children, so the children keep a stable base
            // index for display-order repair.
            n.shapeA = new Shape();
            n.backing.addChild(n.shapeA);
            n.extra[HIT_KEY] = 0;
            n.extra[ACT_KEY] = -1;
            n.extra[BAND_KEY] = null;
            var self:SelectWidget = this;
            n.listen(n.backing, MouseEvent.CLICK,
                function (e:MouseEvent):void { self.onClickAt(n, e); });
        }

        public function payload(n:UiNode, desc:Node):Boolean
        {
            var s:SelectNode = SelectNode(desc);
            n.extra[SEL_FN] = s.onSelect;
            n.extra[OPEN_FN] = s.onOpenChange;
            n.onChange = s.onSelect;
            var wasOpen:Boolean = Boolean(n.extra[OPEN_KEY]);
            n.extra[OPEN_KEY] = s.open;
            // The dropdown gets the same entrance as every other floating surface
            // (see OverlayMotion), armed on the open flip only.
            if (!wasOpen && s.open) OverlayMotion.start(n);
            this.liftForPopup(n, wasOpen, s.open);
            // The dropdown's visibility rides on its own child node, so `open` needs
            // no relayout from here; a width change arrives as a style diff.
            return false;
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
            var drop:UiNode = n.children[n.children.length - 1];
            if (drop.engineNode == null) return;
            var eng:* = n.app.engine;
            var e:* = drop.engineNode;
            // Flush left with the trigger and directly below it. `absH` is the
            // trigger's solved height from the previous arrange -- always available
            // because the trigger itself is never hidden.
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
            this.paintActiveBand(n);
            if (n.children.length > 0)
            {
                var drop:UiNode = n.children[n.children.length - 1];
                if (drop.backing != null) OverlayMotion.apply(n, drop, drop, 0, 6);
            }
            if (n.shapeA == null) return;
            // The caret: a filled triangle at the right, inside the trigger's own
            // 10px horizontal padding. Filled, not stroked, because a fill is
            // integer-exact and a probe can assert it. (Stroke width IS honoured on
            // this backend; re-measured 2026-10-25, see probes/widgets/icon.)
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

        // ---- keyboard ------------------------------------------------------
        // Arrows move an ACTIVE row; Enter/Space activates it (choosing it and
        // closing, exactly like a click); Escape closes. When the dropdown is shut,
        // Down/Enter opens it at the current value.
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
                if (act >= 0 && act < rows) this.choose(n, act);
                else this.close(n, false);
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

        private function choose(n:UiNode, row:int):void
        {
            var sel:Function = n.extra[SEL_FN];
            if (sel != null) sel(row);
            this.close(n, false);
        }

        private function close(n:UiNode, open:Boolean):void
        {
            n.extra[ACT_KEY] = -1;
            var f:Function = n.extra[OPEN_FN];
            if (f != null) f(open);
        }

        // The active row's band. It MUST live on a shape inside the DROPDOWN, above
        // the dropdown's own background and below its rows: drawing it on the
        // select's shapeA would put it under the dropdown's opaque white, and drawing
        // it into drop.shapeA from here is undone anyway by the dropdown's own paint,
        // which runs AFTER its parent.
        //
        // The shape is created once and inserted at `drop.internalCount`, the exact
        // slot the reconciler's display-order repair treats as "before the UiNode
        // children" (see Reconciler.fixDisplayOrder).
        private function paintActiveBand(n:UiNode):void
        {
            var drop:UiNode = n.children.length > 0 ? n.children[n.children.length - 1] : null;
            if (drop == null || drop.backing == null) return;
            var raw:Object = drop.extra[BAND_KEY];
            var sh:Shape;
            if (raw == null)
            {
                sh = new Shape();
                drop.backing.addChildAt(sh, drop.internalCount);
                drop.internalCount = drop.internalCount + 1;
                drop.extra[BAND_KEY] = sh;
            }
            else sh = Shape(raw);
            sh.graphics.clear();
            var act:int = int(Number(n.extra[ACT_KEY]));
            if (!Boolean(n.extra[OPEN_KEY]) || act < 0 || act >= drop.children.length) return;
            var r:UiNode = drop.children[act];
            sh.graphics.beginFill(OverlayChrome.ITEM_HOVER, 1.0);
            sh.graphics.drawRect(r.absX - drop.absX, r.absY - drop.absY, r.absW, r.absH);
            sh.graphics.endFill();
        }

        private function onClickAt(n:UiNode, e:MouseEvent):void
        {
            n.extra[HIT_KEY] = 0;
            var open:Boolean = Boolean(n.extra[OPEN_KEY]);
            var drop:UiNode = n.children.length > 0 ? n.children[n.children.length - 1] : null;

            if (open && drop != null)
            {
                // The point in the DROPDOWN's own space: see OverlayList.localYIn --
                // e.localY is relative to whatever was actually hit (the row), not to
                // this node.
                var row:int = OverlayList.rowAt(drop, OverlayList.localYIn(drop, e));
                if (row >= 0)
                {
                    n.extra[HIT_KEY] = 1;
                    var sel:Function = n.extra[SEL_FN];
                    if (sel != null) sel(row);
                    var oc:Function = n.extra[OPEN_FN];
                    if (oc != null) oc(false);
                    return;
                }
            }
            // A click on the trigger toggles. Rows are only reachable while open, so
            // a click that fell through the row test cannot be a stale row click.
            n.extra[HIT_KEY] = 1;
            var f:Function = n.extra[OPEN_FN];
            if (f != null) f(!open);
        }
    }
}
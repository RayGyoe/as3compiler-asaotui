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
    import asaot.ui.SelectNode;
    import asaot.ui.UiNode;
    import flash.display.Shape;
    import asaot.ui.Widget;

    import flash.events.MouseEvent;

    public class SelectWidget implements Widget
    {
        private static const OPEN_KEY:String = "open";
        private static const SEL_FN:String = "onSelect";
        private static const OPEN_FN:String = "onOpenChange";
        private static const HIT_KEY:String = "hit";

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
            var self:SelectWidget = this;
            n.backing.addEventListener(MouseEvent.CLICK,
                function (e:MouseEvent):void { self.onClickAt(n, e); });
        }

        public function payload(n:UiNode, desc:Node):Boolean
        {
            var s:SelectNode = SelectNode(desc);
            n.extra[SEL_FN] = s.onSelect;
            n.extra[OPEN_FN] = s.onOpenChange;
            n.onChange = s.onSelect;
            n.extra[OPEN_KEY] = s.open;
            // The dropdown's visibility rides on its own child node, so `open` needs
            // no relayout from here; a width change arrives as a style diff.
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
            if (n.shapeA == null) return;
            // The caret: a filled triangle at the right, inside the trigger's own
            // 10px horizontal padding. Filled, not stroked -- stroke width is not
            // honoured on this backend.
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
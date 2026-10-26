// asaot.ui.kind.SplitPaneWidget -- sizes two panes around a drag handle.
//
// THE PANES ARE ORDINARY CHILD NODES. This widget owns exactly two things:
//
//   1. the MAIN-AXIS sizes of children 0, 1 and 2, written in `measure` from the
//      container's own solved size and the author's `ratio`;
//   2. the drag: a press whose point lands on the divider (plus GRAB points either
//      side) starts a stage gesture that reports `onResize(ratio)` on every move
//      and on release.
//
// WHY `setFlex(grow=0, shrink=0, basis=px)` AND NOT `setSize`: a flex item with a
// definite width can still shrink when its content overflows, so a pane whose
// content is wider than the share would quietly eat the other one. Pinning the
// basis with grow/shrink at 0 makes the share absolute -- which is what a splitter
// promises, and what makes the probe's rect assertions meaningful.
//
// WHY THE RATIO COMES FROM THE CHILDREN'S SOLVED RECTS AND NOT FROM `absW`: the
// container may carry padding, and the ruler that matters is the one the engine
// used. `origin` is the first pane's leading edge and `avail` is the distance from
// it to the second pane's trailing edge, minus the divider -- so a padded splitter
// needs no extra arithmetic here.
//
// WHY THE DRAG LISTENS ON THE STAGE: the runtime sends motion to whatever is under
// the POINTER, so a drag that leaves the 6px grip would stop receiving moves. That
// is the same pointer capture SliderWidget / ScrollViewWidget / TableWidget build by
// hand. The closures are stored on `n.extra` so `teardown` can remove them BY
// REFERENCE -- a stage listener that outlives its node is a bug this codebase
// already paid for once.
package asaot.ui.kind
{
    import asaot.ui.Dirty;
    import asaot.ui.LayoutConstants;
    import asaot.ui.Node;
    import asaot.ui.OverlayList;
    import asaot.ui.PaintKit;
    import asaot.ui.SplitPaneNode;
    import asaot.ui.UiNode;
    import asaot.ui.Widget;
    import asaot.ui.WidgetTeardown;

    import flash.display.Shape;
    import flash.display.Stage;
    import flash.events.MouseEvent;

    public class SplitPaneWidget implements Widget, WidgetTeardown
    {
        private static const ROW_KEY:String = "row";
        private static const RATIO_KEY:String = "ratio";
        private static const MIN_KEY:String = "min";
        private static const DIV_KEY:String = "div";
        private static const FN_KEY:String = "onResize";
        private static const MOVE_FN:String = "dragMove";
        private static const UP_FN:String = "dragUp";
        private static const LAST_KEY:String = "lastRatio";
        private static const GRAB:Number = 2;            // hit slack either side of the grip

        public function build(n:UiNode):void
        {
            // Nothing is painted by this node itself, but PaintKit.paintBox needs a
            // shape when the author gives the splitter a background; the same
            // arrangement as BoxWidget keeps the child base index stable.
            n.shapeA = new Shape();
            n.backing.addChild(n.shapeA);
            n.extra[ROW_KEY] = 1;
            n.extra[RATIO_KEY] = 0.5;
            n.extra[MIN_KEY] = 40;
            n.extra[DIV_KEY] = 6;
            n.extra[FN_KEY] = null;
            n.extra[MOVE_FN] = null;
            n.extra[UP_FN] = null;
            n.extra[LAST_KEY] = 0.5;

            var self:SplitPaneWidget = this;
            n.listen(n.backing, MouseEvent.MOUSE_DOWN,
                function (e:MouseEvent):void { self.onPress(n, e); });
        }

        public function payload(n:UiNode, desc:Node):Boolean
        {
            var s:SplitPaneNode = SplitPaneNode(desc);
            var relayout:Boolean = false;
            var row:int = s.direction == "row" ? 1 : 0;
            if (int(Number(n.extra[ROW_KEY])) != row) { n.extra[ROW_KEY] = row; relayout = true; }
            if (!sameNumber(n.extra[RATIO_KEY], s.ratio)) { n.extra[RATIO_KEY] = s.ratio; relayout = true; }
            if (!sameNumber(n.extra[MIN_KEY], s.minSize)) { n.extra[MIN_KEY] = s.minSize; relayout = true; }
            if (!sameNumber(n.extra[DIV_KEY], s.dividerSize)) { n.extra[DIV_KEY] = s.dividerSize; relayout = true; }
            n.extra[FN_KEY] = s.onResize;
            return relayout;
        }

        public function wantsPress():Boolean { return false; }

        public function measure(n:UiNode):void
        {
            if (n.engineNode == null || n.children.length < 3) return;
            var first:UiNode = n.children[0];
            var div:UiNode = n.children[1];
            var second:UiNode = n.children[2];
            if (first.engineNode == null || div.engineNode == null || second.engineNode == null) return;

            var row:Boolean = Number(n.extra[ROW_KEY]) != 0;
            var total:Number = row ? n.absW : n.absH;
            // Nothing solved yet (the first frame of a new subtree), so the styles the
            // factory wrote are the best available answer -- writing bases from a 0
            // total would collapse both panes to `minSize`.
            if (!(total > 0)) return;

            var dv:Number = Number(n.extra[DIV_KEY]);
            var avail:Number = total - dv;
            if (avail <= 1) return;

            var minS:Number = Number(n.extra[MIN_KEY]);
            if (!(minS > 0)) minS = 0;
            // Two minimums wider than the space cannot both hold; halve the demand
            // rather than handing one pane a negative share.
            if (minS * 2 > avail) minS = Math.floor(avail / 2);

            var r:Number = Number(n.extra[RATIO_KEY]);
            if (isNaN(r)) r = 0.5;
            var w1:Number = Math.round(avail * r);
            if (w1 < minS) w1 = minS;
            if (w1 > avail - minS) w1 = avail - minS;

            var eng:* = n.app.engine;
            eng.setFlex(first.engineNode, 0, 0, w1, LayoutConstants.UNIT_POINT);
            eng.setFlex(div.engineNode, 0, 0, dv, LayoutConstants.UNIT_POINT);
            eng.setFlex(second.engineNode, 0, 0, avail - w1, LayoutConstants.UNIT_POINT);
        }

        public function arrange(n:UiNode):void { }

        public function paint(n:UiNode):void
        {
            PaintKit.paintBox(n, n.resolved, PaintKit.w1(n), PaintKit.h1(n));
        }

        public function click(n:UiNode):Boolean { return false; }

        public function teardown(n:UiNode):void
        {
            if (n.extra == null) return;
            this.removeStage(n);
        }

        // ---- drag ----------------------------------------------------------
        private function onPress(n:UiNode, e:MouseEvent):void
        {
            // A gesture whose release was lost (a teardown mid-drag, a dropped event)
            // must not survive into the next press.
            this.removeStage(n);
            if (n.children.length < 3) return;
            var div:UiNode = n.children[1];
            if (div.backing == null) return;

            var row:Boolean = Number(n.extra[ROW_KEY]) != 0;
            var along:Number = row ? OverlayList.localXIn(n, e) : OverlayList.localYIn(n, e);
            if (isNaN(along)) return;
            var lead:Number = row ? div.absX - n.absX : div.absY - n.absY;
            var thick:Number = row ? div.absW : div.absH;
            if (along < lead - GRAB || along > lead + thick + GRAB) return;

            var st:Stage = n.app != null ? n.app.stage : null;
            if (st == null) return;
            n.extra[LAST_KEY] = Number(n.extra[RATIO_KEY]);
            var self:SplitPaneWidget = this;
            var mv:Function = function (ev:MouseEvent):void { self.onDragMove(n, ev); };
            var upFn:Function = function (ev:MouseEvent):void { self.onDragEnd(n); };
            n.extra[MOVE_FN] = mv;
            n.extra[UP_FN] = upFn;
            st.addEventListener(MouseEvent.MOUSE_MOVE, mv);
            st.addEventListener(MouseEvent.MOUSE_UP, upFn);
        }

        private function onDragMove(n:UiNode, e:MouseEvent):void
        {
            if (n.extra[UP_FN] == null) return;
            if (n.children.length < 3) return;
            var row:Boolean = Number(n.extra[ROW_KEY]) != 0;
            var first:UiNode = n.children[0];
            var second:UiNode = n.children[2];
            var dv:Number = Number(n.extra[DIV_KEY]);

            // The ruler the ENGINE used, not `absW`: padding on the splitter (or a
            // pane with a margin) would otherwise shift the 0 point.
            var origin:Number = row ? first.absX - n.absX : first.absY - n.absY;
            var end:Number = row
                ? second.absX - n.absX + second.absW
                : second.absY - n.absY + second.absH;
            var avail:Number = end - origin - dv;
            if (!(avail > 1)) return;

            var pos:Number = row ? OverlayList.localXIn(n, e) : OverlayList.localYIn(n, e);
            if (isNaN(pos)) return;
            var r:Number = (pos - origin) / avail;

            var minS:Number = Number(n.extra[MIN_KEY]);
            if (!(minS > 0)) minS = 0;
            if (minS * 2 > avail) minS = Math.floor(avail / 2);
            var lo:Number = avail > 0 ? minS / avail : 0;
            var hi:Number = 1 - lo;
            if (r < lo) r = lo;
            if (r > hi) r = hi;

            // Report only on a real change: a MOUSE_MOVE stream is per-pixel, and the
            // author re-describes on every reported ratio.
            if (Math.abs(r - Number(n.extra[LAST_KEY])) < 0.0005) return;
            n.extra[LAST_KEY] = r;
            var f:Function = n.extra[FN_KEY] as Function;
            if (f != null) f(r);
        }

        private function onDragEnd(n:UiNode):void
        {
            var r:Number = Number(n.extra[LAST_KEY]);
            this.removeStage(n);
            // The release reports too: a press-and-release without motion is still an
            // intentional "put the splitter here" in some UIs, and swallowing it would
            // make a click on the grip do nothing at all.
            var f:Function = n.extra[FN_KEY] as Function;
            if (f != null) f(r);
        }

        private function removeStage(n:UiNode):void
        {
            var st:Stage = n.app != null ? n.app.stage : null;
            var mv:Function = n.extra[MOVE_FN] as Function;
            var upFn:Function = n.extra[UP_FN] as Function;
            if (st != null)
            {
                if (mv != null) st.removeEventListener(MouseEvent.MOUSE_MOVE, mv);
                if (upFn != null) st.removeEventListener(MouseEvent.MOUSE_UP, upFn);
            }
            n.extra[MOVE_FN] = null;
            n.extra[UP_FN] = null;
        }

        // NaN never equals itself; "still the old value" must not look like a change.
        private static function sameNumber(a:Object, b:Number):Boolean
        {
            var x:Number = Number(a);
            if (isNaN(x) && isNaN(b)) return true;
            return x == b;
        }
    }
}
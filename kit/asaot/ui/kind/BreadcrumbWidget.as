// asaot.ui.kind.BreadcrumbWidget -- the container for BreadcrumbNode.
//
// The crumb and separator labels are CHILD UiNodes the factory made and the
// reconciler mounted; the layout engine places them (so the trail's widths come
// from the text, not from arithmetic). `build` owns only the background shape and
// the click listener; `measure`/`arrange`/`paint` have nothing of their own to do.
//
// HOW A CLICK BECOMES A CRUMB: the crumbs are the direct children whose `role` is
// "link" (separators carry "separator"), so walking the children in order and
// counting only the links gives the crumb index -- no key parsing, no width guess.
// The x test uses each child's laid-out rect, so a click on a separator or in the
// gap between crumbs navigates nowhere (a click on the CURRENT crumb is delivered
// but nothing happens: there is nowhere to navigate to).
package asaot.ui.kind
{
    import asaot.ui.BreadcrumbNode;
    import asaot.ui.Dirty;
    import asaot.ui.Node;
    import asaot.ui.PaintKit;
    import asaot.ui.UiNode;
    import asaot.ui.Widget;

    import flash.display.Shape;
    import flash.events.MouseEvent;

    public class BreadcrumbWidget implements Widget
    {
        private static const HIT_KEY:String = "hit";   // 1 when the last click hit a link
        private static const CUR_KEY:String = "cur";   // resolved current crumb index

        private static const ROLE_LINK:String = "link";

        public function build(n:UiNode):void
        {
            n.shapeA = new Shape();
            n.backing.addChild(n.shapeA);
            n.extra[HIT_KEY] = 0;
            n.extra[CUR_KEY] = -1;

            var self:BreadcrumbWidget = this;
            n.listen(n.backing, MouseEvent.CLICK,
                function (e:MouseEvent):void { self.onClickX(n, e); });
        }

        public function payload(n:UiNode, desc:Node):Boolean
        {
            var b:BreadcrumbNode = BreadcrumbNode(desc);
            n.onChange = b.onNavigate;
            // The resolved current index (the last crumb when the author left it -1)
            // is what makes "this crumb is not navigable" answerable at click time.
            var count:int = b.items == null ? 0 : b.items.length;
            var cur:int = b.currentIndex >= 0 ? int(b.currentIndex) : count - 1;
            n.extra[CUR_KEY] = cur;
            // Nothing here is this widget's own geometry: the labels are children and
            // the trail is sized by the engine.
            return false;
        }

        public function wantsPress():Boolean { return true; }

        public function measure(n:UiNode):void
        {
            // The engine sizes the container from its labels (see BoxWidget).
        }

        public function arrange(n:UiNode):void
        {
            // Labels are placed by the engine; nothing internal to position.
        }

        public function paint(n:UiNode):void
        {
            PaintKit.paintBox(n, n.resolved, PaintKit.w1(n), PaintKit.h1(n));
        }

        public function click(n:UiNode):Boolean
        {
            var hit:* = n.extra[HIT_KEY];
            return hit != null && Boolean(hit);
        }

        private function onClickX(n:UiNode, e:MouseEvent):void
        {
            n.extra[HIT_KEY] = 0;
            var cur:int = int(Number(n.extra[CUR_KEY]));
            var target:int = -1;
            var k:int = -1;
            for (var i:int = 0; i < n.children.length; i++)
            {
                var c:UiNode = n.children[i];
                if (c.role != ROLE_LINK) continue;
                k = k + 1;
                var left:Number = c.backing.x;
                if (e.localX >= left && e.localX < left + c.absW) { target = k; break; }
            }
            if (target < 0) return;

            n.extra[HIT_KEY] = 1;
            if (target == cur) return;   // the current crumb: consumed, nothing to do
            n.app.markPaint(n);
            if (n.onChange != null) n.onChange(target);
            n.app.invalidate(Dirty.VALUE);
        }
    }
}
// asaot.ui.kind.BoxWidget -- a pure container.
//
// The backing Sprite IS the box; one Shape at child index 0 holds the
// background/border, so the UiNode children keep a stable base index for
// display-order repair.
package asaot.ui.kind
{
    import asaot.ui.BoxNode;
    import asaot.ui.PaintKit;
    import asaot.ui.UiNode;
    import asaot.ui.Widget;
    import asaot.ui.Node;

    import flash.display.Shape;

    public class BoxWidget implements Widget
    {
        public function build(n:UiNode):void
        {
            n.shapeA = new Shape();
            n.backing.addChild(n.shapeA);
        }

        public function payload(n:UiNode, desc:Node):Boolean
        {
            var d:String = BoxNode(desc).direction;
            if (d != n.directionOverride)
            {
                n.directionOverride = d;
                // A direction change is a layout change.
                return true;
            }
            return false;
        }

        public function wantsPress():Boolean { return false; }

        public function measure(n:UiNode):void { }

        public function arrange(n:UiNode):void { }

        public function paint(n:UiNode):void
        {
            PaintKit.paintBox(n, n.resolved, PaintKit.w1(n), PaintKit.h1(n));
        }

        public function click(n:UiNode):Boolean { return false; }
    }
}
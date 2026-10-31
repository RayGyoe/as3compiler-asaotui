// asaot.ui.kind.AppBarWidget -- the bar's SURFACE and its CLIP.
//
// Two jobs, both of them the node's own box rather than its contents:
//
//   * paint the background/border from `n.resolved` -- a container is the only
//     kind that can, because the factory hands the bar's colour to the NODE and not
//     to the rows inside (which must stay transparent so the bar reads as one
//     surface behind the safe-area inset too);
//   * clip the contents to that box (see below).
//
// THE ONE JOB IS CLIPPING. While a large title is being collapsed, the extra area
// shrinks below the title's own height, and an unclipped text node would spill
// over the page below the bar -- visible as text hanging in the middle of the
// content for the whole gesture. ScrollViewWidget already answers this with a
// scrollRect on the node's own backing, and the same answer is right here: the
// bar's box IS its viewport, and everything inside it must be cut at that edge.
//
// It also means the bar can be given a fixed height by a parent without the large
// title drawing outside it.
package asaot.ui.kind
{
    import asaot.ui.Node;
    import asaot.ui.UiNode;
    import asaot.ui.Widget;

    import asaot.ui.PaintKit;
    import asaot.ui.style.Style;

    import flash.display.Shape;
    import flash.geom.Rectangle;

    public class AppBarWidget implements Widget
    {
        private static const CLIP:String = "clip";   // the reused Rectangle

        public function build(n:UiNode):void
        {
            // Shape at child index 0, like every container (see BoxWidget): the UiNode
            // children keep a stable base index for display-order repair.
            n.shapeA = new Shape();
            n.backing.addChild(n.shapeA);
        }

        public function payload(n:UiNode, desc:Node):Boolean
        {
            return false;   // every size in the bar comes from the description
        }

        public function wantsPress():Boolean { return false; }

        public function measure(n:UiNode):void
        {
            // The factory's boxes are the layout: a column of fixed rows, so the
            // node's own height is their sum and needs no intrinsic size here.
        }

        public function arrange(n:UiNode):void
        {
        }

        public function paint(n:UiNode):void
        {
            var s:Style = n.resolved;
            PaintKit.paintBox(n, s, PaintKit.w1(n), PaintKit.h1(n));
            PaintKit.decorate(n);

            var r:Rectangle = n.extra[CLIP] as Rectangle;
            if (r == null)
            {
                r = new Rectangle(0, 0, n.absW, n.absH);
                n.extra[CLIP] = r;
            }
            if (r.width != n.absW || r.height != n.absH)
            {
                r.width = n.absW;
                r.height = n.absH;
            }
            n.backing.scrollRect = r;
        }

        public function click(n:UiNode):Boolean
        {
            return false;
        }
    }
}

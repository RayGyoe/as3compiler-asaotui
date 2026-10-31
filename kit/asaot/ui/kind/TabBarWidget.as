// asaot.ui.kind.TabBarWidget -- the registered KIND for TabBarNode. Its one job is
// the surface; every behaviour is in the description.
//
// Everything a tab bar does is in the description the factory builds: the cells are
// equal-width boxes, the selected state is the tint patch on each cell, and a tap
// is the cell's own `onClick` (see OptionSupport.tapIndex for why that handler is
// built by a factory and not inline in the loop).
//
// A no-op widget is still the right shape: the kind has to exist for
// `Widgets.register`, the node still needs to reconcile and lay out, and an empty
// implementation is honest about where the behaviour lives instead of spreading it
// over two files.
package asaot.ui.kind
{
    import asaot.ui.Node;
    import asaot.ui.PaintKit;
    import asaot.ui.UiNode;
    import asaot.ui.Widget;
    import asaot.ui.style.Style;

    import flash.display.Shape;

    public class TabBarWidget implements Widget
    {
        public function build(n:UiNode):void
        {
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
        }

        public function arrange(n:UiNode):void
        {
        }

        public function paint(n:UiNode):void
        {
            // The BACKGROUND is the node's (the factory puts the theme's surface there
            // and the author may override it); the cells paint nothing, so the bar
            // reads as one surface behind the safe-area inset too.
            var s:Style = n.resolved;
            PaintKit.paintBox(n, s, PaintKit.w1(n), PaintKit.h1(n));
            PaintKit.decorate(n);
        }

        public function click(n:UiNode):Boolean
        {
            return false;
        }
    }
}

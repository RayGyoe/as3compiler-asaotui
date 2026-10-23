// asaot.ui.kind.CheckboxWidget -- indicator box + label.
//
// Owns TWO shapes: `shapeA` draws the indicator, `shapeB` the check mark, so the
// mark is not clipped by the indicator's rounded-rect path. The label is a hand
// placed TextField 22pt in (16pt indicator + 6pt gap).
//
// This is the one built-in kind whose `click` CONSUMES the click (it toggles
// itself and writes back through its Binding); every other kind lets
// `UiNode.handleClick` fall through to the author's `onClick`.
package asaot.ui.kind
{
    import asaot.ui.CheckboxNode;
    import asaot.ui.Dirty;
    import asaot.ui.PaintKit;
    import asaot.ui.UiNode;
    import asaot.ui.Widget;
    import asaot.ui.Node;
    import asaot.ui.style.Style;

    import asaot.ui.LayoutConstants;

    import flash.display.Shape;

    public class CheckboxWidget implements Widget
    {
        public function build(n:UiNode):void
        {
            n.shapeA = new Shape();   // indicator box
            n.backing.addChild(n.shapeA);
            n.shapeB = new Shape();   // check mark
            n.backing.addChild(n.shapeB);
            n.tf = PaintKit.makeText(false);
            n.backing.addChild(n.tf);
        }

        public function payload(n:UiNode, desc:Node):Boolean
        {
            var cb:CheckboxNode = CheckboxNode(desc);
            n.label = cb.label;
            n.onChange = cb.onChange;
            n.onClick = cb.onClick;
            n.binding = cb.binding;
            var cv:Boolean = cb.checked;
            if (cb.binding != null)
            {
                // `*`, NOT `Object`: a binding value can be anything, and an `Object`
                // slot BOXES it (one allocation per read). Both of the old reasons to
                // spell this `*` are now historical -- G9 (Boolean lowering) is FIXED in
                // 阶段二四八 and G14 (Array identity) in 阶段二百五十三 -- so `*` is simply
                // the cheapest correct default for "a value of unknown type".
                var bv:* = cb.binding.get();
                cv = bv != null && Boolean(bv);
            }
            if (cv != n.checked)
            {
                n.checked = cv;
                n.dirty |= Dirty.M_PAINT;
            }
            return false;
        }

        public function wantsPress():Boolean { return true; }

        public function measure(n:UiNode):void
        {
            if (n.tf == null) return;
            var s:Style = n.resolved;
            PaintKit.measureField(n, n.tf, n.label, s);
            // 22 = the box + the gap before the label (see `arrange`).
            if (PaintKit.autoW(s))
            {
                PaintKit.setPointSize(n, LayoutConstants.AXIS_WIDTH, 22 + n.state.measuredW);
            }
            if (PaintKit.autoH(s))
            {
                var h:Number = n.state.measuredH;
                if (h < 18) h = 18;
                PaintKit.setPointSize(n, LayoutConstants.AXIS_HEIGHT, h);
            }
        }

        public function arrange(n:UiNode):void
        {
            if (n.tf == null) return;
            n.tf.x = 22;
            n.tf.y = (n.absH - n.state.measuredH) / 2;
        }

        public function paint(n:UiNode):void
        {
            var s:Style = n.resolved;
            var h:Number = n.absH;
            var box:Number = 16;
            var cy:Number = (h - box) / 2;
            var on:Boolean = n.checked;
            if (n.shapeA != null)
            {
                var g:Object = n.shapeA.graphics;
                g.clear();
                g.lineStyle(1, on ? 0x2F80ED : 0xBBBBBB, 1.0);
                g.beginFill(on ? 0x2F80ED : 0xFFFFFF, 1.0);
                g.drawRoundRect(0, cy, box, box, 3, 3);
                g.endFill();
            }
            if (n.shapeB != null)
            {
                var g2:Object = n.shapeB.graphics;
                g2.clear();
                if (on)
                {
                    g2.lineStyle(2, 0xFFFFFF, 1.0);
                    g2.moveTo(4, cy + 8);
                    g2.lineTo(7, cy + 12);
                    g2.lineTo(13, cy + 4);
                }
            }
            if (n.tf != null && s.text.color >= 0) n.tf.textColor = uint(s.text.color);
        }

        public function click(n:UiNode):Boolean
        {
            var next:Boolean = !n.checked;
            n.checked = next;
            if (n.binding != null) n.binding.set(next);
            else if (n.onChange != null) n.onChange();
            n.app.invalidate(Dirty.VALUE);
            return true;
        }
    }
}
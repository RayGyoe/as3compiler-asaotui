// asaot.ui.kind.RadioWidget -- outer ring + inner dot + label.
//
// Structurally a sibling of CheckboxWidget: `shapeA` draws the ring (and the
// white interior), `shapeB` the inner dot so the dot is not clipped by the
// ring's own path. The label is a hand-placed TextField 22pt in (16pt indicator
// + 6pt gap), matching the checkbox.
//
// DISCIPLINE (ChipWidget):
//   * `label` is mirrored onto the node and a change returns TRUE from
//     `payload` -- the intrinsic width follows the text (a layout change);
//   * `selected` is a DECORATION: a change raises only Dirty.M_PAINT, so a
//     selection never re-solves layout.
//
// Clicking SELECTS and CONSUMES the click (like CheckboxWidget): it writes back
// through the Binding (or calls onChange) and the author's `onClick` does not
// additionally fire.
package asaot.ui.kind
{
    import asaot.ui.RadioNode;
    import asaot.ui.Dirty;
    import asaot.ui.PaintKit;
    import asaot.ui.UiNode;
    import asaot.ui.Widget;
    import asaot.ui.Node;
    import asaot.ui.style.Style;

    import asaot.ui.LayoutConstants;

    import flash.display.Shape;

    public class RadioWidget implements Widget
    {
        public function build(n:UiNode):void
        {
            n.shapeA = new Shape();   // outer ring + interior
            n.backing.addChild(n.shapeA);
            n.shapeB = new Shape();   // inner dot
            n.backing.addChild(n.shapeB);
            n.tf = PaintKit.makeText(false);
            n.backing.addChild(n.tf);
        }

        public function payload(n:UiNode, desc:Node):Boolean
        {
            var r:RadioNode = RadioNode(desc);
            var relayout:Boolean = false;
            if (r.label != n.label)
            {
                n.label = r.label;
                relayout = true;      // indicator+label grows with the text
            }
            n.onChange = r.onChange;
            n.onClick = r.onClick;
            n.binding = r.binding;
            var sv:Boolean = r.selected;
            if (r.binding != null)
            {
                // `*`, NOT `Object`: a binding value can be anything, and an `Object`
                // slot BOXES it (one allocation per read). Both of the old reasons to
                // spell this `*` are now historical -- G9 (Boolean lowering) is FIXED in
                // 阶段二四八 and G14 (Array identity) in 阶段二百五十三 -- so `*` is simply
                // the cheapest correct default for "a value of unknown type".
                var bv:* = r.binding.get();
                sv = bv != null && Boolean(bv);
            }
            if (sv != n.checked)
            {
                n.checked = sv;
                n.dirty |= Dirty.M_PAINT;   // decoration only: never a reflow
            }
            return relayout;
        }

        public function wantsPress():Boolean { return true; }

        public function measure(n:UiNode):void
        {
            if (n.tf == null) return;
            var s:Style = n.resolved;
            PaintKit.measureField(n, n.tf, n.label, s);
            // 22 = the 16pt indicator + the 6pt gap (see `arrange`).
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
            var cy:Number = (n.absH - 16) / 2 + 8;   // indicator centre y
            var on:Boolean = n.checked;
            if (n.shapeA != null)
            {
                var g:Object = n.shapeA.graphics;
                g.clear();
                g.beginFill(0xFFFFFF, 1.0);
                g.lineStyle(2, on ? 0x2563EB : 0x9CA3AF, 1.0);
                g.drawCircle(8, cy, 7);
                g.endFill();
            }
            if (n.shapeB != null)
            {
                var g2:Object = n.shapeB.graphics;
                g2.clear();
                if (on)
                {
                    g2.beginFill(0x2563EB, 1.0);
                    g2.drawCircle(8, cy, 4);
                    g2.endFill();
                }
            }
            if (n.tf != null && s.text.color >= 0) n.tf.textColor = uint(s.text.color);
        }

        public function click(n:UiNode):Boolean
        {
            // A radio SELECTS; it does not toggle off on a second click.
            if (!n.checked)
            {
                n.checked = true;
                if (n.binding != null) n.binding.set(true);
                else if (n.onChange != null) n.onChange();
                n.app.invalidate(Dirty.VALUE);
            }
            return true;   // consumed: the author's onClick must not also fire
        }
    }
}
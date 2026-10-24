// asaot.ui.kind.SwitchWidget -- a pill track with a knob.
//
// Two shapes: `shapeA` is the 36x20 rounded track (green when on, grey when
// off), `shapeB` the white knob. The knob's x is a DECORATION of `checked`: it
// is recomputed inside `paint` (checked is a paint-only change), so toggling
// never re-solves layout and there is no knob state to keep in `arrange`.
//
// Clicking toggles and CONSUMES the click (writes back through the Binding, or
// calls onChange). Same discipline as CheckboxWidget.
package asaot.ui.kind
{
    import asaot.ui.SwitchNode;
    import asaot.ui.Dirty;
    import asaot.ui.PaintKit;
    import asaot.ui.UiNode;
    import asaot.ui.Widget;
    import asaot.ui.Node;
    import asaot.ui.style.Style;

    import asaot.ui.LayoutConstants;

    import flash.display.Shape;

    public class SwitchWidget implements Widget
    {
        public function build(n:UiNode):void
        {
            n.shapeA = new Shape();   // track
            n.backing.addChild(n.shapeA);
            n.shapeB = new Shape();   // knob
            n.backing.addChild(n.shapeB);
            n.tf = PaintKit.makeText(false);
            n.backing.addChild(n.tf);
        }

        public function payload(n:UiNode, desc:Node):Boolean
        {
            var sw:SwitchNode = SwitchNode(desc);
            var relayout:Boolean = false;
            if (sw.label != n.label)
            {
                n.label = sw.label;
                relayout = true;      // track+label grows with the text
            }
            n.onChange = sw.onChange;
            n.onClick = sw.onClick;
            n.binding = sw.binding;
            var cv:Boolean = sw.checked;
            if (sw.binding != null)
            {
                // `*`, NOT `Object`: a binding value can be anything, and an `Object`
                // slot BOXES it (one allocation per read). Both of the old reasons to
                // spell this `*` are now historical -- G9 (Boolean lowering) is FIXED in
                // 阶段二四八 and G14 (Array identity) in 阶段二百五十三 -- so `*` is simply
                // the cheapest correct default for "a value of unknown type".
                var bv:* = sw.binding.get();
                cv = bv != null && Boolean(bv);
            }
            if (cv != n.checked)
            {
                n.checked = cv;
                n.dirty |= Dirty.M_PAINT;   // the knob moves: paint only
            }
            return relayout;
        }

        public function wantsPress():Boolean { return true; }

        public function measure(n:UiNode):void
        {
            if (n.tf == null) return;
            var s:Style = n.resolved;
            PaintKit.measureField(n, n.tf, n.label, s);
            // 42 = the 36pt track + the 6pt gap before the label (see paint/arrange).
            if (PaintKit.autoW(s))
            {
                PaintKit.setPointSize(n, LayoutConstants.AXIS_WIDTH, 42 + n.state.measuredW);
            }
            if (PaintKit.autoH(s))
            {
                var h:Number = n.state.measuredH;
                if (h < 24) h = 24;   // never thinner than the 20pt track + 2pt margins
                PaintKit.setPointSize(n, LayoutConstants.AXIS_HEIGHT, h);
            }
        }

        public function arrange(n:UiNode):void
        {
            if (n.tf == null) return;
            n.tf.x = 42;
            n.tf.y = (n.absH - n.state.measuredH) / 2;
        }

        public function paint(n:UiNode):void
        {
            var s:Style = n.resolved;
            var ty:Number = (n.absH - 20) / 2;   // track top
            var on:Boolean = n.checked;
            if (n.shapeA != null)
            {
                var g:Object = n.shapeA.graphics;
                g.clear();
                g.beginFill(PaintKit.stateColor(n, on ? 0x34D399 : 0xD1D5DB), 1.0);
                g.drawRoundRect(0, ty, 36, 20, 20, 20);
                g.endFill();
            }
            if (n.shapeB != null)
            {
                var g2:Object = n.shapeB.graphics;
                g2.clear();
                // Knob centre: 10 (off, left) or 26 (on, right) in the shrunken
                // content box; radius 8 leaves a 2pt margin to the track edge.
                var kx:Number = on ? 26 : 10;
                g2.beginFill(0xFFFFFF, 1.0);
                g2.drawCircle(kx, ty + 10, 8);
                g2.endFill();
            }
            if (n.tf != null && s.text.color >= 0) n.tf.textColor = uint(s.text.color);
        }

        public function click(n:UiNode):Boolean
        {
            var next:Boolean = !n.checked;
            n.checked = next;
            if (n.binding != null) n.binding.set(next);
            // The NEW value is the argument -- a zero-argument call throws #1063 on a
            // `function (v:Boolean)` handler (see UiNode.onChange).
            else if (n.onChange != null) n.onChange(next);
            n.app.invalidate(Dirty.VALUE);
            return true;   // consumed
        }
    }
}
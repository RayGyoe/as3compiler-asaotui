// asaot.ui.kind.SliderWidget -- track + filled portion + knob, plus the label.
//
// SCOPE (honest): there is NO drag/pointer-capture plumbing in the toolkit yet
// (UiApp has only MOUSE_OVER/OUT/DOWN/UP/CLICK on a backing; a MOUSE_MOVE drag
// would need a capture layer that does not exist). So the only interaction is a
// CLICK that SETS the value from the click's x inside the track.
//
// WHY A LISTENER: the `Widget.click(n)` hook receives no event, so it cannot
// know WHERE the click landed. We therefore attach our own MouseEvent.CLICK
// listener in `build` (structure time, once) and read `MouseEvent.localX`. The
// backing's own display objects are laid out from its (0,0), so `localX` is
// already the x inside the node; we divide by `n.absW` to get 0..1. In a real
// window the runtime feeds the same target-relative `localX`, so this works
// with the real pointer too, not only with a synthetic event.
//
// `value` is a DECORATION for layout purposes (a slider never resizes to its
// value), so a value change raises only Dirty.M_PAINT.
package asaot.ui.kind
{
    import asaot.ui.SliderNode;
    import asaot.ui.Dirty;
    import asaot.ui.PaintKit;
    import asaot.ui.UiNode;
    import asaot.ui.Widget;
    import asaot.ui.Node;
    import asaot.ui.style.Style;

    import asaot.ui.LayoutConstants;

    import flash.display.Shape;
    import flash.events.MouseEvent;

    public class SliderWidget implements Widget
    {
        public function build(n:UiNode):void
        {
            n.shapeA = new Shape();   // track + filled portion
            n.backing.addChild(n.shapeA);
            n.shapeB = new Shape();   // knob
            n.backing.addChild(n.shapeB);
            n.tf = PaintKit.makeText(false);
            n.backing.addChild(n.tf);

            // One closure, created at structure time (steady state stays
            // allocation-free). `this` is the kind singleton; `n` is this node.
            var self:SliderWidget = this;
            n.backing.addEventListener(MouseEvent.CLICK,
                function (e:MouseEvent):void { self.onClickX(n, e); });
        }

        public function payload(n:UiNode, desc:Node):Boolean
        {
            var sl:SliderNode = SliderNode(desc);
            var relayout:Boolean = false;
            if (sl.label != n.label)
            {
                n.label = sl.label;
                relayout = true;      // the label is intrinsic-width
            }
            n.onChange = sl.onChange;
            n.binding = sl.binding;
            var val:Number = sl.value;
            if (sl.binding != null)
            {
                var bv:Object = sl.binding.get();
                val = bv == null ? 0 : Number(bv);
            }
            if (val < 0) val = 0;
            if (val > 1) val = 1;
            var prev:Object = n.extra["v"];
            if (prev == null || Number(prev) != val)
            {
                n.extra["v"] = val;
                n.dirty |= Dirty.M_PAINT;   // the fill/knob move: paint only
            }
            return relayout;
        }

        public function wantsPress():Boolean { return true; }

        public function measure(n:UiNode):void
        {
            if (n.tf == null) return;
            var s:Style = n.resolved;
            PaintKit.measureField(n, n.tf, n.label, s);
            // A slider must not shrink to its label; without an explicit width it
            // gets a 160pt default.
            if (PaintKit.autoW(s)) PaintKit.setPointSize(n, LayoutConstants.AXIS_WIDTH, 160);
            if (PaintKit.autoH(s)) PaintKit.setPointSize(n, LayoutConstants.AXIS_HEIGHT, 40);
        }

        public function arrange(n:UiNode):void
        {
            if (n.tf == null) return;
            n.tf.x = PaintKit.insetX(n);
            n.tf.y = PaintKit.insetY(n);
        }

        public function paint(n:UiNode):void
        {
            var s:Style = n.resolved;
            var w:Number = n.absW > 1 ? n.absW : 1;
            var v:Number = Number(n.extra["v"]);
            if (isNaN(v)) v = 0;
            var ty:Number = n.absH - 12;   // track top; knob centre = ty + 4
            var fill:Number = w * v;
            if (n.shapeA != null)
            {
                var g:Object = n.shapeA.graphics;
                g.clear();
                g.beginFill(PaintKit.stateColor(n, 0xE5E7EB), 1.0);
                g.drawRoundRect(0, ty, w, 8, 8, 8);
                g.endFill();
                if (fill > 0)
                {
                    g.beginFill(0x2563EB, 1.0);
                    g.drawRoundRect(0, ty, fill, 8, 8, 8);
                    g.endFill();
                }
            }
            if (n.shapeB != null)
            {
                var g2:Object = n.shapeB.graphics;
                g2.clear();
                g2.beginFill(0xFFFFFF, 1.0);
                g2.lineStyle(2, 0x2563EB, 1.0);
                g2.drawCircle(fill, ty + 4, 7);
                g2.endFill();
            }
            if (n.tf != null && s.text.color >= 0) n.tf.textColor = uint(s.text.color);
        }

        // The click's x -> value is handled by the listener added in `build`; the
        // hook itself only has to CONSUME the click so no author onClick fires.
        public function click(n:UiNode):Boolean { return true; }

        private function onClickX(n:UiNode, e:MouseEvent):void
        {
            var w:Number = n.absW > 1 ? n.absW : 160;
            var v:Number = e.localX / w;
            if (v < 0) v = 0;
            if (v > 1) v = 1;
            n.extra["v"] = v;
            if (n.binding != null) n.binding.set(v);
            if (n.onChange != null) n.onChange();
            n.app.invalidate(Dirty.VALUE);
        }
    }
}
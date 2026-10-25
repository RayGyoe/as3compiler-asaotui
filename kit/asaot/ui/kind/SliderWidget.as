// asaot.ui.kind.SliderWidget -- track + filled portion + knob, plus the label.
//
// INTERACTION: press anywhere in the track to set the value, then DRAG to keep
// following the pointer; release ends it. A press is the whole gesture -- there is
// deliberately no separate "click vs drag" discrimination, because a press on the
// track already means "put the value here" (that is also how AIR's own slider
// behaves). A CLICK that the window glue sends after the release is consumed and
// does NOT re-set anything: the press did the work.
//
// WHY A STAGE LISTENER: the runtime dispatches motion to whatever is under the
// POINTER, so a drag that leaves the node (or the window) would stop receiving
// events. Listening on the STAGE for the duration of the drag is the pointer
// capture this runtime does not have (same trick as ScrollViewWidget.beginDrag).
// The closures are kept in `n.extra` so they can be removed BY REFERENCE in
// endDrag/teardown -- a stage listener pointing at a destroyed node's scratch bag
// is the bug the gallery's menus had.
//
// `value` is a DECORATION for layout purposes (a slider never resizes to its
// value), so a value change raises only Dirty.VALUE / a paint.
package asaot.ui.kind
{
    import asaot.ui.SliderNode;
    import asaot.ui.Dirty;
    import asaot.ui.PaintKit;
    import asaot.ui.UiNode;
    import asaot.ui.Widget;
    import asaot.ui.WidgetTeardown;
    import asaot.ui.Node;
    import asaot.ui.style.Style;

    import asaot.ui.LayoutConstants;

    import flash.display.Shape;
    import flash.display.Stage;
    import flash.events.MouseEvent;

    public class SliderWidget implements Widget, WidgetTeardown
    {
        // Pointer-interaction state. The values are strings because `n.extra` is a
        // plain Object (dialect: no const keys in a Map, no typed scratch bag).
        private static const DRAG:String = "drag";        // 1 while a press owns the pointer
        private static const MOVE_FN:String = "dragmv";   // the stage MOUSE_MOVE closure
        private static const UP_FN:String = "dragup";     // the stage MOUSE_UP closure
        private static const VALUE:String = "v";          // the live 0..1 value

        public function build(n:UiNode):void
        {
            n.shapeA = new Shape();   // track + filled portion
            n.backing.addChild(n.shapeA);
            n.shapeB = new Shape();   // knob
            n.backing.addChild(n.shapeB);
            n.tf = PaintKit.makeText(false);
            n.backing.addChild(n.tf);

            // One closure per event type, created at structure time (steady state
            // stays allocation-free). `this` is the kind singleton; `n` is this node.
            var self:SliderWidget = this;
            n.listen(n.backing, MouseEvent.MOUSE_DOWN,
                function (e:MouseEvent):void { self.onPress(n, e); });
            n.listen(n.backing, MouseEvent.MOUSE_UP,
                function (e:MouseEvent):void { self.endDrag(n); });
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
            var prev:Object = n.extra[VALUE];
            if (prev == null || Number(prev) != val)
            {
                n.extra[VALUE] = val;
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
            var v:Number = Number(n.extra[VALUE]);
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
            PaintKit.decorate(n);
        }

        // The press is the whole gesture (see the file comment), so a CLICK -- which
        // the window glue sends after the release -- must not run the author's
        // onClick: this hook is the widget's only chance to consume it.
        public function click(n:UiNode):Boolean { return true; }

        // ---- pointer interaction ------------------------------------------------
        private function onPress(n:UiNode, e:MouseEvent):void
        {
            if (n.inert()) return;              // a disabled slider ignores the pointer
            this.endDrag(n);                    // a previous drag that never saw its release
            this.commit(n, this.valueAt(n, e.stageX - n.absX));
            var st:Stage = n.app != null ? n.app.stage : null;
            if (st == null) return;
            n.extra[DRAG] = 1;
            var self:SliderWidget = this;
            var mv:Function = function (ev:MouseEvent):void { self.onDragMove(n, ev); };
            var upFn:Function = function (ev:MouseEvent):void { self.endDrag(n); };
            n.extra[MOVE_FN] = mv;
            n.extra[UP_FN] = upFn;
            st.addEventListener(MouseEvent.MOUSE_MOVE, mv);
            st.addEventListener(MouseEvent.MOUSE_UP, upFn);
        }

        private function onDragMove(n:UiNode, e:MouseEvent):void
        {
            if (int(n.extra[DRAG]) == 0) return;
            this.commit(n, this.valueAt(n, e.stageX - n.absX));
        }

        private function endDrag(n:UiNode):void
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
            if (int(n.extra[DRAG]) != 0)
            {
                n.extra[DRAG] = 0;
                // A drag that ended OUTSIDE the node never got its MOUSE_UP here, so
                // the pressed look would stay on forever.
                n.setPressed(0);
            }
        }

        // WidgetTeardown: a slider destroyed mid-drag must not leave its stage
        // listeners pointing at a nulled scratch bag. endDrag is idempotent.
        public function teardown(n:UiNode):void
        {
            this.endDrag(n);
        }

        // The pointer's x, as a fraction of the track. The track spans the FULL node
        // width and the knob centre sits at `w * v`, so `(pointer - absX) / w` is 1:1
        // by construction -- no clamp distance or thumb length to divide by (which is
        // what makes a thumb-drag feel different from a pointer-drag).
        private function valueAt(n:UiNode, localX:Number):Number
        {
            var w:Number = n.absW > 1 ? n.absW : 160;
            var v:Number = localX / w;
            if (v < 0) v = 0;
            if (v > 1) v = 1;
            return v;
        }

        // The single write point for a new value: state, binding, author callback,
        // repaint request -- in that order. NOTHING happens when the value did not
        // change, which is what keeps one gesture to one report (the press and the
        // trailing CLICK cannot both fire the author's handler).
        private function commit(n:UiNode, v:Number):void
        {
            var prev:Number = Number(n.extra[VALUE]);
            if (!isNaN(prev) && prev == v) return;
            // A slider payload re-reads the model, so during a drag the incoming value
            // equals this one a frame later and payload's `prev != val` test stays
            // quiet: no feedback loop.
            n.extra[VALUE] = v;
            if (n.binding != null) n.binding.set(v);
            // The NEW value is the argument: a zero-argument call throws #1063 on a
            // `function (v:Number)` handler (see UiNode.onChange).
            if (n.onChange != null) n.onChange(v);
            // THE WIDGET OWES THE SCREEN ITS OWN REPAINT. `invalidate` alone only
            // requests a describe, and a re-described slider whose value the payload
            // already agrees with raises no M_PAINT -- so a value change with an
            // unchanged label painted nothing at all (the docs demo hid it: "Volume
            // 41%" relayouts, and the relayout repaints everything). The same defect
            // the text field had (STATUS.md item 20).
            n.app.markPaint(n);
            n.app.invalidate(Dirty.VALUE);
        }
    }
}
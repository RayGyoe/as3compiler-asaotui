// asaot.ui.kind.RangeSliderWidget -- track, band between the thumbs, two thumbs.
//
// WHICH THUMB THE POINTER GRABS is decided at PRESS time by distance: the nearer of
// the two, in pixels. That is the only rule that behaves sanely when the thumbs sit
// on top of each other (a "grab the low one if x < band" rule makes the overlapped
// state unreachable). Once grabbed, the thumb stays grabbed for the whole gesture --
// the pointer may cross the other thumb, and the CLAMP (not a re-pick) is what stops
// it: low stops at high and high stops at low.
//
// THE DRAG IS CONTINUOUS. `step` is the KEYBOARD increment only (see RangeSliderNode's
// header): snapping the pointer to a grid makes the thumb lag the cursor, which reads
// as a bug.
//
// WHY A STAGE LISTENER: the runtime dispatches motion to whatever is under the
// POINTER, so a drag that leaves the node would stop receiving events. This is the
// pointer capture the runtime does not have (same trick as SliderWidget /
// ScrollViewWidget / TableWidget): the closures live in `n.extra` so they can be
// removed BY REFERENCE, `endDrag` is idempotent (release, the next press, and
// `teardown` all reach it), and teardown exists because a node destroyed mid-drag
// must not leave a stage listener pointing at a nulled scratch bag.
//
// PAYLOAD DOES NOT FIGHT THE DRAG. While a thumb is held, the payload skips the
// model: an author who has not re-rendered yet would otherwise snap the thumb back
// to the old value on the next frame, once per frame, for the whole gesture.
package asaot.ui.kind
{
    import asaot.ui.Dirty;
    import asaot.ui.LayoutConstants;
    import asaot.ui.Node;
    import asaot.ui.PaintKit;
    import asaot.ui.RangeSliderNode;
    import asaot.ui.Theme;
    import asaot.ui.ThemeTokens;
    import asaot.ui.UiNode;
    import asaot.ui.Widget;
    import asaot.ui.WidgetKeys;
    import asaot.ui.WidgetTeardown;
    import asaot.ui.style.Style;

    import flash.display.Shape;
    import flash.display.Stage;
    import flash.events.MouseEvent;

    public class RangeSliderWidget implements Widget, WidgetTeardown, WidgetKeys
    {
        private static const LO:String = "rlo";
        private static const HI:String = "rhi";
        private static const DRAG:String = "rdrag";      // "" | "lo" | "hi"
        private static const MOVE_FN:String = "rmv";
        private static const UP_FN:String = "rup";
        private static const STEP_K:String = "rstep";

        private static const TRACK_H:Number = 8;
        private static const THUMB_R:Number = 7;

        public function build(n:UiNode):void
        {
            n.shapeA = new Shape();   // track + selected band
            n.backing.addChild(n.shapeA);
            n.shapeB = new Shape();   // the two thumbs
            n.backing.addChild(n.shapeB);
            n.tf = PaintKit.makeText(false);
            n.backing.addChild(n.tf);

            n.extra[LO] = 0;
            n.extra[HI] = 1;
            n.extra[DRAG] = "";
            n.extra[MOVE_FN] = null;
            n.extra[UP_FN] = null;

            var self:RangeSliderWidget = this;
            n.listen(n.backing, MouseEvent.MOUSE_DOWN,
                function (e:MouseEvent):void { self.onPress(n, e); });
            n.listen(n.backing, MouseEvent.MOUSE_UP,
                function (e:MouseEvent):void { self.endDrag(n); });
        }

        public function payload(n:UiNode, desc:Node):Boolean
        {
            var rs:RangeSliderNode = RangeSliderNode(desc);
            var relayout:Boolean = false;
            if (rs.label != n.label)
            {
                n.label = rs.label;
                relayout = true;
            }
            n.extra[STEP_K] = rs.step;
            // A held thumb owns the values until it is released (see the header).
            if (String(n.extra[DRAG]).length > 0) return relayout;

            var lo:Number = rs.value;
            var hi:Number = rs.value2;
            if (isNaN(lo)) lo = 0;
            if (isNaN(hi)) hi = 1;
            if (lo < 0) lo = 0;
            if (lo > 1) lo = 1;
            if (hi < 0) hi = 0;
            if (hi > 1) hi = 1;
            if (lo > hi) { var t:Number = lo; lo = hi; hi = t; }

            var pl:Object = n.extra[LO];
            var ph:Object = n.extra[HI];
            if (pl == null || ph == null || Number(pl) != lo || Number(ph) != hi)
            {
                n.extra[LO] = lo;
                n.extra[HI] = hi;
                n.dirty |= Dirty.M_PAINT;   // the band and the thumbs move: paint only
            }
            return relayout;
        }

        public function wantsPress():Boolean { return true; }

        public function measure(n:UiNode):void
        {
            if (n.tf == null) return;
            var s:Style = n.resolved;
            PaintKit.measureField(n, n.tf, n.label, s);
            if (PaintKit.autoW(s)) PaintKit.setPointSize(n, LayoutConstants.AXIS_WIDTH, 180);
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
            var lo:Number = Number(n.extra[LO]);
            var hi:Number = Number(n.extra[HI]);
            if (isNaN(lo)) lo = 0;
            if (isNaN(hi)) hi = 1;
            var ty:Number = n.absH - 12;
            var lx:Number = w * lo;
            var hx:Number = w * hi;
            var pal:ThemeTokens = Theme.tokens();

            if (n.shapeA != null)
            {
                var g:Object = n.shapeA.graphics;
                g.clear();
                g.beginFill(PaintKit.stateColor(n, pal.track), 1.0);
                g.drawRoundRect(0, ty, w, TRACK_H, TRACK_H, TRACK_H);
                g.endFill();
                if (hx > lx)
                {
                    g.beginFill(pal.accent, 1.0);
                    g.drawRect(lx, ty, hx - lx, TRACK_H);
                    g.endFill();
                }
            }
            if (n.shapeB != null)
            {
                var g2:Object = n.shapeB.graphics;
                g2.clear();
                g2.beginFill(pal.knob, 1.0);
                g2.lineStyle(2, pal.accent, 1.0);
                g2.drawCircle(lx, ty + TRACK_H / 2, THUMB_R);
                g2.endFill();
                g2.beginFill(pal.knob, 1.0);
                g2.lineStyle(2, pal.accent, 1.0);
                g2.drawCircle(hx, ty + TRACK_H / 2, THUMB_R);
                g2.endFill();
            }
            if (n.tf != null && s.text.color >= 0) n.tf.textColor = uint(s.text.color);
            PaintKit.decorate(n);
        }

        // The press is the whole gesture, so the CLICK the glue sends after the release
        // must not also run the author's onClick (same reason as SliderWidget).
        public function click(n:UiNode):Boolean { return true; }

        // ---- keyboard --------------------------------------------------------
        // The LOW thumb is the one the bare arrows move; Shift moves the HIGH one.
        // Without a modifier there has to be one answer, and low-first matches the
        // reading order of "from .. to".
        public function onKey(n:UiNode, keyCode:int, shift:Boolean):Boolean
        {
            var step:Number = Number(n.extra[STEP_K]);
            if (!(step > 0)) step = 0.05;
            var lo:Number = Number(n.extra[LO]);
            var hi:Number = Number(n.extra[HI]);
            var d:Number = 0;
            if (keyCode == 37 || keyCode == 40) d = -step;
            else if (keyCode == 39 || keyCode == 38) d = step;
            else if (keyCode == 36 || keyCode == 35)
            {
                var edge:Number = keyCode == 36 ? 0 : 1;
                if (shift) this.commit(n, lo, edge);
                else this.commit(n, edge, hi);
                return true;
            }
            else return false;
            if (shift) this.commit(n, lo, hi + d);
            else this.commit(n, lo + d, hi);
            return true;
        }

        // ---- pointer ---------------------------------------------------------
        private function onPress(n:UiNode, e:MouseEvent):void
        {
            if (n.inert()) return;
            this.endDrag(n);
            var w:Number = n.absW > 1 ? n.absW : 180;
            var x:Number = e.stageX - n.absX;
            var lo:Number = Number(n.extra[LO]);
            var hi:Number = Number(n.extra[HI]);
            var dl:Number = x - w * lo;
            if (dl < 0) dl = -dl;
            var dh:Number = x - w * hi;
            if (dh < 0) dh = -dh;
            var which:String = dl <= dh ? "lo" : "hi";
            n.extra[DRAG] = which;
            if (which == "lo") this.commit(n, this.at(n, x), hi);
            else this.commit(n, lo, this.at(n, x));

            var st:Stage = n.app != null ? n.app.stage : null;
            if (st == null) return;
            var self:RangeSliderWidget = this;
            var mv:Function = function (ev:MouseEvent):void { self.onDragMove(n, ev); };
            var upFn:Function = function (ev:MouseEvent):void { self.endDrag(n); };
            n.extra[MOVE_FN] = mv;
            n.extra[UP_FN] = upFn;
            st.addEventListener(MouseEvent.MOUSE_MOVE, mv);
            st.addEventListener(MouseEvent.MOUSE_UP, upFn);
        }

        private function onDragMove(n:UiNode, e:MouseEvent):void
        {
            var which:String = String(n.extra[DRAG]);
            if (which.length == 0) return;
            var x:Number = e.stageX - n.absX;
            var v:Number = this.at(n, x);
            var lo:Number = Number(n.extra[LO]);
            var hi:Number = Number(n.extra[HI]);
            if (which == "lo") this.commit(n, v, hi);
            else this.commit(n, lo, v);
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
            if (String(n.extra[DRAG]).length > 0)
            {
                n.extra[DRAG] = "";
                n.setPressed(0);
            }
        }

        public function teardown(n:UiNode):void
        {
            this.endDrag(n);
        }

        private function at(n:UiNode, localX:Number):Number
        {
            var w:Number = n.absW > 1 ? n.absW : 180;
            var v:Number = localX / w;
            if (v < 0) v = 0;
            if (v > 1) v = 1;
            return v;
        }

        // The single write point for a new PAIR: clamp, keep the order, then report
        // once. `lo > hi` cannot be committed -- whichever thumb moved is the one that
        // gets stopped at the other.
        private function commit(n:UiNode, loRaw:Number, hiRaw:Number):void
        {
            var lo:Number = loRaw;
            var hi:Number = hiRaw;
            if (lo < 0) lo = 0;
            if (lo > 1) lo = 1;
            if (hi < 0) hi = 0;
            if (hi > 1) hi = 1;
            if (lo > hi) lo = hi;
            if (hi < lo) hi = lo;

            var pl:Number = Number(n.extra[LO]);
            var ph:Number = Number(n.extra[HI]);
            var changed:Boolean = isNaN(pl) || isNaN(ph) || pl != lo || ph != hi;
            n.extra[LO] = lo;
            n.extra[HI] = hi;
            if (!changed) { n.app.markPaint(n); return; }
            var f:Function = null;
            if (n.desc != null) f = RangeSliderNode(n.desc).onRange;
            // BOTH values are the arguments: a one-argument declaration against a
            // two-argument call is #1063 (see tools/callback-arity.cjs's PAIR_CBS).
            if (f != null) f(lo, hi);
            n.app.markPaint(n);
            n.app.invalidate(Dirty.VALUE);
        }
    }
}
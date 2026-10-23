// asaot.ui.kind.TabsWidget -- a horizontal segmented control.
//
// SEGMENT LAYOUT (and the honest disclosure): the segments are laid out by the
// WIDGET ITSELF in `arrange`/`paint` from the solved `n.absW` -- they are NOT
// child UiNodes fed to the layout engine. A segmented control's segments are
// uniform cells (every one is `(contentW - gap*(n-1)) / n` wide), so there is
// nothing for flexbox to solve that integer arithmetic does not already know,
// and keeping them internal means a click maps to a segment with one division
// (contrast: a `list`, which IS a real container with engine-placed rows).
//
// The LABEL for each segment is a real TextField. Their count follows the labels
// array, so `syncFields` reuses the array in `n.extra` across frames (steady
// state allocates nothing; a count change is a structure change and may).
//
// STATE DISCIPLINE (ChipWidget):
//   * a change to `labels` returns TRUE from `payload` -- the number of segments
//     and their intrinsic width change, so it is a LAYOUT change;
//   * a change to `selectedIndex` is a DECORATION: it raises only
//     Dirty.M_PAINT, never a reflow.
//
// CLICK: the `Widget.click(n)` hook gets no coordinates, so -- exactly like
// SliderWidget -- we attach our own MouseEvent.CLICK listener at structure time
// and read `MouseEvent.localX`. The division by the segment pitch yields the
// index. `click(n)` still returns TRUE so the click is consumed and the author's
// `onClick` does not also fire.
package asaot.ui.kind
{
    import asaot.ui.TabsNode;
    import asaot.ui.Dirty;
    import asaot.ui.Node;
    import asaot.ui.PaintKit;
    import asaot.ui.UiNode;
    import asaot.ui.Widget;
    import asaot.ui.style.Style;

    import asaot.ui.LayoutConstants;

    import flash.display.Shape;
    import flash.events.MouseEvent;
    import flash.text.TextField;

    public class TabsWidget implements Widget
    {
        // n.extra keys (plain property reads in paint: zero allocation).
        private static const TFS_KEY:String = "tfs";       // Array of TextField
        private static const LABELS_KEY:String = "labs";   // previous labels copy
        private static const SEL_KEY:String = "sel";       // previous selected index
        private static const GAP_KEY:String = "gap";       // resolved segment gap

        // Segment colours. Selected/unselected are deliberately far apart so a
        // mis-wired index shows up as an exact-pixel failure, not a subtle shade.
        private static const SEL_BG:uint = 0x2563EB;
        private static const SEL_FG:uint = 0xFFFFFF;
        private static const OFF_BG:uint = 0xE5E7EB;
        private static const OFF_FG:uint = 0x374151;

        public function build(n:UiNode):void
        {
            n.shapeA = new Shape();   // all segment backgrounds in ONE Graphics pass
            n.backing.addChild(n.shapeA);
            n.extra[TFS_KEY] = new Array();
            n.extra[LABELS_KEY] = null;
            n.extra[GAP_KEY] = 0;

            // Structure time: one closure, so a click can be mapped to a segment.
            var self:TabsWidget = this;
            n.backing.addEventListener(MouseEvent.CLICK,
                function (e:MouseEvent):void { self.onClickX(n, e); });
        }

        public function payload(n:UiNode, desc:Node):Boolean
        {
            var t:TabsNode = TabsNode(desc);
            var labs:Array = t.labels == null ? [] : t.labels;
            var count:int = labs.length;
            var tfs:Array = n.extra[TFS_KEY] as Array;

            var relayout:Boolean = false;
            if (tfs.length != count || labelsChanged(n, labs, count))
            {
                if (tfs.length != count) syncFields(n, count);
                for (var i:int = 0; i < count; i++)
                {
                    var tf:TextField = TextField(tfs[i]);
                    if (tf != null) tf.text = labs[i] == null ? "" : String(labs[i]);
                }
                // Store a COPY: the author's array is rebuilt every render().
                n.extra[LABELS_KEY] = labs.concat();
                relayout = true;   // count / text -> different intrinsic size
            }

            // The segment gap: the explicit node field wins, else the style gap.
            var g:Number = t.gap;
            if (isNaN(g))
            {
                var sg:Number = n.resolved.gapX;
                g = isNaN(sg) ? 0 : sg;
            }
            n.extra[GAP_KEY] = g;

            n.onChange = t.onChange;
            n.binding = t.binding;

            var sv:Number = t.selectedIndex;
            if (t.binding != null)
            {
                // `*`, NOT `Object` (compiler-gaps G9). The value is Number-ish.
                var bv:* = t.binding.get();
                sv = bv == null ? 0 : Number(bv);
            }
            var prev:Object = n.extra[SEL_KEY];
            if (prev == null || Number(prev) != sv)
            {
                n.extra[SEL_KEY] = sv;
                n.dirty |= Dirty.M_PAINT;   // decoration only: never a reflow
            }
            return relayout;
        }

        // Element-wise compare against the stored copy. No allocation, so it is
        // safe to run on every reconcile.
        private function labelsChanged(n:UiNode, labs:Array, count:int):Boolean
        {
            var prev:Array = n.extra[LABELS_KEY] as Array;
            if (prev == null) return true;
            if (prev.length != count) return true;
            for (var i:int = 0; i < count; i++)
            {
                var a:String = labs[i] == null ? "" : String(labs[i]);
                var b:String = prev[i] == null ? "" : String(prev[i]);
                if (a != b) return true;
            }
            return false;
        }

        // Grow / shrink the segment TextFields to match the label count. Add at
        // the end (they layer above shapeA) and detach from the end on shrink.
        private function syncFields(n:UiNode, count:int):void
        {
            var tfs:Array = n.extra[TFS_KEY] as Array;
            while (tfs.length < count)
            {
                var tf:TextField = PaintKit.makeText(false);
                n.backing.addChild(tf);
                tfs.push(tf);
            }
            while (tfs.length > count)
            {
                var last:TextField = TextField(tfs.pop());
                if (last != null && last.parent == n.backing) n.backing.removeChild(last);
            }
        }

        public function wantsPress():Boolean { return true; }

        public function measure(n:UiNode):void
        {
            var s:Style = n.resolved;
            var tfs:Array = n.extra[TFS_KEY] as Array;
            if (tfs == null || tfs.length == 0) return;
            var count:int = tfs.length;
            var totalW:Number = 0;
            var maxH:Number = 0;
            for (var i:int = 0; i < count; i++)
            {
                var tf:TextField = TextField(tfs[i]);
                if (tf == null) continue;
                PaintKit.measureField(n, tf, tf.text, s);
                totalW = totalW + n.state.measuredW;
                if (n.state.measuredH > maxH) maxH = n.state.measuredH;
            }
            var gap:Number = Number(n.extra[GAP_KEY]);
            if (PaintKit.autoW(s))
            {
                var w:Number = totalW + gap * (count - 1)
                    + PaintKit.padH(s.padding) + PaintKit.borderH(s.borderWidths);
                PaintKit.setPointSize(n, LayoutConstants.AXIS_WIDTH, w);
            }
            if (PaintKit.autoH(s))
            {
                var h:Number = maxH + PaintKit.padV(s.padding) + PaintKit.borderV(s.borderWidths);
                if (h < 24) h = 24;
                PaintKit.setPointSize(n, LayoutConstants.AXIS_HEIGHT, h);
            }
        }

        public function arrange(n:UiNode):void
        {
            // Nothing to place: paint() computes each segment from the final rect.
        }

        public function paint(n:UiNode):void
        {
            var s:Style = n.resolved;
            var tfs:Array = n.extra[TFS_KEY] as Array;
            if (tfs == null) return;

            // Container background + border first (one Graphics pass), then the
            // segment fills on top of it.
            PaintKit.drawBox(n.shapeA, s, PaintKit.w1(n), PaintKit.h1(n));
            var count:int = tfs.length;
            if (count == 0 || n.shapeA == null) return;

            var x0:Number = PaintKit.insetX(n);
            var y0:Number = PaintKit.insetY(n);
            var cw:Number = PaintKit.contentW(n);
            var ch:Number = PaintKit.contentH(n);
            var gap:Number = Number(n.extra[GAP_KEY]);
            var segW:Number = (cw - gap * (count - 1)) / count;
            var sel:int = int(Number(n.extra[SEL_KEY]));
            var g:Object = n.shapeA.graphics;
            for (var i:int = 0; i < count; i++)
            {
                var segX:Number = x0 + i * (segW + gap);
                var on:Boolean = (i == sel);
                g.beginFill(on ? SEL_BG : OFF_BG, 1.0);
                // radius 6 -> ellipse diameter 12 (same convention as ChipWidget)
                g.drawRoundRect(segX, y0, segW, ch, 12, 12);
                g.endFill();

                var tf:TextField = TextField(tfs[i]);
                if (tf != null)
                {
                    tf.textColor = on ? SEL_FG : OFF_FG;
                    tf.x = segX + (segW - tf.textWidth) / 2;
                    tf.y = y0 + (ch - tf.textHeight) / 2;
                }
            }
        }

        // The click's x -> index is handled by the listener added in `build`; the
        // hook itself only has to CONSUME the click so no author onClick fires.
        public function click(n:UiNode):Boolean { return true; }

        private function onClickX(n:UiNode, e:MouseEvent):void
        {
            var tfs:Array = n.extra[TFS_KEY] as Array;
            if (tfs == null) return;
            var count:int = tfs.length;
            if (count == 0) return;
            var x0:Number = PaintKit.insetX(n);
            var cw:Number = PaintKit.contentW(n);
            var gap:Number = Number(n.extra[GAP_KEY]);
            var segW:Number = (cw - gap * (count - 1)) / count;
            var idx:int = int((e.localX - x0) / (segW + gap));
            if (idx < 0) idx = 0;
            if (idx >= count) idx = count - 1;

            // Do NOT write n.extra[SEL_KEY] here: payload is the single writer of
            // that key, so it can SEE the change and raise Dirty.M_PAINT. Writing
            // it here would make the next payload a no-op and the selection would
            // never repaint.
            if (n.binding != null) n.binding.set(idx);
            n.app.markPaint(n);
            if (n.onChange != null) n.onChange(idx);
            n.app.invalidate(Dirty.VALUE);
        }
    }
}
// asaot.ui.kind.VirtualListWidget -- wheel/keyboard scrolling for a windowed list.
//
// THIS WIDGET MOUNTS NOTHING. The mounted slice is the description's business (see
// virtualList.as), so a scroll here is one call -- `onScroll(firstRow * rowHeight)`
// -- and the author's re-render does the rest. The widget owns exactly three
// things:
//
//   1. THE CLIP. `backing.scrollRect = new Rectangle(0, 0, w, h)` -- a PURE clip,
//      unlike ScrollViewWidget's Rectangle(0, offsetY, w, h), because the rows are
//      already positioned inside the viewport (only the visible slice was mounted).
//      Without it the last mounted row paints below the viewport: the extra "+1" row
//      the factory mounts for a partial viewport would leak out, and so would
//      anything the author put in an overscan band.
//   2. THE SNAP+CLAMP. A wheel notch asks for a window `step` rows away; the answer
//      is always `first * rowHeight`, so the offset the author stores stays
//      row-aligned and rounding never accumulates.
//   3. THE KEYS. Up/Down move one row, PageUp/PageDown move one window, Home/End
//      jump to the ends -- the same keys a browser list answers to. All of them go
//      through `onScroll`, so there is exactly one way the window moves.
//
// WHY THE WHEEL IS NOT `e.delta` SIGN-FLIPPED BY HAND: the runtime's convention is
// `scrollV - delta` (Stage.dispatchWheel, emit.ts:21504) -- a POSITIVE delta scrolls
// toward the START. ScrollViewWidget documents the same thing; both widgets must
// agree or a page with a vlist inside a scrollView would scroll the two in opposite
// directions.
package asaot.ui.kind
{
    import asaot.ui.Node;
    import asaot.ui.PaintKit;
    import asaot.ui.UiNode;
    import asaot.ui.VirtualListNode;
    import asaot.ui.Widget;
    import asaot.ui.WidgetKeys;
    import asaot.ui.WidgetTeardown;

    import asaot.ui.style.Size;
    import asaot.ui.style.Length;
    import asaot.ui.style.Style;
    import asaot.ui.style.StyleRefinement;

    import flash.display.Shape;
    import flash.events.MouseEvent;
    import flash.geom.Rectangle;
    import flash.utils.clearTimeout;
    import flash.utils.setTimeout;

    public class VirtualListWidget implements Widget, WidgetKeys, WidgetTeardown
    {
        public static const DEFAULT_H:Number = 200;

        private static const RH_KEY:String = "rh";
        private static const COUNT_KEY:String = "cnt";
        private static const OFF_KEY:String = "off";
        private static const STEP_KEY:String = "step";
        private static const APPLIED:String = "clip";
        private static const DEFAULT_STEP:int = 3;   // rows per wheel notch
        // The last `scrollToIndex` honoured (the request is a CHANGE, like
        // ScrollViewNode's offset) and the window last reported to `onVisible`.
        private static const REQ_IDX:String = "reqidx";
        private static const PENDING:String = "pend";
        private static const REQ_TMR:String = "reqtmr";
        private static const VISIBLE:String = "vis";

        public function build(n:UiNode):void
        {
            n.shapeA = new Shape();
            n.backing.addChild(n.shapeA);
            var self:VirtualListWidget = this;
            n.listen(n.backing, MouseEvent.MOUSE_WHEEL,
                function (e:MouseEvent):void { self.onWheel(n, e); });
        }

        public function payload(n:UiNode, desc:Node):Boolean
        {
            var v:VirtualListNode = VirtualListNode(desc);
            n.extra[RH_KEY] = v.rowHeight;
            n.extra[COUNT_KEY] = v.count;
            n.extra[OFF_KEY] = v.offsetY;
            // `scrollToIndex` IS DETECTED HERE, NOT IN PAINT. A re-render whose only
            // difference is a non-visual field (a fresh `scrollToIndex` on an otherwise
            // identical tree) reconciles to the same structure and is NOT repainted --
            // measured: paint kept reading the previous description and the request sat
            // unhonoured until something else happened to dirty the node. payload runs on
            // every reconcile with the new description, so the change is seen here and
            // the paint bit is raised to guarantee the frame that honours it.
            var want:int = v.scrollToIndex;
            var seen:Object = n.extra[REQ_IDX];
            if (seen == null || int(seen) != want)
            {
                n.extra[REQ_IDX] = want;
                // A first description with an index (a model that OPENS on row 120) counts
                // as a change, so the initial request is honoured too.
                if (want >= 0)
                {
                    n.extra[PENDING] = want;
                    this.scheduleRequest(n);
                }
            }
            // A different window is a different set of children; the reconciler sees
            // that on its own, so nothing here asks for a reflow.
            return false;
        }

        public function wantsPress():Boolean { return true; }

        public function measure(n:UiNode):void
        {
            // Rows are pinned by the FACTORY (`height` + `flexShrink: 0`), so there is
            // nothing to correct here. See virtualList.as for why that is declarative
            // instead of a min-height pin like ScrollViewWidget's.
        }

        public function arrange(n:UiNode):void { }

        public function paint(n:UiNode):void
        {
            var w:Number = PaintKit.w1(n);
            var h:Number = PaintKit.h1(n);
            PaintKit.paintBox(n, n.resolved, w, h);

            var desc:VirtualListNode = VirtualListNode(n.desc);
            // `onVisible` is held back while a `scrollToIndex` is in flight: the window
            // the author is about to describe is the NEW one, and reporting the stale
            // one first would make every jump produce two sightings.
            if (n.extra[PENDING] == null && n.extra[REQ_TMR] == null)
            {
                this.reportVisible(n, desc);
            }

            // Assign only on change: the runtime copies the rectangle (see
            // ScrollViewWidget), so assigning every paint allocates a Rectangle for a
            // list that is merely sitting still.
            var applied:Array = n.extra[APPLIED] as Array;
            if (applied == null) { applied = [0, 0, 0, 0]; n.extra[APPLIED] = applied; }
            if (applied[0] != w || applied[1] != h)
            {
                n.backing.scrollRect = new Rectangle(0, 0, w, h);
                applied[0] = w;
                applied[1] = h;
            }
        }

        public function click(n:UiNode):Boolean { return false; }

        // ---- keyboard -------------------------------------------------------
        // The row the window starts at, from the CURRENT description. Every key
        // resolves to a target FIRST ROW index and then goes through `request()`.
        public function onKey(n:UiNode, keyCode:int, shift:Boolean):Boolean
        {
            var fit:int = windowRows(n);
            if (keyCode == 38) { this.step(n, -1); return true; }                 // Up
            if (keyCode == 40) { this.step(n, 1); return true; }                  // Down
            if (keyCode == 33) { this.step(n, -fit); return true; }               // PageUp
            if (keyCode == 34) { this.step(n, fit); return true; }                // PageDown
            if (keyCode == 36) { this.request(n, 0); return true; }               // Home
            if (keyCode == 35) { this.request(n, 1 << 28); return true; }         // End
            return false;
        }

        // ---- scrolling ------------------------------------------------------
        private function onWheel(n:UiNode, e:MouseEvent):void
        {
            var step:int = Number(n.extra[STEP_KEY]) > 0
                ? int(Number(n.extra[STEP_KEY])) : DEFAULT_STEP;
            var d:Number = e.delta;
            if (isNaN(d)) d = 0;
            if (d == 0) return;
            // Positive delta scrolls toward the START (see the header).
            this.step(n, d > 0 ? -step : step);
            e.stopPropagation();   // a nested viewport must not also scroll
        }

        private function step(n:UiNode, rows:int):void
        {
            var cur:int = firstRow(n);
            this.request(n, cur + rows);
        }

        // Every path ends here: an INDEX in, a row-aligned offset out.
        private function request(n:UiNode, firstWanted:int):void
        {
            var rh:Number = Number(n.extra[RH_KEY]);
            if (!(rh > 0)) return;
            var count:int = int(Number(n.extra[COUNT_KEY]));
            var fit:int = windowRows(n);
            var maxFirst:int = count - fit;
            if (maxFirst < 0) maxFirst = 0;
            var f:int = firstWanted;
            if (f > maxFirst) f = maxFirst;
            if (f < 0) f = 0;
            var y:Number = f * rh;
            // Already there: do not call back. An `onScroll` that fires on every
            // wheel notch even at the end of the list would make the author re-render
            // for nothing on every bounce.
            if (y == Number(n.extra[OFF_KEY])) return;
            n.extra[OFF_KEY] = y;
            var v:VirtualListNode = VirtualListNode(n.desc);
            // Keep the description in step for an author who kept the reference
            // (ScrollViewNode's header calls this "the live position, published back").
            v.offsetY = y;
            if (v.onScroll != null) v.onScroll(y);
            n.app.markPaint(n);
        }

        // The window changed: tell the author which rows are on screen. Change-detected
        // against the last report, so a re-render for any other reason is silent.
        private function reportVisible(n:UiNode, v:VirtualListNode):void
        {
            var vis:Array = n.extra[VISIBLE] as Array;
            if (vis == null) { vis = [-1, -1]; n.extra[VISIBLE] = vis; }
            if (int(vis[0]) == v.firstIndex && int(vis[1]) == v.lastIndex) return;
            vis[0] = v.firstIndex;
            vis[1] = v.lastIndex;
            if (v.onVisible != null) v.onVisible(v.firstIndex, v.lastIndex);
        }

        // The request leaves the frame pass. THE REASON IS MEASURED, not stylistic:
        // UiApp.reflow ends with `_pending = 0`, so a `view.invalidate()` that the
        // author makes from our `onScroll` would be cleared in the same pass that
        // raised it -- the author's model would hold row 120 and the tree would still
        // show row 0, forever. A 0ms timer puts the callback back in the event loop,
        // where every other callback in this kit runs (a wheel notch, a key, a click),
        // and the author's invalidate survives to the next frame.
        //
        // One timer is enough however many changes arrive: the flush reads the LATEST
        // pending index, so a burst of re-descriptions collapses into one request.
        private function scheduleRequest(n:UiNode):void
        {
            if (n.extra[REQ_TMR] != null) return;
            var self:VirtualListWidget = this;
            n.extra[REQ_TMR] = setTimeout(function ():void { self.flushIndexRequest(n); }, 0);
        }

        private function flushIndexRequest(n:UiNode):void
        {
            n.extra[REQ_TMR] = null;
            var pend:Object = n.extra[PENDING];
            n.extra[PENDING] = null;
            if (pend == null) return;
            this.request(n, int(pend));
        }

        // A list destroyed with a request in flight must not have a timer holding the
        // node (the same reason ToastWidget cancels its dismiss timer).
        public function teardown(n:UiNode):void
        {
            var t:Object = n.extra[REQ_TMR];
            if (t != null) clearTimeout(int(t));
            n.extra[REQ_TMR] = null;
            n.extra[PENDING] = null;
        }

        private function firstRow(n:UiNode):int
        {
            var rh:Number = Number(n.extra[RH_KEY]);
            if (!(rh > 0)) return 0;
            return Math.round(Number(n.extra[OFF_KEY]) / rh);
        }

        // How many rows the viewport shows. `ceil`, the same rule the factory uses for
        // `fit`, so a request and the factory's window agree and End lands on the true
        // last page in ONE re-render (a `floor` here would ask for row 993, be clamped
        // by the factory to 992, and cost the author a second render for nothing).
        private function windowRows(n:UiNode):int
        {
            var rh:Number = Number(n.extra[RH_KEY]);
            if (!(rh > 0)) return 1;
            var h:Number = n.absH > 0 ? n.absH : DEFAULT_H;
            var n2:int = int(Math.ceil(h / rh));
            return n2 < 1 ? 1 : n2;
        }

        // The viewport's own height in POINTs, or NaN when it is auto/percent/unset.
        // A percent height is deliberately NOT resolved by the factory: it runs before
        // layout, so the parent's height is unknown at that point (same boundary
        // ScrollViewWidget documents for its auto axes).
        public static function viewportHeight(s:Style):Number
        {
            if (s == null) return NaN;
            var sz:Size = s.size;
            if (sz == null) return NaN;
            var h:Length = sz.height;
            if (h == null || h.isAuto() || h.unit != Length.UNIT_POINT) return NaN;
            return h.value;
        }
    }
}
// asaot.ui.kind.ScrollViewWidget -- the viewport for ScrollViewNode.
//
// THE CLIP IS `backing.scrollRect`, AND ITS SEMANTICS ARE NOT THE OBVIOUS ONES.
// Measured against adl 51.4.1 (recorded in the compiler, emit.ts:22731): the object
// is shown through a window of the SCROLL RECTANGLE'S SIZE that stays anchored on
// the object's own box, and the CONTENT slides by -x/-y. So
//
//     backing.scrollRect = new Rectangle(0, offsetY, w, h)
//
// clips to the node's own rect AND slides the content up by offsetY -- the clip is
// free. The one consequence is that the slide moves EVERY child of the backing,
// including this widget's own background shape, so `paint` compensates by drawing
// the background at +offsetY. Getting that backwards is how the app's old list
// painted scrolled content over its fixed header (bug D29 in the compiler).
//
// THE CONTENT MUST NOT BE SHRUNK BY THE VIEWPORT. `flex-shrink` defaults to 1 in
// this engine (As3LayoutNode.as:44), so a 120px column inside a 60px viewport would
// be compressed to 60px and there would be nothing to scroll. `measure` therefore
// pins `flex-shrink: 0` on every child that did not ask for a flex of its own --
// a viewport compressing its content is never what the author meant, and an
// explicit `flexShrink` still wins because the check is `anyFlex`.
//
// WHAT A SCROLLVIEW DOES NOT DO: no scrollbars, no kinetic/drag scrolling, no
// `overflow: hidden` on the LAYOUT (children still report their unscrolled rects --
// that is the layout truth; only the pixels slide). Wrap it in a `card` or `box`
// with a border if you want a frame around the viewport.
package asaot.ui.kind
{
    import asaot.ui.Dirty;
    import asaot.ui.Node;
    import asaot.ui.PaintKit;
    import asaot.ui.ScrollViewNode;
    import asaot.ui.UiNode;
    import asaot.ui.Widget;
    import asaot.ui.style.Size;
    import asaot.ui.style.Style;
    import asaot.ui.style.Length;

    import asaot.ui.LayoutConstants;

    import flash.display.Shape;
    import flash.events.MouseEvent;
    import flash.geom.Rectangle;

    public class ScrollViewWidget implements Widget
    {
        // Scratch keys on the node (see Widget for why per-node state lives here and
        // not on the widget: one widget instance serves every node of its kind).
        private static const REQ_X:String = "reqx";
        private static const REQ_Y:String = "reqy";
        private static const LIVE_X:String = "livx";
        private static const LIVE_Y:String = "livy";
        private static const STEP_KEY:String = "step";
        private static const APPLIED:String = "applied";
        private static const REPORTED:String = "reported";

        private static const DEFAULT_W:Number = 200;
        private static const DEFAULT_H:Number = 150;

        public function build(n:UiNode):void
        {
            n.shapeA = new Shape();   // the viewport's own background (kept at +offset)
            n.backing.addChild(n.shapeA);
            // Like Slider/Tabs/List: the widget owns the listener, because only the
            // widget knows what a delta means here.
            var self:ScrollViewWidget = this;
            n.backing.addEventListener(MouseEvent.MOUSE_WHEEL,
                function (e:MouseEvent):void { self.onWheel(n, e); });
        }

        public function payload(n:UiNode, desc:Node):Boolean
        {
            var sv:ScrollViewNode = ScrollViewNode(desc);
            var step:Object = n.extra[STEP_KEY];
            if (step == null || Number(step) != sv.wheelStep) n.extra[STEP_KEY] = sv.wheelStep;
            // A CHANGE in the description is a request; an unchanged one leaves the
            // live position alone (see ScrollViewNode's header).
            if (requested(n, REQ_X, LIVE_X, sv.offsetX)) n.dirty |= Dirty.M_PAINT;
            if (requested(n, REQ_Y, LIVE_Y, sv.offsetY)) n.dirty |= Dirty.M_PAINT;
            return false;   // the viewport's own size is the style's business
        }

        private function requested(n:UiNode, reqKey:String, liveKey:String, v:Number):Boolean
        {
            var prev:Object = n.extra[reqKey];
            if (prev != null && Number(prev) == v) return false;
            n.extra[reqKey] = v;
            n.extra[liveKey] = v;
            return true;
        }

        public function wantsPress():Boolean { return false; }

        public function measure(n:UiNode):void
        {
            var s:Style = n.resolved;
            if (PaintKit.autoW(s)) PaintKit.setPointSize(n, LayoutConstants.AXIS_WIDTH, DEFAULT_W);
            if (PaintKit.autoH(s)) PaintKit.setPointSize(n, LayoutConstants.AXIS_HEIGHT, DEFAULT_H);

            // Stop the viewport from shrinking its own content (see the header). A
            // MIN is what does it, because the engine applies min/max AFTER the flex
            // solve (As3LayoutEngine.setMinMax's note) -- and a min cannot be
            // expressed as a flex instead: `setFlex(child, 0, 0, 0, UNIT_UNDEFINED)`
            // is the engine's "flex: 1" case (a zero basis), which collapses the child
            // to ZERO, and that is exactly how this widget first failed.
            var vertical:Boolean = s.flexDirection != "row";
            var axis:int = vertical ? LayoutConstants.AXIS_HEIGHT : LayoutConstants.AXIS_WIDTH;
            var eng:Object = n.app.engine;
            for (var i:int = 0; i < n.children.length; i++)
            {
                var c:UiNode = n.children[i];
                if (c.engineNode == null) continue;
                var v:Number = mainSizeOf(c, vertical);
                if (v > 0)
                {
                    eng.setMinMax(c.engineNode, axis, false, v, LayoutConstants.UNIT_POINT);
                    continue;
                }
                // No intrinsic main size anywhere: the flex solver WILL shrink this
                // child into the viewport, silently and differently from what the
                // author drew. Say so instead.
                if (!vertical) continue;   // a row viewport's cross axis is not the scroll axis
                throw new Error("asaot.ui: scrollView child "
                    + (c.key == null ? ("#" + i) : ('"' + c.key + '"'))
                    + " has no height: give it an explicit size, or use a widget that"
                    + " measures itself (text, chip, ...). A container child needs its own"
                    + " height -- a viewport silently shrinking its content is never what"
                    + " the author drew, and there would be nothing to scroll.");
            }
        }

        // The child's main-axis size BEFORE the solve: its explicit length if it has
        // one, else what its own measure pass reports. `measureSelf()` runs here
        // rather than waiting for the child's own turn in the pass, because
        // measurePass walks PARENT FIRST -- reading `state.measuredH` without asking
        // for it would use the previous frame's value.
        private function mainSizeOf(c:UiNode, vertical:Boolean):Number
        {
            var sz:Size = c.resolved.size;
            var len:Length = null;
            if (sz != null) len = vertical ? sz.height : sz.width;
            if (len != null && !len.isAuto()) return len.toEngineValue();
            c.measureSelf();
            var m:Number = vertical ? c.state.measuredH : c.state.measuredW;
            return isNaN(m) ? 0 : m;
        }

        public function arrange(n:UiNode):void
        {
            // Nothing to place: the engine places the children, `paint` slides them.
        }

        public function paint(n:UiNode):void
        {
            var w:Number = PaintKit.w1(n);
            var h:Number = PaintKit.h1(n);

            // The content extent comes from the ENGINE, not from the children's
            // `absY/absH`: in arrange the parent runs BEFORE its children, so those
            // fields still hold the previous frame's values. The engine's solve is
            // final by the time any of this runs.
            var eng:Object = n.app.engine;
            var out:Array = n.app.rectScratch;
            var cw:Number = 0;
            var ch:Number = 0;
            for (var i:int = 0; i < n.children.length; i++)
            {
                var c:UiNode = n.children[i];
                if (c.engineNode == null) continue;
                eng.layoutGet(c.engineNode, out);
                if (out[0] + out[2] > cw) cw = out[0] + out[2];
                if (out[1] + out[3] > ch) ch = out[1] + out[3];
            }
            var maxX:Number = cw - w;
            if (maxX < 0) maxX = 0;
            var maxY:Number = ch - h;
            if (maxY < 0) maxY = 0;

            var ox:Number = clamp(Number(n.extra[LIVE_X]), maxX);
            var oy:Number = clamp(Number(n.extra[LIVE_Y]), maxY);
            n.extra[LIVE_X] = ox;
            n.extra[LIVE_Y] = oy;

            if (n.shapeA != null)
            {
                // Compensate for the slide (see the header).
                n.shapeA.x = ox;
                n.shapeA.y = oy;
            }
            PaintKit.paintBox(n, n.resolved, w, h);

            // Re-assign only when it moved: the runtime copies the rectangle into the
            // object (emit.ts:10551, "store a private copy"), so assigning every frame
            // would allocate a rectangle per frame for a viewport that is merely
            // sitting still. The bookkeeping array is reused for the same reason --
            // scrolling is a per-frame path and section 7 forbids per-frame garbage.
            var applied:Array = n.extra[APPLIED] as Array;
            if (applied == null) { applied = [0, 0, 0, 0]; n.extra[APPLIED] = applied; }
            if (applied[0] != ox || applied[1] != oy || applied[2] != w || applied[3] != h)
            {
                n.backing.scrollRect = new Rectangle(0, oy, w, h);
                applied[0] = ox;
                applied[1] = oy;
                applied[2] = w;
                applied[3] = h;
            }

            // Publish the outputs, then report a real move. The CLAMPED position is
            // written back into the description so `offsetY` is always the effective
            // position, whether it was reached by a wheel or by an over-large request
            // (the wheel handler writes back for the same reason).
            var sv:ScrollViewNode = ScrollViewNode(n.desc);
            sv.offsetX = ox;
            sv.offsetY = oy;
            sv.contentW = cw;
            sv.contentH = ch;
            sv.maxOffsetX = maxX;
            sv.maxOffsetY = maxY;
            var reported:Array = n.extra[REPORTED] as Array;
            if (reported == null) { reported = [0, 0]; n.extra[REPORTED] = reported; }
            if (reported[0] != ox || reported[1] != oy)
            {
                reported[0] = ox;
                reported[1] = oy;
                if (sv.onScroll != null) sv.onScroll(ox, oy);
            }
        }

        private function clamp(v:Number, max:Number):Number
        {
            if (isNaN(v) || v < 0) return 0;
            return v > max ? max : v;
        }

        // Only vertical: the widget has no horizontal affordance (no shift-wheel, no
        // horizontal scrollbar), so a horizontal offset can only come from
        // `offsetX`. A wheel in a nested viewport must not also move the outer one.
        private function onWheel(n:UiNode, e:MouseEvent):void
        {
            var step:Number = Number(n.extra[STEP_KEY]);
            if (!(step > 0)) step = 24;
            var d:Number = e.delta;
            if (isNaN(d)) d = 0;
            // The runtime's own convention (Stage.dispatchWheel, emit.ts:21504:
            // `scrollV - delta`): a POSITIVE delta scrolls toward the START.
            var oy:Number = Number(n.extra[LIVE_Y]) - d * step;
            if (oy < 0) oy = 0;   // the upper clamp is applied by paint, which knows maxY
            if (oy == Number(n.extra[LIVE_Y])) return;
            n.extra[LIVE_Y] = oy;
            // Keep the description in step, so an author who built it once and kept a
            // reference can read the position back (authoring style B).
            var sv:ScrollViewNode = ScrollViewNode(n.desc);
            sv.offsetY = oy;
            n.app.markPaint(n);
            e.stopPropagation();
        }

        public function click(n:UiNode):Boolean { return false; }
    }
}

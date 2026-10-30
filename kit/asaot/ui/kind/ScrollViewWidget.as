// asaot.ui.kind.ScrollViewWidget -- the viewport for ScrollViewNode: the clip,
// the wheel, the TWO SCROLLBARS and their thumbs.
//
// THE CLIP IS `backing.scrollRect`, AND ITS SEMANTICS ARE NOT THE OBVIOUS ONES.
// Measured against adl 51.4.1 (recorded in the compiler, emit.ts:22731): the object
// is shown through a window of the SCROLL RECTANGLE'S SIZE that stays anchored on
// the object's own box, and the CONTENT slides by -x/-y. So
//
//     backing.scrollRect = new Rectangle(offsetX, offsetY, w, h)
//
// clips to the node's own rect AND slides the content up/left by the offsets -- the
// clip is free. The one consequence is that the slide moves EVERY child of the
// backing, including this widget's own background and scrollbar shapes, so `paint`
// compensates by placing them at +offset. Getting that backwards is how the app's
// old list painted scrolled content over its fixed header (bug D29).
//
// THE CONTENT MUST NOT BE SHRUNK BY THE VIEWPORT. `flex-shrink` defaults to 1 in
// this engine (As3LayoutNode.as:44), so a 120px column inside a 60px viewport would
// be compressed to 60px and there would be nothing to scroll. `measure` therefore
// pins `flex-shrink: 0` on every child that did not ask for a flex of its own --
// a viewport compressing its content is never what the author meant, and an
// explicit `flexShrink` still wins because the check is `anyFlex`.
//
// THE SCROLLBARS ARE PAINTED, NOT LAID OUT. They are overlay chrome: adding two
// bars as layout children would make the viewport's content width depend on
// whether a bar is showing (the classic scrollbar-gutter feedback loop), and the
// engine's rects are what the rest of the kit (and the docs tour) reason about.
// So they are two Graphics draws on `n.shapeB`, positioned in VIEWPORT space
// (compensated for the scroll, like the background). They are real mouse targets
// because a Graphics fill is a pick region (as_shape_region_hit).
//
// WHAT A SCROLLVIEW STILL DOES NOT DO: no momentum/inertia, no elastic overscroll,
// no keyboard paging, no double-click-to-maximise. A wheel is `wheelStep` per
// delta unit; the bars ARE draggable and a click on the track pages by one
// viewport (this is the honest list; anything else would be a lie in the docs).
package asaot.ui.kind
{
    import asaot.ui.Dirty;
    import asaot.ui.Node;
    import asaot.ui.PaintKit;
    import asaot.ui.ScrollViewNode;
    import asaot.ui.UiNode;
    import asaot.ui.Widget;
    import asaot.ui.WidgetTeardown;
    import asaot.ui.style.Size;
    import asaot.ui.style.Style;
    import asaot.ui.style.Length;

    import asaot.ui.LayoutConstants;

    import flash.display.Shape;
    import flash.display.Stage;
    import flash.events.MouseEvent;
    import flash.geom.Rectangle;

    public class ScrollViewWidget implements Widget, WidgetTeardown
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
        // Outputs paint publishes for the input handlers: the effective scroll
        // range and the last bar geometry. `bars` is one reused number array --
        // paint must not allocate -- with this layout:
        //   [0] hasVertical [1] hasHorizontal
        //   [2..5]  vertical track x,y,w,h
        //   [6..9]  horizontal track x,y,w,h
        //   [10..13] vertical thumb x,y,w,h
        //   [14..17] horizontal thumb x,y,w,h
        private static const MAX_X:String = "maxx";
        private static const MAX_Y:String = "maxy";
        // The PREVIOUS frame's maxY. Sticky-bottom has to compare the live offset with
        // the end it was measured against BEFORE this frame grew the content; after
        // `MAX_Y` has been overwritten, every offset looks "not at the end".
        private static const PREV_MAX_Y:String = "pmaxy";
        private static const BARS:String = "bars";
        // Pointer interaction state. DRAG is the axis being dragged (0 none,
        // 1 vertical, 2 horizontal); HOVER is the bar under the pointer, for the
        // hover colour; DRAGGED records that the drag moved, so the CLICK the
        // window synthesises after a release does not also fire the author's
        // onClick; CONSUMED records that the press landed on a bar for the same
        // reason.
        private static const DRAG:String = "drag";
        private static const DRAG_PTR:String = "dragp";
        private static const DRAG_OFF:String = "drago";
        private static const HOVER:String = "barhover";
        private static const DRAGGED:String = "dragged";
        private static const CONSUMED:String = "barpress";
        // The bar OPTIONS last seen, kept in one reused array so a settings change
        // (a colour, a mode) repaints even though it does not reflow. Comparing
        // them element-wise avoids building a signature string every frame.
        private static const OPTIONS:String = "baropts";
        // The closures installed on the STAGE for the duration of a drag, kept so
        // they can be removed by reference (and by teardown).
        private static const MOVE_FN:String = "moveFn";
        private static const UP_FN:String = "upFn";

        private static const DEFAULT_W:Number = 200;
        private static const DEFAULT_H:Number = 150;
        // Bar metrics. 10px is the "classic" desktop thickness; the thumb needs a
        // usable minimum or a viewport with a huge content stays undraggable.
        private static const BAR_T:Number = 10;
        private static const BAR_INSET:Number = 2;
        private static const MIN_THUMB:Number = 24;

        public function build(n:UiNode):void
        {
            n.shapeA = new Shape();   // the viewport's own background (kept at +offset)
            n.backing.addChild(n.shapeA);
            n.shapeB = new Shape();   // the two scrollbars (kept at +offset, on TOP)
            n.backing.addChild(n.shapeB);
            // The bars are the one display object of this kind that belongs ABOVE
            // the content. Without this the reconciler orders every content child
            // from index 2 upward, which buries the bars until some later repaint
            // happens to raise them again (UiNode.aboveContent has the story).
            n.aboveContent = n.shapeB;
            // Like Slider/Tabs/List: the widget owns the listeners, because only the
            // widget knows what a delta or a bar press means here.
            var self:ScrollViewWidget = this;
            n.listen(n.backing, MouseEvent.MOUSE_WHEEL,
                function (e:MouseEvent):void { self.onWheel(n, e); });
            // MOUSE_MOVE is also how the hover colour of a thumb is decided, and the
            // press handlers are what start a drag or page the track. They all live
            // on the backing, so a press on a child of the viewport (ordinary
            // content) bubbles here too -- the geometry test then says "not a bar".
            n.listen(n.backing, MouseEvent.MOUSE_MOVE,
                function (e:MouseEvent):void { self.onMove(n, e); });
            n.listen(n.backing, MouseEvent.MOUSE_DOWN,
                function (e:MouseEvent):void { self.onDown(n, e); });
            n.listen(n.backing, MouseEvent.MOUSE_UP,
                function (e:MouseEvent):void { self.endDrag(n); });
            n.listen(n.backing, MouseEvent.MOUSE_OUT,
                function (e:MouseEvent):void { self.setHover(n, 0); });
            n.extra[BARS] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
            n.extra[HOVER] = 0;
            n.extra[DRAG] = 0;
            n.extra[DRAGGED] = 0;
            n.extra[CONSUMED] = 0;
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
            if (optionsChanged(n, sv)) n.dirty |= Dirty.M_PAINT;
            return false;   // the viewport's own size is the style's business
        }

        private function optionsChanged(n:UiNode, sv:ScrollViewNode):Boolean
        {
            var o:Array = n.extra[OPTIONS] as Array;
            if (o == null)
            {
                o = [sv.scrollbarX, sv.scrollbarY, sv.barThickness, sv.barColor,
                     sv.barHoverColor, sv.trackColor];
                n.extra[OPTIONS] = o;
                return true;
            }
            var diff:Boolean = String(o[0]) != sv.scrollbarX || String(o[1]) != sv.scrollbarY
                || Number(o[2]) != sv.barThickness || uint(o[3]) != sv.barColor
                || uint(o[4]) != sv.barHoverColor || uint(o[5]) != sv.trackColor;
            if (!diff) return false;
            o[0] = sv.scrollbarX; o[1] = sv.scrollbarY; o[2] = sv.barThickness;
            o[3] = sv.barColor; o[4] = sv.barHoverColor; o[5] = sv.trackColor;
            return true;
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
            var sv:ScrollViewNode = ScrollViewNode(n.desc);
            var ox:Number = clamp(Number(n.extra[LIVE_X]), maxX);
            var oy:Number;
            if (sv.stickToBottom && atBottom(n, maxY))
            {
                // Following the end: jump to the new end. This is a real move (the
                // outputs and `onScroll` below see it), so an author's model stays in
                // step with the screen.
                oy = maxY;
            }
            else
            {
                oy = clamp(Number(n.extra[LIVE_Y]), maxY);
            }
            n.extra[MAX_X] = maxX;
            n.extra[MAX_Y] = maxY;
            n.extra[PREV_MAX_Y] = maxY;
            n.extra[LIVE_X] = ox;
            n.extra[LIVE_Y] = oy;

            if (n.shapeA != null)
            {
                // Compensate for the slide (see the header).
                n.shapeA.x = ox;
                n.shapeA.y = oy;
            }
            PaintKit.paintBox(n, n.resolved, w, h);
            // A VIEWPORT IS A WHEEL TARGET OVER ITS WHOLE BOX, not only where its
            // content happens to be painted. `paintBox` draws NOTHING for a style with
            // no background, and the runtime picks by PAINTED REGION
            // (as_pick_hit_local -> as_obj_region_hit_local): a pane whose style sets no
            // background therefore had holes wherever a content gap sat under the
            // pointer, and a wheel there fell through to the window root instead of
            // scrolling the pane.
            //
            // Found by the docs tour's "wheeling back did not return the pane to
            // offsetY 0": after the pane had scrolled, its fixed sample point landed on
            // a gap. A user hits the same hole by wheeling over the space between two
            // paragraphs. TableWidget already draws this rect for the same reason (it
            // paints only hairlines and glyphs).
            //
            // A transparent fill is how to be a pointer region without painting: the
            // region test does not look at alpha (the trick MOBILE.md 2.3(2) names for
            // hitSlop), and a 0-alpha fill blends to no pixel.
            if (n.shapeA != null && n.resolved.background == null)
            {
                var gh:Object = n.shapeA.graphics;
                gh.beginFill(0x000000, 0.0);
                gh.drawRect(0, 0, w, h);
                gh.endFill();
            }

            // Re-assign only when it moved: the runtime copies the rectangle into the
            // object (emit.ts:10551, "store a private copy"), so assigning every frame
            // would allocate a rectangle per frame for a viewport that is merely
            // sitting still. The bookkeeping array is reused for the same reason --
            // scrolling is a per-frame path and section 7 forbids per-frame garbage.
            var applied:Array = n.extra[APPLIED] as Array;
            if (applied == null) { applied = [0, 0, 0, 0]; n.extra[APPLIED] = applied; }
            if (applied[0] != ox || applied[1] != oy || applied[2] != w || applied[3] != h)
            {
                n.backing.scrollRect = new Rectangle(ox, oy, w, h);
                applied[0] = ox;
                applied[1] = oy;
                applied[2] = w;
                applied[3] = h;
            }

            this.paintBars(n, w, h, maxX, maxY, ox, oy);

            // Publish the outputs, then report a real move. The CLAMPED position is
            // written back into the description so `offsetY` is always the effective
            // position, whether it was reached by a wheel or by an over-large request
            // (the wheel handler writes back for the same reason).
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

        // ---- the scrollbars ---------------------------------------------------
        // Geometry + pixels in one place, because the hit tests must agree with what
        // is on screen: the numbers written into `n.extra[BARS]` here are exactly
        // what barIndexAt() tests against.
        private function paintBars(n:UiNode, w:Number, h:Number, maxX:Number, maxY:Number,
                                   ox:Number, oy:Number):void
        {
            var bars:Array = n.extra[BARS] as Array;
            if (bars == null) { bars = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]; n.extra[BARS] = bars; }
            bars[0] = 0;
            bars[1] = 0;
            if (n.shapeB == null) return;

            var sv:ScrollViewNode = ScrollViewNode(n.desc);
            var t:Number = sv.barThickness;
            if (isNaN(t) || t < 4) t = BAR_T;
            if (t > 24) t = 24;
            // An always-visible bar on an axis that cannot scroll would cover content
            // for no reason; "always" is honoured as the author's explicit choice.
            var wantY:Boolean = sv.scrollbarY == "always" || (sv.scrollbarY == "auto" && maxY > 0);
            var wantX:Boolean = sv.scrollbarX == "always" || (sv.scrollbarX == "auto" && maxX > 0);
            if (w < t * 2 || h < t * 2) { wantY = false; wantX = false; }
            if (!wantY && !wantX)
            {
                var g0:Object = n.shapeB.graphics;
                g0.clear();
                return;
            }

            // A vertical bar gives up its bottom `t` to the horizontal one (the
            // classic "corner square" rule), so the two never overlap.
            var vTrackH:Number = h - (wantX ? t : 0);
            var hTrackW:Number = w - (wantY ? t : 0);
            bars[0] = wantY ? 1 : 0;
            bars[1] = wantX ? 1 : 0;
            if (wantY) { bars[2] = w - t; bars[3] = 0; bars[4] = t; bars[5] = vTrackH; }
            if (wantX) { bars[6] = 0; bars[7] = h - t; bars[8] = hTrackW; bars[9] = t; }

            // The thumb: proportional length (floored at MIN_THUMB) and a position
            // that is the scroll offset's fraction of the free track.
            var vLen:Number = 0;
            var vPos:Number = 0;
            if (wantY)
            {
                vLen = thumbLen(vTrackH, h, maxY);
                vPos = thumbPos(vTrackH, vLen, oy, maxY);
                bars[10] = w - t + BAR_INSET;
                bars[11] = vPos + BAR_INSET;
                bars[12] = t - BAR_INSET * 2;
                bars[13] = vLen - BAR_INSET * 2;
            }
            var hLen:Number = 0;
            var hPos:Number = 0;
            if (wantX)
            {
                hLen = thumbLen(hTrackW, w, maxX);
                hPos = thumbPos(hTrackW, hLen, ox, maxX);
                bars[14] = hPos + BAR_INSET;
                bars[15] = h - t + BAR_INSET;
                bars[16] = hLen - BAR_INSET * 2;
                bars[17] = t - BAR_INSET * 2;
            }

            // Keep the bar shape LAST, so it paints (and picks) above the content.
            // UiNode.aboveContent already gives the reconciler the right base index,
            // so this is only the belt for the OTHER way a sprite ends up on top: a
            // lifted child returning to this backing is re-added at the END of the
            // display list (UiNode.applyLift), and a paint-only frame in between
            // never re-describes.
            if (n.backing != null && n.backing.numChildren > 0
                && n.backing.getChildIndex(n.shapeB) != n.backing.numChildren - 1)
            {
                n.backing.setChildIndex(n.shapeB, n.backing.numChildren - 1);
            }
            // The bars are chrome: they must not slide with the content.
            n.shapeB.x = ox;
            n.shapeB.y = oy;

            var hover:int = int(n.extra[HOVER]);
            var drag:int = int(n.extra[DRAG]);
            var g:Object = n.shapeB.graphics;
            g.clear();
            var track:uint = sv.trackColor;
            if (wantY)
            {
                g.beginFill(track, 1.0);
                g.drawRoundRect(bars[2], bars[3], bars[4], bars[5],
                    Math.min(bars[4], bars[5]) * 0.5, Math.min(bars[4], bars[5]) * 0.5);
                g.endFill();
                var litY:Boolean = hover == 1 || drag == 1;
                g.beginFill(litY ? sv.barHoverColor : sv.barColor, 1.0);
                var r1:Number = Math.min(bars[12], bars[13]) * 0.5;
                g.drawRoundRect(bars[10], bars[11], bars[12], bars[13], r1, r1);
                g.endFill();
            }
            if (wantX)
            {
                g.beginFill(track, 1.0);
                g.drawRoundRect(bars[6], bars[7], bars[8], bars[9],
                    Math.min(bars[8], bars[9]) * 0.5, Math.min(bars[8], bars[9]) * 0.5);
                g.endFill();
                var litX:Boolean = hover == 2 || drag == 2;
                g.beginFill(litX ? sv.barHoverColor : sv.barColor, 1.0);
                var r2:Number = Math.min(bars[16], bars[17]) * 0.5;
                g.drawRoundRect(bars[14], bars[15], bars[16], bars[17], r2, r2);
                g.endFill();
            }
        }

        // Thumb length: the visible fraction of the content, floored so it stays
        // grabbable, and never longer than the track.
        private function thumbLen(track:Number, view:Number, maxOff:Number):Number
        {
            if (track <= 0) return 0;
            var len:Number = view + maxOff > 0 ? track * view / (view + maxOff) : track;
            if (maxOff <= 0) len = track;
            if (len < MIN_THUMB) len = MIN_THUMB;
            if (len > track) len = track;
            return len;
        }

        private function thumbPos(track:Number, len:Number, off:Number, maxOff:Number):Number
        {
            var span:Number = track - len;
            if (span <= 0 || maxOff <= 0) return 0;
            return off / maxOff * span;
        }

        // "Was the view at the END of its content?" asked against the PREVIOUS frame's
        // `maxY`, before this frame's growth changed the answer.
        //
        // `prev == null` (the first paint, or a viewport that has never been laid out)
        // counts as at-the-end: a log's first paint should show its newest line, not its
        // oldest. 0.5px of slack absorbs the fractional offsets a bar drag produces; a
        // whole pixel off the end is a reader who scrolled up and must not be yanked.
        private function atBottom(n:UiNode, maxY:Number):Boolean
        {
            var prev:Object = n.extra[PREV_MAX_Y];
            var live:Number = Number(n.extra[LIVE_Y]);
            if (isNaN(live)) live = 0;
            if (prev == null) return true;
            return live >= Number(prev) - 0.5;
        }

        private function clamp(v:Number, max:Number):Number
        {
            if (isNaN(v) || v < 0) return 0;
            return v > max ? max : v;
        }

        // ---- input ------------------------------------------------------------
        // Which bar sits under a viewport-local point: 1/2 = the vertical /
        // horizontal THUMB, 3/4 = the matching TRACK, 0 = neither. The geometry is
        // the one paint wrote, so the target always matches the pixels.
        private function barIndexAt(n:UiNode, lx:Number, ly:Number):int
        {
            var bars:Array = n.extra[BARS] as Array;
            if (bars == null) return 0;
            if (int(bars[0]) != 0
                && lx >= bars[10] && lx <= bars[10] + bars[12]
                && ly >= bars[11] && ly <= bars[11] + bars[13]) return 1;
            if (int(bars[1]) != 0
                && lx >= bars[14] && lx <= bars[14] + bars[16]
                && ly >= bars[15] && ly <= bars[15] + bars[17]) return 2;
            if (int(bars[0]) != 0
                && lx >= bars[2] && lx <= bars[2] + bars[4]
                && ly >= bars[3] && ly <= bars[3] + bars[5]) return 3;
            if (int(bars[1]) != 0
                && lx >= bars[6] && lx <= bars[6] + bars[8]
                && ly >= bars[7] && ly <= bars[7] + bars[9]) return 4;
            return 0;
        }

        private function setHover(n:UiNode, v:int):void
        {
            if (int(n.extra[HOVER]) == v) return;
            n.extra[HOVER] = v;
            n.app.markPaint(n);
        }

        private function onMove(n:UiNode, e:MouseEvent):void
        {
            if (int(n.extra[DRAG]) != 0) return;   // the stage listener owns a drag
            this.setHover(n, barIndexAt(n, e.stageX - n.absX, e.stageY - n.absY));
        }

        private function onDown(n:UiNode, e:MouseEvent):void
        {
            // A fresh press clears both latches: a drag that ended outside never got
            // its CLICK, so the flags can only be trusted within one press.
            n.extra[DRAGGED] = 0;
            n.extra[CONSUMED] = 0;
            this.endDrag(n);
            var bars:Array = n.extra[BARS] as Array;
            if (bars == null) return;
            var lx:Number = e.stageX - n.absX;
            var ly:Number = e.stageY - n.absY;
            var idx:int = this.barIndexAt(n, lx, ly);
            if (idx == 1 || idx == 2)
            {
                n.extra[CONSUMED] = 1;
                this.beginDrag(n, idx, e);
                return;
            }
            if (idx == 3 || idx == 4)
            {
                // A click on the track pages by one viewport toward the click. The
                // thumb's own position decides the direction (a click ABOVE the
                // thumb goes back).
                n.extra[CONSUMED] = 1;
                if (idx == 3)
                {
                    var up:Boolean = ly < Number(bars[11]);
                    this.pageY(n, up ? -1 : 1);
                }
                else
                {
                    var left:Boolean = lx < Number(bars[14]);
                    this.pageX(n, left ? -1 : 1);
                }
            }
        }

        private function beginDrag(n:UiNode, axis:int, e:MouseEvent):void
        {
            n.extra[DRAG] = axis;
            n.extra[DRAG_PTR] = (axis == 1) ? e.stageY : e.stageX;
            n.extra[DRAG_OFF] = (axis == 1) ? Number(n.extra[LIVE_Y]) : Number(n.extra[LIVE_X]);
            var st:Stage = n.app.stage;
            if (st != null)
            {
                var self:ScrollViewWidget = this;
                var mv:Function = function (ev:MouseEvent):void { self.onDragMove(n, ev); };
                var upFn:Function = function (ev:MouseEvent):void { self.endDrag(n); };
                n.extra[MOVE_FN] = mv;
                n.extra[UP_FN] = upFn;
                // The runtime dispatches motion to whatever is under the POINTER, so
                // a drag that leaves the thumb (or the window's viewport) would stop
                // receiving events. Listening on the STAGE for the duration of the
                // drag is the capture layer this runtime does not have.
                st.addEventListener(MouseEvent.MOUSE_MOVE, mv);
                st.addEventListener(MouseEvent.MOUSE_UP, upFn);
            }
            this.setHover(n, axis);
            n.app.markPaint(n);
        }

        private function onDragMove(n:UiNode, e:MouseEvent):void
        {
            var axis:int = int(n.extra[DRAG]);
            if (axis == 0) return;
            var bars:Array = n.extra[BARS] as Array;
            if (bars == null) return;
            var ptr:Number = (axis == 1) ? e.stageY : e.stageX;
            var startPtr:Number = Number(n.extra[DRAG_PTR]);
            var d:Number = ptr - startPtr;
            if (d > 2 || d < -2) n.extra[DRAGGED] = 1;
            var track:Number = (axis == 1) ? Number(bars[5]) : Number(bars[8]);
            var thumb:Number = (axis == 1) ? Number(bars[13]) : Number(bars[17]);
            // bars[] stores the DRAWN thumb, which is inset by BAR_INSET on both ends,
            // so add the insets back: the pointer must move the thumb 1:1, and the
            // thumb's travel is `track - fullLength`, not `track - drawnLength`
            // (using the drawn length makes the content race ahead of the pointer by
            // 2*BAR_INSET / free-travel, ~8% here).
            var span:Number = track - thumb - BAR_INSET * 2;
            var maxOff:Number = (axis == 1) ? Number(n.extra[MAX_Y]) : Number(n.extra[MAX_X]);
            if (isNaN(span) || span <= 0 || isNaN(maxOff) || maxOff <= 0) return;
            var off:Number = Number(n.extra[DRAG_OFF]) + d * maxOff / span;
            if (off < 0) off = 0;
            if (off > maxOff) off = maxOff;
            if (axis == 1)
            {
                if (off == Number(n.extra[LIVE_Y])) return;
                n.extra[LIVE_Y] = off;
            }
            else
            {
                if (off == Number(n.extra[LIVE_X])) return;
                n.extra[LIVE_X] = off;
            }
            var sv:ScrollViewNode = ScrollViewNode(n.desc);
            if (axis == 1) sv.offsetY = off; else sv.offsetX = off;
            n.app.markPaint(n);
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
                if (n.app != null) n.app.markPaint(n);
            }
        }

        // WidgetTeardown: a viewport destroyed mid-drag must not leave its stage
        // listeners pointing at a nulled scratch bag (the bug the gallery's menus
        // had). endDrag is idempotent.
        public function teardown(n:UiNode):void
        {
            this.endDrag(n);
        }

        // One wheel notch scrolls the axis that can scroll. Vertical wins when both
        // can: a horizontal-only viewport (a film strip) is the case that needs the
        // fallback, and a shift-wheel would need a modifier the runtime's wheel event
        // does not carry (Stage_dispatchWheel has no shiftKey).
        private function onWheel(n:UiNode, e:MouseEvent):void
        {
            var step:Number = Number(n.extra[STEP_KEY]);
            if (!(step > 0)) step = 24;
            var d:Number = e.delta;
            if (isNaN(d)) d = 0;
            var maxY:Number = Number(n.extra[MAX_Y]);
            if (maxY > 0)
            {
                if (this.scrollY(n, -d * step)) e.stopPropagation();
                return;
            }
            var maxX:Number = Number(n.extra[MAX_X]);
            if (maxX > 0 && this.scrollX(n, -d * step)) e.stopPropagation();
        }

        // The runtime's own convention (Stage.dispatchWheel, emit.ts:21504:
        // `scrollV - delta`): a POSITIVE delta scrolls toward the START.
        private function scrollY(n:UiNode, dx:Number):Boolean
        {
            var maxOff:Number = Number(n.extra[MAX_Y]);
            var oy:Number = Number(n.extra[LIVE_Y]) + dx;
            if (oy < 0) oy = 0;
            if (oy > maxOff) oy = maxOff;
            if (oy == Number(n.extra[LIVE_Y])) return false;
            n.extra[LIVE_Y] = oy;
            ScrollViewNode(n.desc).offsetY = oy;
            n.app.markPaint(n);
            return true;
        }

        private function scrollX(n:UiNode, dx:Number):Boolean
        {
            var maxOff:Number = Number(n.extra[MAX_X]);
            var ox:Number = Number(n.extra[LIVE_X]) + dx;
            if (ox < 0) ox = 0;
            if (ox > maxOff) ox = maxOff;
            if (ox == Number(n.extra[LIVE_X])) return false;
            n.extra[LIVE_X] = ox;
            ScrollViewNode(n.desc).offsetX = ox;
            n.app.markPaint(n);
            return true;
        }

        private function pageY(n:UiNode, dir:int):void
        {
            var view:Number = PaintKit.h1(n);
            this.scrollY(n, dir * view * 0.9);
        }

        private function pageX(n:UiNode, dir:int):void
        {
            var view:Number = PaintKit.w1(n);
            this.scrollX(n, dir * view * 0.9);
        }

        // The press landed on a bar, or the pointer moved during a drag: either way
        // this is NOT the author's click, so it is consumed.
        public function click(n:UiNode):Boolean
        {
            var consumed:Boolean = int(n.extra[CONSUMED]) != 0 || int(n.extra[DRAGGED]) != 0;
            n.extra[CONSUMED] = 0;
            n.extra[DRAGGED] = 0;
            return consumed;
        }
    }
}

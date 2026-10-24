// asaot.ui.kind.PopoverWidget -- positions an anchored panel and closes it on an
// outside click.
//
// TWO MECHANISMS, NOTHING ELSE:
//
//   1. POSITION. Every measure pass writes the panel's insets from the anchor's
//      solved rect. Insets (not x/y) because the panel is `position: absolute` and
//      the engine places it during the solve; writing x/y would fight the engine.
//      ALL FOUR insets are cleared first, because UiNode.applyLengthSide returns
//      early for a null side -- nothing else would ever clear a stale edge, and a
//      placement flip would leave the panel pinned to the old side.
//
//   2. DISMISS. A STAGE-level CLICK listener: if the event's target is not inside
//      this node, call onClose. The identity walk (`backing == n.backing` up the
//      parent chain) is used instead of a stageX/stageY comparison because it is
//      exact regardless of where the stage container sits -- and a popover whose
//      panel is 3px from the anchor must not be dismissed by rounding.
//
//      The click is NOT swallowed: whatever is under the pointer still sees it.
//      That is normal popover behaviour; modal surfaces use dialog() instead.
//
// WHY measure AND NOT arrange: the anchor's rect for THIS frame is final after the
// main tree's solve, and the overlay tree is solved second (UiApp.reflow). measure
// runs before this tree's own solve, so writing the insets there is the last word.
package asaot.ui.kind
{
    import asaot.ui.Dirty;
    import asaot.ui.LayoutConstants;
    import asaot.ui.LayoutEngine;
    import asaot.ui.Node;
    import asaot.ui.OverlayMotion;
    import asaot.ui.PaintKit;
    import asaot.ui.PopoverNode;
    import asaot.ui.style.Style;
    import asaot.ui.UiNode;
    import flash.display.Shape;
    import asaot.ui.Widget;
    import asaot.ui.WidgetTeardown;

    import flash.display.DisplayObject;
    import flash.display.Stage;
    import flash.events.MouseEvent;

    public class PopoverWidget implements Widget, WidgetTeardown
    {
        protected static const OPEN_KEY:String = "open";
        protected static const ANCHOR_KEY:String = "anchor";
        protected static const PLACE_KEY:String = "place";
        protected static const OFFSET_KEY:String = "offset";
        protected static const CLOSE_KEY:String = "closeOnOutside";
        protected static const FN_KEY:String = "onClose";
        protected static const MISS_KEY:String = "anchorMiss";
        // The placement ACTUALLY used this frame: the requested one, unless it would
        // have overflowed the window (see `measure`).
        protected static const EFF_KEY:String = "effPlace";
        protected static const EDGE_MARGIN:Number = 4;
        // What teardown() needs to UNDO build(): the stage it subscribed to and the
        // closure it subscribed with. Kept on the node (not on the widget) because
        // one widget instance serves every node of its kind.
        protected static const STAGE_KEY:String = "stage";
        protected static const FNCLICK_KEY:String = "stageFn";

        public function build(n:UiNode):void
        {
            // One Shape at child INDEX 0 holds the panel/trigger background;
            // PaintKit.paintBox draws nothing without it, so the surface used to
            // have a correct solved rect and paint nothing at all. Same layout as
            // BoxWidget: the shape is added in build(), before the reconciler
            // appends this node's children, so the children keep a stable base
            // index for display-order repair.
            n.shapeA = new Shape();
            n.backing.addChild(n.shapeA);
            n.extra[OPEN_KEY] = false;
            n.extra[ANCHOR_KEY] = null;            n.extra[PLACE_KEY] = "bottom";
            n.extra[OFFSET_KEY] = 6;
            n.extra[CLOSE_KEY] = 1;
            n.extra[FN_KEY] = null;
            n.extra[MISS_KEY] = 0;
            n.extra[EFF_KEY] = "bottom";
            // Attached ONCE, at structure time, on the STAGE -- not on this node.
            // A click outside the panel never reaches this node's backing (that is
            // what "outside" means), so a listener here could only ever see clicks
            // that do not dismiss. The stage sees every click that bubbles.
            //
            // Added once instead of per-open: a per-open add/remove pair has to be
            // torn down correctly on every path (open flip, node destroyed, view
            // rebuilt) and one missed removal leaks a listener that keeps the node
            // alive forever. The ONE path that must remove it is the node being
            // destroyed -- see teardown().
            var self:PopoverWidget = this;
            var onStage:Function = function (e:MouseEvent):void { self.onAnyClick(n, e); };
            // Remembered so teardown() can remove it: a stage listener outlives the
            // node, and a destroyed node has no n.extra / n.app left to read.
            n.extra[STAGE_KEY] = n.app.stage;
            n.extra[FNCLICK_KEY] = onStage;
            n.app.stage.addEventListener(MouseEvent.CLICK, onStage);
        }

        public function payload(n:UiNode, desc:Node):Boolean
        {
            var p:PopoverNode = PopoverNode(desc);
            var relayout:Boolean = false;

            var prevAnchor:Object = n.extra[ANCHOR_KEY];
            var prevPlace:Object = n.extra[PLACE_KEY];
            var prevOffset:Object = n.extra[OFFSET_KEY];
            if (prevAnchor != p.anchorKey || prevPlace != p.placement
                || Number(prevOffset) != p.offset)
            {
                n.extra[ANCHOR_KEY] = p.anchorKey;
                n.extra[PLACE_KEY] = p.placement;
                n.extra[OFFSET_KEY] = p.offset;
                // A move is not a re-measure of the CONTENT, but this engine only
                // re-runs the inset writers from measure, so a move has to ask for
                // the same sweep (see UiNode.applyPayload).
                relayout = true;
            }
            n.extra[CLOSE_KEY] = p.closeOnOutside ? 1 : 0;
            n.extra[FN_KEY] = p.onClose;

            var was:Boolean = Boolean(n.extra[OPEN_KEY]);
            if (was != p.open)
            {
                n.extra[OPEN_KEY] = p.open;
                n.visible = p.open;
                if (n.backing != null) n.backing.visible = p.open;
                // The entrance runs on the flip, not on every frame: a surface that
                // re-entered on each describe would never settle.
                if (p.open) OverlayMotion.start(n);
                relayout = true;
            }
            return relayout;
        }

        // Called from UiNode.destroySubtree while n.extra is still readable.
        public function teardown(n:UiNode):void
        {
            if (n.extra == null) return;
            var st:Object = n.extra[STAGE_KEY];
            var fn:Object = n.extra[FNCLICK_KEY];
            n.extra[STAGE_KEY] = null;
            n.extra[FNCLICK_KEY] = null;
            if (st == null || fn == null) return;
            // The runtime removes by (implementation, bound receiver), and this IS
            // the same closure object, so this always matches one entry.
            Stage(st).removeEventListener(MouseEvent.CLICK, fn as Function);
        }

        public function wantsPress():Boolean { return false; }

        public function measure(n:UiNode):void
        {
            if (n.engineNode == null) return;
            var eng:LayoutEngine = n.app.engine;
            var e:Object = n.engineNode;

            // Clear every side first -- see the header.
            eng.setPosition(e, LayoutConstants.EDGE_LEFT, 0, LayoutConstants.UNIT_UNDEFINED);
            eng.setPosition(e, LayoutConstants.EDGE_RIGHT, 0, LayoutConstants.UNIT_UNDEFINED);
            eng.setPosition(e, LayoutConstants.EDGE_TOP, 0, LayoutConstants.UNIT_UNDEFINED);
            eng.setPosition(e, LayoutConstants.EDGE_BOTTOM, 0, LayoutConstants.UNIT_UNDEFINED);

            var a:UiNode = this.anchorOf(n);
            n.extra[MISS_KEY] = a == null ? 1 : 0;
            if (a == null) return;

            var off:Number = Number(n.extra[OFFSET_KEY]);
            var want:String = String(n.extra[PLACE_KEY]);
            var winW:Number = PopoverWidget.windowW(n);
            var winH:Number = PopoverWidget.windowH(n);

            // ABSOLUTE -> PARENT-LOCAL. The engine's insets are relative to the
            // PARENT's padding box (its border box inset by the border), and the
            // anchor's `absX/absY` are absolute. For a top-level surface the parent
            // is the overlay root at the window origin with no border, so ox/oy are
            // 0 and ow/oh are the window -- which is why this used to be written
            // straight through with absolute numbers and worked. A SUBMENU is the
            // first surface whose parent is not at the origin; without this
            // conversion its panel landed one menu-offset away from its row.
            var ox:Number = 0, oy:Number = 0;
            if (n.parent != null)
            {
                var ps:Style = n.parent.resolved;
                var pbx:Number = ps.borderWidths == null ? 0 : PaintKit.nz(ps.borderWidths.left);
                var pby:Number = ps.borderWidths == null ? 0 : PaintKit.nz(ps.borderWidths.top);
                ox = n.parent.absX + pbx;
                oy = n.parent.absY + pby;
            }

            // ---- FLIP ---------------------------------------------------
            // The panel's own size is not known before the solve, so this uses the
            // PREVIOUS frame's solved rect (n.absW/absH; 0 on the very first frame,
            // where the requested placement is used as-is). That is the standard
            // two-pass compromise, and it is safe here because every overlay node is
            // measured on every solve whether or not it is visible -- so a panel is
            // never opened without a size from an earlier pass. (An explicit
            // "please solve again" hook was written first and then removed: no probe
            // could make it observable, which means it had no reachable case.)
            //
            // ONLY START EDGES ARE WRITTEN, and only ever from the anchor's rect and
            // the panel's own size -- never from the PARENT's size. The parent's
            // `absW/absH` are a frame stale during measure (arrange writes them), and
            // on the frame a window resize lands that stale value is the OLD window:
            // a bottom-pinned inset then lands the panel 200px above its anchor and,
            // because nothing measures it again, it stays there. (The flip probe
            // caught exactly that, as a popover at y=-80.)
            var pw:Number = n.absW > 0 ? n.absW : 0;
            var ph:Number = n.absH > 0 ? n.absH : 0;
            var place:String = want;
            if (pw > 0 && ph > 0)
            {
                if (want == "bottom" && a.absY + a.absH + off + ph > winH
                    && a.absY - off - ph >= 0) place = "top";
                else if (want == "top" && a.absY - off - ph < 0
                    && a.absY + a.absH + off + ph <= winH) place = "bottom";
                else if (want == "right" && a.absX + a.absW + off + pw > winW
                    && a.absX - off - pw >= 0) place = "left";
                else if (want == "left" && a.absX - off - pw < 0
                    && a.absX + a.absW + off + pw <= winW) place = "right";
            }
            n.extra[EFF_KEY] = place;

            if (place == "top")
            {
                eng.setPosition(e, LayoutConstants.EDGE_LEFT, clampX(a.absX, pw, winW) - ox,
                                LayoutConstants.UNIT_POINT);
                eng.setPosition(e, LayoutConstants.EDGE_TOP, a.absY - off - ph - oy,
                                LayoutConstants.UNIT_POINT);
            }
            else if (place == "right")
            {
                eng.setPosition(e, LayoutConstants.EDGE_LEFT, a.absX + a.absW + off - ox,
                                LayoutConstants.UNIT_POINT);
                eng.setPosition(e, LayoutConstants.EDGE_TOP, clampY(a.absY, ph, winH) - oy,
                                LayoutConstants.UNIT_POINT);
            }
            else if (place == "left")
            {
                eng.setPosition(e, LayoutConstants.EDGE_LEFT, a.absX - off - pw - ox,
                                LayoutConstants.UNIT_POINT);
                eng.setPosition(e, LayoutConstants.EDGE_TOP, clampY(a.absY, ph, winH) - oy,
                                LayoutConstants.UNIT_POINT);
            }
            else
            {
                eng.setPosition(e, LayoutConstants.EDGE_LEFT, clampX(a.absX, pw, winW) - ox,
                                LayoutConstants.UNIT_POINT);
                eng.setPosition(e, LayoutConstants.EDGE_TOP, a.absY + a.absH + off - oy,
                                LayoutConstants.UNIT_POINT);
            }
        }

        // Keep the panel inside the window on the axis the placement leaves free.
        // `size <= 0` means "not solved yet" -- clamping with a 0 width would pin the
        // panel to the right edge on the very first frame.
        protected static function clampX(x:Number, w:Number, winW:Number):Number
        {
            if (w <= 0) return x;
            var v:Number = x;
            if (v + w > winW - EDGE_MARGIN) v = winW - EDGE_MARGIN - w;
            if (v < EDGE_MARGIN) v = EDGE_MARGIN;
            return v;
        }

        protected static function clampY(y:Number, h:Number, winH:Number):Number
        {
            if (h <= 0) return y;
            var v:Number = y;
            if (v + h > winH - EDGE_MARGIN) v = winH - EDGE_MARGIN - h;
            if (v < EDGE_MARGIN) v = EDGE_MARGIN;
            return v;
        }

        public function arrange(n:UiNode):void { }

        public function paint(n:UiNode):void
        {
            // The panel's own background/border; children paint on top of it.
            PaintKit.paintBox(n, n.resolved, PaintKit.w1(n), PaintKit.h1(n));
            // Entrance: fade + a small rise, on the panel itself.
            OverlayMotion.apply(n, n, n, 0, 8);
        }

        public function click(n:UiNode):Boolean { return false; }

        // ---- helpers ------------------------------------------------------
        protected function anchorOf(n:UiNode):UiNode
        {
            var k:Object = n.extra[ANCHOR_KEY];
            if (k == null || n.app == null) return null;
            return n.app.findByKey(k);
        }

        // The overlay tree is laid out against the stage, so the window size is the
        // stage size. Same fallback as UiApp.reflow, so a headless/stage-less mount
        // cannot make the two disagree.
        protected static function windowW(n:UiNode):Number
        {
            if (n.app != null && n.app.stage != null && n.app.stage.stageWidth > 0)
                return n.app.stage.stageWidth;
            return 560;
        }

        protected static function windowH(n:UiNode):Number
        {
            if (n.app != null && n.app.stage != null && n.app.stage.stageHeight > 0)
                return n.app.stage.stageHeight;
            return 460;
        }

        protected function isInside(n:UiNode, t:Object):Boolean
        {
            var o:DisplayObject = t as DisplayObject;
            while (o != null)
            {
                if (o == n.backing) return true;
                o = o.parent;
            }
            return false;
        }

        protected function onAnyClick(n:UiNode, e:MouseEvent):void
        {
            if (!Boolean(n.extra[OPEN_KEY])) return;
            if (Number(n.extra[CLOSE_KEY]) == 0) return;
            if (this.isInside(n, e.target)) return;
            var f:Function = n.extra[FN_KEY];
            if (f != null) f();
        }
    }
}
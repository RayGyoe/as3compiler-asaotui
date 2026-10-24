// asaot.ui.kind.TableWidget -- the container for TableNode.
//
// The rows and cells are NOT this widget's display objects: they are child
// UiNodes the factory made and the reconciler mounted, and the layout ENGINE
// places them. So `build` only owns the background shape, and `measure`/`arrange`
// do nothing (a container's intrinsic size is the engine's job; see BoxWidget).
//
// EVERYTHING PAINTED HERE IS A FILL, NEVER A STROKE. Measured on this backend
// (temp/stroke/, 2026-10-23): a filled rect rasterises exactly at the declared
// pixel box, while `lineStyle` stroke width is not honoured -- a 1px grid line
// drawn as a line is not the 1px the author asked for. So the hairlines, the zebra
// stripes and the selection highlight are all `drawRect` fills, which is also why
// the probe can assert their exact colours.
//
// The geometry comes from the CHILDREN's laid-out rects (absX/absY/absW/absH,
// resolved by the engine in the arrange pass), never from arithmetic over the
// column list -- so a grid line lands exactly where the engine put the column
// boundary, and a widget bug cannot silently drift from the layout.
//
// SELECTION: like ListWidget, a click's y selects a BODY row (the header is
// skipped) through a listener added at structure time. `selectedIndex` is a
// DECORATION: a selection change raises only Dirty.M_PAINT and never reflows.
package asaot.ui.kind
{
    import asaot.ui.TableNode;
    import asaot.ui.Dirty;
    import asaot.ui.Node;
    import asaot.ui.PaintKit;
    import asaot.ui.UiNode;
    import asaot.ui.Widget;

    import flash.display.Shape;
    import flash.events.MouseEvent;

    public class TableWidget implements Widget
    {
        private static const SEL_KEY:String = "sel";    // selected BODY row (-1 = none)
        private static const HIT_KEY:String = "hit";    // 1 when the last click hit a body row
        private static const HDR_KEY:String = "hdr";    // 1 when a header row exists
        private static const STR_KEY:String = "str";    // stripes on
        private static const GRID_KEY:String = "grid";  // grid lines on

        public function build(n:UiNode):void
        {
            // shapeA sits at backing child index 0, i.e. BEHIND every row/cell
            // backing, so the stripes/grid/selection show through a transparent row.
            n.shapeA = new Shape();
            n.backing.addChild(n.shapeA);
            n.extra[SEL_KEY] = -1;
            n.extra[HIT_KEY] = 0;
            n.extra[HDR_KEY] = 0;
            n.extra[STR_KEY] = 0;
            n.extra[GRID_KEY] = 1;

            var self:TableWidget = this;
            n.listen(n.backing, MouseEvent.CLICK,
                function (e:MouseEvent):void { self.onClickY(n, e); });
        }

        public function payload(n:UiNode, desc:Node):Boolean
        {
            var t:TableNode = TableNode(desc);
            n.binding = t.binding;
            // UiNode has no dedicated onSelect slot; reuse onChange (same
            // Function(Number) contract as the other selectable controls).
            n.onChange = t.onSelect;
            n.extra[HDR_KEY] = t.header ? 1 : 0;
            n.extra[STR_KEY] = t.stripes ? 1 : 0;
            n.extra[GRID_KEY] = t.grid ? 1 : 0;

            var sv:Number = t.selectedIndex;
            if (t.binding != null)
            {
                // `*`, NOT `Object`: an `Object` slot would box the value once per read.
                // Number() never depended on the G9 fix (阶段二四八) and the G14 Array-identity
                // hazard (阶段二百五十三) is closed too, so `*` is now purely the cheaper default.
                var bv:* = t.binding.get();
                sv = bv == null ? -1 : Number(bv);
            }
            var prev:Object = n.extra[SEL_KEY];
            if (prev == null || Number(prev) != sv)
            {
                n.extra[SEL_KEY] = sv;
                n.dirty |= Dirty.M_PAINT;   // decoration only: never a reflow
            }
            // Structure (columns / rows / rowHeight) is carried by the child nodes
            // the factory built; the reconciler diffs them, so this node never
            // reports a re-measure itself.
            return false;
        }

        public function wantsPress():Boolean { return true; }

        public function measure(n:UiNode):void
        {
            // The engine sizes the container from its rows (see BoxWidget).
        }

        public function arrange(n:UiNode):void
        {
            // Rows are placed by the engine; nothing internal to position.
        }

        public function paint(n:UiNode):void
        {
            // Clears shapeA, so every fill below is redrawn from scratch.
            PaintKit.paintBox(n, n.resolved, PaintKit.w1(n), PaintKit.h1(n));
            if (n.shapeA == null) return;

            var g:Object = n.shapeA.graphics;
            var hdr:Boolean = Number(n.extra[HDR_KEY]) != 0;
            var stripes:Boolean = Number(n.extra[STR_KEY]) != 0;
            var sel:int = int(Number(n.extra[SEL_KEY]));
            var w:Number = PaintKit.w1(n);

            // ---- stripes + selection (behind the cells) ----------------------
            var body:int = 0;
            for (var i:int = 0; i < n.children.length; i++)
            {
                var c:UiNode = n.children[i];
                var isHdr:Boolean = hdr && i == 0;
                if (!isHdr && stripes && (body % 2) == 1)
                {
                    g.beginFill(TableNode.STRIPE_BG, 1.0);
                    g.drawRect(c.absX - n.absX, c.absY - n.absY, c.absW, c.absH);
                    g.endFill();
                }
                if (!isHdr && body == sel)
                {
                    g.beginFill(TableNode.SEL_BG, 1.0);
                    g.drawRect(c.absX - n.absX, c.absY - n.absY, c.absW, c.absH);
                    g.endFill();
                }
                if (!isHdr) body = body + 1;
            }

            // ---- grid -------------------------------------------------------
            if (Number(n.extra[GRID_KEY]) == 0) return;
            var count:int = n.children.length;
            if (count == 0) return;
            g.beginFill(TableNode.GRID_LINE, 1.0);
            // Horizontal hairlines on the bottom edge of every row but the last.
            for (var r:int = 0; r < count - 1; r++)
            {
                var rr:UiNode = n.children[r];
                g.drawRect(0, rr.absY - n.absY + rr.absH, w, 1);
            }
            // Vertical hairlines at the column boundaries, taken from the FIRST
            // row's cells (all rows share the same basis, so they agree; the probe
            // asserts exactly that).
            var first:UiNode = n.children[0];
            var top:Number = first.absY - n.absY;
            var last:UiNode = n.children[count - 1];
            var bottom:Number = last.absY - n.absY + last.absH;
            for (var j:int = 1; j < first.children.length; j++)
            {
                var cell:UiNode = first.children[j];
                g.drawRect(cell.absX - n.absX, top, 1, bottom - top);
            }
            g.endFill();
        }

        // Consume the click only when it actually landed on a body row; a click in
        // the container's own padding still falls through to the author's onClick.
        public function click(n:UiNode):Boolean
        {
            var hit:* = n.extra[HIT_KEY];
            return hit != null && Boolean(hit);
        }

        private function onClickY(n:UiNode, e:MouseEvent):void
        {
            n.extra[HIT_KEY] = 0;
            var hdr:Boolean = Number(n.extra[HDR_KEY]) != 0;
            var target:int = -1;
            var body:int = 0;
            for (var i:int = 0; i < n.children.length; i++)
            {
                if (hdr && i == 0) continue;   // the header selects nothing
                var c:UiNode = n.children[i];
                var top:Number = c.backing.y;
                var bot:Number = top + c.absH;
                if (e.localY >= top && e.localY < bot) { target = body; break; }
                body = body + 1;
            }
            if (target < 0) return;

            n.extra[HIT_KEY] = 1;
            // Do NOT write n.extra[SEL_KEY]: payload must observe the change and
            // raise Dirty.M_PAINT (same reason as TabsWidget.onClickX).
            if (n.binding != null) n.binding.set(target);
            n.app.markPaint(n);
            if (n.onChange != null) n.onChange(target);
            n.app.invalidate(Dirty.VALUE);
        }
    }
}
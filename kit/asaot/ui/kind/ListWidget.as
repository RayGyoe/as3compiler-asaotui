// asaot.ui.kind.ListWidget -- the container for ListNode.
//
// The rows are NOT this widget's display objects: they are child UiNodes the
// factory made and the reconciler mounted, and the layout ENGINE places them.
// So `build` only owns the background shape, and `measure`/`arrange` do nothing
// (a container's intrinsic size is the engine's job; see BoxWidget).
//
// SELECTION: a click's y is mapped to a row by walking the children and skipping
// the divider children (a `divider` child is a separator, never a row). The
// selected row is highlighted by a fill drawn into this node's OWN shapeA, which
// sits at backing child index 0 -- i.e. BEHIND every row backing, so a
// transparent row shows the highlight without the rows needing to know about
// selection. Exactly like SliderWidget/TabsWidget, the coordinate comes from our
// own MouseEvent.CLICK listener because `Widget.click(n)` gets no event.
//
// `selectedIndex` is a DECORATION: a selection change raises only
// Dirty.M_PAINT and never reflows.
//
// KEYBOARD (2026-10-26): the list is ONE tab stop and the arrows walk its rows --
// the ARIA listbox model, and the same shape TreeWidget/VirtualListWidget use. The
// two directions are CLAMPED, not wrapped: a listbox stops at its ends (a tree wraps
// because moving off the last row of a tree is a spatial question, not a sequence
// one). Enter is deliberately NOT consumed -- UiApp's default activation then runs the
// node's own onClick, which is the container's handler, not a row's.
package asaot.ui.kind
{
    import asaot.ui.ListNode;
    import asaot.ui.Dirty;
    import asaot.ui.Node;
    import asaot.ui.PaintKit;
    import asaot.ui.UiNode;
    import asaot.ui.Widget;
    import asaot.ui.WidgetKeys;

    import flash.display.Shape;
    import flash.events.MouseEvent;

    public class ListWidget implements Widget, WidgetKeys
    {
        private static const SEL_KEY:String = "sel";   // previous selected index
        private static const HIT_KEY:String = "hit";   // 1 when the last click hit a row

        private static const SEL_BG:uint = 0xDBEAFE;   // selected-row highlight

        public function build(n:UiNode):void
        {
            n.shapeA = new Shape();   // background + selected-row highlight
            n.backing.addChild(n.shapeA);

            var self:ListWidget = this;
            n.listen(n.backing, MouseEvent.CLICK,
                function (e:MouseEvent):void { self.onClickY(n, e); });
        }

        public function payload(n:UiNode, desc:Node):Boolean
        {
            var l:ListNode = ListNode(desc);
            n.binding = l.binding;
            // UiNode has no dedicated onSelect slot; reuse onChange (same
            // Function(Number) contract as the other selectable controls).
            n.onChange = l.onSelect;

            var sv:Number = l.selectedIndex;
            if (l.binding != null)
            {
                // `*`, NOT `Object`: an `Object` slot would box the value once per read.
                // Number() never depended on the G9 fix (阶段二四八) and the G14 Array-identity
                // hazard (阶段二百五十三) is closed too, so `*` is now purely the cheaper default.
                var bv:* = l.binding.get();
                sv = bv == null ? 0 : Number(bv);
            }
            var prev:Object = n.extra[SEL_KEY];
            if (prev == null || Number(prev) != sv)
            {
                n.extra[SEL_KEY] = sv;
                n.dirty |= Dirty.M_PAINT;   // decoration only: never a reflow
            }
            // Structure (rows / separators / itemHeight) is carried by the child
            // nodes the factory built; the reconciler diffs them, so this node
            // never reports a re-measure itself.
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
            PaintKit.paintBox(n, n.resolved, PaintKit.w1(n), PaintKit.h1(n));
            if (n.shapeA == null) return;

            var sel:int = int(Number(n.extra[SEL_KEY]));
            if (sel < 0) return;
            var child:UiNode = rowAt(n, sel);
            if (child == null) return;

            // Highlight in LOCAL coordinates (the backing's origin is the list's
            // top-left; abs* is absolute, so subtract).
            var g:Object = n.shapeA.graphics;
            g.beginFill(SEL_BG, 1.0);
            g.drawRect(child.absX - n.absX, child.absY - n.absY, child.absW, child.absH);
            g.endFill();
        }

        // How many rows there are: the non-divider children. Allocation-free.
        private function rowCount(n:UiNode):int
        {
            var c:int = 0;
            for (var i:int = 0; i < n.children.length; i++)
            {
                if (n.children[i].kind != "divider") c = c + 1;
            }
            return c;
        }

        // The sel-th non-divider child, or null. Allocation-free.
        private function rowAt(n:UiNode, sel:int):UiNode
        {
            var rowIdx:int = -1;
            for (var i:int = 0; i < n.children.length; i++)
            {
                var c:UiNode = n.children[i];
                if (c.kind == "divider") continue;
                rowIdx = rowIdx + 1;
                if (rowIdx == sel) return c;
            }
            return null;
        }

        // Consume the click only when it actually landed on a row; a click in the
        // container's padding may still fall through to the author's onClick.
        public function click(n:UiNode):Boolean
        {
            var hit:* = n.extra[HIT_KEY];
            return hit != null && Boolean(hit);
        }

        private function onClickY(n:UiNode, e:MouseEvent):void
        {
            n.extra[HIT_KEY] = 0;
            var target:int = -1;
            var rowIdx:int = -1;
            for (var i:int = 0; i < n.children.length; i++)
            {
                var c:UiNode = n.children[i];
                if (c.kind == "divider") continue;
                rowIdx = rowIdx + 1;
                var top:Number = c.backing.y;
                var bot:Number = top + c.absH;
                if (e.localY >= top && e.localY < bot) { target = rowIdx; break; }
            }
            if (target < 0) return;

            n.extra[HIT_KEY] = 1;
            this.select(n, target);
        }

        // ---- keyboard -------------------------------------------------------
        // Up/Down move one row, Home/End jump to the ends. The current row is the one
        // payload last APPLIED (`extra[sel]`), never the binding: an author who has not
        // rendered yet still gets the arrow to move from what is on screen.
        public function onKey(n:UiNode, keyCode:int, shift:Boolean):Boolean
        {
            var count:int = this.rowCount(n);
            if (count == 0) return false;
            if (keyCode != 38 && keyCode != 40 && keyCode != 36 && keyCode != 35) return false;

            var cur:int = this.currentIndex(n);
            var next:int;
            if (keyCode == 36) next = 0;
            else if (keyCode == 35) next = count - 1;
            else if (cur < 0 || cur >= count) next = keyCode == 40 ? 0 : count - 1;
            else next = keyCode == 40 ? cur + 1 : cur - 1;
            if (next < 0) next = 0;
            if (next >= count) next = count - 1;
            // Consumed even when nothing moves: at the last row the key must not fall
            // through to a scrolling ancestor.
            if (next != cur) this.select(n, next);
            return true;
        }

        // The row the keys move FROM. The BINDING wins when there is one: it is the
        // freshest intent, and payload has not run yet inside the frame that received
        // the key -- two keys in one frame (a held arrow, a fast repeat) must step
        // twice. Without a binding, fall back to what payload last APPLIED, i.e. what
        // is actually on screen.
        private function currentIndex(n:UiNode):int
        {
            if (n.binding != null)
            {
                var bv:* = n.binding.get();
                if (bv != null) return int(Number(bv));
            }
            return int(Number(n.extra[SEL_KEY]));
        }
        // The ONE write path, shared by the click and the keys. Do NOT write
        // n.extra[SEL_KEY] here: payload must observe the change and raise
        // Dirty.M_PAINT (same reason as TabsWidget.onClickX).
        private function select(n:UiNode, idx:int):void
        {
            if (n.binding != null) n.binding.set(idx);
            n.app.markPaint(n);
            if (n.onChange != null) n.onChange(idx);
            n.app.invalidate(Dirty.VALUE);
        }
    }
}
// asaot.ui.kind.PaginationWidget -- the container for PaginationNode, plus the
// page-slot arithmetic it shares with the factory.
//
// The prev/next/number chips and the ellipsis texts are CHILD UiNodes the factory
// made and the reconciler mounted; the layout engine places them. `build` owns the
// background shape and the click listener; `measure`/`arrange` do nothing.
//
// HOW A CLICK BECOMES A PAGE: the buttons are the direct children whose `role` is
// "button" (the ellipsis texts carry no role of their own). Walking them in order,
// `prev` and `next` are recognised by their `key` -- a String comparison, not a
// parse -- and everything else is a page SLOT, counted from 0. The slot's page
// number comes from `pageList`, i.e. the very list the factory rendered, so a
// click can never land on a page the UI was not showing.
//
// `page`/`pageCount`/`windowSize` are mirrored into `extra` by payload, because the
// click handler must re-derive the list and payload is the only place that sees the
// description.
package asaot.ui.kind
{
    import asaot.ui.PaginationNode;
    import asaot.ui.Dirty;
    import asaot.ui.Node;
    import asaot.ui.PaintKit;
    import asaot.ui.UiNode;
    import asaot.ui.Widget;

    import flash.display.Shape;
    import flash.events.MouseEvent;

    public class PaginationWidget implements Widget
    {
        private static const PAGE_KEY:String = "page";
        private static const PC_KEY:String = "pc";
        private static const WIN_KEY:String = "win";
        private static const HIT_KEY:String = "hit";

        private static const ROLE_BUTTON:String = "button";

        // ---- the shared slot arithmetic -------------------------------------
        // Pure and allocation-light: the factory calls it once per pass and the
        // click handler once per click. Excluded pages collapse into a single -1
        // (an ellipsis) each, so the caller renders `p < 0` as text and `p > 0` as a
        // button -- and the slot index of a button is what maps back to the page.
        public static function pageList(page:int, pageCount:int, windowSize:int):Array
        {
            var out:Array = new Array();
            if (pageCount <= 1) { out.push(1); return out; }
            var w:int = windowSize < 5 ? 5 : windowSize;
            if (pageCount <= w)
            {
                for (var i:int = 1; i <= pageCount; i++) out.push(i);
                return out;
            }
            // Always show the first and the last page; slide `inner` slots around the
            // current one and clamp that window into [2, pageCount-1].
            var inner:int = w - 2;
            var start:int = page - int((inner - 1) / 2);
            var end:int = start + inner - 1;
            if (start < 2) { start = 2; end = start + inner - 1; }
            if (end > pageCount - 1) { end = pageCount - 1; start = end - inner + 1; }
            out.push(1);
            if (start > 2) out.push(-1);
            for (var k:int = start; k <= end; k++) out.push(k);
            if (end < pageCount - 1) out.push(-1);
            out.push(pageCount);
            return out;
        }

        public function build(n:UiNode):void
        {
            n.shapeA = new Shape();
            n.backing.addChild(n.shapeA);
            n.extra[PAGE_KEY] = 1;
            n.extra[PC_KEY] = 1;
            n.extra[WIN_KEY] = 7;
            n.extra[HIT_KEY] = 0;

            var self:PaginationWidget = this;
            n.listen(n.backing, MouseEvent.CLICK,
                function (e:MouseEvent):void { self.onClickX(n, e); });
        }

        public function payload(n:UiNode, desc:Node):Boolean
        {
            var p:PaginationNode = PaginationNode(desc);
            n.binding = p.binding;
            // UiNode has no dedicated onSelect slot; reuse onChange (Function(Number),
            // the same contract as the other selectable controls).
            n.onChange = p.onSelect;

            var pv:Number = p.page;
            if (p.binding != null)
            {
                // `*`, NOT `Object`: an `Object` slot would box the value once per read.
                // Number() never depended on the G9 fix (阶段二四八) and the G14 Array-identity
                // hazard (阶段二百五十三) is closed too, so `*` is now purely the cheaper default.
                var bv:* = p.binding.get();
                pv = bv == null ? 1 : Number(bv);
            }
            n.extra[PAGE_KEY] = int(pv);
            n.extra[PC_KEY] = int(p.pageCount);
            n.extra[WIN_KEY] = int(p.windowSize);
            // The rendered slots are structure (the factory rebuilt the children), so
            // this node has no own geometry to re-measure.
            return false;
        }

        public function wantsPress():Boolean { return true; }

        public function measure(n:UiNode):void
        {
            // The engine sizes the container from its chips (see BoxWidget).
        }

        public function arrange(n:UiNode):void
        {
            // Chips are placed by the engine; nothing internal to position.
        }

        public function paint(n:UiNode):void
        {
            PaintKit.paintBox(n, n.resolved, PaintKit.w1(n), PaintKit.h1(n));
        }

        public function click(n:UiNode):Boolean
        {
            var hit:* = n.extra[HIT_KEY];
            return hit != null && Boolean(hit);
        }

        private function onClickX(n:UiNode, e:MouseEvent):void
        {
            n.extra[HIT_KEY] = 0;
            var page:int = int(Number(n.extra[PAGE_KEY]));
            var pcs:int = int(Number(n.extra[PC_KEY]));
            var win:int = int(Number(n.extra[WIN_KEY]));

            var target:int = -1;   // the page to go to
            var slot:int = -1;
            var found:Boolean = false;
            for (var i:int = 0; i < n.children.length; i++)
            {
                var c:UiNode = n.children[i];
                if (c.role != ROLE_BUTTON) continue;
                var left:Number = c.backing.x;
                var hit:Boolean = e.localX >= left && e.localX < left + c.absW;
                var k:String = c.key == null ? "" : String(c.key);
                var isNav:Boolean = (k == "prev" || k == "next");
                if (!isNav) slot = slot + 1;
                if (!hit) continue;
                found = true;
                if (k == "prev") { target = page - 1; }
                else if (k == "next") { target = page + 1; }
                else
                {
                    var list:Array = pageList(page, pcs, win);
                    if (slot >= 0 && slot < list.length) target = int(list[slot]);
                }
                break;
            }
            if (!found) return;   // a click on an ellipsis or in the gaps
            if (target < 1) target = 1;
            if (target > pcs) target = pcs;
            // The click is consumed either way, but landing on the page we are
            // already on (clamped prev/next at the ends, or the current number)
            // reports nothing: no callback, no binding write.
            if (target == page) { n.extra[HIT_KEY] = 1; return; }

            n.extra[HIT_KEY] = 1;
            // Do NOT write extra[PAGE_KEY]: payload is the single writer of it.
            if (n.binding != null) n.binding.set(target);
            n.app.markPaint(n);
            if (n.onChange != null) n.onChange(target);
            n.app.invalidate(Dirty.VALUE);
        }
    }
}
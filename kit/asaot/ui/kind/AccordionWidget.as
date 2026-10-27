// asaot.ui.kind.AccordionWidget -- the container for AccordionNode.
//
// The headers and the open panel are CHILD UiNodes the factory made and the
// reconciler mounted; the layout engine places them. So `build` owns only the
// background shape, and `measure`/`arrange` do nothing (a container's intrinsic
// size is the engine's job; see BoxWidget).
//
// HOW A CLICK BECOMES A SECTION: the headers are the direct children whose `role`
// is "button" (see accordion.as). Walking the children in order, the n-th
// button-roled child IS section n -- the open panel is a child too but does not
// carry that role, so it is skipped by construction. The y test uses the children's
// laid-out rects, so a click in the gap or in the panel body changes nothing.
//
// `activeIndex` is the author's state: a toggle writes it back through the Binding
// (the CONTAINER never edits its own copy directly -- payload is the single writer
// of `extra[ACT]`, so it can see the change and raise Dirty.M_PAINT for the open
// header's fill). The panel itself is added/removed by the reconciler from the
// description, which is what re-runs layout.
//
// MULTI MODE (2026-10-26) is the same machinery with an ARRAY instead of one index:
// `extra[open]` is a COPY of the open set that payload maintains (so a change of
// identity with the same contents does not repaint every frame -- the author's array
// is rebuilt per render), and a click writes a NEW array back through the binding,
// in ascending order, with the clicked section toggled. `onToggle(i)` reports the
// CLICKED index in multi mode (there is no single "now open" index to report); the
// author reads the array for the resulting state.
package asaot.ui.kind
{
    import asaot.ui.AccordionNode;
    import asaot.ui.Dirty;
    import asaot.ui.Node;
    import asaot.ui.PaintKit;
    import asaot.ui.Theme;
    import asaot.ui.ThemeTokens;
    import asaot.ui.UiNode;
    import asaot.ui.Widget;

    import flash.display.Shape;
    import flash.events.MouseEvent;

    public class AccordionWidget implements Widget
    {
        private static const ACT_KEY:String = "act";    // single: open section (-1 = none)
        private static const OPEN_KEY:String = "open";  // multi: copy of the open set
        private static const MULTI_KEY:String = "mult"; // 1 when the node is in multi mode
        private static const HIT_KEY:String = "hit";    // 1 when the last click hit a header

        private static const ROLE_HEADER:String = "button";

        public function build(n:UiNode):void
        {
            // shapeA sits at backing child index 0, i.e. BEHIND the header rows, so
            // the header fills show through their TRANSPARENT background (the factory
            // deliberately gives a header no background -- see accordion.as).
            n.shapeA = new Shape();
            n.backing.addChild(n.shapeA);
            n.extra[ACT_KEY] = -1;
            n.extra[OPEN_KEY] = [];
            n.extra[MULTI_KEY] = 0;
            n.extra[HIT_KEY] = 0;

            var self:AccordionWidget = this;
            n.listen(n.backing, MouseEvent.CLICK,
                function (e:MouseEvent):void { self.onClickY(n, e); });
        }

        public function payload(n:UiNode, desc:Node):Boolean
        {
            var a:AccordionNode = AccordionNode(desc);
            n.binding = a.binding;
            // UiNode has no dedicated onToggle slot; reuse onChange (Function(Number),
            // the same contract as the other selectable controls).
            n.onChange = a.onToggle;

            var multi:Boolean = a.mode == "multi";
            n.extra[MULTI_KEY] = multi ? 1 : 0;
            if (multi)
            {
                var list:Array = a.openIndices;
                if (a.binding != null)
                {
                    list = AccordionNode.asIndices(a.binding.get());
                }
                if (!this.sameOpen(n.extra[OPEN_KEY] as Array, list))
                {
                    n.extra[OPEN_KEY] = this.copyOpen(list);
                    n.dirty |= Dirty.M_PAINT;
                }
                return false;
            }

            var av:Number = a.activeIndex;
            if (a.binding != null)
            {
                // `*`, NOT `Object`: an `Object` slot would box the value once per read.
                // Number() never depended on the G9 fix (阶段二四八) and the G14 Array-identity
                // hazard (阶段二百五十三) is closed too, so `*` is now purely the cheaper default.
                var bv:* = a.binding.get();
                av = bv == null ? -1 : Number(bv);
            }
            var prev:Object = n.extra[ACT_KEY];
            if (prev == null || Number(prev) != av)
            {
                n.extra[ACT_KEY] = av;
                n.dirty |= Dirty.M_PAINT;   // the open header's fill changes
            }
            // The section LIST and which panel is a child are structure: the factory
            // rebuilt the children and the reconciler diffs them, so this node never
            // reports a re-measure itself.
            return false;
        }

        public function wantsPress():Boolean { return true; }

        public function measure(n:UiNode):void
        {
            // The engine sizes the container from its headers/panel (see BoxWidget).
        }

        public function arrange(n:UiNode):void
        {
            // Children are placed by the engine; nothing internal to position.
        }

        public function paint(n:UiNode):void
        {
            PaintKit.paintBox(n, n.resolved, PaintKit.w1(n), PaintKit.h1(n));
            if (n.shapeA == null) return;

            var act:int = int(Number(n.extra[ACT_KEY]));
            var multi:Boolean = Number(n.extra[MULTI_KEY]) != 0;
            var openSet:Array = n.extra[OPEN_KEY] as Array;
            var g:Object = n.shapeA.graphics;
            var pal:ThemeTokens = Theme.tokens();

            // A header background AND a hairline under it, both drawn as FILLS: a filled
            // rect rasterises exactly, so the hairline is the 1px that was asked for and
            // a probe can assert a single pixel. (The reason recorded here on 2026-10-23 --
            // "lineStyle stroke width is not honoured" -- was re-measured on 2026-10-25
            // and is FALSE: see probes/widgets/icon, which pins a 2px line at 2 rows and
            // a 12px line at 12. The fill stays because it is integer-exact, not because
            // a stroke is broken.) The fill is
            // here rather than in the header's own style because a child paints IN
            // FRONT of this shape: an open header declared with a background would hide
            // exactly the highlight we want (found by probes/widgets/data).
            var k:int = -1;
            for (var i:int = 0; i < n.children.length; i++)
            {
                var c:UiNode = n.children[i];
                if (c.role != ROLE_HEADER) continue;
                k = k + 1;
                var isOpen:Boolean = multi ? AccordionNode.isOpen(openSet, k) : (k == act);
                g.beginFill(isOpen ? pal.accentSoft : pal.surfaceMuted, 1.0);
                g.drawRect(c.absX - n.absX, c.absY - n.absY, c.absW, c.absH);
                g.endFill();
                g.beginFill(pal.border, 1.0);
                g.drawRect(c.absX - n.absX, c.absY - n.absY + c.absH - 1, c.absW, 1);
                g.endFill();
            }
        }

        // Consume the click only when it actually landed on a header; a click in the
        // open panel still falls through to the author's onClick.
        public function click(n:UiNode):Boolean
        {
            var hit:* = n.extra[HIT_KEY];
            return hit != null && Boolean(hit);
        }

        private function onClickY(n:UiNode, e:MouseEvent):void
        {
            n.extra[HIT_KEY] = 0;
            var act:int = int(Number(n.extra[ACT_KEY]));
            var target:int = -1;
            var k:int = -1;
            for (var i:int = 0; i < n.children.length; i++)
            {
                var c:UiNode = n.children[i];
                if (c.role != ROLE_HEADER) continue;
                k = k + 1;
                var top:Number = c.backing.y;
                if (e.localY >= top && e.localY < top + c.absH) { target = k; break; }
            }
            if (target < 0) return;

            n.extra[HIT_KEY] = 1;
            if (Number(n.extra[MULTI_KEY]) != 0)
            {
                this.toggleMulti(n, target);
                return;
            }
            // Single-open: the open header closes (toggle), any other opens.
            var next:int = (target == act) ? -1 : target;
            // Do NOT write n.extra[ACT_KEY] here: payload must observe the change
            // and raise Dirty.M_PAINT (same reason as TabsWidget.onClickX).
            if (n.binding != null) n.binding.set(next);
            n.app.markPaint(n);
            if (n.onChange != null) n.onChange(next);
            n.app.invalidate(Dirty.VALUE);
        }

        private function toggleMulti(n:UiNode, target:int):void
        {
            var was:Array = n.extra[OPEN_KEY] as Array;
            var next:Array = [];
            // Rebuilt in ASCENDING order: the array the author sees has one canonical
            // spelling whatever order they handed us, so `[2,0]` and `[0,2]` do not
            // look like a change on the next payload.
            // `k` counts HEADERS, not children: the open panels are children too, so a
            // children index is not a section index (the same walk paint/onClickY do).
            var k:int = -1;
            for (var i:int = 0; i < n.children.length; i++)
            {
                if (n.children[i].role != ROLE_HEADER) continue;
                k = k + 1;
                var on:Boolean = AccordionNode.isOpen(was, k);
                if (k == target) on = !on;
                if (on) next.push(k);
            }
            if (n.binding != null) n.binding.set(next);
            n.app.markPaint(n);
            if (n.onChange != null) n.onChange(target);
            n.app.invalidate(Dirty.VALUE);
        }

        // Element-wise, order-insensitive comparison against the copy we kept. Without
        // it every render would look like a change (the author's array is a fresh
        // object each pass) and the accordion would repaint forever.
        private function sameOpen(have:Array, want:Array):Boolean
        {
            var a:Array = have == null ? [] : have;
            var b:Array = want == null ? [] : want;
            if (a.length != b.length) return false;
            for (var i:int = 0; i < a.length; i++)
            {
                if (!this.hasIndex(b, int(Number(a[i])))) return false;
            }
            return true;
        }

        private function hasIndex(list:Array, v:int):Boolean
        {
            for (var i:int = 0; i < list.length; i++)
            {
                if (list[i] == null) continue;
                if (int(Number(list[i])) == v) return true;
            }
            return false;
        }

        private function copyOpen(list:Array):Array
        {
            var out:Array = [];
            if (list == null) return out;
            for (var i:int = 0; i < list.length; i++)
            {
                if (list[i] == null) continue;
                out.push(int(Number(list[i])));
            }
            return out;
        }
    }
}
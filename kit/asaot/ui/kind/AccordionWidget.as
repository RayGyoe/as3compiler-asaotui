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
package asaot.ui.kind
{
    import asaot.ui.AccordionNode;
    import asaot.ui.Dirty;
    import asaot.ui.Node;
    import asaot.ui.PaintKit;
    import asaot.ui.UiNode;
    import asaot.ui.Widget;

    import flash.display.Shape;
    import flash.events.MouseEvent;

    public class AccordionWidget implements Widget
    {
        private static const ACT_KEY:String = "act";    // open section (-1 = none)
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
            n.extra[HIT_KEY] = 0;

            var self:AccordionWidget = this;
            n.backing.addEventListener(MouseEvent.CLICK,
                function (e:MouseEvent):void { self.onClickY(n, e); });
        }

        public function payload(n:UiNode, desc:Node):Boolean
        {
            var a:AccordionNode = AccordionNode(desc);
            n.binding = a.binding;
            // UiNode has no dedicated onToggle slot; reuse onChange (Function(Number),
            // the same contract as the other selectable controls).
            n.onChange = a.onToggle;

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
            var g:Object = n.shapeA.graphics;

            // A header background AND a hairline under it, both drawn as FILLS:
            // measured on this backend, `lineStyle` stroke width is not honoured while
            // a filled rect rasterises exactly (temp/stroke/, 2026-10-23). The fill is
            // here rather than in the header's own style because a child paints IN
            // FRONT of this shape: an open header declared with a background would hide
            // exactly the highlight we want (found by probes/widgets/data).
            var k:int = -1;
            for (var i:int = 0; i < n.children.length; i++)
            {
                var c:UiNode = n.children[i];
                if (c.role != ROLE_HEADER) continue;
                k = k + 1;
                g.beginFill(k == act ? AccordionNode.OPEN_BG : AccordionNode.HEADER_BG, 1.0);
                g.drawRect(c.absX - n.absX, c.absY - n.absY, c.absW, c.absH);
                g.endFill();
                g.beginFill(AccordionNode.RULE, 1.0);
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
            // Single-open: the open header closes (toggle), any other opens.
            var next:int = (target == act) ? -1 : target;
            // Do NOT write n.extra[ACT_KEY] here: payload must observe the change
            // and raise Dirty.M_PAINT (same reason as TabsWidget.onClickX).
            if (n.binding != null) n.binding.set(next);
            n.app.markPaint(n);
            if (n.onChange != null) n.onChange(next);
            n.app.invalidate(Dirty.VALUE);
        }
    }
}
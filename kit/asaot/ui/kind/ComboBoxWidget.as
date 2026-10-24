// asaot.ui.kind.ComboBoxWidget -- a select's dropdown behaviour with an editable
// trigger.
//
// THE KEY PATH IS DIFFERENT HERE, AND THAT IS THE WHOLE STORY OF THIS FILE.
// `UiApp.onKeyDown` gives a key to the FOCUSED node's widget and to nobody else --
// no bubbling. A combobox's focus target must be its TextField (the runtime only
// inserts characters into a focused TextField), so the focused widget is InputWidget,
// which consumes Enter/Esc and ignores the arrows. The combobox's own widget would
// therefore never see a key.
//
// So this kind listens for KEY_DOWN ON THE STAGE and -- crucially -- only acts when
// the focused node is INSIDE this combobox. That is the same technique PopoverWidget
// uses for outside-clicks, with the same cost: the listener outlives the node, so the
// kind implements WidgetTeardown.
//
// WHAT IT DOES WITH THEM: while the dropdown is open, arrows move the active row,
// Enter chooses it, Esc closes. While it is closed nothing is intercepted -- typing,
// Enter-to-commit and Esc-to-revert all belong to the field.
package asaot.ui.kind
{
    import asaot.ui.Dirty;
    import asaot.ui.LayoutConstants;
    import asaot.ui.Node;
    import asaot.ui.OverlayChrome;
    import asaot.ui.OverlayList;
    import asaot.ui.OverlayMotion;
    import asaot.ui.PaintKit;
    import asaot.ui.ComboBoxNode;
    import asaot.ui.UiNode;
    import asaot.ui.Widget;
    import asaot.ui.WidgetTeardown;
    import flash.display.Shape;
    import flash.display.Stage;
    import flash.events.KeyboardEvent;
    import flash.events.MouseEvent;

    public class ComboBoxWidget implements Widget, WidgetTeardown
    {
        private static const OPEN_KEY:String = "open";
        private static const SEL_FN:String = "onSelect";
        private static const OPEN_FN:String = "onOpenChange";
        private static const ACT_KEY:String = "actRow";
        private static const HIT_KEY:String = "hit";
        private static const KEYS_ON:String = "keysOn";
        private static const KEYS_FN:String = "keysFn";

        public function build(n:UiNode):void
        {
            n.extra[OPEN_KEY] = false;
            n.extra[SEL_FN] = null;
            n.extra[OPEN_FN] = null;
            n.extra[ACT_KEY] = -1;
            n.extra[HIT_KEY] = 0;
            n.extra[KEYS_ON] = false;
            n.extra[KEYS_FN] = null;
            n.shapeA = new Shape();
            n.backing.addChild(n.shapeA);
            var self:ComboBoxWidget = this;
            n.backing.addEventListener(MouseEvent.CLICK,
                function (e:MouseEvent):void { self.onClickAt(n, e); });
        }

        public function payload(n:UiNode, desc:Node):Boolean
        {
            var c:ComboBoxNode = ComboBoxNode(desc);
            n.extra[SEL_FN] = c.onSelect;
            n.extra[OPEN_FN] = c.onOpenChange;
            n.onChange = c.onSelect;
            var wasOpen:Boolean = Boolean(n.extra[OPEN_KEY]);
            n.extra[OPEN_KEY] = c.open;
            if (!wasOpen && c.open) OverlayMotion.start(n);
            this.liftForPopup(n, wasOpen, c.open);
            if (!c.open) n.extra[ACT_KEY] = -1;
            this.armKeys(n);
            return false;
        }

        // Attach the stage listener ONCE, the first time this node is mounted with a
        // stage (build() runs before the node is attached, so `stage` is still null
        // there -- and payload() runs every frame after).
        private function armKeys(n:UiNode):void
        {
            if (Boolean(n.extra[KEYS_ON])) return;
            if (n.backing == null) return;
            var st:Stage = n.backing.stage as Stage;
            if (st == null) return;
            var self:ComboBoxWidget = this;
            var fn:Function = function (e:KeyboardEvent):void { self.onStageKey(n, e); };
            n.extra[KEYS_FN] = fn;
            n.extra[KEYS_ON] = true;
            st.addEventListener(KeyboardEvent.KEY_DOWN, fn);
        }

        public function teardown(n:UiNode):void
        {
            var fn:Function = n.extra[KEYS_FN] as Function;
            if (fn == null) return;
            if (n.backing != null && n.backing.stage != null)
            {
                Stage(n.backing.stage).removeEventListener(KeyboardEvent.KEY_DOWN, fn);
            }
            n.extra[KEYS_FN] = null;
            n.extra[KEYS_ON] = false;
        }


        // THE OPEN POPUP ESCAPES THE FLOW (see UiNode.lifted). The dropdown/panel
        // is the node's LAST CHILD -- i.e. a child of this card -- and a child can
        // never paint above a sibling that its own parent renders later, which is
        // the "the list opens UNDER the widget below it" defect. While open this
        // node is hoisted onto the stage container (positioned at its ABSOLUTE
        // rect) so it wins the stacking order; closing puts it straight back.
        // Layout, keys, focus and events are untouched: only the display object
        // moves, because an open popup is exactly what a floating layer is for.
        private function liftForPopup(n:UiNode, wasOpen:Boolean, open:Boolean):void
        {
            if (wasOpen == open) return;
            n.lifted = open;
            n.app.markPaint(n);
        }

        public function wantsPress():Boolean { return true; }

        public function measure(n:UiNode):void
        {
            if (n.engineNode == null || n.children.length == 0) return;
            var drop:UiNode = n.children[n.children.length - 1];
            if (drop.engineNode == null) return;
            var eng:* = n.app.engine;
            var e:* = drop.engineNode;
            var h:Number = n.absH > 0 ? n.absH : 34;
            eng.setPosition(e, LayoutConstants.EDGE_LEFT, 0, LayoutConstants.UNIT_POINT);
            eng.setPosition(e, LayoutConstants.EDGE_TOP, h, LayoutConstants.UNIT_POINT);
            eng.setPosition(e, LayoutConstants.EDGE_RIGHT, 0, LayoutConstants.UNIT_UNDEFINED);
            eng.setPosition(e, LayoutConstants.EDGE_BOTTOM, 0, LayoutConstants.UNIT_UNDEFINED);
            eng.setSize(e, LayoutConstants.AXIS_WIDTH,
                        n.absW > 0 ? n.absW : 200, LayoutConstants.UNIT_POINT);
        }

        public function arrange(n:UiNode):void { }

        public function paint(n:UiNode):void
        {
            PaintKit.paintBox(n, n.resolved, PaintKit.w1(n), PaintKit.h1(n));
            var drop:UiNode = n.children.length > 0 ? n.children[n.children.length - 1] : null;
            if (drop != null)
            {
                this.paintActiveBand(n, drop);
                if (drop.backing != null) OverlayMotion.apply(n, drop, drop, 0, 6);
            }
            if (n.shapeA == null) return;
            // The caret, in the 10pt right padding the trigger style reserves. The
            // field stops before it (flexGrow on the field + this padding on the node).
            var w:Number = PaintKit.w1(n);
            var h:Number = PaintKit.h1(n);
            var cx:Number = w - 10 - 4;
            var cy:Number = Math.floor(h / 2);
            var g:Object = n.shapeA.graphics;
            g.beginFill(OverlayChrome.SELECT_CARET, 1.0);
            g.moveTo(cx - 4, cy - 2);
            g.lineTo(cx + 4, cy - 2);
            g.lineTo(cx, cy + 3);
            g.lineTo(cx - 4, cy - 2);
            g.endFill();
        }

        public function click(n:UiNode):Boolean
        {
            return Number(n.extra[HIT_KEY]) != 0;
        }

        // The active row's band, inside the DROPDOWN and below its rows -- exactly the
        // slot SelectWidget documents (`drop.internalCount` is "before the UiNode
        // children", which is where Reconciler.fixDisplayOrder expects an extra shape).
        private function paintActiveBand(n:UiNode, drop:UiNode):void
        {
            if (drop.backing == null) return;
            var raw:Object = drop.extra["bandShape"];
            var sh:Shape;
            if (raw == null)
            {
                sh = new Shape();
                drop.backing.addChildAt(sh, drop.internalCount);
                drop.internalCount = drop.internalCount + 1;
                drop.extra["bandShape"] = sh;
            }
            else sh = Shape(raw);
            sh.graphics.clear();
            var act:int = int(Number(n.extra[ACT_KEY]));
            if (!Boolean(n.extra[OPEN_KEY]) || act < 0 || act >= drop.children.length) return;
            var r:UiNode = drop.children[act];
            sh.graphics.beginFill(OverlayChrome.ITEM_HOVER, 1.0);
            sh.graphics.drawRect(r.absX - drop.absX, r.absY - drop.absY, r.absW, r.absH);
            sh.graphics.endFill();
        }

        // Is the focused node inside this combobox? A UiNode-tree walk, not a display
        // walk: the focus target is the field's TextField (a display object), but the
        // focus is recorded on its NODE, and ancestors are what "inside" means here.
        private function focusInside(n:UiNode):Boolean
        {
            var f:UiNode = n.app.focusedNode();
            var p:UiNode = f;
            while (p != null)
            {
                if (p == n) return true;
                p = p.parent;
            }
            return false;
        }

        private function onStageKey(n:UiNode, e:KeyboardEvent):void
        {
            if (!Boolean(n.extra[OPEN_KEY])) return;
            if (!this.focusInside(n)) return;
            var kc:int = e.keyCode;
            var drop:UiNode = n.children.length > 0 ? n.children[n.children.length - 1] : null;
            var rows:int = drop == null ? 0 : drop.children.length;

            if (kc == 27)
            {
                this.report(n, false);
                e.preventDefault();
                return;
            }
            if (kc == 13)
            {
                var act:int = int(Number(n.extra[ACT_KEY]));
                if (act >= 0 && act < rows) this.choose(n, act);
                else this.report(n, false);
                e.preventDefault();
                return;
            }
            if ((kc == 40 || kc == 38) && rows > 0)
            {
                var a:int = int(Number(n.extra[ACT_KEY]));
                if (a < 0) a = 0;
                else a = kc == 40 ? (a + 1) % rows : (a - 1 + rows) % rows;
                n.extra[ACT_KEY] = a;
                n.app.markPaint(n);
                e.preventDefault();
            }
        }

        private function choose(n:UiNode, row:int):void
        {
            var sel:Function = n.extra[SEL_FN];
            if (sel != null) sel(row);
            this.report(n, false);
        }

        private function report(n:UiNode, open:Boolean):void
        {
            n.extra[ACT_KEY] = -1;
            var f:Function = n.extra[OPEN_FN];
            if (f != null) f(open);
        }

        private function onClickAt(n:UiNode, e:MouseEvent):void
        {
            n.extra[HIT_KEY] = 0;
            var open:Boolean = Boolean(n.extra[OPEN_KEY]);
            var drop:UiNode = n.children.length > 0 ? n.children[n.children.length - 1] : null;

            if (open && drop != null)
            {
                var row:int = OverlayList.rowAt(drop, OverlayList.localYIn(drop, e));
                if (row >= 0)
                {
                    n.extra[HIT_KEY] = 1;
                    this.choose(n, row);
                    return;
                }
                // A click on the trigger while open is a CARET PLACEMENT for the field,
                // not a close: closing would fight the text selection the user is
                // making. (A select, which has no field, toggles instead.)
                n.extra[HIT_KEY] = 1;
                return;
            }
            n.extra[HIT_KEY] = 1;
            this.report(n, true);
        }
    }
}
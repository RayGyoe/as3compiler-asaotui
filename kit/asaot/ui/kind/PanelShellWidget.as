// asaot.ui.kind.PanelShellWidget -- the shared shell of every "a panel over the
// window, dismissed by clicking outside it" control (dialog, drawer).
//
// WHY A BASE CLASS: dialog and drawer differ only in (a) which layer style the
// factory patches (centre vs edge) and (b) which Node class carries the fields.
// The behaviour -- mirror `open` onto visibility, and turn a click outside the
// panel into `onClose` -- is identical, and duplicating it is how the two drift
// apart (one of them forgetting to unblock input when it closes).
//
// THE OUTSIDE TEST IS GEOMETRIC, not "did it hit the scrim child". A click on the
// panel's own background is dispatched on the panel's backing and BUBBLES to this
// node's backing, so a target-based test would fire onClose for every click inside
// the dialog. Comparing the point against the panel's solved rect is the same
// technique TableWidget's row hit test uses, and it stays correct with
// `scrim: false` (where there is no scrim child to blame).
//
// THE PANEL IS ALWAYS THE LAST CHILD -- that is the contract both factories keep,
// and it is why this code never counts: with `scrim: false` the panel is child 0,
// so an index constant would silently point at the panel's title instead.
package asaot.ui.kind
{
    import asaot.ui.Node;
    import asaot.ui.OverlayMotion;
    import asaot.ui.UiNode;
    import asaot.ui.Widget;
    import asaot.ui.WidgetKeys;

    import flash.events.MouseEvent;
    import flash.events.KeyboardEvent;

    public class PanelShellWidget implements Widget, WidgetKeys
    {
        protected static const OPEN_KEY:String = "open";
        protected static const CLOSE_KEY:String = "closeOnScrim";
        protected static const FN_KEY:String = "onClose";
        protected static const HIT_KEY:String = "hitOutside";
        // Which edge the sheet arrives from ("" = the centred dialog). Mirrored from
        // the descriptor by the subclass, because the edge is pure STYLE in the
        // factory and a retained node does not keep its style refinement's fields.
        protected static const SLIDE_KEY:String = "slide";

        // ---- what the subclass supplies ---------------------------------
        protected function openOf(desc:Node):Boolean { return false; }
        protected function closeOnScrimOf(desc:Node):Boolean { return true; }
        protected function onCloseOf(desc:Node):Function { return null; }
        protected function slideOf(desc:Node):String { return ""; }

        // ---- the shared behaviour ---------------------------------------
        public function build(n:UiNode):void
        {
            n.extra[OPEN_KEY] = false;
            n.extra[CLOSE_KEY] = 1;
            n.extra[FN_KEY] = null;
            n.extra[HIT_KEY] = 0;
            n.extra[SLIDE_KEY] = "";
            n.backing.addEventListener(MouseEvent.CLICK,
                function (e:MouseEvent):void { PanelShellWidget.onClick(n, e); });
        }

        public function payload(n:UiNode, desc:Node):Boolean
        {
            n.extra[CLOSE_KEY] = closeOnScrimOf(desc) ? 1 : 0;
            n.extra[FN_KEY] = onCloseOf(desc);
            n.extra[SLIDE_KEY] = slideOf(desc);

            var open:Boolean = openOf(desc);
            var prev:* = n.extra[OPEN_KEY];
            var was:Boolean = prev != null && Boolean(prev);
            if (was == open) return false;
            n.extra[OPEN_KEY] = open;
            if (open) OverlayMotion.start(n);
            // Mirror onto the retained node AND the display object immediately: an
            // `open` change can land on a frame with no arrange pass, and a closed
            // shell must stop blocking input in the SAME frame it closes (the pick
            // walk returns NULL for an invisible object -- src/emit.ts
            // as_pick_hit_m).
            n.visible = open;
            if (n.backing != null) n.backing.visible = open;
            // Returning true forces the layout + arrange + full-paint sweep that
            // re-applies `backing.visible` from the n.visible/opacity pair. It is
            // not a size change, but it is the documented way to ask for the sweep.
            return true;
        }

        public function wantsPress():Boolean { return true; }

        public function measure(n:UiNode):void { }

        public function arrange(n:UiNode):void { }

        public function paint(n:UiNode):void
        {
            // The LAYER is the fade target (so the scrim ramps with the panel) and
            // the PANEL is the moving one -- a centred dialog rises 8px, an edge
            // sheet slides in from its own edge by its own size.
            if (n.children.length == 0) { OverlayMotion.apply(n, n, null, 0, 0); return; }
            var panel:UiNode = n.children[n.children.length - 1];
            if (panel == null || panel.backing == null)
            {
                OverlayMotion.apply(n, n, null, 0, 0);
                return;
            }
            var dx:Number = 0;
            var dy:Number = 8;
            var side:String = String(n.extra[SLIDE_KEY]);
            if (side == "left") { dx = -(panel.absW > 0 ? panel.absW : 240); dy = 0; }
            else if (side == "right") { dx = panel.absW > 0 ? panel.absW : 240; dy = 0; }
            else if (side == "top") { dx = 0; dy = -(panel.absH > 0 ? panel.absH : 200); }
            else if (side == "bottom") { dx = 0; dy = panel.absH > 0 ? panel.absH : 200; }
            OverlayMotion.apply(n, n, panel, dx, dy);
        }

        // Escape closes -- but only while this shell HOLDS the keyboard (see the
        // header of WidgetKeys): the shell deliberately does not steal focus when it
        // opens, so an author who wants a keyboard-dismissable modal calls
        // `app.focusNode(app.findByKey("<first control>"))` from its open handler.
        public function onKey(n:UiNode, keyCode:int, shift:Boolean):Boolean
        {
            if (keyCode != 27) return false;
            if (Number(n.extra[CLOSE_KEY]) == 0) return true;   // consumed but ignored
            var f:Function = n.extra[FN_KEY];
            if (f != null) f();
            return true;
        }

        public function click(n:UiNode):Boolean
        {
            return Boolean(n.extra[HIT_KEY]);
        }

        // Static so the listener needs no instance reference (which would keep the
        // widget alive through the closure for the node's whole life).
        protected static function onClick(n:UiNode, e:MouseEvent):void
        {
            n.extra[HIT_KEY] = 0;
            if (Number(n.extra[CLOSE_KEY]) == 0) return;
            if (n.children.length == 0) return;
            var panel:UiNode = n.children[n.children.length - 1];
            if (panel == null) return;
            // Local to THIS node: the layer is the window and the panel's abs rect
            // is in the same coordinate space, so the difference is a translation.
            var px:Number = panel.absX - n.absX;
            var py:Number = panel.absY - n.absY;
            if (e.localX >= px && e.localX < px + panel.absW
                && e.localY >= py && e.localY < py + panel.absH) return;
            n.extra[HIT_KEY] = 1;
            var f:Function = n.extra[FN_KEY];
            if (f != null) f();
        }
    }
}
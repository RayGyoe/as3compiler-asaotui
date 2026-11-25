// asaot.ui.kind.ColorWheelWidget -- the conic hue ring + inner disc + draggable dot.
// The ring hues are the colour SPECTRUM (semantic, not theme palette); the disc and
// dot read Theme.tokens() so they follow theme swaps. Drag reports hue angle via
// onChange(v) (arity 1) and keeps the dot radius in `spread`.
package asaot.ui.kind
{
    import asaot.ui.ColorWheelNode;
    import asaot.ui.Dirty;
    import asaot.ui.Node;
    import asaot.ui.PaintKit;
    import asaot.ui.Theme;
    import asaot.ui.ThemeTokens;
    import asaot.ui.UiNode;
    import asaot.ui.Widget;
    import asaot.ui.WidgetTeardown;
    import asaot.ui.LayoutConstants;
    import flash.display.Shape;
    import flash.events.MouseEvent;

    public class ColorWheelWidget implements Widget, WidgetTeardown
    {
        private static const VAL:String = "cwv";
        private static const SPR:String = "cws";
        private static const MV:String = "cwmv";
        private static const UP:String = "cwup";
        private static const DRAG:String = "cwdrag";
        private static const DEFAULT:Number = 72;

        public function build(n:UiNode):void
        {
            n.shapeA = new Shape();
            n.backing.addChild(n.shapeA);
            n.extra = {};
            var self:ColorWheelWidget = this;
            n.listen(n.backing, MouseEvent.MOUSE_DOWN, function(e:MouseEvent):void { self.down(n, e); });
        }
        public function teardown(n:UiNode):void { endDrag(n); }
        public function wantsPress():Boolean { return false; }

        public function payload(n:UiNode, desc:Node):Boolean
        {
            var cw:ColorWheelNode = ColorWheelNode(desc);
            if (diff(n, VAL, cw.value)) n.dirty |= Dirty.M_PAINT;
            if (diff(n, SPR, cw.spread)) n.dirty |= Dirty.M_PAINT;
            return false;
        }
        private function diff(n:UiNode, k:String, v:Number):Boolean
        {
            var p:Number = Number(n.extra[k]);
            if (p == v) return false;
            n.extra[k] = v; return true;
        }

        public function measure(n:UiNode):void
        {
            if (PaintKit.autoW(n.resolved)) PaintKit.setPointSize(n, LayoutConstants.AXIS_WIDTH, DEFAULT);
            if (PaintKit.autoH(n.resolved)) PaintKit.setPointSize(n, LayoutConstants.AXIS_HEIGHT, DEFAULT);
        }
        public function arrange(n:UiNode):void { }

        public function paint(n:UiNode):void
        {
            var pal:ThemeTokens = Theme.tokens();
            var w:Number = PaintKit.w1(n), h:Number = PaintKit.h1(n);
            if (n.shapeA == null) return;
            var g:Object = n.shapeA.graphics;
            g.clear();
            var r:Number = Math.min(w, h) / 2;
            var cx:Number = w / 2, cy:Number = h / 2;
            var hues:Array = [0xFF5A4A, 0xF7C84A, 0x5AD17A, 0x4AC8F0, 0x5A6CFF, 0xE05AE0];
            var seg:int = 48;
            for (var i:int = 0; i < seg; i++)
            {
                var a0:Number = i / seg * Math.PI * 2, a1:Number = (i + 1) / seg * Math.PI * 2;
                g.beginFill(hues[int(i / seg * hues.length) % hues.length]);
                g.moveTo(cx, cy);
                g.lineTo(cx + Math.cos(a0) * r, cy + Math.sin(a0) * r);
                g.lineTo(cx + Math.cos(a1) * r, cy + Math.sin(a1) * r);
                g.endFill();
            }
            g.beginFill(pal.surfaceSunken);
            g.drawCircle(cx, cy, r - 3);
            g.endFill();
            var val:Number = Number(n.extra[VAL]);
            var spr:Number = Number(n.extra[SPR]);
            var ang:Number = val * Math.PI * 2;
            var dr:Number = (r - 8) * spr;
            g.beginFill(pal.knob);
            g.drawCircle(cx + Math.cos(ang) * dr, cy + Math.sin(ang) * dr, 4.5);
            g.endFill();
        }

        private function down(n:UiNode, e:MouseEvent):void
        {
            endDrag(n);
            var self:ColorWheelWidget = this;
            apply(n, e.stageX - n.absX, e.stageY - n.absY);
            var st:* = n.app != null ? n.app.stage : null;
            if (st == null) return;
            n.extra[DRAG] = 1;
            var mv:Function = function(ev:MouseEvent):void { self.apply(n, ev.stageX - n.absX, ev.stageY - n.absY); };
            var up:Function = function(ev:MouseEvent):void { self.endDrag(n); };
            n.extra[MV] = mv; n.extra[UP] = up;
            st.addEventListener(MouseEvent.MOUSE_MOVE, mv);
            st.addEventListener(MouseEvent.MOUSE_UP, up);
        }
        private function apply(n:UiNode, x:Number, y:Number):void
        {
            var w:Number = PaintKit.w1(n), h:Number = PaintKit.h1(n);
            var cx:Number = w / 2, cy:Number = h / 2;
            var r:Number = Math.min(w, h) / 2 - 8;
            var dx:Number = x - cx, dy:Number = y - cy;
            var ang:Number = Math.atan2(dy, dx) / (Math.PI * 2);
            if (ang < 0) ang += 1;
            var dist:Number = Math.sqrt(dx * dx + dy * dy);
            var spr:Number = r > 0 ? Math.min(1, dist / r) : 0;
            n.extra[VAL] = ang; n.extra[SPR] = spr;
            n.dirty |= Dirty.M_PAINT;
            if (n.app != null) n.app.markPaint(n);
            var cw:ColorWheelNode = n.desc as ColorWheelNode;
            if (cw != null && cw.onChange != null) cw.onChange(ang);
        }
        private function endDrag(n:UiNode):void
        {
            if (n.extra == null) return;
            var st:* = n.app != null ? n.app.stage : null;
            if (st != null)
            {
                if (n.extra[MV] != null) st.removeEventListener(MouseEvent.MOUSE_MOVE, n.extra[MV]);
                if (n.extra[UP] != null) st.removeEventListener(MouseEvent.MOUSE_UP, n.extra[UP]);
            }
            n.extra[MV] = null; n.extra[UP] = null; n.extra[DRAG] = 0;
        }
        public function click(n:UiNode):Boolean { return false; }
    }
}
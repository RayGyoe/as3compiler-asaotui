// asaot.ui.kind.IconWidget -- the Shape behind IconNode.
//
// ONE SHAPE, TWO PASSES OF THE SAME PATH
// --------------------------------------
// `paint` replays the (cached) command list twice at most: once under a fill paint and
// once under a stroke paint. The stroke width arrives in VIEWBOX units, so it is
// multiplied by the render scale -- an icon drawn at 48 from a 24 viewBox has a 4px
// outline, which is what the source SVG means.
//
// CUBICS ARE NATIVE NOW. `C`/`S` in the data reach `cubicCurveTo` unchanged (one command
// per segment) and SVG arcs arrive already converted, so this widget replays four
// command kinds and approximates nothing. (Until compiler-gaps.md G26 was fixed the
// engine had only a quadratic, and PathData subdivided; that code is gone.)
//
// THE COMMAND LIST IS CACHED, AND THE CACHE KEY INCLUDES THE RENDER SIZE. Parsing
// allocates (one array per segment), and the cached list is in SCALED space -- the
// glyph is fitted into the box and the stroke width is a viewBox quantity -- so the key
// is data + viewBox + box + stroke width: a settled frame only replays.
//
// Z IS A LINE BACK TO THE SUBPATH START. `Graphics` has no `closePath` -- not in this
// subset and not in AIR's API either -- so the engine has nothing to close. Replaying
// Z as `lineTo(start)` is geometry a fill cannot tell apart from a real close, and for
// a stroke it produces the corner the data asked for. (PathData still reports CLOSE,
// so a reader of the command list can see the data's intent.)
//
// NO HIT RECT. Unlike the table, an icon has no interactive region of its own: a click
// on an icon is a click on whatever wraps it (a button's label, a row). Adding an
// invisible region would make the icon swallow clicks the author meant for its parent.
package asaot.ui.kind
{
    import asaot.ui.Dirty;
    import asaot.ui.IconNode;
    import asaot.ui.Node;
    import asaot.ui.PaintKit;
    import asaot.ui.PathData;
    import asaot.ui.Theme;
    import asaot.ui.UiNode;
    import asaot.ui.Widget;
    import asaot.ui.style.Style;

    import asaot.ui.LayoutConstants;

    import flash.display.Shape;

    public class IconWidget implements Widget
    {
        private static const SIG_KEY:String = "isig";   // data + viewBox + box + width
        private static const CMDS_KEY:String = "icmd";  // scaled, ready to replay

        public function build(n:UiNode):void
        {
            n.shapeA = new Shape();
            n.backing.addChild(n.shapeA);
        }

        public function payload(n:UiNode, desc:Node):Boolean
        {
            var d:IconNode = IconNode(desc);
            var changed:Boolean = false;
            if (n.extra["ipath"] == null || String(n.extra["ipath"]) != d.path)
            {
                n.extra["ipath"] = d.path;
                changed = true;
            }
            if (n.extra["icol"] == null || Number(n.extra["icol"]) != d.color) n.extra["icol"] = d.color;
            if (n.extra["istr"] == null || Boolean(n.extra["istr"]) != d.stroke) n.extra["istr"] = d.stroke;
            if (n.extra["ifil"] == null || Boolean(n.extra["ifil"]) != d.fill) n.extra["ifil"] = d.fill;
            if (n.extra["isw"] == null || Number(n.extra["isw"]) != d.strokeWidth)
            {
                n.extra["isw"] = d.strokeWidth;
                changed = true;                  // the cache key contains the width
            }
            // The viewBox is the INTRINSIC SIZE a boxless icon gets, so a change to it is
            // a layout change; the rest of the fields only change pixels.
            var vb:Number = d.viewBox > 0 ? d.viewBox : 24;
            if (n.extra["ivb"] == null || Number(n.extra["ivb"]) != vb)
            {
                n.extra["ivb"] = vb;
                n.extra[SIG_KEY] = null;          // the cached geometry is in the old space
                return true;
            }
            if (changed) n.extra[SIG_KEY] = null;
            return false;
        }

        public function wantsPress():Boolean { return false; }

        public function measure(n:UiNode):void
        {
            var s:Style = n.resolved;
            var vb:Number = Number(n.extra["ivb"]);
            if (!(vb > 0)) vb = 24;
            if (PaintKit.autoW(s)) PaintKit.setPointSize(n, LayoutConstants.AXIS_WIDTH, vb);
            if (PaintKit.autoH(s)) PaintKit.setPointSize(n, LayoutConstants.AXIS_HEIGHT, vb);
        }

        // Nothing is placed: the glyph is drawn into the solved box, centred, in paint.
        public function arrange(n:UiNode):void { }

        public function paint(n:UiNode):void
        {
            if (n.shapeA == null) return;
            var s:Style = n.resolved;
            var w:Number = PaintKit.w1(n);
            var h:Number = PaintKit.h1(n);
            var vb:Number = Number(n.extra["ivb"]);
            if (!(vb > 0)) vb = 24;

            // Contain: the glyph keeps its aspect and is centred in the box. A square
            // box therefore fills exactly, and a wide box gets two margins.
            var scale:Number = Math.min(w / vb, h / vb);
            if (!(scale > 0)) return;            // a zero-sized box draws nothing
            var ox:Number = (w - vb * scale) / 2;
            var oy:Number = (h - vb * scale) / 2;

            var sw:Number = n.extra["isw"] == null ? 2 : Number(n.extra["isw"]);
            var sig:String = String(n.extra["ipath"]) + "|" + vb + "|" + w + "|" + h + "|" + sw;
            if (n.extra[SIG_KEY] == null || String(n.extra[SIG_KEY]) != sig)
            {
                // Tolerance: a quarter of a RENDERED pixel, expressed in viewBox units.
                var cmds:Array = PathData.parse(String(n.extra["ipath"]));
                n.extra[CMDS_KEY] = scaleAll(cmds, scale, ox, oy);
                n.extra[SIG_KEY] = sig;
            }

            var col:uint = Theme.tokens().textStrong;
            if (!isNaN(s.text.color)) col = uint(s.text.color) & 0xFFFFFF;
            var own:Number = n.extra["icol"] == null ? NaN : Number(n.extra["icol"]);
            if (!isNaN(own)) col = uint(own) & 0xFFFFFF;
            var wantStroke:Boolean = n.extra["istr"] == null ? true : Boolean(n.extra["istr"]);
            var wantFill:Boolean = n.extra["ifil"] == null ? false : Boolean(n.extra["ifil"]);

            var g:Object = n.shapeA.graphics;
            g.clear();
            if (wantFill)
            {
                g.beginFill(col, 1.0);
                replay(g, n.extra[CMDS_KEY] as Array);
                g.endFill();
            }
            if (wantStroke)
            {
                // Round caps and joins: the icon sets this channel targets author with
                // stroke-linecap/-linejoin round.
                g.lineStyle(sw * scale, col, 1.0, false, "normal", "round", "round", 3);
                replay(g, n.extra[CMDS_KEY] as Array);
                g.endFill();
            }
        }

        public function click(n:UiNode):Boolean { return false; }

        // ---- geometry ----------------------------------------------------

        private static function scaleAll(cmds:Array, scale:Number, ox:Number, oy:Number):Array
        {
            var out:Array = [];
            for (var i:int = 0; i < cmds.length; i++)
            {
                var c:Array = cmds[i];
                var op:int = int(c[0]);
                if (op == PathData.MOVE || op == PathData.LINE)
                {
                    out.push([op, ox + Number(c[1]) * scale, oy + Number(c[2]) * scale]);
                }
                else if (op == PathData.QUAD)
                {
                    out.push([op, ox + Number(c[1]) * scale, oy + Number(c[2]) * scale,
                        ox + Number(c[3]) * scale, oy + Number(c[4]) * scale]);
                }
                else if (op == PathData.CUBIC)
                {
                    out.push([op, ox + Number(c[1]) * scale, oy + Number(c[2]) * scale,
                        ox + Number(c[3]) * scale, oy + Number(c[4]) * scale,
                        ox + Number(c[5]) * scale, oy + Number(c[6]) * scale]);
                }
                else
                {
                    out.push([op]);
                }
            }
            return out;
        }

        private static function replay(g:Object, cmds:Array):void
        {
            var startX:Number = 0;
            var startY:Number = 0;
            for (var i:int = 0; i < cmds.length; i++)
            {
                var c:Array = cmds[i];
                var op:int = int(c[0]);
                if (op == PathData.MOVE)
                {
                    startX = Number(c[1]);
                    startY = Number(c[2]);
                    g.moveTo(startX, startY);
                }
                else if (op == PathData.LINE)
                {
                    g.lineTo(Number(c[1]), Number(c[2]));
                }
                else if (op == PathData.QUAD)
                {
                    g.curveTo(Number(c[1]), Number(c[2]), Number(c[3]), Number(c[4]));
                }
                else if (op == PathData.CUBIC)
                {
                    g.cubicCurveTo(Number(c[1]), Number(c[2]), Number(c[3]), Number(c[4]),
                        Number(c[5]), Number(c[6]));
                }
                else
                {
                    g.lineTo(startX, startY);       // Z: Graphics has no closePath
                }
            }
        }
    }
}
// asaot.ui.kind.AvatarWidget -- the circle + initials for AvatarNode.
//
// THE POINT OF THIS WIDGET is where the initials are built. `paint` runs every
// frame and must allocate nothing (AGENTS.md memory rule), and initials OF a
// name are a freshly-built String, so they are computed ONCE in `payload`
// (when the name changes) and remembered on `n.extra`. `paint` only reads that
// string back for positioning/colouring.
//
// Sizing discipline: the diameter comes from the STYLE, so neither the name nor
// the tone ever returns true from `payload`. Both are paint-only changes.
package asaot.ui.kind
{
    import asaot.ui.AvatarNode;
    import asaot.ui.Dirty;
    import asaot.ui.Node;
    import asaot.ui.PaintKit;
    import asaot.ui.UiNode;
    import asaot.ui.Widget;
    import asaot.ui.style.Style;

    import flash.display.Shape;

    public class AvatarWidget implements Widget
    {
        private static const NAME_KEY:String = "name";
        private static const INITIALS_KEY:String = "initials";
        private static const TONE_KEY:String = "tone";

        public function build(n:UiNode):void
        {
            n.shapeA = new Shape();   // the circle
            n.backing.addChild(n.shapeA);
            n.tf = PaintKit.makeText(false);
            n.backing.addChild(n.tf);
        }

        public function payload(n:UiNode, desc:Node):Boolean
        {
            var a:AvatarNode = AvatarNode(desc);
            var nm:String = a.name;
            var prevName:Object = n.extra[NAME_KEY];
            if (prevName == null || nm != String(prevName))
            {
                n.extra[NAME_KEY] = nm;
                n.extra[INITIALS_KEY] = initialsOf(nm);
                // The letters changed, so refresh and re-measure the field HERE
                // (payload may allocate; paint may not).
                refreshText(n, String(n.extra[INITIALS_KEY]));
                n.dirty |= Dirty.M_PAINT;
            }
            var t:String = a.tone == null ? "neutral" : a.tone;
            var prevTone:Object = n.extra[TONE_KEY];
            if (prevTone == null || t != String(prevTone))
            {
                n.extra[TONE_KEY] = t;
                n.dirty |= Dirty.M_PAINT;   // decoration only: never a reflow
            }
            return false;   // the avatar's size comes from style, never the name
        }

        public function wantsPress():Boolean { return false; }

        public function measure(n:UiNode):void
        {
            // No intrinsic size: the diameter is a style value. But a style/font
            // change re-runs this pass, so re-measure the text so the centring in
            // `paint` stays correct.
            if (n.tf == null) return;
            refreshText(n, String(n.extra[INITIALS_KEY]));
        }

        public function arrange(n:UiNode):void
        {
            // The circle and its initials are placed in paint, where the solved
            // rect is final.
        }

        public function paint(n:UiNode):void
        {
            var s:Style = n.resolved;
            var w:Number = PaintKit.w1(n);
            var h:Number = PaintKit.h1(n);
            var bg:uint = 0x9CA3AF;
            var tone:String = String(n.extra[TONE_KEY]);
            if (tone == "info") bg = 0x2563EB;
            else if (tone == "danger") bg = 0xDC2626;

            var r:Number = w < h ? w / 2 : h / 2;
            if (n.shapeA != null)
            {
                var g:Object = n.shapeA.graphics;
                g.clear();
                g.beginFill(bg, 1.0);
                g.drawCircle(w / 2, h / 2, r);
                g.endFill();
            }
            if (n.tf != null)
            {
                n.tf.x = (w - n.state.measuredW) / 2;
                n.tf.y = (h - n.state.measuredH) / 2;
                n.tf.textColor = 0xFFFFFF;
            }
        }

        public function click(n:UiNode):Boolean { return false; }

        // Writes the initials into the field and refreshes the measured text
        // size used for centring. Called only from payload/measure (never paint).
        private function refreshText(n:UiNode, txt:String):void
        {
            PaintKit.measureField(n, n.tf, txt, n.resolved);
        }

        // "Ada Lovelace" -> "AL"; "grace" -> "G"; "  " -> "". The first letter of
        // each of the first two whitespace-separated words, uppercased.
        private static function initialsOf(name:String):String
        {
            if (name == null) return "";
            var out:String = "";
            var count:int = 0;
            var i:int = 0;
            var len:int = name.length;
            while (i < len && count < 2)
            {
                var c:String = name.charAt(i);
                if (c == " " || c == "\t" || c == "\n" || c == "\r") { i = i + 1; continue; }
                out = out + name.substr(i, 1).toUpperCase();
                count = count + 1;
                while (i < len)
                {
                    var d:String = name.charAt(i);
                    if (d == " " || d == "\t" || d == "\n" || d == "\r") break;
                    i = i + 1;
                }
            }
            return out;
        }
    }
}
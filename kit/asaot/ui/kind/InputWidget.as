// asaot.ui.kind.InputWidget -- the single-line editable field.
//
// The editing text object is a REAL flash.text.TextField with type="input"
// (design doc sections 4.2/4.4), so caret/selection/masking come from the
// existing, adl-calibrated text pipeline.
//
// KNOWN GAP (recorded in asaotui/STATUS.md section 3.1, NOT fixed here): this
// widget mirrors the MODEL into the field on every paint and there is no
// TEXT_INPUT listener writing edits back, so a repaint reverts typed text and
// `onCommit` is never called. Closing that needs the keyboard/focus pass
// (UiApp has no KeyboardEvent handling at all yet).
package asaot.ui.kind
{
    import asaot.ui.Dirty;
    import asaot.ui.PaintKit;
    import asaot.ui.TextInput;
    import asaot.ui.UiNode;
    import asaot.ui.Widget;
    import asaot.ui.Node;
    import asaot.ui.style.Style;
    import asaot.ui.style.TextStyle;

    import asaot.ui.LayoutConstants;

    import flash.display.Shape;
    import flash.text.TextFormat;

    public class InputWidget implements Widget
    {
        public function build(n:UiNode):void
        {
            n.shapeA = new Shape();
            n.backing.addChild(n.shapeA);
            n.tf = PaintKit.makeText(true);
            n.tf.type = "input";
            n.tf.autoSize = "none";
            n.backing.addChild(n.tf);
        }

        public function payload(n:UiNode, desc:Node):Boolean
        {
            var ti:TextInput = TextInput(desc);
            n.placeholder = ti.placeholder;
            n.password = ti.password;
            n.onCommit = ti.onCommit;
            n.onClick = ti.onClick;
            n.binding = ti.binding;
            var tv:String = ti.value;
            if (ti.binding != null)
            {
                var bv:Object = ti.binding.get();
                tv = bv == null ? "" : String(bv);
            }
            if (tv != n.value)
            {
                n.value = tv;
                // A value change is a PAINT change only: the field must never
                // resize itself to fit the typing (see `measure`).
                n.dirty |= Dirty.M_PAINT;
            }
            return false;
        }

        public function wantsPress():Boolean { return false; }

        public function measure(n:UiNode):void
        {
            // A field with no explicit height gets a 32pt default; its width is
            // never intrinsic (a text field must not grow with the typing).
            if (PaintKit.autoH(n.resolved)) PaintKit.setPointSize(n, LayoutConstants.AXIS_HEIGHT, 32);
        }

        public function arrange(n:UiNode):void
        {
            if (n.tf == null) return;
            n.tf.x = PaintKit.insetX(n);
            n.tf.y = PaintKit.insetY(n);
            n.tf.width = PaintKit.contentW(n);
            n.tf.height = PaintKit.contentH(n);
            n.tf.displayAsPassword = n.password;
        }

        public function paint(n:UiNode):void
        {
            var s:Style = n.resolved;
            PaintKit.paintBox(n, s, PaintKit.w1(n), PaintKit.h1(n));
            if (n.tf == null) return;
            var shown:String = n.value;
            var color:Number = isNaN(s.text.color) ? 0x202020 : s.text.color;
            if ((shown == null || shown.length == 0) && n.placeholder != null && n.placeholder.length > 0)
            {
                shown = n.placeholder;
                color = 0x9A9A9A;
            }
            var f:TextFormat = PaintKit.formatFor(s);
            f.color = uint(color);
            n.tf.defaultTextFormat = f;
            if (n.tf.text != shown) n.tf.text = shown == null ? "" : shown;
            n.tf.setTextFormat(f);
            n.tf.textColor = uint(color);
        }

        public function click(n:UiNode):Boolean { return false; }
    }
}
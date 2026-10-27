// asaot.ui.kind.TextAreaWidget -- the multi-line editable field.
//
// Sibling of InputWidget, deliberately NOT a subclass of it. The four things it
// does differently are all contracts, not options (see TextAreaNode's header):
// Enter inserts instead of committing, the box height comes from `rows`, the field
// wraps, and Escape still reverts to the last committed value.
//
// The controlled/uncontrolled split, the placeholder overlay, the "never write the
// field while it agrees" rule and the write-through Binding are the same as
// InputWidget's -- same reasons, measured there (see that file's header points 1-4
// and defects a/b). What is NOT copied is setTextFormat: this file paints through
// defaultTextFormat + textColor for the same single-format reason.
package asaot.ui.kind
{
    import asaot.ui.Dirty;
    import asaot.ui.Node;
    import asaot.ui.PaintKit;
    import asaot.ui.TextAreaNode;
    import asaot.ui.Theme;
    import asaot.ui.UiNode;
    import asaot.ui.Widget;
    import asaot.ui.WidgetFocus;
    import asaot.ui.WidgetKeys;
    import asaot.ui.style.Style;

    import asaot.ui.LayoutConstants;

    import flash.display.DisplayObject;
    import flash.display.Shape;
    import flash.events.Event;
    import flash.events.FocusEvent;
    import flash.text.TextField;
    import flash.text.TextFormat;

    public class TextAreaWidget implements Widget, WidgetFocus, WidgetKeys
    {
        private static const MODEL_KEY:String = "modelValue";
        private static const COMMIT_KEY:String = "committed";
        private static const PH_KEY:String = "placeholderField";
        private static const ROWS_KEY:String = "rows";
        private static const DEFAULT_ROWS:int = 4;
        // Used only when a measurement returns nothing (a 0-height font, e.g.
        // before the theme is resolved). NOT a layout constant: the real height is
        // measured from the resolved font each time.
        private static const FALLBACK_LINE:Number = 16;

        public function build(n:UiNode):void
        {
            n.shapeA = new Shape();
            n.backing.addChild(n.shapeA);
            n.tf = PaintKit.makeText(true);
            n.tf.type = "input";
            n.tf.autoSize = "none";
            // The two flags that make this a text AREA. Without wordWrap a long line
            // would scroll horizontally instead of wrapping.
            n.tf.multiline = true;
            n.tf.wordWrap = true;
            n.backing.addChild(n.tf);

            // Ghost text, on top, never interactive (see InputWidget for why it is a
            // second field rather than text written into the editing one).
            var ph:TextField = PaintKit.makeText(false);
            ph.autoSize = "none";
            n.backing.addChild(ph);
            n.extra[PH_KEY] = ph;
            n.extra[MODEL_KEY] = null;
            n.extra[COMMIT_KEY] = "";

            var self:TextAreaWidget = this;
            n.listen(n.tf, Event.CHANGE, function (e:Event):void { self.onFieldChange(n); });
            n.listen(n.tf, FocusEvent.FOCUS_OUT, function (e:FocusEvent):void { self.onFieldBlur(n); });
        }

        public function payload(n:UiNode, desc:Node):Boolean
        {
            var ta:TextAreaNode = TextAreaNode(desc);
            n.placeholder = ta.placeholder;
            n.onCommit = ta.onCommit;
            n.onChange = ta.onChange;
            n.onClick = ta.onClick;
            n.binding = ta.binding;
            // `rows` is mirrored through `extra` so measure can read it without a
            // cast (UiNode has no rows field, and adding one would put a widget's
            // private knob on the base class).
            var rows:int = ta.rows > 0 ? ta.rows : DEFAULT_ROWS;
            if (n.extra[ROWS_KEY] != rows) { n.extra[ROWS_KEY] = rows; n.dirty |= Dirty.M_MEASURE; }
            var tv:String = ta.value;
            if (ta.binding != null)
            {
                var bv:Object = ta.binding.get();
                tv = bv == null ? "" : String(bv);
            }
            var last:Object = n.extra[MODEL_KEY];
            n.extra[MODEL_KEY] = tv;
            if (tv != last && tv != n.value)
            {
                n.value = tv;
                n.extra[COMMIT_KEY] = tv;
                n.dirty |= Dirty.M_PAINT;
            }
            else if (tv != last)
            {
                n.extra[COMMIT_KEY] = tv;
            }
            return false;
        }

        public function wantsPress():Boolean { return false; }

        public function focusTarget(n:UiNode):DisplayObject
        {
            return n.tf;
        }

        // WidgetKeys: Enter is NOT consumed -- the runtime inserts a newline into a
        // multiline field, and consuming 13 here would suppress exactly that
        // (`as_key_text_suppressed`, src/emit.ts). So a text area commits on BLUR;
        // there is no "Enter means done" in a control where Enter means newline.
        // Escape reverts to the last committed value, same as textField.
        public function onKey(n:UiNode, keyCode:int, shift:Boolean):Boolean
        {
            if (keyCode == 27)
            {
                var keep:String = String(n.extra[COMMIT_KEY]);
                if (n.tf != null) n.tf.text = keep;
                n.value = keep;
                n.dirty |= Dirty.M_PAINT;
                return true;
            }
            return false;
        }

        // Real line height of the resolved font, measured with the field itself so
        // there is no second width/height model to drift. The field is restored to
        // the model before returning.
        private function lineHeight(n:UiNode, s:Style):Number
        {
            var f:TextFormat = PaintKit.formatFor(s);
            n.tf.defaultTextFormat = f;
            n.tf.text = "Xg";
            var h:Number = n.tf.textHeight;
            var model:String = n.value == null ? "" : n.value;
            if (n.tf.text != model) n.tf.text = model;
            return h > 0 ? h : FALLBACK_LINE;
        }

        public function measure(n:UiNode):void
        {
            if (n.tf == null || n.extra == null) return;
            var s:Style = n.resolved;
            if (!PaintKit.autoH(s)) return;
            var rows:int = DEFAULT_ROWS;
            if (n.extra[ROWS_KEY] != null) rows = int(n.extra[ROWS_KEY]);
            var h:Number = rows * this.lineHeight(n, s)
                + PaintKit.padV(s.padding) + PaintKit.borderV(s.borderWidths);
            PaintKit.setPointSize(n, LayoutConstants.AXIS_HEIGHT, h);
        }

        public function arrange(n:UiNode):void
        {
            if (n.tf == null) return;
            var x:Number = PaintKit.insetX(n);
            var y:Number = PaintKit.insetY(n);
            var w:Number = PaintKit.contentW(n);
            var h:Number = PaintKit.contentH(n);
            n.tf.x = x;
            n.tf.y = y;
            n.tf.width = w;
            n.tf.height = h;
            var ph:Object = n.extra[PH_KEY];
            if (ph != null)
            {
                TextField(ph).x = x;
                TextField(ph).y = y;
                TextField(ph).width = w;
                TextField(ph).height = h;
            }
        }

        public function paint(n:UiNode):void
        {
            var s:Style = n.resolved;
            PaintKit.paintBox(n, s, PaintKit.w1(n), PaintKit.h1(n));
            if (n.tf == null) return;
            var shown:String = n.value == null ? "" : n.value;
            var color:Number = isNaN(s.text.color) ? Theme.tokens().textControl : s.text.color;
            var f:TextFormat = PaintKit.formatFor(s);
            f.color = uint(color);
            n.tf.defaultTextFormat = f;
            // Never write the field while it agrees (assignment resets the caret; the
            // measurement in `lineHeight` can leave the field holding a probe string).
            if (n.tf.text != shown) n.tf.text = shown;
            n.tf.textColor = uint(color);

            var ph:TextField = TextField(n.extra[PH_KEY]);
            var usePh:Boolean = shown.length == 0 && n.state.focused == 0
                && n.placeholder != null && n.placeholder.length > 0;
            ph.visible = usePh;
            if (usePh && ph.text != n.placeholder)
            {
                var pf:TextFormat = PaintKit.formatFor(s);
                pf.color = Theme.tokens().placeholder;
                ph.defaultTextFormat = pf;
                ph.text = n.placeholder;
            }
            PaintKit.decorate(n);
        }

        public function click(n:UiNode):Boolean { return false; }

        // ---- edits ---------------------------------------------------------
        private function onFieldChange(n:UiNode):void
        {
            if (n.tf == null || n.extra == null) return;
            var t:String = n.tf.text;
            if (t == n.value) return;
            n.value = t;
            n.app.markPaint(n);
            if (n.binding != null) n.binding.set(t);
            if (n.onChange != null) n.onChange(t);
        }

        private function onFieldBlur(n:UiNode):void
        {
            this.onFieldChange(n);
            this.commit(n);
        }

        private function commit(n:UiNode):void
        {
            if (n.extra == null) return;
            n.app.markPaint(n);
            n.extra[COMMIT_KEY] = n.value;
            if (n.binding != null) n.binding.set(n.value);
            if (n.onCommit != null) n.onCommit(n.value);
        }
    } // class
}
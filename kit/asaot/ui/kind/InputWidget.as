// asaot.ui.kind.InputWidget -- the single-line editable field.
//
// The editing text object is a REAL flash.text.TextField with type="input"
// (design doc sections 4.2/4.4), so caret/selection/masking come from the
// existing, adl-calibrated text pipeline. We do not write a second one.
//
// WHAT CHANGED FROM THE MIRROR-ONLY VERSION (this widget used to be the one
// control in the kit that looked usable and was not: it copied the MODEL into the
// field on every paint, so the first repaint erased whatever the user had typed
// and `onCommit` could never fire)
//
//   1. EDITS GO FORWARD. `Event.CHANGE` on the field writes `n.value` (so the next
//      paint agrees with the field instead of reverting it), writes the Binding if
//      there is one, and calls `onChange(value)`. The runtime dispatches CHANGE
//      after every real edit -- typed text, paste, cut, backspace.
//   2. THE MODEL GOES FORWARD TOO, ONCE. `payload` adopts the descriptor's `value`
//      only when that value CHANGED since the last payload -- not when it merely
//      differs from the field. That is the controlled/uncontrolled split: an
//      author who writes the new value back (controlled) still wins, while a
//      descriptor that just repeats its initial value (uncontrolled) no longer
//      stomps the user's typing.
//   3. COMMIT = ENTER OR BLUR. `onCommit(value)` fires on Enter and on the field's
//      FOCUS_OUT (the runtime's own signal, which covers "clicked somewhere else"
//      without this widget having to track the pointer).
//   4. THE PLACEHOLDER IS A SEPARATE FIELD. It used to be written INTO the editing
//      field, which is harmless only while the field is read-only: the moment
//      typing works, the user types after the ghost text. Now a second,
//      non-interactive TextField sits on top and is shown only while the model is
//      empty AND the field is not focused -- so the editing field is always
//      exactly the model, and the ghost never sits under a live caret.
//
// TWO DEFECTS THIS FILE HAD TO LEARN (both reported from the gallery):
//
//   a. THE GHOST STAYED WHILE TYPING. `paint` decided on `n.value`, but a
//      keystroke reaches `paint` only if something asks for one -- `onFieldChange`
//      wrote the model and nothing else, so the frame that showed the new text was
//      the NEXT unrelated repaint. The edit now marks itself dirty, and the ghost
//      is also hidden while the field is focused: a focused empty field shows a
//      caret exactly where the ghost text is, so an overlay ghost would cover it.
//
//   b. THE TEXT RENDERED TWICE. `paint` called `setTextFormat(fmt)` on EVERY
//      repaint. The runtime APPENDED one (begin,end,format) run per call instead
//      of replacing the formatting for that range (see compiler-gaps.md G20), and
//      its run-to-paragraph builder emits every byte once per run -- so N repaints
//      made the same string paint N times, which is what "lose focus, focus again
//      and my text is duplicated" was. G20 is FIXED (compiler stage 268: the setter
//      now REBUILDS the run table), so the same call would only be redundant work
//      today. This file paints through `defaultTextFormat` + `textColor` because a
//      single-format field has nothing to say per range; the single-copy rule is
//      pinned by probes/widgets/typing, the replace semantics by
//      probes/g20-settextformat.
package asaot.ui.kind
{
    import asaot.ui.Dirty;
    import asaot.ui.Node;
    import asaot.ui.PaintKit;
    import asaot.ui.TextInput;
    import asaot.ui.Theme;
    import asaot.ui.UiNode;
    import asaot.ui.Widget;
    import asaot.ui.WidgetFocus;
    import asaot.ui.WidgetKeys;
    import asaot.ui.style.Style;
    import asaot.ui.style.TextStyle;

    import asaot.ui.LayoutConstants;

    import flash.display.DisplayObject;
    import flash.display.Shape;
    import flash.events.Event;
    import flash.events.FocusEvent;
    import flash.text.TextField;
    import flash.text.TextFormat;

    public class InputWidget implements Widget, WidgetFocus, WidgetKeys
    {
        private static const MODEL_KEY:String = "modelValue";
        private static const COMMIT_KEY:String = "committed";
        private static const PH_KEY:String = "placeholderField";

        public function build(n:UiNode):void
        {
            n.shapeA = new Shape();
            n.backing.addChild(n.shapeA);
            n.tf = PaintKit.makeText(true);
            n.tf.type = "input";
            n.tf.autoSize = "none";
            n.backing.addChild(n.tf);

            // The ghost text. Added AFTER the field so it draws on top; it takes no
            // mouse and no keyboard, so it can never steal the caret.
            var ph:TextField = PaintKit.makeText(false);
            ph.autoSize = "none";
            n.backing.addChild(ph);
            n.extra[PH_KEY] = ph;
            n.extra[MODEL_KEY] = null;
            n.extra[COMMIT_KEY] = "";

            var self:InputWidget = this;
            n.listen(n.tf, Event.CHANGE, function (e:Event):void { self.onFieldChange(n); });
            n.listen(n.tf, FocusEvent.FOCUS_OUT, function (e:FocusEvent):void { self.onFieldBlur(n); });
        }

        public function payload(n:UiNode, desc:Node):Boolean
        {
            var ti:TextInput = TextInput(desc);
            n.placeholder = ti.placeholder;
            n.password = ti.password;
            n.onCommit = ti.onCommit;
            n.onChange = ti.onChange;
            n.onClick = ti.onClick;
            n.binding = ti.binding;
            var tv:String = ti.value;
            if (ti.binding != null)
            {
                var bv:Object = ti.binding.get();
                tv = bv == null ? "" : String(bv);
            }
            // Only a CHANGE in the model is authoritative (see the header, point 2).
            var last:Object = n.extra[MODEL_KEY];
            n.extra[MODEL_KEY] = tv;
            if (tv != last && tv != n.value)
            {
                n.value = tv;
                n.extra[COMMIT_KEY] = tv;
                // A value change is a PAINT change only: the field must never
                // resize itself to fit the typing (see `measure`).
                n.dirty |= Dirty.M_PAINT;
            }
            else if (tv != last)
            {
                n.extra[COMMIT_KEY] = tv;
            }
            return false;
        }

        public function wantsPress():Boolean { return false; }

        // WidgetFocus: typing goes to the REAL field (see the interface).
        public function focusTarget(n:UiNode):DisplayObject
        {
            return n.tf;
        }

        // WidgetKeys: Enter commits, Escape reverts to the last committed value.
        // Space and the arrows are NOT consumed -- they belong to the field.
        public function onKey(n:UiNode, keyCode:int, shift:Boolean):Boolean
        {
            if (keyCode == 13)
            {
                this.onFieldChange(n);      // a programmatic set does not fire CHANGE
                this.commit(n);
                return true;
            }
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

        public function measure(n:UiNode):void
        {
            // A field with no explicit height gets a 32pt default; its width is
            // never intrinsic (a text field must not grow with the typing).
            if (PaintKit.autoH(n.resolved)) PaintKit.setPointSize(n, LayoutConstants.AXIS_HEIGHT, 32);
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
            n.tf.displayAsPassword = n.password;
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
            // NEVER write the field while it agrees: assigning `text` in AIR resets
            // the caret to the end of the inserted run, which shows up as a caret
            // that jumps to position 0 on every keystroke's repaint.
            if (n.tf.text != shown) n.tf.text = shown;
            // NO setTextFormat HERE (defect b in the header). That is a design
            // choice now, not a workaround: one format per field is fully described
            // by defaultTextFormat + textColor, and a run table is only needed for
            // RICH text (htmlText / a per-range format). Since G20 was fixed
            // (stage 268) a call here would no longer duplicate the glyphs -- it
            // would just be redundant work on every paint.
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

        // ---- edits (see the header) ----------------------------------------
        // Reads the field into the model. Idempotent, so the key path can call it
        // before committing (a programmatic `tf.text = ...` dispatches no CHANGE).
        private function onFieldChange(n:UiNode):void
        {
            if (n.tf == null || n.extra == null) return;
            var t:String = n.tf.text;
            if (t == n.value) return;
            n.value = t;
            // The ghost depends on `n.value`, so the edit owes the screen a paint
            // (defect a in the header -- without this the first keystroke of a
            // freshly focused field kept "Account or email" over the typed text).
            n.app.markPaint(n);
            if (n.binding != null) n.binding.set(t);
            if (n.onChange != null) n.onChange(t);
        }

        private function onFieldBlur(n:UiNode):void
        {
            // The runtime blurs the field when focus moves to anything that is not a
            // TextField, which is exactly "the user finished with this field".
            this.onFieldChange(n);
            this.commit(n);
        }

        private function commit(n:UiNode):void
        {
            if (n.extra == null) return;
            // A blur that leaves the field empty brings the ghost back.
            n.app.markPaint(n);
            n.extra[COMMIT_KEY] = n.value;
            if (n.binding != null) n.binding.set(n.value);
            if (n.onCommit != null) n.onCommit(n.value);
        }
    }
}
// asaot.ui.kind.NumberInputWidget -- a numeric field plus a stepper column.
//
// THREE SOURCES, ONE WRITE POINT. The value can change from the field's Enter/blur,
// from the arrow keys, or from a press on the +- column; all three end in
// `commit()`, which clamps, rounds, writes the Binding, calls `onChange`, repaints
// and asks for one describe. There is no second place that writes `extra[MODEL]`,
// which is what keeps the stepper and the typed value from disagreeing.
//
// THE FIELD IS NOT SYNCOPATED WHILE YOU TYPE. `payload` writes the model into the
// field ONLY when the model itself changed since the last time it looked (the same
// controlled/uncontrolled split InputWidget documents). A payload that merely
// repeats the current value must not rewrite the field: assigning `tf.text` in AIR
// moves the caret to the end, so a keystroke whose repaint re-asserted the model
// would move the caret on every character.
//
// TYPING IS NOT PARSED UNTIL IT IS FINISHED. "12." and "-" and "" are legal
// intermediate states of a number and `Number()` answers NaN for all three; parsing
// per keystroke would either refuse them (the author cannot type 1.5) or write a
// wrong value. So Enter and FOCUS_OUT parse, and anything unparseable REVERTS to the
// model -- no silent repair, no 0 substituted for garbage.
//
// THE STEP APPLIES TO THE VALUE, NOT TO A GRID. `step: 5` with a typed 7 stays 7:
// snapping typed input to `min + k*step` would change what the user wrote, and the
// author who wants that can clamp in `onCommit`. The arrow keys move BY step from
// wherever the value is, which is what every spin button does.
package asaot.ui.kind
{
    import asaot.ui.Dirty;
    import asaot.ui.LayoutConstants;
    import asaot.ui.Node;
    import asaot.ui.NumberInputNode;
    import asaot.ui.PaintKit;
    import asaot.ui.Theme;
    import asaot.ui.ThemeTokens;
    import asaot.ui.UiNode;
    import asaot.ui.Widget;
    import asaot.ui.WidgetFocus;
    import asaot.ui.WidgetKeys;
    import asaot.ui.style.Style;

    import flash.display.DisplayObject;
    import flash.display.Shape;
    import flash.events.Event;
    import flash.events.FocusEvent;
    import flash.events.MouseEvent;
    import flash.text.TextField;
    import flash.text.TextFormat;

    public class NumberInputWidget implements Widget, WidgetFocus, WidgetKeys
    {
        private static const FIELD:String = "numField";   // the editable value field (== n.tf)
        private static const LABEL_TF:String = "numLabel";
        private static const MODEL:String = "numModel";   // the widget's own value
        private static const AUTHOR:String = "numAuthor"; // last desc.value seen (see payload)
        private static const HIT:String = "numHit";       // 1 when a press landed on a stepper
        private static const LBL_W:String = "numLblW";
        private static const MIN_K:String = "numMin";
        private static const MAX_K:String = "numMax";
        private static const STEP_K:String = "numStep";
        private static const DEC_K:String = "numDec";
        private static const LBL_K:String = "numLbl";

        private static const STEP_W:Number = 32;    // two 32pt-wide pointer targets
        private static const GAP:Number = 8;        // between the label and the field
        private static const DEFAULT_W:Number = 150;
        private static const DEFAULT_H:Number = 36;

        public function build(n:UiNode):void
        {
            n.shapeA = new Shape();          // background / border (child 0)
            n.backing.addChild(n.shapeA);

            var lbl:TextField = PaintKit.makeText(false);
            lbl.autoSize = "none";
            n.backing.addChild(lbl);
            n.extra[LABEL_TF] = lbl;

            n.tf = PaintKit.makeText(true);  // the REAL field: caret/selection/mask
            n.tf.type = "input";
            n.tf.autoSize = "none";
            n.backing.addChild(n.tf);
            n.extra[FIELD] = n.tf;

            n.shapeB = new Shape();          // the +- column, above the field
            n.backing.addChild(n.shapeB);

            n.extra[MODEL] = null;
            n.extra[HIT] = 0;
            n.extra[LBL_W] = 0;

            var self:NumberInputWidget = this;
            n.listen(n.tf, Event.CHANGE,
                function (e:Event):void { n.app.markPaint(n); });
            n.listen(n.tf, FocusEvent.FOCUS_OUT,
                function (e:FocusEvent):void { self.commitText(n); });
            n.listen(n.backing, MouseEvent.MOUSE_DOWN,
                function (e:MouseEvent):void { self.onPress(n, e); });
        }

        public function payload(n:UiNode, desc:Node):Boolean
        {
            var ni:NumberInputNode = NumberInputNode(desc);
            n.binding = ni.binding;
            n.onChange = ni.onChange;
            n.onCommit = ni.onCommit;
            n.extra[MIN_K] = ni.min;
            n.extra[MAX_K] = ni.max;
            n.extra[STEP_K] = ni.step;
            n.extra[DEC_K] = ni.decimals;
            n.extra[LBL_K] = ni.label;

            // ---- controlled / uncontrolled, the one place it is decided --------
            // The widget keeps its OWN value; the description is the author's OPENING
            // value. Without the AUTHOR snapshot the next describe would read
            // `desc.value` again and quietly undo every edit -- and a describe happens
            // on ANY unrelated change (another node invalidating ALL re-runs this
            // payload too). So: adopt the description ONLY when it MOVED since the
            // last payload. A binding is different -- it IS the model -- and wins
            // every frame.
            var authored:Number = ni.value;
            if (ni.binding != null)
            {
                // `*`, NOT `Object`: an Object slot would box the value once per read.
                var bv:* = ni.binding.get();
                authored = bv == null ? 0 : Number(bv);
            }
            if (isNaN(authored)) authored = 0;
            authored = NumberInputNode.clamp(ni.min, ni.max, authored);
            authored = NumberInputNode.roundTo(authored, ni.decimals);

            var prevAuthor:Object = n.extra[AUTHOR];
            var adopt:Boolean = ni.binding != null
                || prevAuthor == null || Number(prevAuthor) != authored;
            var model:Object = n.extra[MODEL];
            if (adopt)
            {
                n.extra[AUTHOR] = authored;
                if (model == null || Number(model) != authored)
                {
                    n.extra[MODEL] = authored;
                    this.show(n, authored);
                    n.value = this.textOf(authored);
                    n.dirty |= Dirty.M_PAINT;
                }
                return false;
            }

            // Nothing was authored: the widget's own value stands. Only repair the
            // FIELD when it has focus-free disagreement (a half-typed value that never
            // committed).
            var keep:Number = model == null ? authored : Number(model);
            if (n.state.focused == 0 && n.tf != null && n.tf.text != this.textOf(keep))
            {
                this.show(n, keep);
            }
            n.value = this.textOf(keep);
            return false;
        }

        public function wantsPress():Boolean { return true; }

        public function focusTarget(n:UiNode):DisplayObject { return n.tf; }

        public function measure(n:UiNode):void
        {
            if (PaintKit.autoW(n.resolved)) PaintKit.setPointSize(n, LayoutConstants.AXIS_WIDTH, DEFAULT_W);
            if (PaintKit.autoH(n.resolved)) PaintKit.setPointSize(n, LayoutConstants.AXIS_HEIGHT, DEFAULT_H);
        }

        public function arrange(n:UiNode):void
        {
            var s:Style = n.resolved;
            var x:Number = PaintKit.insetX(n);
            var y:Number = PaintKit.insetY(n);
            var w:Number = PaintKit.contentW(n);
            var h:Number = PaintKit.contentH(n);

            var lbl:TextField = TextField(n.extra[LABEL_TF]);
            var name:String = n.extra[LBL_K] == null ? "" : String(n.extra[LBL_K]);
            var lw:Number = 0;
            if (name.length > 0)
            {
                var lf:TextFormat = PaintKit.formatFor(s);
                lbl.defaultTextFormat = lf;
                if (lbl.text != name) lbl.text = name;
                lw = lbl.textWidth + 2;
                var cap:Number = w * 0.45;
                if (lw > cap) lw = cap;
                if (lw < 0) lw = 0;
            }
            n.extra[LBL_W] = lw;
            lbl.x = x;
            lbl.y = y;
            lbl.width = lw;
            lbl.height = h;

            var fx:Number = x + lw + (lw > 0 ? GAP : 0);
            var fw:Number = w - (fx - x) - STEP_W - 2;
            if (fw < 0) fw = 0;
            if (n.tf != null)
            {
                n.tf.x = fx;
                n.tf.y = y;
                n.tf.width = fw;
                n.tf.height = h;
            }
        }

        public function paint(n:UiNode):void
        {
            var s:Style = n.resolved;
            var w:Number = PaintKit.w1(n);
            var h:Number = PaintKit.h1(n);
            PaintKit.paintBox(n, s, w, h);
            if (n.tf == null) return;

            var color:Number = isNaN(s.text.color) ? Theme.tokens().textControl : s.text.color;
            var f:TextFormat = PaintKit.formatFor(s);

            var lbl:TextField = TextField(n.extra[LABEL_TF]);
            var lf:TextFormat = PaintKit.formatFor(s);
            lf.color = Theme.tokens().textMuted;
            lbl.defaultTextFormat = lf;
            lbl.textColor = Theme.tokens().textMuted;

            // Right-aligned: a numeric column reads by its last digit, and a
            // left-aligned number jitters the ones place as the digits grow.
            var ff:TextFormat = PaintKit.formatFor(s);
            ff.color = uint(color);
            ff.align = "right";
            n.tf.defaultTextFormat = ff;
            n.tf.textColor = uint(color);

            this.paintSteppers(n, w, h);
            PaintKit.decorate(n);
        }

        public function click(n:UiNode):Boolean
        {
            return Number(n.extra[HIT]) != 0;
        }

        // ---- pointer ---------------------------------------------------------
        // A press on the stepper column steps once. There is no repeat-while-held:
        // that is a pointer-capture feature this runtime does not have, and a timer
        // per press would be a per-gesture allocation the steady-state rule forbids.
        private function onPress(n:UiNode, e:MouseEvent):void
        {
            n.extra[HIT] = 0;
            if (n.inert()) return;
            var w:Number = n.absW > 1 ? n.absW : DEFAULT_W;
            var h:Number = n.absH > 1 ? n.absH : DEFAULT_H;
            if (e.localX < w - STEP_W) return;
            n.extra[HIT] = 1;
            // The press landed on the STEPPER, which is not a text field: the runtime
            // focused nothing and UiApp dropped the node on the FOCUS_OUT that follows,
            // so the arrow keys would be dead right after a click on `+`. Claim the node
            // back -- the stepper is part of this editor, not a separate control.
            n.app.focusNode(n);
            var up:Boolean = e.localY < h / 2;
            var step:Number = Number(n.extra[STEP_K]);
            if (!(step > 0)) step = 1;
            var v:Number = Number(n.extra[MODEL]);
            this.commit(n, up ? v + step : v - step);
        }

        private function paintSteppers(n:UiNode, w:Number, h:Number):void
        {
            if (n.shapeB == null) return;
            var g:Object = n.shapeB.graphics;
            g.clear();
            var x0:Number = w - STEP_W;
            var pal:ThemeTokens = Theme.tokens();
            // The whole column is a pointer target, not just the +/- strokes.
            // An alpha-0 fill still participates in this backend's path hit test;
            // without it a press between the strokes falls through to the field.
            g.beginFill(0x000000, 0);
            g.drawRect(x0, 0, STEP_W, h);
            g.endFill();
            // The divider: the column is a separate affordance, so it gets an edge.
            g.lineStyle(1, pal.border, 1.0);
            g.moveTo(x0, 2);
            g.lineTo(x0, h - 2);
            // A line between the two halves so +/- are two targets, not one.
            g.moveTo(x0 + 2, h / 2);
            g.lineTo(w - 2, h / 2);

            var cx:Number = x0 + STEP_W / 2;
            var color:uint = PaintKit.stateColor(n, pal.textMuted);
            g.lineStyle(1.5, color, 1.0);
            var topY:Number = h / 4;
            var botY:Number = topY + h / 2;
            var arm:Number = 4;
            // plus
            g.moveTo(cx - arm, topY);
            g.lineTo(cx + arm, topY);
            g.moveTo(cx, topY - arm);
            g.lineTo(cx, topY + arm);
            // minus
            g.moveTo(cx - arm, botY);
            g.lineTo(cx + arm, botY);
        }

        // ---- keyboard --------------------------------------------------------
        public function onKey(n:UiNode, keyCode:int, shift:Boolean):Boolean
        {
            var step:Number = Number(n.extra[STEP_K]);
            if (!(step > 0)) step = 1;
            var v:Number = Number(n.extra[MODEL]);
            if (keyCode == 38) { this.commit(n, v + step); return true; }
            if (keyCode == 40) { this.commit(n, v - step); return true; }
            if (keyCode == 33) { this.commit(n, v + step * 10); return true; }
            if (keyCode == 34) { this.commit(n, v - step * 10); return true; }
            if (keyCode == 36)
            {
                var mn:Number = Number(n.extra[MIN_K]);
                if (isNaN(mn)) return false;
                this.commit(n, mn);
                return true;
            }
            if (keyCode == 35)
            {
                var mx:Number = Number(n.extra[MAX_K]);
                if (isNaN(mx)) return false;
                this.commit(n, mx);
                return true;
            }
            if (keyCode == 13) { this.commitText(n); return true; }
            if (keyCode == 27) { this.show(n, Number(n.extra[MODEL])); return true; }
            return false;
        }

        // ---- the one write point --------------------------------------------
        private function commit(n:UiNode, raw:Number):void
        {
            var mn:Number = Number(n.extra[MIN_K]);
            var mx:Number = Number(n.extra[MAX_K]);
            var dec:int = int(Number(n.extra[DEC_K]));
            var v:Number = NumberInputNode.clamp(mn, mx, NumberInputNode.roundTo(raw, dec));
            var prev:Number = Number(n.extra[MODEL]);
            n.extra[MODEL] = v;
            n.value = this.textOf(v);
            this.show(n, v);
            if (!isNaN(prev) && prev == v) { n.app.markPaint(n); return; }
            if (n.binding != null) n.binding.set(v);
            // The NEW value is the argument: a zero-argument call throws #1063 on a
            // `function (v:Number)` handler (see UiNode.onChange).
            if (n.onChange != null) n.onChange(v);
            n.app.markPaint(n);
            n.app.invalidate(Dirty.VALUE);
        }

        // Enter / blur: parse what is in the field. Unparseable input reverts.
        private function commitText(n:UiNode):void
        {
            var before:Number = Number(n.extra[MODEL]);
            var raw:String = n.tf == null ? "" : n.tf.text;
            var parsed:Number = Number(raw);
            if (raw == null || raw.length == 0 || isNaN(parsed))
            {
                // REVERT, not 0: substituting zero for garbage would silently overwrite
                // whatever the author's model held.
                this.show(n, before);
                return;
            }
            this.commit(n, parsed);
            if (n.onCommit != null) n.onCommit(Number(n.extra[MODEL]));
        }

        private function textOf(v:Number):String
        {
            return String(v);
        }

        // Write the model into the field, but never when it already agrees: assigning
        // `tf.text` in AIR resets the caret to the end of the inserted run.
        private function show(n:UiNode, v:Number):void
        {
            if (n.tf == null) return;
            var t:String = this.textOf(v);
            if (n.tf.text != t) n.tf.text = t;
        }
    }
}
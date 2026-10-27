// demo/DocsControls.as -- button / textField / checkbox / radio / toggle / slider.
// Every demo here is AUTHOR-OWNED state: the widget reports, the model writes, the
// next render re-describes. That is the kit's whole interaction contract, so the
// docs page would be lying if it hid the callback in the widget.
package demo
{
    import asaot.ui.Node;
    import asaot.ui.button;
    import asaot.ui.numberInput;
    import asaot.ui.rangeSlider;
    import asaot.ui.checkbox;
    import asaot.ui.column;
    import asaot.ui.radio;
    import asaot.ui.row;
    import asaot.ui.slider;
    import asaot.ui.text;
    import asaot.ui.textArea;
    import asaot.ui.textField;
    import asaot.ui.toggle;
    import asaot.ui.style.StyleRefinement;

    public final class DocsControls
    {
        public static function sections(view:DocsView, id:String):Array
        {
            var m:DocsModel = view.model;

            if (id == "button") return [
                new DocSection("Variants are styles", [
                    "There is one button kind. Primary / quiet / danger are three style refinements, not",
                    "three widgets, so a variant never drifts from the base behaviour."
                ], [
                    "button({ label: \"Save\",   style: PRIMARY, onClick: save }),",
                    "button({ label: \"Cancel\", style: QUIET,   onClick: cancel }),",
                    "button({ label: \"Delete\", style: DANGER,  onClick: drop })"
                ], 84, function ():Node
                {
                    return row({ gap: 10, alignItems: "center" }, [
                        button({ key: "btnSave", label: "Save", style: DocsDemo.PRIMARY,
                                 onClick: function ():void { m.put("btn.last", "save"); } }),
                        button({ key: "btnCancel", label: "Cancel", style: DocsDemo.QUIET,
                                 onClick: function ():void { m.put("btn.last", "cancel"); } }),
                        button({ key: "btnDelete", label: "Delete", style: DocsDemo.DANGER,
                                 onClick: function ():void { } })
                    ]);
                }),

                new DocSection("Disabled", [
                    "`disabled` is an Element field, so every factory accepts it and the kit drops the",
                    "hover/press modulation and the handler in one place (see UiNode.inert)."
                ], [
                    "button({ label: \"Publish\", disabled: true }),",
                    "button({ label: \"Draft\", disabled: true, style: PRIMARY })"
                ], 76, function ():Node
                {
                    return row({ gap: 10, alignItems: "center" }, [
                        button({ label: "Publish", disabled: true, style: DocsDemo.QUIET }),
                        button({ label: "Draft", disabled: true, style: DocsDemo.PRIMARY })
                    ]);
                }),

                new DocSection("Label from state", [
                    "A button's label is just a string the render computes -- it is re-pointed every",
                    "frame, so a counter needs no special API."
                ], [
                    "button({ label: \"Clicked \" + model.n + \"x\", onClick: bump })"
                ], 76, function ():Node
                {
                    return row({ gap: 12, alignItems: "center" }, [
                        button({ key: "btnCount", label: "Clicked " + int(m.num("btn.n", 0)) + "x",
                                 style: DocsDemo.QUIET,
                                 onClick: function ():void { m.put("btn.n", int(m.num("btn.n", 0)) + 1); } }),
                        text("last action: " + (m.val("btn.last", "-")), { style: DocsDemo.MONO, ariaName: "" })
                    ]);
                })
            ];

            if (id == "textField") return [
                new DocSection("Placeholder and value", [
                    "The ghost text is its own non-interactive TextField, shown only while the field is",
                    "empty and NOT focused (a focused empty field shows the caret instead)."
                ], [
                    "textField({ key: \"email\", placeholder: \"you@example.com\",",
                    "            style: { size: [220, null] } })"
                ], 84, function ():Node
                {
                    return row({ gap: 10, alignItems: "center" }, [
                        textField({ key: "tfOne", placeholder: "you@example.com",
                            style: StyleRefinement.from({ size: [220, null] }) }),
                        text("type into it", { style: DocsDemo.MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("Masked", [
                    "password:true masks the display and leaves the MODEL string alone, so the value you",
                    "commit is the real one."
                ], [
                    "textField({ password: true, placeholder: \"Password\",",
                    "            value: model.pw, onChange: function (t:String):void { model.pw = t; } })"
                ], 84, function ():Node
                {
                    return row({ gap: 10, alignItems: "center" }, [
                        textField({ key: "tfPw", password: true, placeholder: "Password",
                            value: m.val("tf.pw", "hunter2"),
                            style: StyleRefinement.from({ size: [200, null] }),
                            onCommit: function (t:String):void { m.put("tf.pw", t); } }),
                        text("masked; the model keeps the text", { style: DocsDemo.MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("Commit, not every keystroke", [
                    "onChange fires per keystroke and onCommit on Enter/blur. A page that writes the",
                    "model on every keystroke re-renders the whole page -- fine here, wasteful in a form."
                ], [
                    "textField({ value: \"search\", onCommit: function (t:String):void {",
                    "    model.query = t; model.notify(Dirty.VALUE);",
                    "} })"
                ], 84, function ():Node
                {
                    return row({ gap: 10, alignItems: "center" }, [
                        textField({ key: "tfCommit", placeholder: "press Enter",
                            style: StyleRefinement.from({ size: [200, null] }),
                            onCommit: function (t:String):void { m.put("tf.commit", t); } }),
                        text("committed: '" + m.val("tf.commit", "") + "'", { style: DocsDemo.MONO, ariaName: "" })
                    ]);
                })
            ];

            if (id == "textArea") return [
                new DocSection("Enter inserts a newline", [
                    "A text area is its own KIND, not a flag on the single-line field: the difference is",
                    "Enter -- a single-line field COMMITS on it, here it inserts. So this widget never",
                    "consumes 13; the runtime inserts the line break itself, and only for a key nobody took."
                ], [
                    "textArea({ key: \"notes\", rows: 4, placeholder: \"Notes...\",",
                    "           style: { size: [320, null] },",
                    "           onChange: function (t:String):void { model.notes = t; } })"
                ], 140, function ():Node
                {
                    return column({ gap: 8 }, [
                        textArea({ key: "taNotes", rows: 4, placeholder: "Notes for the reviewer...",
                            value: String(m.val("ta.notes", "")),
                            style: StyleRefinement.from({ size: [340, null] }),
                            onChange: function (t:String):void { m.put("ta.notes", t); } }),
                        text("model length: " + String(m.val("ta.notes", "")).length,
                            { style: DocsDemo.MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("rows sets the height; commit is on blur", [
                    "With no height in the style the box is `rows` REAL line heights of the resolved font",
                    "(measured with the field itself, not a constant), plus padding and border. There is",
                    "no Enter-to-commit here, so onCommit fires when focus leaves the field."
                ], [
                    "textArea({ rows: 2, value: model.bio,",
                    "           onCommit: function (t:String):void { model.bio = t; } })"
                ], 120, function ():Node
                {
                    return column({ gap: 8 }, [
                        textArea({ key: "taBio", rows: 2, value: String(m.val("ta.bio", "two lines tall")),
                            style: StyleRefinement.from({ size: [340, null] }),
                            onCommit: function (t:String):void { m.put("ta.bio", t); } }),
                        text("committed: '" + String(m.val("ta.bio", "") ) + "'",
                            { style: DocsDemo.MONO, ariaName: "" })
                    ]);
                })
            ];

            if (id == "checkbox") return [
                new DocSection("Checked state", [
                    "The checkbox reports the NEW boolean through onChange; the model owns it. A checkbox",
                    "that kept its own state would be the one thing the reconciler cannot re-describe."
                ], [
                    "checkbox({ label: \"Email me\", checked: model.optIn,",
                    "           onChange: function (v:Boolean):void { model.optIn = v; } })"
                ], 84, function ():Node
                {
                    return column({ gap: 8 }, [
                        checkbox({ key: "cbOpt", label: "Email me about releases",
                            checked: m.bool("cb.opt", true),
                            onChange: function (v:Boolean):void { m.put("cb.opt", v); } }),
                        text("model: " + m.bool("cb.opt", true), { style: DocsDemo.MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("Disabled", [
                    "A disabled checkbox keeps its checked state and drops the handler -- the state is",
                    "displayed, not destroyed."
                ], [
                    "checkbox({ label: \"Locked\", checked: true, disabled: true })"
                ], 76, function ():Node
                {
                    return column({ gap: 8 }, [
                        checkbox({ label: "Locked and checked", checked: true, disabled: true }),
                        checkbox({ label: "Locked and empty", checked: false, disabled: true })
                    ]);
                })
            ];

            if (id == "radio") return [
                new DocSection("One of N", [
                    "A radio names its GROUP: two radios with the same `group` are mutually exclusive",
                    "without any shared parent widget, so a group can span columns."
                ], [
                    "radio(\"Daily\",  { group: \"freq\", value: \"d\", selected: model.freq == \"d\",",
                    "                  onChange: pick }),",
                    "radio(\"Weekly\", { group: \"freq\", value: \"w\", ... })"
                ], 104, function ():Node
                {
                    var cur:String = m.val("r.freq", "d");
                    return column({ gap: 6 }, [
                        radioAt(m, "Daily", "d", cur),
                        radioAt(m, "Weekly", "w", cur),
                        radioAt(m, "Never", "n", cur)
                    ]);
                })
            ];

            if (id == "toggle") return [
                new DocSection("A switch", [
                    "The kind is `switch`; the factory is toggle(), because `switch` is a reserved word.",
                    "Same boolean contract as the checkbox, with a sliding knob instead of a tick."
                ], [
                    "toggle(\"Sync now\", { checked: model.sync,",
                    "       onChange: function (v:Boolean):void { model.sync = v; } })"
                ], 84, function ():Node
                {
                    return column({ gap: 8 }, [
                        toggle("Sync automatically", { key: "tgSync", checked: m.bool("tg.sync", true),
                            onChange: function (v:Boolean):void { m.put("tg.sync", v); } }),
                        toggle("Send diagnostics", { key: "tgDiag", checked: m.bool("tg.diag", false),
                            onChange: function (v:Boolean):void { m.put("tg.diag", v); } })
                    ]);
                })
            ];

            if (id == "slider") return [
                new DocSection("A value along a track", [
                    "The value is a Number in the model; the widget reports a new one on drag. The label",
                    "is the slider's own first argument, not a separate text node."
                ], [
                    "slider(\"Volume\", { value: model.vol, onChange: function (v:Number):void {",
                    "    model.vol = v; model.notify(Dirty.VALUE);",
                    "} })"
                ], 104, function ():Node
                {
                    var v:Number = m.num("sl.vol", 0.4);
                    return column({ gap: 10 }, [
                        slider("Volume " + int(v * 100) + "%", { key: "slVol", value: v,
                            onChange: function (n:Number):void { m.put("sl.vol", n); } }),
                        slider("Zoom " + int(m.num("sl.zoom", 1.0) * 100) + "%", { key: "slZoom",
                            value: m.num("sl.zoom", 1.0),
                            onChange: function (n:Number):void { m.put("sl.zoom", n); } })
                    ]);
                })
            ];

            if (id == "numberInput") return [
                new DocSection("A number, with steppers", [
                    "The right 32pt of the box is the STEPPER strip (upper half adds, lower half",
                    "subtracts); everything to its left is a real textField, so typing, selection and",
                    "the caret behave exactly like the single-line field on the previous page.",
                    "step is what the steppers AND the arrow keys move by, and every write is CLAMPED",
                    "into [min, max] before any callback sees it."
                ], [
                    "numberInput(\"Qty\", { key: \"qty\", value: 4, min: 0, max: 99, step: 2,",
                    "                     onChange: function (v:Number):void { model.qty = v; },",
                    "                     onCommit: function (v:Number):void { save(v); } })"
                ], 96, function ():Node
                {
                    return row({ gap: 12, alignItems: "center" }, [
                        numberInput("Qty", { key: "numQty", value: m.num("num.qty", 4),
                            min: 0, max: 99, step: 2,
                            style: StyleRefinement.from({ size: [180, 32] }),
                            onChange: function (v:Number):void { m.put("num.qty", v); },
                            onCommit: function (v:Number):void { m.put("num.commit", v); } }),
                        text("model " + m.num("num.qty", 4) + " - committed "
                                + m.val("num.commit", "-"),
                            { style: DocsDemo.MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("Typing commits; junk reverts", [
                    "onChange fires on every accepted change, onCommit on Enter or on blur. Text that",
                    "does not parse is REVERTED to the model -- never NaN, never 0 -- because a number",
                    "field that invented a value would silently overwrite what the author stored.",
                    "decimals rounds every write, including the value the author passed in."
                ], [
                    "numberInput(\"Price\", { value: 12.5, min: 0, max: 1000, step: 0.5, decimals: 2,",
                    "                     onChange: function (v:Number):void { model.price = v; } })"
                ], 96, function ():Node
                {
                    return row({ gap: 12, alignItems: "center" }, [
                        numberInput("Price", { key: "numPrice", value: m.num("num.price", 12.5),
                            min: 0, max: 1000, step: 0.5, decimals: 2,
                            style: StyleRefinement.from({ size: [180, 32] }),
                            onChange: function (v:Number):void { m.put("num.price", v); } }),
                        text("type letters, then click away: the field comes back",
                            { style: DocsDemo.LABEL, ariaName: "" })
                    ]);
                })
            ];

            if (id == "rangeSlider") return [
                new DocSection("Two thumbs, one track", [
                    "A range is TWO numbers, so there is no Binding: the contract is onRange(lo, hi) and",
                    "each one is a 0..1 position on the track. A thumb cannot be dragged past its",
                    "partner -- the pair is clamped against itself, so lo never exceeds hi -- and the",
                    "widget reports both values on every move, not a delta."
                ], [
                    "rangeSlider(\"Price\", { value: model.lo, value2: model.hi, step: 0.05,",
                    "                         onRange: function (lo:Number, hi:Number):void {",
                    "                             model.lo = lo; model.hi = hi;",
                    "                         } })"
                ], 96, function ():Node
                {
                    var lo:Number = m.num("rng.lo", 0.2);
                    var hi:Number = m.num("rng.hi", 0.75);
                    return row({ gap: 12, alignItems: "center" }, [
                        rangeSlider("Price", { key: "rngDemo", value: lo, value2: hi, step: 0.05,
                            style: StyleRefinement.from({ size: [220, 44] }),
                            onRange: function (a:Number, b:Number):void
                            {
                                m.put("rng.lo", a); m.put("rng.hi", b);
                            } }),
                        text(int(lo * 100) + " - " + int(hi * 100),
                            { style: DocsDemo.MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("Normalised once, in the factory", [
                    "value and value2 are clamped into 0..1 and SWAPPED when they arrive backwards, at",
                    "construction time. Doing that in the widget instead would leave the first painted",
                    "frame -- the one before any interaction -- showing an inverted band.",
                    "The arrow keys move the thumb nearest the focus, step at a time."
                ], [
                    "// value: 0.9, value2: 0.1  renders as 0.1 .. 0.9, not as a broken track",
                    "rangeSlider(\"Reversed\", { value: 0.9, value2: 0.1 })"
                ], 96, function ():Node
                {
                    return row({ gap: 12, alignItems: "center" }, [
                        rangeSlider("Reversed", { key: "rngSwap", value: 0.9, value2: 0.1,
                            style: StyleRefinement.from({ size: [220, 44] }) }),
                        text("0.1 .. 0.9", { style: DocsDemo.MONO, ariaName: "" })
                    ]);
                })
            ];

            return null;
        }

        // A radio bound to the model through a parameter, so each closure owns its
        // own value (a loop-built closure would all see the last one).
        private static function radioAt(m:DocsModel, label:String, value:String, cur:String):Node
        {
            return radio(label, { key: "r:" + value, group: "freq", value: value,
                selected: cur == value,
                onChange: function (sel:Boolean):void { if (sel) m.put("r.freq", value); } });
        }
    }
}

// demo/DocsControls.as -- button / textField / checkbox / radio / toggle / slider.
// Every demo here is AUTHOR-OWNED state: the widget reports, the model writes, the
// next render re-describes. That is the kit's whole interaction contract, so the
// docs page would be lying if it hid the callback in the widget.
package demo
{
    import asaot.ui.Node;
    import asaot.ui.button;
    import asaot.ui.card;
    import asaot.ui.numberInput;
    import asaot.ui.rangeSlider;
    import asaot.ui.checkbox;
    import asaot.ui.column;
    import asaot.ui.divider;
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
                }),

                new DocSection("A dialog footer is two buttons and one alignment", [
                    "The three buttons below are the same kind; the row supplies the position. That is",
                    "the whole reason a footer needs no widget: `justifyContent: flex-end` on a row of",
                    "declared widths lines up right edges without measuring anything."
                ], [
                    "row({ gap: 8, justifyContent: \"flex-end\", size: [420, null] }, [",
                    "    button({ label: \"Cancel\", style: QUIET }),",
                    "    button({ label: \"Save\",   style: PRIMARY })",
                    "])"
                ], 84, function ():Node
                {
                    return row({ gap: 8, justifyContent: "flex-end",
                        style: StyleRefinement.from({ size: [420, null], alignItems: "center" }) }, [
                        button({ key: "btnFootCancel", label: "Cancel", style: DocsDemo.QUIET,
                                 onClick: function ():void { m.put("btn.last", "cancel"); } }),
                        button({ key: "btnFootSave", label: "Save", style: DocsDemo.PRIMARY,
                                 onClick: function ():void { m.put("btn.last", "save"); } })
                    ]);
                }),

                new DocSection("Enter and Space press the focused control", [
                    "Tab to a button and press Enter or Space: UiApp runs the default activation path,",
                    "which calls the click handler unless the control names an `action` (then the",
                    "app's action registry gets it). One exception is deliberate -- when the focused",
                    "thing is an editable field, Enter is its commit and Space is a character.",
                    "`tabEnabled: false` keeps a button out of the tab walk."
                ], [
                    "button({ label: \"Save\", action: \"doc.save\" })      // registry",
                    "button({ label: \"Save\", onClick: save })          // plain handler",
                    "button({ label: \"Skip\", tabEnabled: false })      // not in the walk"
                ], 84, function ():Node
                {
                    return row({ gap: 10, alignItems: "center" }, [
                        button({ key: "btnTabA", label: "Tab me", style: DocsDemo.QUIET,
                                 tabEnabled: true,
                                 onClick: function ():void { m.put("btn.last", "tab-me"); } }),
                        button({ key: "btnTabB", label: "Skipped", style: DocsDemo.QUIET,
                                 tabEnabled: false,
                                 onClick: function ():void { m.put("btn.last", "skipped"); } })
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
                }),

                new DocSection("The box is yours; the text is centred in it", [
                    "A field measures nothing but its own text: give it a height and the run is",
                    "vertically centred in it, give it a width and the caret walks inside it. Three",
                    "sizes of the same placeholder, which is how a dense toolbar and a form differ."
                ], [
                    "textField({ style: { size: [160, 28] } }),",
                    "textField({ style: { size: [160, 32] } }),",
                    "textField({ style: { size: [160, 40] } })"
                ], 96, function ():Node
                {
                    return row({ gap: 10, alignItems: "center" }, [
                        textField({ key: "tfS28", placeholder: "28pt",
                            style: StyleRefinement.from({ size: [150, 28] }) }),
                        textField({ key: "tfS32", placeholder: "32pt",
                            style: StyleRefinement.from({ size: [150, 32] }) }),
                        textField({ key: "tfS40", placeholder: "40pt",
                            style: StyleRefinement.from({ size: [150, 40] }) })
                    ]);
                }),

                new DocSection("Disabled is the container's word", [
                    "A locked field still shows its value and still keeps the text -- what it loses is",
                    "the press, the caret and the focus. The second field below is the same call inside",
                    "a disabled column, which is how a read-only form section is usually built."
                ], [
                    "column({ gap: 8, disabled: true }, [",
                    "    textField({ value: \"ada@example.com\" }),",
                    "    textField({ value: \"locked by policy\" })",
                    "])"
                ], 96, function ():Node
                {
                    return column({ gap: 8, disabled: true }, [
                        textField({ key: "tfDis1", value: "ada@example.com",
                            style: StyleRefinement.from({ size: [220, null] }) }),
                        textField({ key: "tfDis2", value: "locked by policy",
                            style: StyleRefinement.from({ size: [220, null] }) })
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
                }),

                new DocSection("Longer than the box, so it scrolls", [
                    "rows:3 is the HEIGHT of the box, not a limit on the text. The value below is",
                    "eight lines; the field is three line-heights tall and scrolls, and the caret",
                    "walking past the bottom scrolls the view with it."
                ], [
                    "textArea({ rows: 3, value: longText })   // longText is 8 lines"
                ], 132, function ():Node
                {
                    var s:String = "line one\nline two\nline three\nline four\nline five"
                        + "\nline six\nline seven\nline eight";
                    return column({ gap: 8 }, [
                        textArea({ key: "taLong", rows: 3, value: s,
                            style: StyleRefinement.from({ size: [340, null] }) }),
                        text("8 lines in a 3-row box", { style: DocsDemo.MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("Only the Enter key tells them apart", [
                    "Same box, same border, same text: the two below are a textArea(rows:1) and a",
                    "textField. Press Enter in each -- the left one grows a line, the right one",
                    "commits and stays one line. That difference is the entire reason they are two",
                    "kinds instead of one with a flag."
                ], [
                    "textArea({ rows: 1 })   // Enter inserts",
                    "textField()             // Enter commits"
                ], 108, function ():Node
                {
                    return row({ gap: 16, alignItems: "flex-start" }, [
                        column({ gap: 6 }, [
                            text("textArea", { style: DocsDemo.LABEL, ariaName: "" }),
                            textArea({ key: "taOne", rows: 1, placeholder: "Enter adds a line",
                                style: StyleRefinement.from({ size: [180, null] }) })
                        ]),
                        column({ gap: 6 }, [
                            text("textField", { style: DocsDemo.LABEL, ariaName: "" }),
                            textField({ key: "tfOneLine", placeholder: "Enter commits",
                                style: StyleRefinement.from({ size: [180, null] }) })
                        ])
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
                }),

                new DocSection("Three independent booleans", [
                    "No group, no parent: each checkbox owns exactly one boolean in the model, and the",
                    "summary line is an expression over the three. This is the shape a settings block",
                    "uses -- and the shape a radio group deliberately does not."
                ], [
                    "checkbox({ label: \"Email\", checked: model.email, onChange: set }),",
                    "checkbox({ label: \"Push\",  checked: model.push,  onChange: set })"
                ], 120, function ():Node
                {
                    var a:Boolean = m.bool("cb.a", true);
                    var b:Boolean = m.bool("cb.b", false);
                    var c:Boolean = m.bool("cb.c", true);
                    var n:int = (a ? 1 : 0) + (b ? 1 : 0) + (c ? 1 : 0);
                    return column({ gap: 8 }, [
                        checkbox({ key: "cbA", label: "Email me", checked: a,
                            onChange: function (v:Boolean):void { m.put("cb.a", v); } }),
                        checkbox({ key: "cbB", label: "Push notifications", checked: b,
                            onChange: function (v:Boolean):void { m.put("cb.b", v); } }),
                        checkbox({ key: "cbC", label: "Weekly digest", checked: c,
                            onChange: function (v:Boolean):void { m.put("cb.c", v); } }),
                        text(n + " of 3 on", { style: DocsDemo.MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("The label is part of the hit target", [
                    "A checkbox is one node: the 16pt box AND the text beside it. Click the word, not",
                    "just the square. The label also wraps nowhere -- a checkbox is a single-line",
                    "control, so a long label needs a column and a separate text() if it must break."
                ], [
                    "checkbox({ label: \"Send me every release, including the ones nobody reads\" })"
                ], 96, function ():Node
                {
                    return column({ gap: 8 }, [
                        checkbox({ key: "cbLong", label: "Send me every release note",
                            checked: m.bool("cb.long", true),
                            onChange: function (v:Boolean):void { m.put("cb.long", v); } }),
                        text("click the words: the whole row answers",
                            { style: DocsDemo.LABEL, ariaName: "" })
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
                }),

                new DocSection("A group is a string, so it can span containers", [
                    "The two columns below are different subtrees; the radios still exclude each other",
                    "because the group is the string \"side\", not the parent. A widget-tree group would",
                    "have forced both columns into one node just to share a selection."
                ], [
                    "radio(\"Left\",  { group: \"side\", value: \"l\" }),",
                    "radio(\"Right\", { group: \"side\", value: \"r\" })   // same group, other column"
                ], 96, function ():Node
                {
                    var cur:String = m.val("r.side", "l");
                    return row({ gap: 28 }, [
                        column({ gap: 6 }, [
                            radio("Left", { key: "rSideL", group: "side", value: "l",
                                selected: cur == "l",
                                onChange: function (sel:Boolean):void { if (sel) m.put("r.side", "l"); } }),
                            radio("Right", { key: "rSideR", group: "side", value: "r",
                                selected: cur == "r",
                                onChange: function (sel:Boolean):void { if (sel) m.put("r.side", "r"); } })
                        ]),
                        column({ gap: 6 }, [
                            radio("Auto", { key: "rSideA", group: "side", value: "a",
                                selected: cur == "a",
                                onChange: function (sel:Boolean):void { if (sel) m.put("r.side", "a"); } }),
                            text("model: " + cur, { style: DocsDemo.MONO, ariaName: "" })
                        ])
                    ]);
                }),

                new DocSection("A radio with no group excludes nothing", [
                    "Leave `group` out and the radio is just a circle that reports its own boolean --",
                    "both below can be selected at once. That is not a bug to work around: it is how",
                    "the widget stays honest when the author has not said what the set is."
                ], [
                    "radio(\"A\"), radio(\"B\")   // no group: two independent checkboxes"
                ], 96, function ():Node
                {
                    return column({ gap: 6 }, [
                        radio("Independent A", { key: "rFreeA", selected: m.bool("r.a", true),
                            onChange: function (v:Boolean):void { m.put("r.a", v); } }),
                        radio("Independent B", { key: "rFreeB", selected: m.bool("r.b", true),
                            onChange: function (v:Boolean):void { m.put("r.b", v); } })
                    ]);
                }),

                new DocSection("Disabled keeps the choice visible", [
                    "A locked option still shows WHICH one is chosen; it only refuses the click. That is",
                    "the difference between a disabled radio and an omitted one."
                ], [
                    "radio(\"Monthly\", { group: \"plan\", selected: true, disabled: true })"
                ], 96, function ():Node
                {
                    return column({ gap: 6 }, [
                        radio("Monthly (locked)", { key: "rDisA", group: "plan2", value: "m",
                            selected: true, disabled: true }),
                        radio("Yearly (locked)", { key: "rDisB", group: "plan2", value: "y",
                            selected: false, disabled: true })
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
                }),

                new DocSection("The same contract as the checkbox", [
                    "A switch and a checkbox take the same `checked` and report the same boolean -- so",
                    "one model field can drive both. The kit keeps two kinds because the two are read",
                    "differently (\"takes effect now\" vs \"part of what I am submitting\"), not because",
                    "the data differs."
                ], [
                    "toggle(\"Power\", { checked: model.on, onChange: set }),",
                    "checkbox({ label: \"Power\", checked: model.on, onChange: set })"
                ], 84, function ():Node
                {
                    var on:Boolean = m.bool("tg.same", true);
                    return row({ gap: 24, alignItems: "center" }, [
                        toggle("Power", { key: "tgSame", checked: on,
                            onChange: function (v:Boolean):void { m.put("tg.same", v); } }),
                        checkbox({ key: "cbSame", label: "Power", checked: on,
                            onChange: function (v:Boolean):void { m.put("tg.same", v); } })
                    ]);
                }),

                new DocSection("A settings block", [
                    "Three switches, two hairlines, one card. The rows are not a widget: a card whose",
                    "children alternate toggle and divider. Everything left/right in it is the card's",
                    "padding, so the block moves as one if the padding changes."
                ], [
                    "card({ title: \"Sync\" }, [ toggle(...), divider(), toggle(...) ])"
                ], 168, function ():Node
                {
                    return card({ title: "Sync", style: StyleRefinement.from({ size: [280, null] }) }, [
                        toggle("Photos", { key: "tgPh", checked: m.bool("tg.ph", true),
                            onChange: function (v:Boolean):void { m.put("tg.ph", v); } }),
                        divider(),
                        toggle("Documents", { key: "tgDoc", checked: m.bool("tg.doc", false),
                            onChange: function (v:Boolean):void { m.put("tg.doc", v); } }),
                        divider(),
                        toggle("Mail", { key: "tgMail", checked: m.bool("tg.mail", true),
                            onChange: function (v:Boolean):void { m.put("tg.mail", v); } })
                    ]);
                }),

                new DocSection("Disabled keeps the position", [
                    "A locked switch still shows whether it is on. The knob does not slide and the row",
                    "does not click -- but the state the user needs to read is still there."
                ], [
                    "toggle(\"On but locked\",  { checked: true,  disabled: true }),",
                    "toggle(\"Off but locked\", { checked: false, disabled: true })"
                ], 108, function ():Node
                {
                    return column({ gap: 8 }, [
                        toggle("On but locked", { key: "tgLockOn", checked: true, disabled: true }),
                        toggle("Off but locked", { key: "tgLockOff", checked: false, disabled: true })
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
                }),

                new DocSection("The ends are values too", [
                    "0 and 1 are positions, not absences: a slider at its left end still draws a knob",
                    "and still reports 0. The two below are pinned to the ends so the track, the fill",
                    "and the knob can be read without dragging anything."
                ], [
                    "slider(\"Muted\", { value: 0 }),",
                    "slider(\"Full\",  { value: 1 })"
                ], 108, function ():Node
                {
                    return column({ gap: 10 }, [
                        slider("Muted 0%", { key: "slZero", value: 0 }),
                        slider("Full 100%", { key: "slOne", value: 1 })
                    ]);
                }),

                new DocSection("A labelled form row", [
                    "The widget's first argument is a LABEL it draws itself, in the same run as the",
                    "track -- there is no separate text node to align. When the design wants the name",
                    "above the track instead, pass an empty label and put the text in a column: the",
                    "widget then reserves no label line at all."
                ], [
                    "column({ gap: 4 }, [",
                    "    text(\"Volume\"),",
                    "    slider(\"\", { value: model.vol })",
                    "])"
                ], 132, function ():Node
                {
                    return column({ gap: 4 }, [
                        text("Playback volume", { style: DocsDemo.LABEL_B, ariaName: "" }),
                        slider("", { key: "slBare", value: m.num("sl.bare", 0.6),
                            style: StyleRefinement.from({ size: [240, 40] }),
                            onChange: function (n:Number):void { m.put("sl.bare", n); } })
                    ]);
                }),

                new DocSection("Disabled keeps its position", [
                    "A disabled slider is drawn at the disabled alpha and its track refuses the press;",
                    "the value it was given is what you see. This is how a slider shows a setting that",
                    "is controlled elsewhere."
                ], [
                    "slider(\"Volume 40%\", { value: 0.4, disabled: true })"
                ], 84, function ():Node
                {
                    return slider("Volume 40% (locked)", { key: "slLock", value: 0.4, disabled: true });
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
                }),

                new DocSection("The bounds are the widget's, not the handler's", [
                    "The two fields below sit ON min and max. The steppers, the arrow keys and a typed",
                    "commit all stop there before any callback runs, so a handler never has to clamp:",
                    "what arrives is already in range."
                ], [
                    "numberInput(\"At min\", { value: 0,  min: 0, max: 10 }),",
                    "numberInput(\"At max\", { value: 10, min: 0, max: 10 })"
                ], 96, function ():Node
                {
                    return row({ gap: 12, alignItems: "center" }, [
                        numberInput("At min", { key: "numMin", value: 0, min: 0, max: 10,
                            style: StyleRefinement.from({ size: [170, 32] }) }),
                        numberInput("At max", { key: "numMax", value: 10, min: 0, max: 10,
                            style: StyleRefinement.from({ size: [170, 32] }) })
                    ]);
                }),

                new DocSection("decimals decides how many digits you see", [
                    "The same 12.5 in three fields: decimals 0 rounds to 13, decimals 1 keeps 12.5 and",
                    "decimals 2 pads to 12.50. The rounding happens on every write, including the value",
                    "the author passed in, so the model and the box never disagree."
                ], [
                    "numberInput(\"Value\",   { value: 12.5, decimals: 0 }),   // 13",
                    "numberInput(\"Value\",   { value: 12.5, decimals: 1 }),   // 12.5",
                    "numberInput(\"Value\",   { value: 12.5, decimals: 2 })    // 12.50"
                ], 96, function ():Node
                {
                    return row({ gap: 10, alignItems: "center" }, [
                        numberInput("0 dp", { key: "numD0", value: 12.5, decimals: 0,
                            style: StyleRefinement.from({ size: [140, 32] }) }),
                        numberInput("1 dp", { key: "numD1", value: 12.5, decimals: 1,
                            style: StyleRefinement.from({ size: [140, 32] }) }),
                        numberInput("2 dp", { key: "numD2", value: 12.5, decimals: 2,
                            style: StyleRefinement.from({ size: [140, 32] }) })
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
                }),

                new DocSection("The band can be everything or a point", [
                    "Two legal extremes: 0..1 fills the whole track, and 0.4..0.4 collapses to a",
                    "single position with the two thumbs on top of each other. Neither is a special",
                    "case in the code -- the band is drawn between the two positions it was given."
                ], [
                    "rangeSlider(\"All\",   { value: 0,   value2: 1 })",
                    "rangeSlider(\"Point\", { value: 0.4, value2: 0.4 })"
                ], 132, function ():Node
                {
                    return column({ gap: 8 }, [
                        rangeSlider("All", { key: "rngAll", value: 0, value2: 1, step: 0.05,
                            style: StyleRefinement.from({ size: [220, 44] }) }),
                        rangeSlider("Point", { key: "rngPoint", value: 0.4, value2: 0.4, step: 0.05,
                            style: StyleRefinement.from({ size: [220, 44] }) })
                    ]);
                }),

                new DocSection("step is the keyboard increment", [
                    "`step` does not quantise the drag (the thumb follows the pointer 1:1); it is how",
                    "far an arrow key moves the focused thumb. It must be positive -- the factory",
                    "throws otherwise, because a zero step would make every arrow key a silent no-op.",
                    "Left right arrow keys, then compare the numbers below with the labels."
                ], [
                    "rangeSlider(\"Coarse\", { step: 0.25, onRange: pair }),   // quarters",
                    "rangeSlider(\"Fine\",   { step: 0.01, onRange: pair })    // percents"
                ], 132, function ():Node
                {
                    var lo:Number = m.num("rng.coarse.lo", 0.25);
                    var hi:Number = m.num("rng.coarse.hi", 0.5);
                    return column({ gap: 8 }, [
                        rangeSlider("Coarse step 0.25", { key: "rngCoarse", value: lo, value2: hi,
                            step: 0.25,
                            style: StyleRefinement.from({ size: [220, 44] }),
                            onRange: function (a:Number, b:Number):void
                            {
                                m.put("rng.coarse.lo", a); m.put("rng.coarse.hi", b);
                            } }),
                        text(lo.toFixed(2) + " .. " + hi.toFixed(2),
                            { style: DocsDemo.MONO, ariaName: "" })
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

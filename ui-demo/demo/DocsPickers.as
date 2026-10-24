// demo/DocsPickers.as -- select / combobox / datePicker / pagination.
//
// Every one of these is a TRIGGER plus a panel, and the panel is a CHILD of the
// trigger node. That is why a picker lifts itself into the stage container while it
// is open (UiNode.lifted): a dropdown inside a scrolling page would otherwise be
// clipped by the scroll view and covered by the next sibling.
package demo
{
    import asaot.ui.Node;
    import asaot.ui.column;
    import asaot.ui.combobox;
    import asaot.ui.datePicker;
    import asaot.ui.pagination;
    import asaot.ui.row;
    import asaot.ui.select;
    import asaot.ui.text;
    import asaot.ui.style.StyleRefinement;

    public final class DocsPickers
    {
        private static const CITIES:Array = ["Amsterdam", "Berlin", "Cairo", "Delhi", "Lisbon"];
        private static const PLANS:Array = ["Free", "Team", "Business"];
        // Force this class's lazy static initializer. compiler-gaps G21: a static
        // read emitted INSIDE a closure omits the class's _cinit() guard, so a field
        // whose only readers are demo closures is still NULL when the closure first
        // runs (measured: a static const Array came back null -> #1009). Reading one
        // field from a plain method runs the guard, which initialises the WHOLE class
        // in one go. DocsMain calls this before the first render. Remove when G21 is
        // fixed.
        public static function warmUp():void
        {
            var probe:Object = PLANS;
        }

        public static function sections(view:DocsView, id:String):Array
        {
            var m:DocsModel = view.model;

            if (id == "select") return [
                new DocSection("Options behind a trigger", [
                    "`value` is the SELECTED OPTION'S VALUE, not its index, and onSelect reports the",
                    "row index. Both facts matter: the label lives in the option, the key in the model."
                ], [
                    "select({ key: \"plan\", width: 200, value: model.plan,",
                    "         open: model.planOpen, placeholder: \"Choose a plan\",",
                    "         options: [\"Free\", \"Team\", \"Business\"],",
                    "         onSelect: function (i:int):void { model.plan = options[i]; },",
                    "         onOpenChange: function (o:Boolean):void { model.planOpen = o; } })"
                ], 96, function ():Node
                {
                    return row({ gap: 12, alignItems: "center" }, [
                        select({ key: "demoSel", width: 200, value: m.val("sel.value", ""),
                                 open: m.bool("sel.open", false), placeholder: "Choose a plan",
                                 options: PLANS,
                                 onSelect: function (i:int):void { m.put("sel.value", String(PLANS[i])); },
                                 onOpenChange: function (o:Boolean):void { m.put("sel.open", o); } }),
                        text("value: '" + m.val("sel.value", "") + "'",
                             { style: DocsDemo.MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("Open is author-owned too", [
                    "The widget does not close itself behind your back: every open/close is reported",
                    "through onOpenChange and drawn from the `open` you pass back in."
                ], [
                    "// A click on the trigger reports onOpenChange(true);",
                    "// only the model closes it -- so a select can be closed by a",
                    "// toolbar button, an Escape handler or a page change."
                ], 76, function ():Node
                {
                    return row({ gap: 12, alignItems: "center" }, [
                        text("open: " + m.bool("sel.open", false), { style: DocsDemo.MONO, ariaName: "" }),
                        text("try the picker above -- the boolean is the model's",
                             { style: DocsDemo.LABEL, ariaName: "" })
                    ]);
                })
            ];

            if (id == "combobox") return [
                new DocSection("Type to filter", [
                    "The factory renders whatever options it is given and does NOT filter: onQuery hands",
                    "you the text, and the match rule (case, accents, word-start) is yours to choose."
                ], [
                    "combobox({ key: \"city\", width: 220, value: model.q, open: model.cbOpen,",
                    "           options: filter(model.q), placeholder: \"Type a city\",",
                    "           onQuery: function (t:String):void { model.q = t; model.cbOpen = true; },",
                    "           onSelect: function (i:int):void { model.city = cities[i]; } })"
                ], 96, function ():Node
                {
                    var q:String = m.val("cb.q", "");
                    var shown:Array = match(CITIES, q);
                    return row({ gap: 12, alignItems: "center" }, [
                        combobox({ key: "demoCb", width: 220, value: q,
                                   open: m.bool("cb.open", false), placeholder: "Type a city",
                                   options: shown,
                                   onQuery: function (t:String):void { m.put("cb.q", t); m.put("cb.open", true); },
                                   onSelect: function (i:int):void { m.put("cb.city", String(shown[i])); m.put("cb.open", false); },
                                   onOpenChange: function (o:Boolean):void { m.put("cb.open", o); } }),
                        text("city: '" + m.val("cb.city", "-") + "'", { style: DocsDemo.MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("The trigger is a real textField", [
                    "Typing goes through the same text field as everywhere else -- selection, caret and",
                    "the CHANGE event all come from the runtime, not from key sniffing in the widget."
                ], [
                    "// the trigger is textField({ onChange: onQuery }) -- nothing else"
                ], 76, function ():Node
                {
                    return text("A combobox costs one textField plus one box per option.",
                        { style: DocsDemo.LABEL, ariaName: "" });
                })
            ];

            if (id == "datePicker") return [
                new DocSection("A calendar panel", [
                    "`value` is an ISO string (YYYY-MM-DD), and `year`/`month` say which month the",
                    "panel shows -- so paging months is a model write, not widget state."
                ], [
                    "datePicker({ key: \"due\", width: 190, value: model.due,",
                    "             open: model.dpOpen, year: model.y, month: model.m,",
                    "             placeholder: \"Pick a date\",",
                    "             onSelect: function (iso:String):void { model.due = iso; },",
                    "             onMonthChange: function (y:int, mo:int):void { ... } })"
                ], 96, function ():Node
                {
                    return row({ gap: 12, alignItems: "center" }, [
                        datePicker({ key: "demoDp", width: 190, value: m.val("dp.value", ""),
                                     open: m.bool("dp.open", false),
                                     year: int(m.num("dp.y", 2026)), month: int(m.num("dp.m", 10)),
                                     placeholder: "Pick a date",
                                     onSelect: function (iso:String):void { m.put("dp.value", iso); },
                                     onMonthChange: function (y:int, mo:int):void
                                     {
                                         m.put("dp.y", y); m.put("dp.m", mo);
                                     },
                                     onOpenChange: function (o:Boolean):void { m.put("dp.open", o); } }),
                        text("value: '" + m.val("dp.value", "") + "'",
                             { style: DocsDemo.MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("Always six weeks", [
                    "The grid is six week rows even in a five-week month, so paging to March does not",
                    "make the panel (and everything under it) jump by one row."
                ], [
                    "// six rows by construction -- see datePicker.as"
                ], 76, function ():Node
                {
                    return text("Fixed height, constant anchoring, no layout jump when paging.",
                        { style: DocsDemo.LABEL, ariaName: "" });
                })
            ];

            if (id == "pagination") return [
                new DocSection("Page numbers with ellipses", [
                    "The visible window is computed by the same function that maps a click back to a",
                    "page, so a rendered slot and a clicked slot cannot disagree."
                ], [
                    "pagination(model.page, 20, {",
                    "    key: \"pg\", windowSize: 5,",
                    "    onSelect: function (p:int):void { model.page = p; }",
                    "})"
                ], 84, function ():Node
                {
                    return row({ gap: 12, alignItems: "center" }, [
                        pagination(int(m.num("pg.page", 3)), 20, { key: "pg",
                            windowSize: 5,
                            onSelect: function (p:int):void { m.put("pg.page", p); } }),
                        text("page " + int(m.num("pg.page", 3)) + " of 20",
                             { style: DocsDemo.MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("The chips are chips", [
                    "Each number is a chip with role \"button\"; the current page is the `info` tone.",
                    "So a page change is a re-resolve, not a repaint hook."
                ], [
                    "chip(String(p), { role: \"button\", tone: (p == current ? \"info\" : \"neutral\") })"
                ], 76, function ():Node
                {
                    return text("Click a number above: the tone moves with the model.",
                        { style: DocsDemo.LABEL, ariaName: "" });
                })
            ];

            return null;
        }

        // The match rule the docs chose to show: case-insensitive prefix on any word.
        private static function match(all:Array, q:String):Array
        {
            if (q == null || q == "") return all;
            // Case-SENSITIVE prefix: the toolkit ships no toLowerCase (the AOT's
            // String surface is the ES3 subset this project implements), and the docs
            // page should not pretend otherwise. The rule is the author's anyway.
            var out:Array = [];
            for (var i:int = 0; i < all.length; i++)
            {
                var s:String = String(all[i]);
                if (s.indexOf(q) == 0) out.push(s);
            }
            return out;
        }
    }
}

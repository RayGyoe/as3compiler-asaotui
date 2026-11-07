// demo/DocsOverlay.as -- dialog / drawer / popover / menu / toast / toastHost.
//
// These six pages are the only ones whose demo does NOT live in render()'s tree:
// each trigger is an ordinary button that flips a model flag, and DocsView's
// renderOverlay() describes the surface itself. That split is the point of the
// second retained tree, and the tour asserts the panel is centred in the WINDOW
// rather than in the page.
package demo
{
    import asaot.ui.Node;
    import asaot.ui.box;
    import asaot.ui.button;
    import asaot.ui.chip;
    import asaot.ui.divider;
    import asaot.ui.scrollView;
    import asaot.ui.slider;
    import asaot.ui.column;
    import asaot.ui.row;
    import asaot.ui.text;
    import asaot.ui.style.StyleRefinement;

    public final class DocsOverlay
    {
        public static function sections(view:DocsView, id:String):Array
        {
            var m:DocsModel = view.model;

            if (id == "dialog") return [
                new DocSection("A scrim plus a centred panel", [
                    "The dialog is described in renderOverlay(), so it is laid out against the WINDOW: a page that scrolls cannot drag its dialog along with it."
                ], [
                    "// render()",
                    "button({ key: \"demoDlgBtn\", label: \"Delete files\",",
                    "         onClick: function ():void { model.dlgOpen = true; } })",
                    "// renderOverlay()",
                    "dialog({ key: \"demoDlg\", open: model.dlgOpen, width: 320,",
                    "         title: \"Delete 3 files?\", footer: [ cancel, confirm ],",
                    "         onClose: function ():void { model.dlgOpen = false; } },",
                    "       [ text(\"This cannot be undone.\") ])"
                ], 96, function ():Node
                {
                    return row({ gap: 12, alignItems: "center" }, [
                        button({ key: "demoDlgBtn", label: "Open dialog", style: DocsDemo.PRIMARY,
                                 onClick: function ():void { m.put("dlg.open", true); } }),
                        text("open: " + m.bool("dlg.open", false), { style: DocsDemo.MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("Closing is a model write", [
                    "Escape, a scrim click and the footer's Cancel all funnel into onClose -- the author writes `false` once, and the next render stops describing the dialog."
                ], [
                    "onClose: function ():void { model.dlgOpen = false; }"
                ], 76, function ():Node
                {
                    return text("Escape closes it too: the widget handles the key, the model owns the flag.",
                        { style: DocsDemo.LABEL, ariaName: "" });
                }),

                // closeOnScrim is a POLICY, not a detail: the default (close on a scrim
                // press) is right for a confirmation and wrong for a form.
                new DocSection("closeOnScrim: false, for a dialog with unsaved input", [
                    "By default a scrim press closes the dialog. That is what a confirmation wants and exactly what a FORM does not: one stray click outside and the typed text is gone.",
                    "`closeOnScrim: false` makes Escape and the panel's own buttons the only exits -- the scrim still swallows the press, because a modal blocks the page, it is not a giant close button. `onClose` remains the single writer either way."
                ], [
                    "dialog({ key: \"demoDlg2\", open: model.formOpen, width: 300,",
                    "         closeOnScrim: false,",
                    "         onClose: function ():void { model.formOpen = false; } },",
                    "       [ form, row([ discard, save ]) ])"
                ], 96, function ():Node
                {
                    return row({ gap: 12, alignItems: "center" }, [
                        button({ key: "demoDlg2Btn", label: "Open a form",
                                 onClick: function ():void { m.put("dlg2.open", true); } }),
                        text("click the scrim: nothing happens; Escape still closes",
                            { style: DocsDemo.MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("Centred in the window, not in the page", [
                    "Scroll the list below to the bottom and press the button: the panel still lands in the middle of the WINDOW. That is the whole difference between the second tree and a positioned box -- position:absolute is relative to a PARENT, and the parent here is the window."
                ], [
                    "// the trigger may be 900pt down a scroll view;",
                    "// the dialog is solved against the stage rect either way"
                ], 148, function ():Node
                {
                    var rows:Array = [];
                    for (var i:int = 0; i < 14; i++)
                    {
                        rows.push(row({ style: StyleRefinement.from({ size: [260, 24] }) }, [
                            text("row " + (i + 1), { style: DocsDemo.LABEL, ariaName: "" })
                        ]));
                    }
                    rows.push(button({ key: "demoDlgBtn2", label: "Open dialog",
                        style: DocsDemo.PRIMARY,
                        onClick: function ():void { m.put("dlg.open", true); } }));
                    return scrollView({ key: "dlgScroller",
                        style: StyleRefinement.from({ size: [300, 120], borderWidths: 1,
                            borderColor: 0xE2E8F0 }) }, [
                        // A viewport needs to know how tall its CONTENT is before it can
                        // decide whether there is anything to scroll, so the child carries
                        // the height the 14 rows + the button add up to (380 > the 120pt
                        // viewport) rather than letting it collapse to auto.
                        column({ gap: 4, style: StyleRefinement.from({ padding: 6,
                            size: [null, 380] }) }, rows)
                    ]);
                })
            ];

            if (id == "drawer") return [
                new DocSection("An edge sheet", [
                    "Same second tree, anchored to an EDGE instead of the centre. `side` picks which, and `size` is its width (or height for a bottom sheet)."
                ], [
                    "drawer({ key: \"demoDrw\", open: model.drwOpen, side: \"right\", size: 280,",
                    "         title: \"Filters\", onClose: function ():void { model.drwOpen = false; } },",
                    "       [ text(\"A right-edge sheet over a scrim.\") ])"
                ], 96, function ():Node
                {
                    return row({ gap: 12, alignItems: "center" }, [
                        button({ key: "demoDrwBtn", label: "Open drawer", style: DocsDemo.PRIMARY,
                                 onClick: function ():void { m.put("drw.open", true); } }),
                        text("open: " + m.bool("drw.open", false), { style: DocsDemo.MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("The page behind is untouched", [
                    "A drawer is not a modal layout: the main tree keeps its rects and its scroll position, which is what makes it usable next to a long list."
                ], [
                    "// the main tree is not re-laid out -- only the overlay tree is solved"
                ], 76, function ():Node
                {
                    return text("Open it: the page behind neither scrolls nor reflows.",
                        { style: DocsDemo.LABEL, ariaName: "" });
                }),

                // The other AXIS: for a top/bottom sheet `size` is a HEIGHT. Same widget,
                // same scrim, same close contract -- only the anchor edge changes.
                new DocSection("The other axis: a bottom sheet", [
                    "`side: \"left\" | \"right\" | \"top\" | \"bottom\"`. On a left/right sheet `size` is a WIDTH; on a top/bottom one it is a HEIGHT, and the layer spans the window on the other axis. An unknown side throws at describe time rather than landing on a default edge -- there is no such thing as a drawer with no edge."
                ], [
                    "drawer({ key: \"demoDrw2\", open: model.shareOpen, side: \"bottom\",",
                    "         size: 160, title: \"Share\",",
                    "         onClose: function ():void { model.shareOpen = false; } })"
                ], 96, function ():Node
                {
                    return row({ gap: 12, alignItems: "center" }, [
                        button({ key: "demoDrw2Btn", label: "Open a bottom sheet",
                                 onClick: function ():void { m.put("drw2.open", true); } }),
                        text("same widget, size is the height here",
                            { style: DocsDemo.MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("What size means on each side", [
                    "Drawn here as a diagram, because the real sheet opens in the overlay tree: on left/right the number is a WIDTH and the sheet spans the full height; on top/bottom it is a HEIGHT and the sheet spans the full width. Same widget, same scrim, same close contract -- only the anchoring edge changes."
                ], [
                    "side: \"right\",  size: 280   // width,  full height",
                    "side: \"bottom\", size: 160   // height, full width"
                ], 148, function ():Node
                {
                    return row({ gap: 14, alignItems: "flex-start" }, [
                        column({ gap: 6 }, [
                            text("side: right, size 280", { style: DocsDemo.MONO, ariaName: "" }),
                            box({ style: StyleRefinement.from({
                                size: [150, 96], background: 0xF8FAFC, borderWidths: 1,
                                borderColor: 0xE2E8F0, cornerRadii: 6 }) }, [
                                box({ key: "drwDiagR", style: StyleRefinement.from({
                                    position: "absolute", inset: [0, 0, 0, null],
                                    size: [54, null], background: 0xE0E7FF,
                                    borderWidths: 1, borderColor: 0xC7D2FE }) })
                            ])
                        ]),
                        column({ gap: 6 }, [
                            text("side: bottom, size 160", { style: DocsDemo.MONO, ariaName: "" }),
                            box({ style: StyleRefinement.from({
                                size: [150, 96], background: 0xF8FAFC, borderWidths: 1,
                                borderColor: 0xE2E8F0, cornerRadii: 6 }) }, [
                                box({ key: "drwDiagB", style: StyleRefinement.from({
                                    position: "absolute", inset: [null, 0, 0, 0],
                                    size: [null, 34], background: 0xE0E7FF,
                                    borderWidths: 1, borderColor: 0xC7D2FE }) })
                            ])
                        ])
                    ]);
                })
            ];

            if (id == "popover") return [
                new DocSection("Anchored by key", [
                    "The popover finds its anchor through a STABLE key, not a node reference: the anchor survives a reconcile, so a popover stays put when the page re-renders."
                ], [
                    "// render()",
                    "button({ key: \"popBtn\", label: \"Show details\", onClick: open })",
                    "// renderOverlay()",
                    "popover({ key: \"demoPop\", open: model.popOpen, anchorKey: \"popBtn\",",
                    "          placement: \"bottom\", offset: 8, width: 220,",
                    "          onClose: function ():void { model.popOpen = false; } }, [ body ])"
                ], 96, function ():Node
                {
                    return row({ gap: 12, alignItems: "center" }, [
                        button({ key: "popBtn", label: "Show details", style: DocsDemo.PRIMARY,
                                 onClick: function ():void { m.put("pop.open", !m.bool("pop.open", false)); } }),
                        text("open: " + m.bool("pop.open", false), { style: DocsDemo.MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("Sized by its content", [
                    "`width` is a maximum-ish hint: the panel wraps its children and the placement flips when the bottom would leave the window."
                ], [
                    "placement: \"bottom\" | \"top\" | \"left\" | \"right\",  offset: 8"
                ], 76, function ():Node
                {
                    return text("Close it by clicking outside or on the trigger again.",
                        { style: DocsDemo.LABEL, ariaName: "" });
                }),

                // The inverse policy of closeOnScrim: a popover can refuse the outside
                // press too, and then it MUST carry its own way out.
                new DocSection("closeOnOutside: false", [
                    "A popover closes on any press outside it by default. `closeOnOutside: false` makes it a panel you dismiss yourself, which is what a colour picker or a mini form wants: a stray click on the page must not throw the work away.",
                    "It still never closes ITSELF -- `onClose` is the only writer, so the panel needs a button of its own (the one inside this popover is that button)."
                ], [
                    "popover({ key: \"demoPop2\", open: model.pinOpen, anchorKey: \"pop2Btn\",",
                    "          closeOnOutside: false,",
                    "          onClose: function ():void { model.pinOpen = false; } },",
                    "        [ text(\"no outside press closes me\"), button({ label: \"Done\", ... }) ])"
                ], 96, function ():Node
                {
                    return row({ gap: 12, alignItems: "center" }, [
                        button({ key: "demoPop2Btn", label: "Pin a popover",
                                 onClick: function ():void { m.put("pop2.open", true); } }),
                        text("click outside it: it stays; press Done inside",
                            { style: DocsDemo.MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("Placement is a request", [
                    "The four placements are what the author asks for; the layer flips one when the panel would leave the window. A page therefore does not have to know where in the window its trigger ended up -- which is the case the diagram shows."
                ], [
                    "placement: \"bottom\"   // near the window's bottom edge it opens upward",
                    "offset: 8               // the gap to the anchor, in points"
                ], 132, function ():Node
                {
                    return row({ gap: 14, alignItems: "flex-start" }, [
                        column({ gap: 6 }, [
                            text("asked: bottom", { style: DocsDemo.MONO, ariaName: "" }),
                            box({ style: StyleRefinement.from({
                                size: [150, 96], background: 0xF8FAFC, borderWidths: 1,
                                borderColor: 0xE2E8F0, cornerRadii: 6 }) }, [
                                chip("trigger", { key: "popDiagTrig",
                                    style: StyleRefinement.from({ position: "absolute",
                                        inset: [null, null, 6, 6] }) }),
                                box({ key: "popDiagPanel", style: StyleRefinement.from({
                                    position: "absolute", inset: [null, 6, 34, 6],
                                    size: [null, 32], background: 0xFFFFFF,
                                    borderWidths: 1, borderColor: 0xC7D2FE, cornerRadii: 6 }) }, [
                                    text("opened upward", { style: DocsDemo.LABEL, ariaName: "" })
                                ])
                            ])
                        ]),
                        column({ gap: 6, style: StyleRefinement.from({ size: [180, null] }) }, [
                            text("Placement is measured against the WINDOW rect, not the page, and",
                                { style: DocsDemo.LABEL, ariaName: "" }),
                            text("the flip happens on the frame that would clip the panel.",
                                { style: DocsDemo.LABEL, ariaName: "" })
                        ])
                    ]);
                })
            ];

            if (id == "menu") return [
                new DocSection("A list of actions", [
                    "The menu is the popover's sibling: same anchoring, same overlay, but a list of items and one selected index."
                ], [
                    "menu({ key: \"demoMnu\", open: model.mnuOpen, anchorKey: \"mnuBtn\", width: 170,",
                    "       items: [\"Rename\", \"Duplicate\", \"Delete\"], selectedIndex: -1,",
                    "       onSelect: function (i:int):void { act(i); },",
                    "       onClose: function ():void { model.mnuOpen = false; } })"
                ], 96, function ():Node
                {
                    return row({ gap: 12, alignItems: "center" }, [
                        button({ key: "mnuBtn", label: "Actions", style: DocsDemo.QUIET,
                                 onClick: function ():void { m.put("mnu.open", !m.bool("mnu.open", false)); } }),
                        text("last pick: " + m.num("mnu.pick", -1), { style: DocsDemo.MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("Items are strings or {label, value}", [
                    "labelOf()/valueOf() are the same helpers the overlays use, so a menu, a select and a combobox accept exactly the same option shapes."
                ], [
                    "items: [\"Rename\", { label: \"Delete\", value: \"rm\" }]"
                ], 76, function ():Node
                {
                    return text("Click an item: onSelect(index) fires and the menu closes.",
                        { style: DocsDemo.LABEL, ariaName: "" });
                }),

                // A submenu is a MENU, not a special widget: it is the item's child, so it
                // inherits the same keys, the same placement maths and the same close rule.
                new DocSection("A submenu is an item with a list", [
                    "`items: [{ label: \"Move to\", submenu: [...] }]` -- the submenu is described as a child MENU of the item, so it reuses the same keyboard map, the same placement code and the same close-on-outside rule. `submenuIndex` says which item's list is open; the widget reports the ITEM index, not a flat index into a merged list."
                ], [
                    "menu({ key: \"demoMnu2\", open: model.m2Open, anchorKey: \"mnu2Btn\",",
                    "       items: [ \"Rename\", { label: \"Move to\", submenu: [ \"Inbox\", \"Archive\" ] },",
                    "                { label: \"Delete\", value: \"rm\" } ],",
                    "       submenuIndex: 1, onSelect: onItem })"
                ], 96, function ():Node
                {
                    return row({ gap: 12, alignItems: "center" }, [
                        button({ key: "mnu2Btn", label: "Menu with a submenu",
                                 onClick: function ():void { m.put("mnu2.open", true); } }),
                        text("submenuIndex 1 is open: Inbox / Archive",
                            { style: DocsDemo.MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("The keyboard map is the listbox's", [
                    "A menu is a list of rows, so it answers the keys a listbox answers: Up/Down move, Home/End jump to the ends, Enter activates and Escape closes. The submenu takes Right to enter and Left to come back, which is the one pair the main list does not use -- and the reason a submenu is a child MENU rather than a nested array."
                ], [
                    "// Up/Down move, Home/End jump, Enter selects, Escape closes",
                    "// Right opens the item's submenu, Left returns to the parent list"
                ], 96, function ():Node
                {
                    return column({ gap: 8 }, [
                        row({ gap: 8, alignItems: "center" }, [
                            button({ key: "mnu3Btn", label: "Open the menu",
                                onClick: function ():void { m.put("mnu.open", true); } }),
                            text("last item: " + m.val("mnu.last", "none yet"),
                                { style: DocsDemo.MONO, ariaName: "" })
                        ]),
                        row({ gap: 6, alignItems: "center" }, [
                            chip("Up"), chip("Down"), chip("Home"), chip("End"),
                            chip("Enter"), chip("Esc"), chip("Right"), chip("Left")
                        ])
                    ]);
                })
            ];

            if (id == "toast") return [
                new DocSection("A transient corner message", [
                    "Toasts are self-expiring: `duration` decides when onClose fires, and the author's model removes it. The host stacks them bottom-right. `tone` is one of default | success | danger -- a NAME, not a colour (toast.as throws on anything else)."
                ], [
                    "toastHost({ key: \"demoToasts\" }, [",
                    "    toast({ key: \"demoToast\", open: model.tstOpen, message: \"Draft saved\",",
                    "            tone: \"success\", duration: 2500,",
                    "            onClose: function ():void { model.tstOpen = false; } })",
                    "])"
                ], 96, function ():Node
                {
                    return row({ gap: 12, alignItems: "center" }, [
                        button({ key: "tstBtn", label: "Show toast", style: DocsDemo.PRIMARY,
                                 onClick: function ():void { m.put("tst.open", true); } }),
                        text("open: " + m.bool("tst.open", false), { style: DocsDemo.MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("It closes itself", [
                    "`open:false` is what removes it; the widget never removes its own node. A second toast with the same key replaces the first one's content."
                ], [
                    "// the timer calls onClose -> the model flips `open` -> the next render drops it"
                ], 76, function ():Node
                {
                    return text("Watch it: a toast disappears after its duration, not on a click.",
                        { style: DocsDemo.LABEL, ariaName: "" });
                }),

                new DocSection("tone is a name, not a colour", [
                    "The factory accepts default, success and danger and throws on anything else, so a theme swap moves every toast with the rest of the kit. Pick a tone, then press the button: the toast that opens uses the one you picked."
                ], [
                    "toast({ message: \"Saved\", tone: \"success\" })   // default | success | danger",
                    "toast({ message: \"Nope\",  tone: \"danger\" })"
                ], 108, function ():Node
                {
                    var tone:String = String(m.val("tst.tone", "success"));
                    return column({ gap: 8 }, [
                        row({ gap: 8, alignItems: "center" }, [
                            chip("default", { key: "tstT0", tone: tone == "default" ? "info" : "neutral",
                                onClick: function ():void { m.put("tst.tone", "default"); } }),
                            chip("success", { key: "tstT1", tone: tone == "success" ? "info" : "neutral",
                                onClick: function ():void { m.put("tst.tone", "success"); } }),
                            chip("danger", { key: "tstT2", tone: tone == "danger" ? "info" : "neutral",
                                onClick: function ():void { m.put("tst.tone", "danger"); } }),
                            button({ key: "tstBtn2", label: "Show it", style: DocsDemo.PRIMARY,
                                onClick: function ():void { m.put("tst.open", true); } })
                        ]),
                        text("tone: " + tone, { style: DocsDemo.MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("duration is the author's number", [
                    "There is no default that suits every message: a 2.5s toast is right for \"saved\" and wrong for \"3 items failed to sync\". The slider sets what the next toast is given; the widget only counts it down and calls onClose."
                ], [
                    "toast({ duration: 2500, onClose: function ():void { open = false; } })",
                    "// duration <= 0 never fires: the toast then waits for a click"
                ], 132, function ():Node
                {
                    var d:Number = m.num("tst.dur", 2500);
                    return column({ gap: 8 }, [
                        row({ gap: 10, alignItems: "center" }, [
                            slider("duration " + int(d) + " ms", { key: "tstDur",
                                value: d / 6000,
                                style: StyleRefinement.from({ size: [220, 40] }),
                                onChange: function (v:Number):void { m.put("tst.dur", v * 6000); } }),
                            button({ key: "tstBtn3", label: "Show", style: DocsDemo.QUIET,
                                onClick: function ():void { m.put("tst.open", true); } })
                        ]),
                        text("next toast: " + int(d) + " ms", { style: DocsDemo.MONO, ariaName: "" })
                    ]);
                })
            ];

            if (id == "toastHost") return [
                new DocSection("The stack", [
                    "A host is a positioned container in the overlay tree: toasts drop into its bottom- right corner in the order they were described. Without a host, a toast has no corner.",
                    "`tone` is a NAME, not a colour: default | success | danger, and anything else throws."
                ], [
                    "toastHost({ key: \"demoToasts\" }, [",
                    "    toast({ key: \"t1\", open: true, message: \"One\", tone: \"default\" }),",
                    "    toast({ key: \"t2\", open: true, message: \"Two\", tone: \"success\" })",
                    "])"
                ], 96, function ():Node
                {
                    return row({ gap: 12, alignItems: "center" }, [
                        button({ key: "tshBtn", label: "Show two toasts", style: DocsDemo.PRIMARY,
                                 onClick: function ():void { m.put("tsh.open", true); } }),
                        text("open: " + m.bool("tsh.open", false), { style: DocsDemo.MONO, ariaName: "" })
                    ]);
                }),

                new DocSection("Order is stacking order", [
                    "The overlay has no z-index: the last child is painted last. Toasts stack in the order they are described, and the host is the last thing in the overlay."
                ], [
                    "// overlay([ dialog, drawer, popover, menu, toastHost ])  <- host last"
                ], 76, function ():Node
                {
                    return text("Two toasts, one above the other, newest at the bottom.",
                        { style: DocsDemo.LABEL, ariaName: "" });
                }),

                new DocSection("The host owns the corner", [
                    "A toast does NOT position itself: the host is the positioned container, and the toasts stack inside its bottom-right corner in describe order. Two hosts in one overlay is legal -- one per screen edge -- and each stacks its own children."
                ], [
                    "toastHost({ key: \"a\" }, [ toast({ ... }), toast({ ... }) ]),",
                    "// the corner is the host's; the toast only supplies its size"
                ], 148, function ():Node
                {
                    return box({ style: StyleRefinement.from({
                        size: [300, 110], background: 0xF1F5F9, borderWidths: 1,
                        borderColor: 0xE2E8F0, cornerRadii: 8 }) }, [
                        box({ key: "thDiag1", style: StyleRefinement.from({
                            position: "absolute", inset: [null, 10, 34, null],
                            size: [150, 30], background: 0x1F2937, cornerRadii: 6 }) }, [
                            text("Saved", { style: StyleRefinement.from({
                                size: [null, 30], padding: [8, 12], text: { fontSize: 11,
                                    color: 0xFFFFFF } }), ariaName: "" })
                        ]),
                        box({ key: "thDiag2", style: StyleRefinement.from({
                            position: "absolute", inset: [null, 10, 6, null],
                            size: [150, 30], background: 0xDC2626, cornerRadii: 6 }) }, [
                            text("3 failed", { style: StyleRefinement.from({
                                size: [null, 30], padding: [8, 12], text: { fontSize: 11,
                                    color: 0xFFFFFF } }), ariaName: "" })
                        ])
                    ]);
                }),

                new DocSection("Without a host there is no corner", [
                    "A toast that is not inside a toastHost is laid out like any other node -- in the overlay's flow. Nothing breaks; it simply is not in a corner, which is how a component gallery ends up with a toast in the middle of the screen."
                ], [
                    "overlay([ toastHost({}, [ toast({ open: true }) ]) ])   // corner",
                    "overlay([ toast({ open: true }) ])                     // not a corner"
                ], 96, function ():Node
                {
                    return row({ gap: 12, alignItems: "center" }, [
                        divider({ orientation: "vertical" }),
                        text("toasts live and die inside a host; the host outlives them",
                            { style: DocsDemo.LABEL, ariaName: "" })
                    ]);
                })
            ];

            return null;
        }
    }
}

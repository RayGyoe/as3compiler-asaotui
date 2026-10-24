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
    import asaot.ui.button;
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
                    "The dialog is described in renderOverlay(), so it is laid out against the WINDOW:",
                    "a page that scrolls cannot drag its dialog along with it."
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
                    "Escape, a scrim click and the footer's Cancel all funnel into onClose -- the author",
                    "writes `false` once, and the next render stops describing the dialog."
                ], [
                    "onClose: function ():void { model.dlgOpen = false; }"
                ], 76, function ():Node
                {
                    return text("Escape closes it too: the widget handles the key, the model owns the flag.",
                        { style: DocsDemo.LABEL, ariaName: "" });
                })
            ];

            if (id == "drawer") return [
                new DocSection("An edge sheet", [
                    "Same second tree, anchored to an EDGE instead of the centre. `side` picks which,",
                    "and `size` is its width (or height for a bottom sheet)."
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
                    "A drawer is not a modal layout: the main tree keeps its rects and its scroll",
                    "position, which is what makes it usable next to a long list."
                ], [
                    "// the main tree is not re-laid out -- only the overlay tree is solved"
                ], 76, function ():Node
                {
                    return text("Open it: the page behind neither scrolls nor reflows.",
                        { style: DocsDemo.LABEL, ariaName: "" });
                })
            ];

            if (id == "popover") return [
                new DocSection("Anchored by key", [
                    "The popover finds its anchor through a STABLE key, not a node reference: the anchor",
                    "survives a reconcile, so a popover stays put when the page re-renders."
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
                    "`width` is a maximum-ish hint: the panel wraps its children and the placement flips",
                    "when the bottom would leave the window."
                ], [
                    "placement: \"bottom\" | \"top\" | \"left\" | \"right\",  offset: 8"
                ], 76, function ():Node
                {
                    return text("Close it by clicking outside or on the trigger again.",
                        { style: DocsDemo.LABEL, ariaName: "" });
                })
            ];

            if (id == "menu") return [
                new DocSection("A list of actions", [
                    "The menu is the popover's sibling: same anchoring, same overlay, but a list of",
                    "items and one selected index."
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
                    "labelOf()/valueOf() are the same helpers the overlays use, so a menu, a select and",
                    "a combobox accept exactly the same option shapes."
                ], [
                    "items: [\"Rename\", { label: \"Delete\", value: \"rm\" }]"
                ], 76, function ():Node
                {
                    return text("Click an item: onSelect(index) fires and the menu closes.",
                        { style: DocsDemo.LABEL, ariaName: "" });
                })
            ];

            if (id == "toast") return [
                new DocSection("A transient corner message", [
                    "Toasts are self-expiring: `duration` decides when onClose fires, and the author's",
                    "model removes it. The host stacks them bottom-right. `tone` is one of default |",
                    "success | danger -- a NAME, not a colour (toast.as throws on anything else)."
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
                    "`open:false` is what removes it; the widget never removes its own node. A second",
                    "toast with the same key replaces the first one's content."
                ], [
                    "// the timer calls onClose -> the model flips `open` -> the next render drops it"
                ], 76, function ():Node
                {
                    return text("Watch it: a toast disappears after its duration, not on a click.",
                        { style: DocsDemo.LABEL, ariaName: "" });
                })
            ];

            if (id == "toastHost") return [
                new DocSection("The stack", [
                    "A host is a positioned container in the overlay tree: toasts drop into its bottom-",
                    "right corner in the order they were described. Without a host, a toast has no corner.",
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
                    "The overlay has no z-index: the last child is painted last. Toasts stack in the",
                    "order they are described, and the host is the last thing in the overlay."
                ], [
                    "// overlay([ dialog, drawer, popover, menu, toastHost ])  <- host last"
                ], 76, function ():Node
                {
                    return text("Two toasts, one above the other, newest at the bottom.",
                        { style: DocsDemo.LABEL, ariaName: "" });
                })
            ];

            return null;
        }
    }
}

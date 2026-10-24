// demo/DocsView.as -- the component documentation app: one window, a scrolling
// index on the left, one component page on the right.
//
// SHAPE (and why it is not the old seven-page gallery):
//   * The sidebar lists every factory the kit exports, grouped, and scrolls. A
//     click is `model.pick(id)` -- one model write, one invalidate, one render.
//   * The content pane describes ONE component: a title, a blurb, and a stack of
//     sections. Each section is a heading, prose, a LIVE demo and the source that
//     produced it, so "what it looks like" and "how you ask for it" are the same
//     artifact -- the code under a demo cannot drift from it, because both come
//     out of the same render pass.
//   * Every widget state the demos show (a checkbox, a picker's `open`, a slider
//     value) lives in DocsModel, not in the node. That is the library's own
//     contract; a docs page that hid it inside a widget would be lying.
//
// HEIGHTS ARE EXPLICIT, ON PURPOSE. A scrollView refuses a container child with
// no height (ScrollViewWidget.measure throws), so the index column and the
// content column are sized from the data: DocSection.height() sums the same
// constants DocsStyle hands the engine. The tour then checks the arithmetic the
// only way that cannot lie -- by requiring that no child's solved rect escapes
// its block.
package demo
{
    import asaot.ui.Node;
    import asaot.ui.View;
    import asaot.ui.dialog;
    import asaot.ui.drawer;
    import asaot.ui.menu;
    import asaot.ui.overlay;
    import asaot.ui.popover;
    import asaot.ui.text;
    import asaot.ui.toast;
    import asaot.ui.toastHost;
    import asaot.ui.box;
    import asaot.ui.button;
    import asaot.ui.column;
    import asaot.ui.row;
    import asaot.ui.scrollView;
    import asaot.ui.style.Length;
    import asaot.ui.style.StyleRefinement;

    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;

    public class DocsView extends View
    {
        public var model:DocsModel;
        // Evidence that the sidebar is what changes the page (the tour clicks a
        // row and reads this): every pick() that came from a click lands here.
        public var picks:int = 0;
        public var lastPick:String = "";

        public function DocsView(m:DocsModel):void
        {
            super();
            this.model = m;
        }

        // ---- the whole window -------------------------------------------------
        override public function render():Node
        {
            var p:DocPage = DocsCatalog.page(this.model.doc);
            if (p == null) p = DocPage(DocsCatalog.pages()[0]);
            var secs:Array = DocsCatalog.sections(this, p.id);
            // A page whose builder has nothing yet renders an empty content pane
            // rather than crashing: the tour walks EVERY page, so a missing
            // builder must be a visible empty page, not a null dereference.
            if (secs == null) secs = [];
            var group:String = String(DocsCatalog.GROUPS[p.group]);
            var meta:String = "kind \"" + p.id + "\"  -  " + group.toLowerCase()
                + "  -  " + secs.length + " example" + (secs.length == 1 ? "" : "s");

            // row(), not column(): a widget's own direction OVERRIDES the style, so the
            // root has to be built with the row factory to lay the two panes side by side.
            return row({ key: "root", style: DocsStyle.ROOT, ariaName: "asaot.ui documentation" }, [
                this.sidebar(p),
                column({ key: "main", style: DocsStyle.MAIN, ariaName: "Component page" }, [
                    text(p.title, { key: "docTitle", style: DocsStyle.DOC_TITLE, ariaName: "Component" }),
                    text(p.blurb, { key: "docBlurb", style: DocsStyle.DOC_BLURB, ariaName: "Summary" }),
                    text(meta, { key: "docMeta", style: DocsStyle.DOC_META, ariaName: "Details" }),
                    scrollView({ key: "docScroll", style: DocsStyle.DOC_SCROLL, wheelStep: 40 }, [
                        this.docColumn(secs)
                    ])
                ])
            ]);
        }

        // ---- the sidebar ------------------------------------------------------
        private function sidebar(cur:DocPage):Node
        {
            var pages:Array = DocsCatalog.pages();
            var rows:Array = [];
            var h:Number = 0;
            var group:int = -1;
            for (var i:int = 0; i < pages.length; i++)
            {
                var p:DocPage = DocPage(pages[i]);
                if (p.group != group)
                {
                    group = p.group;
                    rows.push(text(String(DocsCatalog.GROUPS[group]),
                        { key: "navg" + group, style: DocsStyle.NAV_GROUP, ariaName: "" }));
                    h = h + DocsStyle.NAV_H_GROUP;
                }
                rows.push(this.navItem(p, p.id == cur.id));
                h = h + DocsStyle.NAV_H_ITEM;
            }

            var colStyle:StyleRefinement = DocsStyle.NAV_COL.withPatch(
                StyleRefinement.from({ size: [Length.pct(1), Length.px(h)] }));

            return column({ key: "side", style: DocsStyle.SIDE, ariaName: "Index" }, [
                text("asaot.ui", { key: "brand", style: DocsStyle.BRAND, ariaName: "Product" }),
                text("pure-AS3 UI toolkit", { key: "tag", style: DocsStyle.TAG, ariaName: "Tagline" }),
                scrollView({ key: "nav", style: DocsStyle.NAV, wheelStep: 26 }, [
                    column({ key: "navCol", style: colStyle }, rows)
                ]),
                text(pages.length + " components  -  one page each",
                    { key: "foot", style: DocsStyle.FOOT, ariaName: "" })
            ]);
        }

        // One sidebar row. Built by a METHOD, not inline in the loop: an AS3
        // closure captures the VARIABLE, and `var` is function-scoped, so a
        // closure made inside the loop would all point at the last page.
        private function navItem(p:DocPage, on:Boolean):Node
        {
            var self:DocsView = this;
            var id:String = p.id;
            var style:StyleRefinement = on ? DocsStyle.NAV_ITEM_ON : DocsStyle.NAV_ITEM;
            return box({
                key: "nav:" + id, style: style, ariaName: p.title,
                onClick: function ():void { self.clicked(id); }
            }, [
                text(p.title, { key: "nav:" + id + ":t",
                                style: on ? DocsStyle.NAV_TEXT_ON : DocsStyle.NAV_TEXT, ariaName: "" })
            ]);
        }

        private function clicked(id:String):void
        {
            this.picks = this.picks + 1;
            this.lastPick = id;
            this.model.pick(id);
        }

        // ---- the page body ----------------------------------------------------
        private function docColumn(secs:Array):Node
        {
            var blocks:Array = [];
            var h:Number = 0;
            for (var i:int = 0; i < secs.length; i++)
            {
                var sec:DocSection = DocSection(secs[i]);
                blocks.push(this.block(sec, i));
                h = h + sec.height();
                if (i > 0) h = h + DocsStyle.SEC_GAP;
            }
            // A short page still fills the viewport, so the column's height is never 0
            // (a scrollView refuses a container child with no height).
            if (h < DocsStyle.DOC_VIEW_H) h = DocsStyle.DOC_VIEW_H;
            var style:StyleRefinement = DocsStyle.DOC_COL.withPatch(
                StyleRefinement.from({ size: [Length.pct(1), Length.px(h)] }));
            return column({ key: "docCol", style: style, ariaName: "" }, blocks);
        }

        private function block(sec:DocSection, i:int):Node
        {
            var pre:String = "b" + i;
            var kids:Array = [];
            kids.push(text(sec.heading, { key: pre + ":h", style: DocsStyle.SEC_HEAD, ariaName: "" }));

            if (sec.prose.length > 0)
            {
                var lines:Array = [];
                for (var j:int = 0; j < sec.prose.length; j++)
                {
                    lines.push(text(String(sec.prose[j]),
                        { key: pre + ":p" + j, style: DocsStyle.PROSE, ariaName: "" }));
                }
                var proseStyle:StyleRefinement = StyleRefinement.from({
                    flexDirection: "column", gap: 0,
                    size: [Length.pct(1), Length.px(sec.prose.length * DocsStyle.SEC_PROSE_H)]
                });
                kids.push(column({ key: pre + ":prose", style: proseStyle, ariaName: "" }, lines));
            }

            var demoStyle:StyleRefinement = DocsStyle.DEMO.withPatch(
                StyleRefinement.from({ size: [Length.pct(1), Length.px(sec.demoH)] }));
            var demoNode:Node = sec.build();
            kids.push(box({ key: pre + ":demo", style: demoStyle, ariaName: "Example" },
                demoNode == null ? [] : [demoNode]));

            var code:Array = [];
            for (var c:int = 0; c < sec.code.length; c++)
            {
                code.push(text(String(sec.code[c]),
                    { key: pre + ":c" + c, style: DocsStyle.CODE_LINE, ariaName: "" }));
            }
            var codeStyle:StyleRefinement = DocsStyle.CODE.withPatch(
                StyleRefinement.from({ size: [Length.pct(1), Length.px(sec.codeHeight())] }));
            kids.push(box({ key: pre + ":code", style: codeStyle, ariaName: "Source" }, code));

            var blockStyle:StyleRefinement = DocsStyle.SEC.withPatch(
                StyleRefinement.from({ size: [Length.pct(1), Length.px(sec.height())] }));
            return column({ key: pre, style: blockStyle, ariaName: sec.heading }, kids);
        }

        // ---- the floating layer ------------------------------------------------
        // Only the component pages that DOCUMENT a floating surface add anything
        // here. Everything is author-owned: each widget is passed `open` from the
        // model and writes it back through onClose, so closing is a model write
        // like any other.
        override public function renderOverlay():Node
        {
            var m:DocsModel = this.model;
            var nodes:Array = [];
            if (m.doc == "overlay" && m.bool("ov.open", false))
            {
                nodes.push(popover({
                    key: "ovPop", open: true, anchorKey: "ovBtn", placement: "bottom",
                    offset: 8, width: 230,
                    onClose: function ():void { m.put("ov.open", false); }
                }, [
                    text("The overlay tree is reconciled on top of render()'s tree.",
                        { key: "ovPopBody", style: StyleRefinement.from({
                            text: { fontSize: 12, color: 0x334155 } }) })
                ]));
            }
            if (m.doc == "dialog" && m.bool("dlg.open", false))
            {
                nodes.push(dialog({
                    key: "demoDlg", open: true, width: 320, title: "Delete 3 files?",
                    footer: [
                        button({ key: "demoDlgNo", label: "Cancel",
                                 onClick: function ():void { m.put("dlg.open", false); } }),
                        button({ key: "demoDlgYes", label: "Delete",
                                 style: StyleRefinement.from({
                                     background: 0xDC2626, borderColor: 0xB91C1C,
                                     text: { color: 0xFFFFFF, fontWeight: "bold" } }),
                                 onClick: function ():void { m.put("dlg.open", false); } })
                    ],
                    onClose: function ():void { m.put("dlg.open", false); }
                }, [
                    text("This cannot be undone.", { key: "demoDlgBody",
                         style: StyleRefinement.from({ text: { fontSize: 13, color: 0x4B5563 } }) })
                ]));
            }
            if (m.doc == "drawer" && m.bool("drw.open", false))
            {
                nodes.push(drawer({
                    key: "demoDrw", open: true, side: "right", size: 280, title: "Filters",
                    onClose: function ():void { m.put("drw.open", false); }
                }, [
                    text("A right-edge sheet over a scrim: the page behind it is not re-laid out.",
                        { key: "demoDrwBody", style: StyleRefinement.from({
                            text: { fontSize: 13, color: 0x374151 } }) })
                ]));
            }
            if (m.doc == "popover" && m.bool("pop.open", false))
            {
                nodes.push(popover({
                    key: "demoPop", open: true, anchorKey: "popBtn", placement: "bottom",
                    offset: 8, width: 220,
                    onClose: function ():void { m.put("pop.open", false); }
                }, [
                    text("Anchored to popBtn by KEY, so it survives a reconcile.",
                        { key: "demoPopBody", style: StyleRefinement.from({
                            text: { fontSize: 12, color: 0x374151 } }) })
                ]));
            }
            if (m.doc == "menu" && m.bool("mnu.open", false))
            {
                nodes.push(menu({
                    key: "demoMnu", open: true, anchorKey: "mnuBtn", placement: "bottom",
                    offset: 8, width: 170, selectedIndex: -1,
                    items: ["Rename", "Duplicate", "Delete"],
                    onSelect: function (i:int):void { m.put("mnu.pick", i); m.put("mnu.open", false); },
                    onClose: function ():void { m.put("mnu.open", false); }
                }));
            }
            if (m.doc == "toast" && m.bool("tst.open", false))
            {
                nodes.push(toastHost({ key: "demoToasts" }, [
                    toast({ key: "demoToast", open: true, message: "Draft saved",
                            tone: "success", duration: 2500,
                            onClose: function ():void { m.put("tst.open", false); } })
                ]));
            }
            if (m.doc == "toastHost" && m.bool("tsh.open", false))
            {
                nodes.push(toastHost({ key: "demoToasts" }, [
                    toast({ key: "demoToast1", open: true, message: "Two files moved",
                            tone: "info", duration: 4000,
                            onClose: function ():void { } }),
                    toast({ key: "demoToast2", open: true, message: "Draft saved",
                            tone: "success", duration: 4000,
                            onClose: function ():void { } })
                ]));
            }
            if (nodes.length == 0) return null;
            return overlay(nodes);
        }
    }
}

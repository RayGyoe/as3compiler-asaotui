// demo/GalleryView.as -- the multi-page demo's view: a five-page app whose page
// switching goes through the tabs widget's Binding.
//
// STRUCTURE (and why it is shaped this way):
//   * ONE `render()` describes whichever page the model says is selected. There is
//     no per-page widget tree kept alive: switching a page is just a model write,
//     and the reconciler replaces the `body` slot. That is the whole point of a
//     keyed reconciler, and it is what the demo tour asserts (the other pages'
//     nodes are GONE, not merely invisible).
//   * Every page is a subtree with key "body", so it lands in the same slot.
//   * Layout sticks to the frozen surface: row/column, explicit px/pct sizes,
//     padding, gap, flexGrow, border, cornerRadii. Sizes on the gallery columns
//     are explicit precisely so the acceptance tour can hand-compute them.
//   * `tick()` is the ONLY clock-driven piece, and it drives the Motion page by
//     flipping `model.phase` -- no setTimeout, no timer bookkeeping, and it only
//     invalidates while the Motion page is on screen, so a settled frame on any
//     other page still does nothing.
package demo
{
    import asaot.ui.Dirty;
    import asaot.ui.Node;
    import asaot.ui.View;
    import asaot.ui.accordion;
    import asaot.ui.avatar;
    import asaot.ui.badge;
    import asaot.ui.bindTo;
    import asaot.ui.box;
    import asaot.ui.breadcrumb;
    import asaot.ui.button;
    import asaot.ui.card;
    import asaot.ui.checkbox;
    import asaot.ui.chip;
    import asaot.ui.column;
    import asaot.ui.divider;
    import asaot.ui.image;
    import asaot.ui.list;
    import asaot.ui.pagination;
    import asaot.ui.progress;
    import asaot.ui.radio;
    import asaot.ui.row;
    import asaot.ui.skeleton;
    import asaot.ui.slider;
    import asaot.ui.spinner;
    import asaot.ui.table;
    import asaot.ui.tabs;
    import asaot.ui.text;
    import asaot.ui.textField;
    import asaot.ui.toggle;
    import asaot.ui.tooltip;
    import asaot.ui.style.Length;
    import asaot.ui.style.StyleRefinement;

    import flash.display.BitmapData;

    public class GalleryView extends View
    {
        // ---- the shell -------------------------------------------------------
        private static const PAGE:StyleRefinement = StyleRefinement.from({
            flexDirection: "column", padding: 24, gap: 12,
            size: [Length.px(700), Length.px(560)], background: 0xFFFFFF
        });
        private static const TITLE:StyleRefinement = StyleRefinement.from({
            text: { fontSize: 24, fontWeight: "bold", color: 0x111827 }
        });
        private static const SUB:StyleRefinement = StyleRefinement.from({
            text: { fontSize: 12, color: 0x6B7280 }
        });
        private static const TABS:StyleRefinement = StyleRefinement.from({
            size: [Length.pct(1), Length.px(38)]
        });
        private static const BODY:StyleRefinement = StyleRefinement.from({
            flexDirection: "column", gap: 12, flexGrow: 1, size: [Length.pct(1), null]
        });
        private static const ROWBODY:StyleRefinement = StyleRefinement.from({
            flexDirection: "row", gap: 12, flexGrow: 1, size: [Length.pct(1), null]
        });
        private static const COL:StyleRefinement = StyleRefinement.from({
            flexDirection: "column", gap: 12, flexGrow: 1, size: [null, null]
        });
        private static const STATUS:StyleRefinement = StyleRefinement.from({
            size: [Length.pct(1), Length.px(18)],
            text: { fontSize: 12, color: 0x2563EB }
        });
        // ---- cards -----------------------------------------------------------
        private static const CARD:StyleRefinement = StyleRefinement.from({
            flexDirection: "column", padding: 14, gap: 10, size: [Length.pct(1), null],
            background: 0xF9FAFB, border: 1, borderColor: 0xE5E7EB, cornerRadii: 10
        });
        private static const CARD_H:StyleRefinement = StyleRefinement.from({
            flexDirection: "column", padding: 14, gap: 10, size: [Length.pct(1), Length.px(250)],
            background: 0xF9FAFB, border: 1, borderColor: 0xE5E7EB, cornerRadii: 10
        });
        // Gallery cards. Heights are chosen so each control's label line fits ABOVE
        // its control: the kit draws a progress/slider label at the node's top and
        // its track at (height - 12), so a control shorter than ~28 would have its
        // own label painted over its own track.
        private static const CARD_G:StyleRefinement = StyleRefinement.from({
            flexDirection: "column", padding: 14, gap: 10, size: [Length.pct(1), Length.px(160)],
            background: 0xF9FAFB, border: 1, borderColor: 0xE5E7EB, cornerRadii: 10
        });
        private static const CARD_G2:StyleRefinement = StyleRefinement.from({
            flexDirection: "column", padding: 14, gap: 10, size: [Length.pct(1), Length.px(202)],
            background: 0xF9FAFB, border: 1, borderColor: 0xE5E7EB, cornerRadii: 10
        });
        private static const CARD_G3:StyleRefinement = StyleRefinement.from({
            flexDirection: "column", padding: 14, gap: 10, size: [Length.pct(1), Length.px(180)],
            background: 0xF9FAFB, border: 1, borderColor: 0xE5E7EB, cornerRadii: 10
        });
        private static const CARD_G4:StyleRefinement = StyleRefinement.from({
            flexDirection: "column", padding: 14, gap: 10, size: [Length.pct(1), Length.px(182)],
            background: 0xF9FAFB, border: 1, borderColor: 0xE5E7EB, cornerRadii: 10
        });
        // NOTE on card titles: the demo passes the title as a real CHILD text node
        // instead of using `card({title: ...})`. The `title` opt draws the text in
        // the content box's top-left WITHOUT reserving layout space, so it overlaps
        // the first child (see STATUS.md section 3.3). A child text node is laid
        // out like anything else, so the card and its title never collide.
        private static const CARD_TITLE:StyleRefinement = StyleRefinement.from({
            size: [Length.pct(1), Length.px(18)],
            text: { fontSize: 13, fontWeight: "bold", color: 0x374151 }
        });
        private static const NOTE:StyleRefinement = StyleRefinement.from({
            size: [Length.pct(1), Length.px(16)],
            text: { fontSize: 11, color: 0x9CA3AF }
        });
        private static const ROW:StyleRefinement = StyleRefinement.from({
            flexDirection: "row", gap: 10, size: [Length.pct(1), null]
        });
        private static const ROW36:StyleRefinement = StyleRefinement.from({
            flexDirection: "row", gap: 10, size: [Length.pct(1), Length.px(36)]
        });
        // ---- widget sizes (all explicit: the tour hand-computes rects) --------
        private static const CHIP_S:StyleRefinement = StyleRefinement.from({ size: [Length.px(92), Length.px(28)] });
        private static const PILL_S:StyleRefinement = StyleRefinement.from({ size: [Length.px(40), Length.px(24)] });
        private static const CIRCLE_S:StyleRefinement = StyleRefinement.from({ size: [Length.px(40), Length.px(40)] });
        private static const PROG_S:StyleRefinement = StyleRefinement.from({ size: [Length.pct(1), Length.px(28)] });
        private static const CTRL_S:StyleRefinement = StyleRefinement.from({ size: [Length.px(200), Length.px(24)] });
        private static const SLIDER_S:StyleRefinement = StyleRefinement.from({ size: [Length.pct(1), Length.px(34)] });
        private static const FIELD_S:StyleRefinement = StyleRefinement.from({
            size: [Length.px(280), Length.px(38)], text: { fontSize: 13, color: 0x111827 }
        });
        private static const SIGNIN_S:StyleRefinement = StyleRefinement.from({
            size: [Length.px(280), Length.px(42)], background: 0x2563EB, border: 1,
            borderColor: 0x1D4ED8, cornerRadii: 8, text: { fontSize: 14, fontWeight: "bold", color: 0xFFFFFF }
        });
        private static const GHOST_S:StyleRefinement = StyleRefinement.from({
            size: [Length.px(130), Length.px(36)], background: 0xFFFFFF, border: 1,
            borderColor: 0xD1D5DB, cornerRadii: 8, text: { fontSize: 13, color: 0x374151 }
        });
        private static const DANGER_S:StyleRefinement = StyleRefinement.from({
            size: [Length.px(130), Length.px(36)], background: 0xDC2626, border: 1,
            borderColor: 0xB91C1C, cornerRadii: 8, text: { fontSize: 13, fontWeight: "bold", color: 0xFFFFFF }
        });
        private static const LIST_S:StyleRefinement = StyleRefinement.from({
            size: [Length.px(300), Length.px(280)], background: 0xF9FAFB
        });
        private static const ROWW_S:StyleRefinement = StyleRefinement.from({ width: 300 });
        private static const MOTION_S:StyleRefinement = StyleRefinement.from({
            size: [Length.px(180), Length.px(110)], cornerRadii: 10, border: 1, borderColor: 0xD1D5DB
        });

        // ---- page 4: the component catalog -----------------------------------
        // The 8x8 source of every image on that page. A STATIC (not per-render) so
        // the image widget sees the same object identity each pass -- a fresh
        // BitmapData per frame would read as "new pixels" and re-measure for ever.
        private static const SRC8:BitmapData = new BitmapData(8, 8, false, 0x3366CC);
        private static const CAT_H:StyleRefinement = StyleRefinement.from({ size: [Length.pct(1), Length.px(72)] });
        private static const CAT_SPIN_S:StyleRefinement = StyleRefinement.from({ size: [Length.pct(1), Length.px(56)] });
        private static const CAT_SK_S:StyleRefinement = StyleRefinement.from({ size: [Length.pct(1), Length.px(26)] });
        // No size: the tooltip's own measure() makes a bubble that fits its label
        // (and paint() centres the text), so pinning a box here would only be a
        // wider bubble with a hole in it.
        private static const CAT_TIP_S:StyleRefinement = StyleRefinement.from({});
        // 26 * 3 = 78: a header plus two rows, so the table has no dead strip under it.
        private static const CAT_TBL_S:StyleRefinement = StyleRefinement.from({ size: [Length.pct(1), Length.px(78)] });
        private static const CAT_ACC_S:StyleRefinement = StyleRefinement.from({ size: [Length.pct(1), Length.px(120)], gap: 2 });
        private static const CAT_PANEL_S:StyleRefinement = StyleRefinement.from({
            size: [Length.pct(1), Length.px(32)], background: 0xEAEAEA
        });
        private static const CAT_CRUMB_S:StyleRefinement = StyleRefinement.from({ size: [Length.pct(1), Length.px(20)] });
        private static const CAT_PAGE_S:StyleRefinement = StyleRefinement.from({ size: [Length.pct(1), Length.px(28)] });

        // ---- page 5: the floating layer --------------------------------------
        // The page BODY is ordinary layout; everything that floats comes from
        // renderOverlay() below, which is the toolkit's second retained tree. A
        // dialog is open on arrival so page 5 shows the scrim, the centred panel and
        // the toast stack without the tour clicking anything.
        private static const OVL_BTN_S:StyleRefinement = StyleRefinement.from({
            size: [Length.px(160), Length.px(34)], background: 0xFFFFFF, border: 1,
            borderColor: 0xD1D5DB, cornerRadii: 8, text: { fontSize: 13, color: 0x374151 }
        });
        // 264 x 80: the dialog's own arithmetic is 1+18+80+12+28+18+1 = 158 tall, so
        // the panel is centred at y = (560-158)/2 = 201 with no font metrics involved.
        private static const OVL_BODY_S:StyleRefinement = StyleRefinement.from({
            size: [Length.px(264), Length.px(80)], background: 0xF9FAFB
        });
        private static const OVL_OK_S:StyleRefinement = StyleRefinement.from({
            size: [Length.px(100), Length.px(28)], background: 0x2563EB, cornerRadii: 6,
            text: { fontSize: 13, fontWeight: "bold", color: 0xFFFFFF }
        });

        public var model:GalleryModel;
        // Evidence that page switching is driven by the widget, not by the tour
        // poking the model: every onChange callback lands here.
        public var switchCalls:int = 0;
        public var lastSwitch:int = -1;

        public function GalleryView(m:GalleryModel):void
        {
            super();
            this.model = m;
        }

        // ---- the one description --------------------------------------------
        override public function render():Node
        {
            var p:int = int(this.model.page);
            return column({ key: "root", style: PAGE, ariaName: "asaot.ui gallery" }, [
                text("asaot.ui", { key: "title", style: TITLE, ariaName: "Product" }),
                text("Pure-AS3 UI toolkit: described by a View, placed by the AS3 layout engine, painted by the AOT runtime.",
                    { key: "sub", style: SUB, ariaName: "Tagline" }),
                tabs(this.tabNames(), {
                    key: "tabs", style: TABS, gap: 8,
                    selectedIndex: bindTo(this.model, "page"),
                    onChange: this.pageChanged
                }),
                this.pageBody(p),
                text("page " + p + " of " + this.tabNames().length + "  -  " + this.model.status,
                    { key: "status", style: STATUS, ariaName: "Status" })
            ]);
        }

        // ONE list of page names: the tab strip renders it and the footer counter
        // reads it, so the count cannot drift from the pages again (it said "of 3"
        // while there were four tabs, and no assertion noticed).
        private function tabNames():Array
        {
            return ["Home", "Widgets", "Data", "Motion", "Catalog", "Overlay"];
        }

        // The per-frame hook. The Motion page's two boxes change colour on a wall
        // clock, so the tween is driven by time, not by frame count: on a 120Hz
        // machine it changes on the same real schedule as on 60Hz.
        override public function tick(nowMs:Number):void
        {
            var next:int = int(Math.floor(nowMs / 900)) % 2;
            if (next == this.model.phase) return;
            this.model.phase = next;
            // Only repaint for a page that shows the phase. Elsewhere the change is
            // recorded and simply takes effect the next time that page is built.
            if (int(this.model.page) == 3) this.invalidate(Dirty.VALUE);
        }

        private function pageBody(p:int):Node
        {
            if (p == 0) return this.homePage();
            if (p == 2) return this.dataPage();
            if (p == 3) return this.motionPage();
            if (p == 4) return this.catalogPage();
            if (p == 5) return this.overlayPage();
            return this.widgetsPage();
        }

        // ---- page 0: Home ---------------------------------------------------
        private function homePage():Node
        {
            return column({ key: "body", style: BODY, ariaName: "Home page" }, [
                card({ key: "loginCard", style: CARD_H }, [
                    text("Sign in", { key: "loginTitle", style: CARD_TITLE }),
                    textField({
                        key: "account", style: FIELD_S, ariaName: "Account",
                        placeholder: "Account or email", value: bindTo(this.model, "account")
                    }),
                    textField({
                        key: "password", style: FIELD_S, ariaName: "Password", password: true,
                        placeholder: "Password", value: bindTo(this.model, "password")
                    }),
                    checkbox({
                        key: "remember", ariaName: "Remember me",
                        label: "Keep me signed in", checked: bindTo(this.model, "remember")
                    }),
                    button({ key: "signin", style: SIGNIN_S, ariaName: "Sign in", label: "Sign in", onClick: this.signIn })
                ]),
                note("Two-way bound: typing updates the model, and the model updates the field.", "homeNote"),
                note("The tabs above switch pages through model.page; each page reuses the SAME body slot.", "homeNote2")
            ]);
        }

        // ---- page 1: the widget gallery -------------------------------------
        private function widgetsPage():Node
        {
            return row({ key: "body", style: ROWBODY, ariaName: "Widget gallery" }, [
                column({ key: "colA", style: COL, ariaName: "Column A" }, [
                    card({ key: "cardChips", style: CARD_G }, [
                        text("Chips & badges", { key: "chipsTitle", style: CARD_TITLE }),
                        row({ key: "chipRow", style: ROW36 }, [
                            chip("Neutral", { key: "c1", style: CHIP_S, tone: "neutral" }),
                            chip("Info", { key: "c2", style: CHIP_S, tone: "info" }),
                            chip("Danger", { key: "c3", style: CHIP_S, tone: "danger" })
                        ]),
                        row({ key: "badgeRow", style: ROW36 }, [
                            badge("3", { key: "b1", style: PILL_S, tone: "neutral" }),
                            badge("12", { key: "b2", style: PILL_S, tone: "info" }),
                            badge("99", { key: "b3", style: PILL_S, tone: "danger" })
                        ])
                    ]),
                    card({ key: "cardControls", style: CARD_G2 }, [
                        text("Controls", { key: "ctrlTitle", style: CARD_TITLE }),
                        row({ key: "ctrlRow", style: ROW36 }, [
                            radio("Standard", { key: "r1", style: CTRL_S, selected: bindTo(this.model, "notify"), group: "ship" }),
                            radio("Express", { key: "r2", style: CTRL_S, selected: false, group: "ship" })
                        ]),
                        row({ key: "swRow", style: ROW36 }, [
                            toggle("Wifi", { key: "t1", style: CTRL_S, checked: bindTo(this.model, "wifi") }),
                            toggle("Off", { key: "t2", style: CTRL_S, checked: false })
                        ]),
                        slider("Volume", { key: "sl", style: SLIDER_S, value: bindTo(this.model, "volume") })
                    ])
                ]),
                column({ key: "colB", style: COL, ariaName: "Column B" }, [
                    card({ key: "cardAvatars", style: CARD_G3 }, [
                        text("Avatars & progress", { key: "avTitle", style: CARD_TITLE }),
                        row({ key: "avRow", style: ROW36 }, [
                            avatar("Ada Lovelace", { key: "a1", style: CIRCLE_S, tone: "neutral" }),
                            avatar("Grace Hopper", { key: "a2", style: CIRCLE_S, tone: "info" }),
                            avatar("Alan Turing", { key: "a3", style: CIRCLE_S, tone: "neutral" })
                        ]),
                        progress("Low", { key: "p1", style: PROG_S, value: 0.25 }),
                        progress("Full", { key: "p2", style: PROG_S, value: 1 })
                    ]),
                    card({ key: "cardActions", style: CARD_G4 }, [
                        text("Actions", { key: "actTitle", style: CARD_TITLE }),
                        button({ key: "ok", style: SIGNIN_S, ariaName: "Primary", label: "Primary action", onClick: this.primaryClicked }),
                        row({ key: "btnRow", style: ROW36 }, [
                            button({ key: "ghost", style: GHOST_S, ariaName: "Secondary", label: "Secondary", onClick: this.secondaryClicked }),
                            button({ key: "del", style: DANGER_S, ariaName: "Danger", label: "Danger", onClick: this.dangerClicked })
                        ]),
                        divider({ key: "hair", orientation: "horizontal" }),
                        note("25 widget kinds registered.", "actNote")
                    ])
                ])
            ]);
        }

        // ---- page 2: Data (the list) -----------------------------------------
        private function dataPage():Node
        {
            var i:int = int(this.model.listIndex);
            var picked:String = i >= 0 && i < this.model.items.length ? String(this.model.items[i]) : "(none)";
            return row({ key: "body", style: ROWBODY, ariaName: "Data page" }, [
                list(this.model.items, this.buildRow, {
                    key: "list", style: LIST_S, separator: true, itemHeight: 40,
                    selectedIndex: bindTo(this.model, "listIndex"),
                    onSelect: this.rowSelected
                }),
                column({ key: "detailCol", style: COL, ariaName: "Detail" }, [
                    card({ key: "detailCard", style: CARD }, [
                        text("Selection", { key: "dataTitle", style: CARD_TITLE }),
                        text("Selected: " + picked, { key: "picked", style: NOTE, ariaName: "Selected item" }),
                        note("Engine places every row; a click writes back.", "dataNote")
                    ])
                ])
            ]);
        }

        // ---- page 4: the component catalog ----------------------------------
        // The widgets the other four pages never showed -- the media, feedback and
        // data groups -- on two 320px flex columns (the same geometry page 1 uses, so
        // the tour's column rects are shared). Every size is explicit: this page is
        // photographed (gallery-page4.png) and its rect report is the text half of
        // that evidence.
        private function catalogPage():Node
        {
            return row({ key: "body", style: ROWBODY, ariaName: "Component catalog" }, [
                column({ key: "colM", style: COL, ariaName: "Media and feedback" }, [
                    image({ key: "catImg", style: CAT_H, bitmapData: SRC8, scaleMode: "fit", smooth: false }),
                    spinner({ key: "catSpin", style: CAT_SPIN_S, tone: "info", spin: true }),
                    skeleton({ key: "catSk", style: CAT_SK_S, variant: "rect", tone: 0xE5E7EB }),
                    tooltip("Saved", { key: "catTip", style: CAT_TIP_S, arrow: "up" })
                ]),
                column({ key: "colD", style: COL, ariaName: "Data" }, [
                    table([{ key: "name", title: "Name" }, { key: "qty", title: "Qty" }],
                          [{ name: "Widget", qty: 3 }, { name: "Gadget", qty: 12 }],
                          { key: "catTable", style: CAT_TBL_S, rowHeight: 26, stripes: true, grid: true,
                            selectedIndex: bindTo(this.model, "compRow") }),
                    accordion([{ title: "General", content: box({ key: "catP0", style: CAT_PANEL_S }) },
                               { title: "Advanced", content: box({ key: "catP1", style: CAT_PANEL_S }) }],
                              { key: "catAcc", style: CAT_ACC_S,
                                activeIndex: bindTo(this.model, "compOpen") }),
                    breadcrumb(["Library", "Data", "Raw"], { key: "catCrumb", style: CAT_CRUMB_S }),
                    pagination(3, 20, { key: "catPage", style: CAT_PAGE_S, windowSize: 7,
                                        page: bindTo(this.model, "compPage") })
                ])
            ]);
        }

        // ---- page 5: the floating layer --------------------------------------
        // The second tree is rebuilt from this description on every reflow, and it is
        // NULL on every other page -- which is what proves the layer is torn down
        // rather than merely hidden (the tour checks the keys are GONE).
        override public function renderOverlay():Node
        {
            if (int(this.model.page) != 5) return null;
            var m:GalleryModel = this.model;
            // Method references, not closures: an anonymous function is supported,
            // but a named handler keeps the wiring readable and is what every other
            // page already does (the tabs widget takes this.pageChanged).
            var d:Node = dialog({
                key: "ovlDlg", open: m.ovlDlg, width: 300, title: "Unsaved changes",
                footer: [ box({ key: "ovlOk", style: OVL_OK_S, ariaName: "ok" }) ],
                onClose: this.ovlDlgClosed
            }, [
                box({ key: "ovlDlgBody", style: OVL_BODY_S, ariaName: "dialog body" })
            ]);
            var mn:Node = menu({
                key: "ovlMenu", open: m.ovlMenu, anchorKey: "ovlBtn",
                placement: "bottom", offset: 6, width: 160,
                items: ["Rename", "Duplicate", "Delete"], selectedIndex: -1,
                onSelect: this.ovlMenuPicked,
                onClose: this.ovlMenuClosed
            });
            var ts:Node = toastHost({ key: "ovlToasts" }, [
                toast({ key: "ovlT1", open: m.ovlToast, message: "Draft saved", tone: "success",
                        onClose: this.ovlToastClosed })
            ]);
            return overlay([d, mn, ts]);
        }

        private function overlayPage():Node
        {
            return column({ key: "body", style: BODY, ariaName: "Overlay page" }, [
                text("Six floating surfaces in a SECOND retained tree: the page below never re-lays out when one opens.",
                    { key: "ovlNote", style: NOTE }),
                row({ key: "ovlRow", style: ROW }, [
                    button({ key: "ovlBtn", label: "Actions", style: OVL_BTN_S,
                             onClick: this.ovlMenuClicked })
                ]),
                note("The dialog, the menu and the toast are author-owned: `open` lives in the model.", "ovlNote2")
            ]);
        }

        private function ovlDlgClosed():void
        {
            this.model.ovlDlg = false;
            this.invalidate(Dirty.VALUE);
        }

        private function ovlMenuClosed():void
        {
            this.model.ovlMenu = false;
            this.invalidate(Dirty.VALUE);
        }

        private function ovlMenuPicked(i:int):void
        {
            // Choosing an item closes the menu; the selection itself is not kept on
            // this page (the menu is here to show the floating layer, not to edit a
            // model value).
            this.model.ovlMenu = false;
            this.invalidate(Dirty.VALUE);
        }

        private function ovlToastClosed():void
        {
            this.model.ovlToast = false;
            this.invalidate(Dirty.VALUE);
        }

        private function ovlMenuClicked():void
        {
            this.model.ovlMenu = !this.model.ovlMenu;
            this.invalidate(Dirty.VALUE);
        }

        public function buildRow(item:Object, index:int):Node
        {
            return row({ key: "row" + index, style: ROWW_S, ariaName: "Row" }, [
                text("Item " + index + ": " + String(item), { key: "rowtext" + index, style: NOTE })
            ]);
        }

        // ---- page 3: Motion (the animation surface) --------------------------
        private function motionPage():Node
        {
            var hot:uint = this.model.phase == 0 ? 0x2563EB : 0x16A34A;
            return column({ key: "body", style: BODY, ariaName: "Motion page" }, [
                text("Two boxes, one transition. The colour flips every 900ms on the wall clock.",
                    { key: "motionNote", style: NOTE }),
                row({ key: "motionRow", style: ROW }, [
                    box({ key: "animated", style: this.motionStyle(hot, 700) }),
                    box({ key: "snapped", style: this.motionStyle(0xE5E7EB, 0) })
                ]),
                note("Left: transitionMs 700, outCubic -- it eases. Right: no transitionMs -- it snaps.", "motionNote2")
            ]);
        }

        // A fresh refinement per render is fine: render only runs on a DIRTY
        // frame, so this is not a steady-state allocation. The identity test in
        // the resolver exists for static constants, and the two boxes below are
        // the deliberate exception.
        private function motionStyle(color:uint, ms:Number):StyleRefinement
        {
            var o:Object = { size: [180, 110], cornerRadii: 10, border: 1, borderColor: 0xD1D5DB, background: color };
            if (ms > 0)
            {
                o.transitionMs = ms;
                o.transitionEase = "outCubic";
            }
            return StyleRefinement.from(o);
        }

        private function note(s:String, key:String):Node
        {
            return text(s, { key: key, style: NOTE });
        }

        // ---- handlers --------------------------------------------------------
        private function pageChanged(i:int):void
        {
            this.switchCalls = this.switchCalls + 1;
            this.lastSwitch = i;
        }

        private function rowSelected(i:int):void
        {
            this.model.status = "selected " + i;
        }

        private function primaryClicked():void
        {
            this.model.status = "primary clicked";
            this.invalidate(Dirty.VALUE);
        }

        private function secondaryClicked():void
        {
            this.model.status = "secondary clicked";
            this.invalidate(Dirty.VALUE);
        }

        private function dangerClicked():void
        {
            this.model.status = "danger clicked";
            this.invalidate(Dirty.VALUE);
        }

        private function signIn():void
        {
            var who:String = this.model.account;
            if (who == null || who.length == 0) who = "(no account)";
            this.model.status = "signing in as " + who;
            this.invalidate(Dirty.VALUE);
        }
    }
}

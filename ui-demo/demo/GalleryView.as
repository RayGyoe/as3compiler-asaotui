// demo/GalleryView.as -- the multi-page demo's view: a four-page app whose page
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
    import asaot.ui.avatar;
    import asaot.ui.badge;
    import asaot.ui.bindTo;
    import asaot.ui.box;
    import asaot.ui.button;
    import asaot.ui.card;
    import asaot.ui.checkbox;
    import asaot.ui.chip;
    import asaot.ui.column;
    import asaot.ui.divider;
    import asaot.ui.list;
    import asaot.ui.progress;
    import asaot.ui.radio;
    import asaot.ui.row;
    import asaot.ui.slider;
    import asaot.ui.tabs;
    import asaot.ui.text;
    import asaot.ui.textField;
    import asaot.ui.toggle;
    import asaot.ui.style.Length;
    import asaot.ui.style.StyleRefinement;

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
                tabs(["Home", "Widgets", "Data", "Motion"], {
                    key: "tabs", style: TABS, gap: 8,
                    selectedIndex: bindTo(this.model, "page"),
                    onChange: this.pageChanged
                }),
                this.pageBody(p),
                text("page " + p + " of 3  -  " + this.model.status,
                    { key: "status", style: STATUS, ariaName: "Status" })
            ]);
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
                        note("16 widget kinds registered.", "actNote")
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

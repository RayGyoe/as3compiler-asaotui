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
    import asaot.ui.Dirty;
    import asaot.ui.Env;
    import asaot.ui.EnvBase;
    import asaot.ui.I18n;
    import asaot.ui.Node;
    import asaot.ui.OverlayChrome;
    import asaot.ui.UiApp;
    import asaot.ui.UiNode;
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
    import asaot.ui.style.Style;
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

        // ---- the live page's two inputs ---------------------------------
        // THE MARKET. One per view (not a static), so the docs app and a second
        // instance in the same process -- the tour's and a probe's -- cannot share
        // tick state.
        public var market:LiveMarket;
        // THE APP, for its pass counters. Set by the entry point after `mount()`;
        // null until then, and every read below tolerates that (the first frame is
        // described before an entry point can hand it over).
        public var app:UiApp;

        // What the live page prints, sampled once a second by frameTick(). Deliberately
        // plain public numbers: the page reads them like any other model value, and a
        // probe can read them without a setter.
        public var fps:int = 0;
        public var nodeCount:int = 0;
        public var describesPerSec:int = 0;
        public var paintsPerSec:int = 0;
        // Per-pass averages in MILLISECONDS, over the passes that actually ran in the
        // last second. `getTimer()` is integer ms, so one frame's solve reads 0 or 1;
        // dividing a SUM by a COUNT is the only way to see a sub-millisecond phase
        // from an integer clock -- the same arithmetic the `perf` probe uses.
        public var solveMs:Number = 0;
        public var paintMs:Number = 0;
        // Has the once-a-second sample run at all? A rate needs an INTERVAL, and the
        // first frame has none -- so the page prints a dash rather than a zero. "0 fps"
        // would be a number the app never measured, and it reads as a dead demo; a
        // static capture (the tour's screenshots) is exactly the case that shows it.
        public var sampled:Boolean = false;
        // Changes only when the once-a-second values above change. Live regions use
        // this instead of the 100ms market tick, so stats do not rebuild 10x/second.
        internal var liveStatsVersion:int = 0;

        private var _lastStep:int = 0;
        private var _frames:int = 0;
        private var _nodeSeeded:Boolean = false;
        private var _secStart:int = 0;
        private var _d0:int = 0;
        private var _p0:int = 0;
        private var _s0:Number = 0;
        private var _l0:int = 0;
        private var _q0:Number = 0;
        private var _pa0:int = 0;
        // The env the app was using before this page put a simulated phone in front
        // of it. Null = no simulation installed.
        private var _realEnv:Env;

        public function DocsView(m:DocsModel):void
        {
            super();
            this.model = m;
            this.market = new LiveMarket();
        }

        // ---- the frame clock the live page rides ----------------------------
        // Called from ONE ENTER_FRAME listener in the entry point (all three arms),
        // never from render(): a describe pass must not advance data, or a reflow
        // caused by a resize would move the market too.
        //
        // TWO DUTIES, one function: (a) once a second, publish what the app actually
        // did -- frames drawn, nodes retained, describe/paint passes -- and (b) while
        // the live page is on screen and the market is running, step it every
        // LiveMarket.TICK_MS and notify. Nothing else in the app ticks.
        public function frameTick(now:int):void
        {
            if (this._secStart == 0)
            {
                this._secStart = now;
                if (this.app != null) this.sample();
            }
            // The node count is a fact about the tree, not a rate, so it is available
            // before any interval has elapsed -- and it is walked ONCE here, not every
            // tick: the real loop reaches the once-a-second sample a moment later.
            // (A capture that says "0 nodes" is worse than no capture at all.)
            if (!this._nodeSeeded && this.app != null)
            {
                var first:UiNode = this.app.getRoot();
                this.nodeCount = first == null ? 0 : countNodes(first);
                this._nodeSeeded = true;
                this.liveStatsVersion = this.liveStatsVersion + 1;
            }
            this._frames = this._frames + 1;

            // The simulated phone belongs to ONE page. Leaving it must restore the
            // platform, or every page after it would lay out under a notch that is
            // not there -- and the tour's fixed rects would (correctly) go red.
            if (this._realEnv != null && this.model.doc != "gesture") this.restoreEnv();

            if (now - this._secStart >= 1000)
            {
                var span:int = now - this._secStart;
                if (span < 1) span = 1;
                this.fps = int(Math.round(this._frames * 1000 / span));
                if (this.app != null)
                {
                    this.describesPerSec = this.app.describeCalls - this._d0;
                    this.paintsPerSec = this.app.paintPasses - this._p0;
                    var solves:int = this.app.layoutSolves - this._l0;
                    var paints:int = this.app.paintPasses - this._pa0;
                    this.solveMs = solves > 0 ? round2((this.app.profSolveMs - this._s0) / solves) : 0;
                    this.paintMs = paints > 0 ? round2((this.app.profPaintMs - this._q0) / paints) : 0;
                    this.sample();
                }
                this._frames = 0;
                this._secStart = now;
                // The node count walks the retained tree, which is why it is a
                // once-a-second job and not a per-frame one.
                var root:UiNode = this.app == null ? null : this.app.getRoot();
                this.nodeCount = root == null ? 0 : countNodes(root);
                // From here on the rates are measured, not assumed.
                this.sampled = true;
                this.liveStatsVersion = this.liveStatsVersion + 1;
                // The counters themselves are model values: repaint so the page
                // shows THIS second's numbers rather than last second's.
                if (this.model.doc == "live") this.model.notify(Dirty.VALUE);
            }

            // The two phase timers are off by default (one boolean test per phase in a
            // shipping app). This page is the one that reads them, so it is the one that
            // turns them on -- and turns them back off on the way out.
            if (this.app != null) UiApp.profile = (this.model.doc == "live");

            if (this.model.doc != "live") return;
            if (!this.model.bool("live.run", true)) return;
            if (now - this._lastStep < LiveMarket.TICK_MS) return;
            this._lastStep = now;
            this.market.step();
            this.model.notify(Dirty.VALUE);
        }

        // DocsLive is a package-internal builder, not a View subclass. Keep the
        // protected View cache encapsulated while giving its independent regions
        // one namespaced slot family.
        internal function memoLive(key:String, version:*, build:Function):Node
        {
            return this.memo("live:" + key, version, build);
        }

        // Take the baseline for the next second's deltas.
        private function sample():void
        {
            if (this.app == null) return;
            this._d0 = this.app.describeCalls;
            this._p0 = this.app.paintPasses;
            this._l0 = this.app.layoutSolves;
            this._pa0 = this.app.paintPasses;
            this._s0 = this.app.profSolveMs;
            this._q0 = this.app.profPaintMs;
        }

        private static function round2(v:Number):Number
        {
            return Math.round(v * 100) / 100;
        }

        // ---- the simulated phone (the gesture page's last section) -----------
        // This is not a mock of the Env interface: it IS an EnvBase, the same
        // writable record a real iOS shell fills in, handed to the same one entry
        // point (`UiApp.bindEnv`). What the reader sees change -- the root padding,
        // the hover branches -- is the production path.
        public function simulatePhone():void
        {
            if (this.app == null || this._realEnv != null) return;
            var e:EnvBase = new EnvBase();
            e.setSafeArea(44, 0, 34, 0);   // a notch above, a home indicator below
            e.setPixelRatio(3);
            e.setHasTouch(true);
            e.setHasHover(false);
            this._realEnv = this.app.env;
            this.app.bindEnv(e);
            this.model.notify(Dirty.THEME);
        }

        public function restoreEnv():void
        {
            if (this.app == null || this._realEnv == null) return;
            this.app.bindEnv(this._realEnv);
            this._realEnv = null;
            this.model.notify(Dirty.THEME);
        }

        public function isSimulated():Boolean
        {
            return this._realEnv != null;
        }

        private function countNodes(n:UiNode):int
        {
            var total:int = 1;
            var kids:Vector.<UiNode> = n.children;
            if (kids == null) return total;
            for (var i:int = 0; i < kids.length; i++) total = total + countNodes(kids[i]);
            return total;
        }

        // ---- the whole window -------------------------------------------------
        override public function render():Node
        {
            // The shell's own strings are localized too, and one of them (the meta
            // line) goes through I18n's PLURAL path -- so the demo's chrome
            // messages have to be registered before the first one is read. Idempotent.
            DemoText.ensure();
            var p:DocPage = DocsCatalog.page(this.model.doc);
            if (p == null) p = DocPage(DocsCatalog.pages()[0]);
            var secs:Array = DocsCatalog.sections(this, p.id);
            // A page whose builder has nothing yet renders an empty content pane
            // rather than crashing: the tour walks EVERY page, so a missing
            // builder must be a visible empty page, not a null dereference.
            if (secs == null) secs = [];
            // THE GROUP NAME IS DATA in DocsCatalog (it is the sidebar's heading and
            // half of this line), so it is translated at the point of use rather than
            // stored localized -- the catalog is built once, per process.
            var group:String = DemoText.t(String(DocsCatalog.GROUPS[p.group]));
            // `tn` for the count: English has two forms ("1 example" / "3 examples")
            // and this line used to glue the suffix on in code. Chinese has one, and
            // the `#other` row is what it lands on.
            var meta:String = I18n.tn("demo.meta", secs.length,
                { kind: p.id, group: group.toLowerCase() });

            // row(), not column(): box() honours the style's flexDirection, but row()
            // also PINS the axis, so the two panes cannot be stacked by a later patch.
            // The navigation subtree depends only on the selected page. Do not build
            // its rows and click closures again for every live quote / window resize.
            var self:DocsView = this;
            return row({ key: "root", style: DocsStyle.ROOT,
                         ariaName: DemoText.t("asaot.ui documentation") }, [
                this.memo("sidebar", p.id, function ():Node { return self.sidebar(p); }),
                column({ key: "main", style: DocsStyle.MAIN,
                         ariaName: DemoText.t("Component page") }, [
                    // THE API NAME IS NOT TRANSLATED: `textField` is the factory's own
                    // spelling, and the page's whole job is to say what it looks like.
                    text(p.title, { key: "docTitle", style: DocsStyle.DOC_TITLE,
                                    ariaName: DemoText.t("Component") }),
                    text(DemoText.t(p.blurb), { key: "docBlurb", style: DocsStyle.DOC_BLURB,
                                                ariaName: DemoText.t("Summary") }),
                    text(meta, { key: "docMeta", style: DocsStyle.DOC_META,
                                 ariaName: DemoText.t("Details") }),
                    // `scrollbarGutter: "stable"` -- the page's cards are `pct(1)`, so the
                    // bar gets its own 10px lane and never sits on a code block's last
                    // column. See ScrollViewNode's header for why this is a switch.
                    scrollView({ key: "docScroll", style: DocsStyle.DOC_SCROLL,
                                 scrollbarGutter: "stable",
                                 barThickness: DocsStyle.DOC_GUTTER,
                                 // `never` on the cross axis: a reading column does not
                                 // scroll sideways, and a reserved BOTTOM lane would
                                 // spare a bar that can never appear.
                                 scrollbarX: "never", wheelStep: 40 }, [
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
                    rows.push(text(DemoText.t(String(DocsCatalog.GROUPS[group])),
                        { key: "navg" + group, style: DocsStyle.NAV_GROUP, ariaName: "" }));
                    h = h + DocsStyle.NAV_H_GROUP;
                }
                rows.push(this.navItem(p, p.id == cur.id));
                h = h + DocsStyle.NAV_H_ITEM;
            }

            var colStyle:StyleRefinement = DocsStyle.NAV_COL.withPatch(
                StyleRefinement.from({ size: [Length.pct(1), Length.px(h)] }));

            return column({ key: "side", style: DocsStyle.SIDE,
                            ariaName: DemoText.t("Index") }, [
                // THE PRODUCT NAME IS NOT TRANSLATED ("asaot.ui" is a name), but the
                // tagline, the group headings, the footer and the accessible names
                // around them are.
                text("asaot.ui", { key: "brand", style: DocsStyle.BRAND,
                                   ariaName: DemoText.t("Product") }),
                text(DemoText.t("pure-AS3 UI toolkit"), { key: "tag", style: DocsStyle.TAG,
                                                           ariaName: DemoText.t("Tagline") }),
                scrollView({ key: "nav", style: DocsStyle.NAV,
                             scrollbarGutter: "stable",
                             barThickness: DocsStyle.DOC_GUTTER,
                             scrollbarX: "never", wheelStep: 26 }, [
                    column({ key: "navCol", style: colStyle }, rows)
                ]),
                // THE LANGUAGE SWITCHER, always in the same place: the app's own text
                // is what it switches, so a reader who cannot read the current
                // language must not have to find a page first. Each entry says the
                // language in ITS OWN language -- translating "中文" would defeat it.
                row({ key: "langs", style: DocsStyle.LANGS,
                      ariaName: DemoText.t("Language") }, [
                    this.langBtn("en", "EN"),
                    this.langBtn("zh-CN", "中文"),
                    this.langBtn("ar", "AR")
                ]),
                text(I18n.t("demo.foot", { n: pages.length }),
                    { key: "foot", style: DocsStyle.FOOT, ariaName: "" })
            ]);
        }

        // One language button. `I18n.setLocale` is the whole body: it bumps the
        // epoch, UiApp turns the epoch into one describe at the next frame boundary,
        // and DemoText rebuilds its table on the first lookup of that describe. No
        // model write, no invalidate call -- a locale is not this app's data.
        private function langBtn(tag:String, label:String):Node
        {
            var on:Boolean = I18n.locale().toLowerCase() == tag.toLowerCase();
            return button({
                key: "lang:" + tag, label: label,
                style: on ? DocsStyle.LANG_ITEM_ON : DocsStyle.LANG_ITEM,
                ariaName: DemoText.t("Language") + ": " + label,
                onClick: function ():void { I18n.setLocale(tag); }
            });
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

        // A body line inside a fixed-width SURFACE. The kit's `whiteSpace: "normal"`
        // needs a POINT width (it refuses a percent: the wrapped height has to exist at
        // measure time), and a panel gives its children none -- so a body text used to
        // be laid out at its natural width and print straight out of the panel on both
        // sides. The width here is the panel's own content box.
        //
        // Height stays AUTO: the node publishes its WRAPPED height, so the panel grows
        // with the number of lines instead of clipping the last one.
        private function barBody(s:String, key:String, panelW:Number, panel:Style,
                                  size:Number, color:uint):Node
        {
            var inner:Number = DocsStyle.panelInnerWidth(panelW, panel);
            return text(s, { key: key, ariaName: "", style: StyleRefinement.from({
                size: [inner, null],
                text: { fontSize: size, color: color, whiteSpace: "normal" } }) });
        }

        // The stage width THIS describe is for. render() also runs on the first
        // frame, before the window exists, where the stage still reports 0 -- the
        // descriptor size is then the only answer, and the frame after picks up the
        // real one.
        private function stageW():Number
        {
            if (this.app != null && this.app.stage != null && this.app.stage.stageWidth > 0)
                return this.app.stage.stageWidth;
            return DocsStyle.W;
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
            // ONE reading width for the whole column, read from the stage this frame
            // is being described for: the prose breaks where the pane ends, and a
            // window resize re-describes (UiApp invalidates STRUCTURE on a size
            // change), so the breaks follow the window.
            var wrapW:Number = DocsStyle.docWrapW(this.stageW());
            for (var i:int = 0; i < secs.length; i++)
            {
                var sec:DocSection = DocSection(secs[i]);
                blocks.push(this.block(sec, i, wrapW));
                h = h + sec.height(wrapW);
                if (i > 0) h = h + DocsStyle.SEC_GAP;
            }
            // A short page still fills the viewport, so the column's height is never 0
            // (a scrollView refuses a container child with no height).
            if (h < DocsStyle.DOC_VIEW_H) h = DocsStyle.DOC_VIEW_H;
            var style:StyleRefinement = DocsStyle.DOC_COL.withPatch(
                StyleRefinement.from({ size: [Length.pct(1), Length.px(h)] }));
            return column({ key: "docCol", style: style, ariaName: "" }, blocks);
        }

        private function block(sec:DocSection, i:int, wrapW:Number):Node
        {
            var pre:String = "b" + i;
            var kids:Array = [];
            kids.push(text(sec.heading, { key: pre + ":h", style: DocsStyle.SEC_HEAD, ariaName: "" }));

            var para:Array = sec.proseLines(wrapW);
            if (para.length > 0)
            {
                var self:DocsView = this;
                kids.push(this.memo("prose:" + this.model.doc + ":" + i, wrapW, function ():Node
                {
                    var lines:Array = [];
                    for (var j:int = 0; j < para.length; j++)
                    {
                        lines.push(text(String(para[j]),
                            { key: pre + ":p" + j, style: DocsStyle.PROSE, ariaName: "" }));
                    }
                    var proseStyle:StyleRefinement = StyleRefinement.from({
                        flexDirection: "column", gap: 0,
                        size: [Length.pct(1), Length.px(para.length * DocsStyle.SEC_PROSE_H)]
                    });
                    return column({ key: pre + ":prose", style: proseStyle, ariaName: "" }, lines);
                }));
            }

            var demoStyle:StyleRefinement = (sec.wide ? DocsStyle.DEMO_BLEED : DocsStyle.DEMO).withPatch(
                StyleRefinement.from({ size: [Length.pct(1), Length.px(sec.demoH)] }));
            var demoNode:Node = sec.build();
            kids.push(box({ key: pre + ":demo", style: demoStyle, ariaName: DemoText.t("Example") },
                demoNode == null ? [] : [demoNode]));

            // DocSection.code is static source text (see DocSection's data-only
            // contract); only the demo subtree above is model-live.
            kids.push(this.memo("code:" + this.model.doc + ":" + i, 0, function ():Node
            {
                var code:Array = [];
                for (var c:int = 0; c < sec.code.length; c++)
                {
                    code.push(text(String(sec.code[c]),
                        { key: pre + ":c" + c, style: DocsStyle.CODE_LINE, ariaName: "" }));
                }
                var codeStyle:StyleRefinement = DocsStyle.CODE.withPatch(
                    StyleRefinement.from({ size: [Length.pct(1), Length.px(sec.codeHeight())] }));
                return box({ key: pre + ":code", style: codeStyle, ariaName: DemoText.t("Source") }, code);
            }));

            var blockStyle:StyleRefinement = DocsStyle.SEC.withPatch(
                StyleRefinement.from({ size: [Length.pct(1), Length.px(sec.height(wrapW))] }));
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
                    barBody("The overlay tree is reconciled on top of render()'s tree.",
                        "ovPopBody", 230, OverlayChrome.POPOVER_PANEL, 12, 0x334155)
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
                    barBody("This cannot be undone.", "demoDlgBody", 320,
                        OverlayChrome.DIALOG_PANEL, 13, 0x4B5563)
                ]));
            }
            if (m.doc == "drawer" && m.bool("drw.open", false))
            {
                nodes.push(drawer({
                    key: "demoDrw", open: true, side: "right", size: 280, title: "Filters",
                    onClose: function ():void { m.put("drw.open", false); }
                }, [
                    barBody("A right-edge sheet over a scrim: the page behind it is not re-laid out.",
                        "demoDrwBody", 280, OverlayChrome.DRAWER_PANEL, 13, 0x374151)
                ]));
            }
            if (m.doc == "popover" && m.bool("pop.open", false))
            {
                nodes.push(popover({
                    key: "demoPop", open: true, anchorKey: "popBtn", placement: "bottom",
                    offset: 8, width: 220,
                    onClose: function ():void { m.put("pop.open", false); }
                }, [
                    barBody("Anchored to popBtn by KEY, so it survives a reconcile.",
                        "demoPopBody", 220, OverlayChrome.POPOVER_PANEL, 12, 0x374151)
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
            if (m.doc == "dialog" && m.bool("dlg2.open", false))
            {
                // closeOnScrim: false -- the scrim still absorbs the press, it just does
                // not report a close. Escape and the panel's own buttons remain.
                nodes.push(dialog({
                    key: "demoDlg2", open: true, width: 300, title: "Rename the file",
                    closeOnScrim: false,
                    footer: [
                        button({ key: "demoDlg2No", label: "Discard",
                                 onClick: function ():void { m.put("dlg2.open", false); } }),
                        button({ key: "demoDlg2Yes", label: "Save",
                                 style: StyleRefinement.from({
                                     background: 0x2563EB, borderColor: 0x1D4ED8,
                                     text: { color: 0xFFFFFF, fontWeight: "bold" } }),
                                 onClick: function ():void { m.put("dlg2.open", false); } })
                    ],
                    onClose: function ():void { m.put("dlg2.open", false); }
                }, [
                    barBody("A press on the scrim is ignored here; the two buttons and Escape are the exits.",
                        "demoDlg2Body", 300, OverlayChrome.DIALOG_PANEL, 13, 0x4B5563)
                ]));
            }
            if (m.doc == "drawer" && m.bool("drw2.open", false))
            {
                // The bottom sheet: `size` is the HEIGHT on this axis.
                nodes.push(drawer({
                    key: "demoDrw2", open: true, side: "bottom", size: 160, title: "Share",
                    onClose: function ():void { m.put("drw2.open", false); }
                }, [
                    // The bottom sheet spans the window, so its inner width is not a
                    // constant -- it is read off the stage this frame is described for.
                    barBody("A bottom sheet spans the window's width; its `size` is a height.",
                        "demoDrw2Body", this.stageW(), OverlayChrome.DRAWER_PANEL, 13, 0x374151)
                ]));
            }
            if (m.doc == "popover" && m.bool("pop2.open", false))
            {
                nodes.push(popover({
                    key: "demoPop2", open: true, anchorKey: "demoPop2Btn", placement: "bottom",
                    offset: 8, width: 230, closeOnOutside: false,
                    onClose: function ():void { m.put("pop2.open", false); }
                }, [
                    column({ gap: 6 }, [
                        barBody("No outside press closes this one.", "demoPop2Body", 230,
                            OverlayChrome.POPOVER_PANEL, 12, 0x374151),
                        button({ key: "demoPop2Done", label: "Done",
                                 onClick: function ():void { m.put("pop2.open", false); } })
                    ])
                ]));
            }
            if (m.doc == "menu" && m.bool("mnu2.open", false))
            {
                nodes.push(menu({
                    key: "demoMnu2", open: true, anchorKey: "mnu2Btn", placement: "bottom",
                    offset: 8, width: 180, selectedIndex: -1, submenuIndex: 1,
                    items: ["Rename",
                            { label: "Move to", submenu: ["Inbox", "Archive"] },
                            "Delete"],
                    onSelect: function (i:int):void { m.put("mnu2.pick", i); m.put("mnu2.open", false); },
                    onClose: function ():void { m.put("mnu2.open", false); }
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
                // `tone` is the TOAST vocabulary (default / success / danger) -- not the
                // chip vocabulary this demo was first written with. "info" is a chip
                // tone and toast.as THROWS on anything outside its three, which is what
                // made this page print 'unknown tone' on every frame after the click
                // (2026-10-24). The two toasts stay on DIFFERENT tones on purpose: that
                // is what makes the stack readable in a screenshot.
                nodes.push(toastHost({ key: "demoToasts" }, [
                    toast({ key: "demoToast1", open: true, message: "Two files moved",
                            tone: "default", duration: 4000,
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

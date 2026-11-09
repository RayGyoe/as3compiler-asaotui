// DocsMain.as -- the documentation app as an AIR DOCUMENT CLASS, plus its
// headless acceptance tour.
//
// It is the same shape the gallery used (see CONTRIBUTING-widget.md section 4):
// `--air-app` generates a bootstrap that does `new <Main>()`, `stage.addChild` and
// only then `stage.showWindow(...)`, so the window's size, title, renderMode and
// requestedDisplayResolution come from air-gallery/app.xml and nothing here calls
// showWindow. On ADDED_TO_STAGE -- before the window blocks on the event loop --
// the tour runs headlessly and writes docs.txt + docs.done.
//
// WHAT THE TOUR IS FOR:
//   1. the shell's hand-computed rects (sidebar / index / content pane), so the
//      layout engine's own arithmetic is pinned by numbers written down BEFORE
//      the run;
//   2. BLOCK ARITHMETIC. Every section's box height comes from
//      DocSection.height(), which sums the same constants DocsStyle gives the
//      engine. The tour compares the scroll view's published contentH against a
//      recomputed sum, and then -- the part that cannot lie -- requires that no
//      child's solved rect escapes its block on ANY of the 61 pages. A forgotten
//      gap or a wrong line height shows up as a rect outside its box;
//   3. a real wheel scroll (the content pane), asserting the offset, the clamp and
//      that the pixels actually moved while the layout did not;
//   4. a real sidebar click, asserting it is the WIDGET that switches the page;
//   5. the floating layer: a documented dialog opens in the overlay tree, and
//      closing it tears the tree down;
//   6. eight screenshots, one per kind of page (the landing board included).
package demo
{
    import asaot.ui.Dirty;
    import asaot.ui.I18n;
    import asaot.ui.ScrollViewNode;
    import asaot.ui.TextNode;
    import asaot.ui.UiApp;
    import asaot.ui.UiNode;
    import flash.display.BitmapData;
    import flash.display.Sprite;
    import flash.display.StageAlign;
    import flash.display.StageScaleMode;
    import flash.events.Event;
    import flash.events.MouseEvent;
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;
    import flash.utils.getTimer;

    public class DocsMain extends Sprite
    {
        public static const OUT:String = "gallery";

        private var model:DocsModel;
        private var view:DocsView;
        private var app:UiApp;
        private var problems:String = "";
        private var report:String = "";
        private var kidsBase:int = -1;
        // Where the tour has got to. Written to the result file before each stage, so a
        // crash (an uncaught #1009 stops the app mid-frame, and no report is ever
        // written) still says WHERE it happened instead of only that it did.
        private var at:String = "";

        public function DocsMain():void
        {
            addEventListener(Event.ADDED_TO_STAGE, onAdded);
        }

        private function onAdded(e:Event):void
        {
            removeEventListener(Event.ADDED_TO_STAGE, onAdded);

            this.model = new DocsModel();
            this.view = new DocsView(this.model);
            this.stage.scaleMode = StageScaleMode.NO_SCALE;
            this.stage.align = StageAlign.TOP_LEFT;
            // The cadence is asked for EXPLICITLY, one line under the scale mode: the
            // runtime's default follows the display's own refresh rate, which is 60 on
            // this box but 120 on a ProMotion panel -- and every number this demo
            // prints about frames would then be a statement about the monitor. 60 is
            // the rate the tour's per-frame arithmetic (and the live board's 100 ms
            // tick) was measured at.
            this.stage.frameRate = 60;
            this.app = new UiApp(this.view);
            // THE DATA FLOW IS NOT OPTIONAL. A widget reports (onClick / onChange) to
            // the MODEL, and the model notifies -- but nothing repaints unless someone
            // is subscribed to that notify. Without this line a click changed only the
            // model: the tree, the window and the pixels all stayed on the previous
            // page (found by the tour: doc=box while the title still read 'Getting
            // started' and the old page's demo was still mounted).
            var self:DocsMain = this;
            this.model.subscribe(function (d:int):void { self.app.invalidate(d); });
            this.app.mount(this.stage);
            this.app.attachRoot();
            // The frame-rate HUD, in the library's own THIRD tree (see
            // UiApp.showFps): top-right, above every page and every dialog, and not
            // clickable, so it cannot take a click from the control under it.
            this.app.showFps("top-right");
            // Hand the app to the view: the live page reads its pass counters and its
            // Env, and the frame clock below is the ONLY thing that steps the market.
            this.view.app = this.app;
            addEventListener(Event.ENTER_FRAME, onFrame);

            this.tour();

            // Land on the app's landing page (the live board): the window's first
            // frame is painted after showWindow returns to the event loop.
            this.model.doc = DocsCatalog.LANDING;
            this.app.invalidate(Dirty.ALL);
            this.app.reflow();

            this.out(OUT + ".done", this.problems == "" ? "PASS" : "FAIL " + this.problems);
            trace("DocsMain: tour finished, " + (this.problems == "" ? "all checks passed" : this.problems));
        }

        // The frame clock. ONE listener for the whole app: it advances the simulated
        // market (only while the live page is on screen), samples the pass counters
        // once a second, and restores the real Env if a page left a fake phone bound.
        // It is deliberately not inside DocsView.render(): a describe pass must not
        // advance data, or a reflow caused by a resize would move the market too.
        private function onFrame(e:Event):void
        {
            if (this.view != null) this.view.frameTick(getTimer());
        }

        // ---- the tour ----------------------------------------------------------
        private function tour():void
        {
            if (this.stage.stageWidth != DocsStyle.W || this.stage.stageHeight != DocsStyle.H)
            {
                // Every number below is derived from DocsStyle.W/H and the descriptor,
                // so a mismatch makes the whole derivation void -- say THAT.
                this.problems = this.problems + "stage is " + this.stage.stageWidth + "x"
                    + this.stage.stageHeight + " but the tour's rects are derived for "
                    + DocsStyle.W + "x" + DocsStyle.H + " (air-gallery/app.xml); ";
            }
            this.kidsBase = this.stage.numChildren;

            this.mark("1 shell");

            // ---- 1. the shell ------------------------------------------------
            // The layout is FLUID, so every number here is derived from the stage
            // the window actually gave us, never from DocsStyle.W/H. Only the
            // fixed metrics (the sidebar's width, the paddings, the header block)
            // are constants.
            var winW:Number = this.stage.stageWidth;
            var winH:Number = this.stage.stageHeight;
            var docX:Number = DocsStyle.NAV_W + DocsStyle.PAD_X;         // 280
            var docW:Number = winW - DocsStyle.NAV_W - DocsStyle.PAD_X * 2;   // 688
            // ... and the CONTENT is one scrollbar lane narrower, because the page
            // pane declares `scrollbarGutter: "stable"`: the bar owns the rightmost
            // DOC_GUTTER px and the cards stop short of it. `docScroll` (the viewport)
            // is still `docW`; only what is inside it moves.
            var docCW:Number = docW - DocsStyle.DOC_GUTTER;                   // 678
            var docY:Number = 100;   // 24 top pad + 30 title + 4 + 18 blurb + 4 + 16 meta + 4
            var docH:Number = winH - docY - 16;                            // 584
            var navH:Number = DocsStyle.navHeight(winH);                     // index viewport
            this.problems = this.problems + this.rect("side", 0, 0, DocsStyle.NAV_W, winH);
            this.problems = this.problems + this.rect("main", DocsStyle.NAV_W, 0,
                winW - DocsStyle.NAV_W, winH);
            this.problems = this.problems + this.rect("docScroll", docX, docY, docW, docH);
            // The sidebar pads 14 horizontally and carries a 1px right border, so the
            // index column is 248 - 28 - 1 = 219 wide: the border sits INSIDE the box.
            this.problems = this.problems + this.rect("nav", 14, 68, 219, navH);

            this.mark("2 block arithmetic");

            // ---- 2. block arithmetic on the first page -----------------------
            // "Describe": head 22 + 8 + prose 2*17 + 8 + demo 104 + 8 + code
            // (2*10 + 6*14 = 104) = 288. The code box then starts at
            // 100 + 22 + 8 + 34 + 8 + 104 + 8 = 284.
            // The demo surface is 104, not the 76 default, because this example
            // is a card with 14px padding around a 20px heading, an 8px gap and a
            // 44px button: 14+20+8+44+14 = 100. At 76 the button was drawn across
            // the surface's own border.
            this.problems = this.problems + this.rect("b0", docX, docY, docCW, 288);
            this.problems = this.problems + this.rect("b0:code", docX, 284, docCW, 104);

            var sv:UiNode = this.app.findByKey("docScroll");
            if (sv == null || sv.desc == null)
            {
                this.problems = this.problems + "no docScroll node; ";
            }
            else
            {
                var sn:ScrollViewNode = ScrollViewNode(sv.desc);
                var want:Number = this.contentHeight("start");
                this.report = this.report + "== start page ==\n  contentH=" + sn.contentH
                    + " (computed " + want + ") maxOffsetY=" + sn.maxOffsetY + "\n";
                if (sn.contentH != want)
                {
                    this.problems = this.problems + "the content pane is " + sn.contentH
                        + " tall but the blocks sum to " + want + "; ";
                }
                if (sn.maxOffsetY != want - docH)
                {
                    this.problems = this.problems + "maxOffsetY is " + sn.maxOffsetY
                        + ", expected " + (want - docH) + " (content - viewport); ";
                }

                // ---- 3. a real wheel scroll ---------------------------------
                // delta < 0 scrolls toward the END; one notch is `wheelStep` 40.
                var bd0:BitmapData = new BitmapData(int(DocsStyle.W), int(DocsStyle.H), true, 0xFF000000);
                bd0.draw(this.stage);
                var before:uint = bd0.getPixel(900, 200) & 0xFFFFFF;
                this.stage.dispatchWheel(600, 300, -3);
                this.app.reflow();
                var oy:Number = ScrollViewNode(sv.desc).offsetY;
                var bd1:BitmapData = new BitmapData(int(DocsStyle.W), int(DocsStyle.H), true, 0xFF000000);
                bd1.draw(this.stage);
                var after:uint = bd1.getPixel(900, 200) & 0xFFFFFF;
                var b0:UiNode = this.app.findByKey("b0");
                this.report = this.report + "  wheel -3 -> offsetY=" + oy + " b0.y=" + (b0 == null ? -1 : b0.absY)
                    + " px(900,200) #" + before.toString(16) + " -> #" + after.toString(16) + "\n";
                if (oy != 120)
                {
                    this.problems = this.problems + "a -3 wheel notch left offsetY at " + oy + ", expected 120; ";
                }
                if (b0 != null && b0.absY != 100)
                {
                    this.problems = this.problems + "scrolling moved the LAYOUT box b0 to y=" + b0.absY + " (layout must not scroll); ";
                }
                // The pixels DID move: at y=200 the scrolled pane now shows the code
                // block's dark surface (content y=220, inside b0's code box which
                // starts at 184 at offset 0) instead of the demo surface.
                if (after != 0x0F172A)
                {
                    this.problems = this.problems + "after the scroll, (900,200) is #" + after.toString(16)
                        + " not #0f172a -- the viewport did not slide its content; ";
                }
                if (before == 0x0F172A)
                {
                    this.problems = this.problems + "(900,200) already painted #0f172a before the scroll -- the sample point is wrong; ";
                }
                // Back to the top, so the screenshots below are of a settled page.
                //
                // THE POINT IS NOT ARBITRARY, and this line is a regression test of
                // its own: after the notch above, (600,300) falls on a GAP in the
                // pane's content -- no painted region under it, only the surface. The
                // runtime picks a wheel target by PAINTED REGION (as_shape_region_hit),
                // so a hit-test hole there sent the event to the window root and the
                // pane never saw it: that is exactly how this assertion went red on
                // macOS after the scroll code had been reworked. ScrollViewWidget now
                // paints a transparent hit rect over its whole viewport (the idiom
                // TableWidget already used), so a wheel anywhere in the pane reaches
                // it. If that ever regresses, this reads a non-zero offset.
                this.stage.dispatchWheel(600, 300, 3);
                this.app.reflow();
                var back:Number = ScrollViewNode(sv.desc).offsetY;
                if (back != 0)
                {
                    this.problems = this.problems + "wheeling back over a content gap left the pane at offsetY "
                        + back + ", expected 0 (a wheel inside the viewport must reach it, even over a gap); ";
                }
            }

            this.mark("4 sidebar");

            // ---- 4. the sidebar is what switches the page ---------------------
            // The row's key is "nav:" + the page id (see DocsView.navItem), and the
            // page id is also what the model stores -- so the assertion can compare the
            // model, the view's own record of the click, and the header's text.
            var navBtn:UiNode = this.app.findByKey("nav:box");
            if (navBtn == null)
            {
                this.problems = this.problems + "no 'box' row in the index; ";
            }
            else
            {
                // Through the ENGINE mouse pipeline (see click()): the app hit-tests the
                // stage, so a CLICK dispatched at the sprite never reaches the handler.
                this.click(navBtn);
                this.app.reflow();
                var title:String = this.tf("docTitle");
                if (this.model.doc != "box")
                {
                    this.problems = this.problems + "clicking the index's 'box' row left doc=" + this.model.doc + "; ";
                }
                if (this.view.lastPick != "box")
                {
                    this.problems = this.problems + "the row's onClick did not report 'box' (got '" + this.view.lastPick + "'); ";
                }
                if (title != "box")
                {
                    this.problems = this.problems + "the page title reads '" + title + "' after the click, expected 'box'; ";
                }
                if (this.app.findByKey("startBtn") != null)
                {
                    this.problems = this.problems + "the previous page's demo widget is still mounted; ";
                }
                // THE LABEL IS CENTRED IN ITS ROW. A text node paints from the top of
                // its box, so a label that carries the ROW's height leaves the row's
                // align-items with nothing to centre (that was the reported "the menu
                // labels sit high"). Auto height hands the centring back to the row, and
                // this is the arithmetic version of the screenshot.
                var nrow:UiNode = this.app.findByKey("nav:box");
                var nlab:UiNode = this.app.findByKey("nav:box:t");
                if (nrow != null && nlab != null)
                {
                    var want:Number = (nrow.absH - nlab.absH) / 2;
                    var got:Number = nlab.absY - nrow.absY;
                    this.report = this.report + "  nav row " + nrow.absH + " label "
                        + nlab.absH + " y offset " + got + " (centre " + want + ")\n";
                    if (got < 0.5 || got > want + 0.5 || got < want - 0.5)
                    {
                        this.problems = this.problems + "the index label sits at y+" + got
                            + " in a " + nrow.absH + "pt row, expected the centre (+"
                            + want + "); ";
                    }
                }
                else
                {
                    this.problems = this.problems + "the index row or its label is missing; ";
                }

                this.report = this.report + "== index click ==\n  doc=" + this.model.doc
                    + " title='" + title + "' startBtnGone=" + (this.app.findByKey("startBtn") == null) + "\n";
            }

            // ---- 5. every page renders, and every block is TIGHT --------------
            // The height sweep is the one assertion that can catch the block
            // arithmetic: children are placed by the engine from DocsStyle's gaps and
            // line heights, while the box heights come from DocSection.height(). If
            // the two disagree, something sticks out of its block.
            //
            // Each page is tried on its own: an uncaught exception is recovered at the
            // frame boundary, which means a single widget can stop the TOUR (no
            // gallery.done, an opaque TIMEOUT) while the window keeps running. Catching
            // per page turns that into a named failure and lets the other 40 pages
            // still report -- which is what a docs app has to do with 61 pages.
            var pages:Array = DocsCatalog.pages();
            var badPages:int = 0;
            var badBlocks:int = 0;
            // The per-page list was gated on badPages, so a page whose LAYOUT overflowed
            // (badBlocks > 0, badPages == 0) reported the total and named nothing --
            // useless for finding the block. Both counters gate it now.
            var badNamed:int = 0;
            var totalNodes:int = 0;
            var badList:String = "";
            for (var i:int = 0; i < pages.length; i++)
            {
                var p:DocPage = DocPage(pages[i]);
                this.mark("5 " + p.id);
                try
                {
                    this.model.pick(p.id);
                    this.app.invalidate(Dirty.ALL);
                    this.app.reflow();

                    var acc:Object = { total: 0, nullEng: 0, zero: 0, detached: 0, shown: 0, text: "" };
                    this.treeDiag(this.app.getRoot(), 0, acc);
                    totalNodes = totalNodes + int(acc.total);

                    var bad:String = "";
                    if (this.app.findByKey("docCol") == null) bad = "no content column";
                    if (this.tf("docTitle") != p.title) bad = bad + " title='" + this.tf("docTitle") + "'";
                    if (int(acc.nullEng) > 0) bad = bad + " " + acc.nullEng + " node(s) without an engine node";
                    if (int(acc.zero) > 0) bad = bad + " " + acc.zero + " zero-rect node(s)" + String(acc.text);
                    if (int(acc.detached) > 0) bad = bad + " " + acc.detached + " detached backing(s)";
                    if (bad != "")
                    {
                        badPages = badPages + 1;
                        if (badNamed <= 6) badList = badList + "  " + p.id + ": " + bad + "\n";
                        badNamed = badNamed + 1;
                    }

                    var blocks:int = this.overflowingBlocks();
                    if (blocks > 0)
                    {
                        badBlocks = badBlocks + blocks;
                        if (badNamed <= 6)
                            badList = badList + "  " + p.id + ": " + blocks + " block(s) with a child outside\n";
                        badNamed = badNamed + 1;
                    }
                }
                catch (err:Error)
                {
                    badPages = badPages + 1;
                    if (badNamed <= 6) badList = badList + "  " + p.id + ": threw " + err.message + "\n";
                    badNamed = badNamed + 1;
                }
            }
            var sweep:String = "  pages=" + pages.length + " nodes=" + totalNodes
                + " badPages=" + badPages + " overflowingBlocks=" + badBlocks + "\n" + badList;
            this.report = this.report + "== every page ==\n" + sweep;
            if (badPages > 0)
            {
                this.problems = this.problems + badPages + " of " + pages.length + " pages failed the sweep; ";
            }
            if (badBlocks > 0)
            {
                this.problems = this.problems + badBlocks + " block(s) have a child outside their box, or a prose line painting wider than its"
                    + " box (DocSection.height() / DocsWrap disagree with the layout); ";
            }

            // ---- 6. the floating layer ---------------------------------------
            this.mark("6a anchored");

            // 6a first: an ANCHORED surface, opened and closed on a page that stays
            // put. The popover's rect is derived from the anchor's LIVE rect (same left
            // edge, 8px below its bottom), not from a constant: the anchor sits under
            // two sections whose heights come from the content, so a constant here
            // would be a guess that passes by accident.
            this.model.pick("overlay");
            this.model.put("ov.open", false);
            this.app.invalidate(Dirty.ALL);
            this.app.reflow();
            var ovb:UiNode = this.app.findByKey("ovBtn");
            if (ovb == null)
            {
                this.problems = this.problems + "the overlay page has no anchor button; ";
            }
            else
            {
                var kidsBefore:int = this.stage.numChildren;
                this.click(ovb);
                this.app.reflow();
                var pop:UiNode = this.app.findByKey("ovPop");
                if (pop == null)
                {
                    this.problems = this.problems + "clicking the overlay page's button did not mount the anchored popover; ";
                }
                else
                {
                    this.report = this.report + "== anchored overlay ==\n  anchor " + ovb.absX + ","
                        + ovb.absY + "," + ovb.absW + "," + ovb.absH + "  popover " + pop.absX + ","
                        + pop.absY + "," + pop.absW + "," + pop.absH + "\n";
                    if (pop.absX != ovb.absX || pop.absY != ovb.absY + ovb.absH + 8)
                    {
                        this.problems = this.problems + "the popover is at " + pop.absX + "," + pop.absY
                            + ", expected the anchor's left edge and 8px below its bottom; ";
                    }
                    // THE BODY INSIDE THE PANEL. This surface is 230 wide with a 12pt
                    // padding and a 1pt border, so the body must publish 204 and paint
                    // no wider -- the reported popover printed its sentence across the
                    // panel and over the code block behind it.
                    var pbody:UiNode = this.app.findByKey("ovPopBody");
                    if (pbody == null)
                    {
                        this.problems = this.problems + "the popover mounted without its body; ";
                    }
                    else
                    {
                        var pin:Number = DocsStyle.panelInnerWidth(230, OverlayChrome.POPOVER_PANEL);
                        this.report = this.report + "  popover body " + pbody.absX + ","
                            + pbody.absY + "," + pbody.absW + "," + pbody.absH + "\n";
                        if (pbody.absW != pin || pbody.absX != pop.absX + 13)
                        {
                            this.problems = this.problems + "the popover body is at " + pbody.absX
                                + " w=" + pbody.absW + ", expected the panel's content box ("
                                + (pop.absX + 13) + " w=" + pin + "); ";
                        }
                        if (pbody.tf != null && pbody.tf.textWidth > pbody.absW + 0.5)
                        {
                            this.problems = this.problems + "the popover body paints "
                                + pbody.tf.textWidth + "pt of ink in a " + pbody.absW + "pt box; ";
                        }
                    }
                }
                this.click(ovb);
                this.app.reflow();
                if (this.app.findByKey("ovPop") != null)
                {
                    this.problems = this.problems + "closing the popover left it mounted; ";
                }
                if (this.stage.numChildren != kidsBefore)
                {
                    this.problems = this.problems + "the overlay layer left " + (this.stage.numChildren - kidsBefore)
                        + " display object(s) on the stage after the popover was torn down; ";
                }
            }

            this.mark("6b dialog");

            // 6b: the dialog, which is centred in the WINDOW rather than placed in the
            // page. If it were a page child it would scroll away with the content.
            this.model.pick("dialog");
            this.app.invalidate(Dirty.ALL);
            this.app.reflow();
            // THE BODY WRAPS AT THE PANEL'S CONTENT WIDTH. The second dialog on
            // this page (300 wide, closeOnScrim false) carries a 470pt sentence; it
            // used to paint out of both sides of the panel. `whiteSpace: "normal"`
            // at the panel's content box is the fix, and all three consequences are
            // numbers: the node publishes that point width, it wraps (so its height
            // is more than one line box), and it stays inside the panel.
            // The button is the third section's demo, below the reading pane's
            // viewport at scroll 0, so a stage click on it lands nowhere -- the
            // model is the honest driver here (the click path is exercised for the
            // FIRST dialog immediately below).
            this.model.put("dlg2.open", true);
            this.app.invalidate(Dirty.ALL);
            this.app.reflow();
            {
                var p2:UiNode = this.app.findByKey("demoDlg2:panel");
                var b2:UiNode = this.app.findByKey("demoDlg2Body");
                if (p2 == null || b2 == null)
                {
                    this.problems = this.problems + "the second dialog's "
                        + (p2 == null ? "panel " : "") + (b2 == null ? "body " : "")
                        + "did not mount; ";
                }
                else
                {
                    // 300 wide, DIALOG_PANEL padding 18 and a 1pt border per side.
                    var inner:Number = DocsStyle.panelInnerWidth(300, OverlayChrome.DIALOG_PANEL);
                    this.report = this.report + "  dialog body " + b2.absX + "," + b2.absY
                        + "," + b2.absW + "," + b2.absH + " in panel " + p2.absX + ","
                        + p2.absY + "," + p2.absW + "," + p2.absH + "\n";
                    if (b2.absW != inner)
                    {
                        this.problems = this.problems + "the dialog body is " + b2.absW
                            + " wide, expected " + inner + " (the panel content box); ";
                    }
                    // TWO LINE BOXES OR MORE. 13 is the SIZE; a line box here is 12, so a
                    // single line publishes 12 and the wrapped sentence publishes 24 --
                    // which is also what makes the panel 133 tall instead of 121.
                    if (b2.absH <= 12)
                    {
                        this.problems = this.problems + "the dialog body is " + b2.absH
                            + " tall: the sentence does not fit on one line at "
                            + inner + ", so it must have wrapped; ";
                    }
                    // THE INK, ONE PROPERTY APART FROM THE RECT: drop `whiteSpace:
                    // \"normal\" and the box keeps its point width while the run paints
                    // straight through the panel.
                    if (b2.tf != null && b2.tf.textWidth > b2.absW + 0.5)
                    {
                        this.problems = this.problems + "the dialog body paints "
                            + b2.tf.textWidth + "pt of ink in a " + b2.absW + "pt box; ";
                    }
                    if (b2.absX < p2.absX + 19 || b2.absX + b2.absW > p2.absX + p2.absW - 19)
                    {
                        this.problems = this.problems + "the dialog body spans " + b2.absX
                            + ".." + (b2.absX + b2.absW) + ", outside the panel's content box "
                            + (p2.absX + 19) + ".." + (p2.absX + p2.absW - 19) + "; ";
                    }
                }
                this.model.put("dlg2.open", false);
                this.app.invalidate(Dirty.ALL);
                this.app.reflow();
            }
            var openBtn:UiNode = this.app.findByKey("demoDlgBtn");
            if (openBtn == null)
            {
                this.problems = this.problems + "the dialog page has no demo button; ";
            }
            else
            {
                this.click(openBtn);
                this.app.reflow();
                var dlg:UiNode = this.app.findByKey("demoDlg:panel");
                if (dlg == null)
                {
                    this.problems = this.problems + "clicking the dialog demo's button did not mount the panel in the overlay tree; ";
                }
                else
                {
                    this.report = this.report + "== overlay ==\n  dialog panel " + dlg.absX + "," + dlg.absY
                        + "," + dlg.absW + "," + dlg.absH + "\n";
                    // The panel is centred in the WINDOW, not in the page: 320 wide ->
                    // x = (winW - 320)/2, which is 340 at the descriptor's 1000.
                    if (dlg.absX != (winW - 320) / 2 || dlg.absW != 320)
                    {
                        this.problems = this.problems + "the dialog panel is at x=" + dlg.absX
                            + " w=" + dlg.absW + ", expected x=" + ((winW - 320) / 2)
                            + " w=320 (window-centred); ";
                    }
                }
                var noBtn:UiNode = this.app.findByKey("demoDlgNo");
                if (noBtn != null)
                {
                    this.click(noBtn);
                    this.app.reflow();
                }
                if (this.app.findByKey("demoDlg") != null)
                {
                    this.problems = this.problems + "closing the dialog left it mounted; ";
                }
                // An overlay lifecycle must not add or remove a STAGE child.
                // kidsBase already counts the main tree AND the overlay root (both are
                // attached before the tour starts), so the honest baseline is kidsBase
                // itself: the old kidsBase + 1 was a leftover from when the overlay
                // root was created lazily on first use.
                if (this.stage.numChildren != this.kidsBase)
                {
                    this.problems = this.problems + "the stage holds " + this.stage.numChildren
                        + " display objects after the overlay was torn down, expected " + this.kidsBase
                        + " (main tree + overlay root); ";
                }
            }

            // A settled tree must not re-solve layout for a re-description.
            this.model.pick("start");
            this.app.invalidate(Dirty.ALL);
            this.app.reflow();
            var solves:Number = this.app.layoutSolves;
            this.app.invalidate(Dirty.VALUE);
            this.app.reflow();
            this.app.reflow();
            var extra:Number = this.app.layoutSolves - solves;
            this.report = this.report + "\nlayoutSolves after two redundant reflows: +" + extra + "\n";
            if (extra > 0)
            {
                this.problems = this.problems + "two redundant reflows re-solved layout " + extra + " time(s); ";
            }

            this.mark("6c resize");

            // ---- 6c. the shell is FLUID --------------------------------------
            // The requirement this pins: resizing the WINDOW resizes the sidebar and
            // the content pane. A window resize reaches the app as two writes plus an
            // event -- stage_w/stage_h and Event.RESIZE (src/emit.ts:25381, ASC_window_
            // on_resize) -- and that is exactly what is done here, so nothing in the
            // layout path can tell this apart from a dragged window edge. The
            // assertions are therefore RECTS, and any px() left in ROOT/SIDE/NAV/
            // DOC_SCROLL (the old 1000x700 shell) would fail them.
            var w0:Number = this.stage.stageWidth;
            var h0:Number = this.stage.stageHeight;
            var w2:Number = w0 + 180;
            var h2:Number = h0 + 130;
            this.stage.stageWidth = w2;
            this.stage.stageHeight = h2;
            this.stage.dispatchEvent(new Event(Event.RESIZE));
            this.app.invalidate(Dirty.STRUCTURE);
            this.app.reflow();
            var docH2:Number = h2 - docY - 16;
            this.problems = this.problems + this.rect("side", 0, 0, DocsStyle.NAV_W, h2);
            this.problems = this.problems + this.rect("main", DocsStyle.NAV_W, 0,
                w2 - DocsStyle.NAV_W, h2);
            this.problems = this.problems + this.rect("docScroll", docX, docY,
                w2 - DocsStyle.NAV_W - DocsStyle.PAD_X * 2, docH2);
            // The index viewport is the sidebar's leftover height. The top 68 is
            // padding + brand + gap + tag + gap; below the index sit the language row,
            // its two gaps, the foot and the bottom padding -- all of them in
            // DocsStyle.navHeight(), because the switcher added a row and a copied
            // number is exactly what would rot here.
            this.problems = this.problems + this.rect("nav", 14, 68, 219, DocsStyle.navHeight(h2));
            this.report = this.report + "\n  resized to " + w2 + "x" + h2
                + ": nav " + DocsStyle.navHeight(h2) + " tall, content viewport " + docH2 + "\n";

            var sv2:UiNode = this.app.findByKey("docScroll");
            if (sv2 != null && sv2.desc != null)
            {
                // The page is the one stage 6 left selected (start), and its content
                // height is whatever it is at THIS width -- compare the published
                // range against it instead of a constant, because a wider pane can
                // re-wrap a block and legitimately change the content height.
                var sn2:ScrollViewNode = ScrollViewNode(sv2.desc);
                if (sn2.maxOffsetY != sn2.contentH - docH2)
                {
                    this.problems = this.problems + "after the resize maxOffsetY is " + sn2.maxOffsetY
                        + ", expected " + (sn2.contentH - docH2) + " (content " + sn2.contentH
                        + " - viewport " + docH2 + "); ";
                }
            }

            // ... and back, so the screenshots below are the published 1000x700 shape.
            this.stage.stageWidth = w0;
            this.stage.stageHeight = h0;
            this.stage.dispatchEvent(new Event(Event.RESIZE));
            this.app.invalidate(Dirty.STRUCTURE);
            this.app.reflow();
            this.problems = this.problems + this.rect("docScroll", docX, docY, docW, docH);
            this.problems = this.problems + this.rect("nav", 14, 68, 219, navH);

            this.mark("6d toastHost");

            // ---- 6d. the toastHost demo ---------------------------------------
            // Every stage above checks a surface the page mounts BY ITSELF. The
            // toastHost page is the opposite: its two toasts exist only once the
            // model's `tsh.open` flips, so the 42-page sweep (which only renders)
            // never built them -- and the demo had shipped asking for "tone: info", a
            // CHIP tone that toast.as throws on. The frame guard recovers the throw and
            // re-renders the same tree, so the symptom was a console stream, not a
            // broken page: nothing but a real click could have found it.
            //
            // The reflow is wrapped because an uncaught throw here would stop the tour
            // and leave no gallery.done at all (the reason the page sweep catches per
            // page): a named failure beats an opaque timeout.
            this.model.pick("toastHost");
            this.app.invalidate(Dirty.ALL);
            this.app.reflow();

            // A page switch is a describe with no paint, which makes it the one frame
            // where nothing else would put a bar back on top: if the ordering base is
            // wrong (a chrome object counted as "before the children"), this is where
            // it shows. Page 0's screenshot had exactly that -- a thumb painted over
            // by the code block below it.
            this.problems = this.problems + this.chromeOnTop("docScroll");
            this.problems = this.problems + this.chromeOnTop("nav");
            var tsh:UiNode = this.app.findByKey("tshBtn");
            if (tsh == null)
            {
                this.problems = this.problems + "the toastHost page has no demo button; ";
            }
            else
            {
                var kidsT:int = this.stage.numChildren;
                var threw:Boolean = false;
                this.click(tsh);
                try
                {
                    this.app.reflow();
                }
                catch (terr:Error)
                {
                    threw = true;
                    this.problems = this.problems + "opening the toastHost demo threw: " + terr.message + "; ";
                }
                var tA:UiNode = this.app.findByKey("demoToast1");
                var tB:UiNode = this.app.findByKey("demoToast2");
                if (tA == null || tB == null)
                {
                    this.problems = this.problems + "clicking 'Show two toasts' mounted "
                        + (tA == null ? "no" : "a") + " first toast and "
                        + (tB == null ? "no" : "a") + " second one; ";
                }
                else
                {
                    // Both numbers are DERIVED, not measured: the corner is
                    // OverlayChrome.TOAST_LAYER (padding 16, gap 8, flex-end on both
                    // axes) and a toast is 220 wide unless the author passes `width`.
                    var wantX:Number = winW - 16 - 220;
                    var wantY:Number = winH - 16;
                    this.report = this.report + "== toasts ==\n  t1 " + tA.absX + "," + tA.absY + ","
                        + tA.absW + "," + tA.absH + "  t2 " + tB.absX + "," + tB.absY + ","
                        + tB.absW + "," + tB.absH + "\n";
                    if (tA.absX != wantX || tB.absX != wantX || tA.absW != 220 || tB.absW != 220)
                    {
                        this.problems = this.problems + "the toasts are not the 220-wide corner stack: t1 "
                            + tA.absX + "," + tA.absW + " t2 " + tB.absX + "," + tB.absW
                            + " expected x=" + wantX + " w=220; ";
                    }
                    if (tB.absY + tB.absH != wantY)
                    {
                        this.problems = this.problems + "the last toast's bottom is " + (tB.absY + tB.absH)
                            + ", expected " + wantY + " (the window's bottom edge minus 16); ";
                    }
                    if (tA.absY + tA.absH + 8 != tB.absY)
                    {
                        this.problems = this.problems + "the toast gap is not 8 (" + (tA.absY + tA.absH)
                            + " -> " + tB.absY + "); ";
                    }
                }
                // ... and closing them from the MODEL must unmount both, leaving no
                // stage child behind.
                this.model.put("tsh.open", false);
                this.app.invalidate(Dirty.ALL);
                try
                {
                    this.app.reflow();
                }
                catch (terr2:Error)
                {
                    threw = true;
                }
                if (!threw && (this.app.findByKey("demoToast1") != null
                    || this.app.findByKey("demoToast2") != null))
                {
                    this.problems = this.problems + "flipping tsh.open back left a toast mounted; ";
                }
                if (!threw && this.stage.numChildren != kidsT)
                {
                    this.problems = this.problems + "the toast layer left "
                        + (this.stage.numChildren - kidsT) + " display object(s) on the stage; ";
                }
            }

            this.mark("6e slider drag");

            // ---- 6e. a real DRAG on the docs' own slider ----------------------
            // This is the surface the user reported: press and drag on the slider page
            // threw #1063 out of every callback (SliderWidget called `n.onChange()`
            // with no argument while every page declares `function (v:Number)`), so the
            // handler never ran -- and the widget had no drag mechanism either.
            //
            // The label is built by the DEMO from the model, so reading it after a
            // reflow proves the WHOLE chain: gesture -> widget commit -> onChange(v) ->
            // model.put -> notify -> invalidate -> describe -> new label text. A drag
            // that only moved the knob would leave the label alone; a dead callback
            // would leave both alone.
            this.model.pick("slider");
            this.app.invalidate(Dirty.ALL);
            this.app.reflow();
            var sl:UiNode = this.app.findByKey("slVol");
            if (sl == null)
            {
                this.problems = this.problems + "the slider page has no demo slider; ";
            }
            else
            {
                // The track is the 8pt band at local h-12 .. h-4 (its middle is h-8):
                // the pick region is the DRAWN region, so the box centre is empty.
                var trackY:Number = sl.absY + sl.absH - 8;
                // PAST the right edge, not "the last pixel inside" it: `valueAt` is
                // localX / absW, so absW-1 is 99.4% and the label would read 99%.
                // Clamped to the window so the point still lands on the stage.
                var rightX:Number = sl.absX + sl.absW + 10;
                if (rightX > DocsStyle.W - 1) rightX = DocsStyle.W - 1;
                var beforeLabel:String = this.tf("slVol");
                var dragThrew:Boolean = false;
                try
                {
                    this.stage.dispatchMouse(sl.absX + 20, trackY, "mouseDown");
                    this.stage.dispatchMouse(rightX, trackY, "mouseMove");
                    // Past the LEFT edge: the stage listener owns the pointer during a
                    // drag, so the value has to clamp at 0 rather than stop updating.
                    this.stage.dispatchMouse(sl.absX - 24, trackY, "mouseMove");
                    this.stage.dispatchMouse(sl.absX - 24, trackY, "mouseUp");
                    this.app.reflow();
                    // A move AFTER the release is not a drag any more.
                    this.stage.dispatchMouse(rightX, trackY, "mouseMove");
                    this.app.reflow();
                }
                catch (derrp:Error)
                {
                    dragThrew = true;
                    this.problems = this.problems + "dragging the demo slider threw: "
                        + derrp.message + "; ";
                }
                if (!dragThrew)
                {
                    var midLabel:String = this.tf("slVol");
                    if (midLabel != "Volume 0%")
                    {
                        this.problems = this.problems + "a drag to the left edge left the label at '"
                            + midLabel + "', expected 'Volume 0%' (it read '" + beforeLabel
                            + "' before the drag; a stale 'Volume 100%' means the release did not"
                            + " end the drag); ";
                    }
                    if (this.model.num("sl.vol", -1) != 0)
                    {
                        this.problems = this.problems + "the drag never reached the model (sl.vol="
                            + this.model.num("sl.vol", -1) + "); ";
                    }
                    // ... and the other clamp, from a fresh press (the release must have
                    // cleared the drag state, or this press would be ignored).
                    try
                    {
                        this.stage.dispatchMouse(sl.absX + 20, trackY, "mouseDown");
                        this.stage.dispatchMouse(rightX, trackY, "mouseMove");
                        this.stage.dispatchMouse(rightX, trackY, "mouseUp");
                        this.app.reflow();
                        var endLabel:String = this.tf("slVol");
                        if (endLabel != "Volume 100%")
                        {
                            this.problems = this.problems + "a second drag to the right edge left '"
                                + endLabel + "', expected 'Volume 100%'; ";
                        }
                        this.report = this.report + "\n  slider drag: '" + beforeLabel + "' -> '"
                            + midLabel + "' -> '" + endLabel + "', model "
                            + this.model.num("sl.vol", -1) + "\n";
                    }
                    catch (derrp2:Error)
                    {
                        this.problems = this.problems + "the second slider drag threw: "
                            + derrp2.message + "; ";
                    }
                }
            }

            this.mark("7 screenshots");

            // ---- 7. screenshots ----------------------------------------------
            // One per KIND of page: the landing app, a container, a control, a leaf, a
            // picker, a data view, a nav strip and a floating surface. Eight, because
            // that is what run-gallery.cjs measures -- page0 IS the landing board now,
            // since that is what a reader of the published demo sees first.
            var stops:Array = ["live", "box", "button", "image", "select", "table", "tabs", "dialog"];
            for (var k:int = 0; k < stops.length; k++)
            {
                this.mark("7 shot " + String(stops[k]));
                // ONE frame tick BEFORE the page is described: the tour drives renders by
                // hand and never lets the real ENTER_FRAME loop run, so without this the
                // landing board's footer reads "0 nodes" -- a number the app never
                // measured. The tick publishes the tree walk; the RATES still read "—",
                // because a rate needs an interval and a static capture has none.
                this.view.frameTick(getTimer());
                this.model.pick(String(stops[k]));
                this.app.invalidate(Dirty.ALL);
                this.app.reflow();
                if (String(stops[k]) == "live")
                {
                    this.liveColumn();
                    this.liveRegions();
                }
                if (String(stops[k]) == "dialog")
                {
                    var ob:UiNode = this.app.findByKey("demoDlgBtn");
                    if (ob != null)
                    {
                        this.click(ob);
                        this.app.reflow();
                    }
                }
                this.stage.render(DocsStyle.W, DocsStyle.H, OUT + "-page" + k + ".png");
            }

            this.mark("8 i18n");

            // ---- 8. the locale switch ---------------------------------------------
            // Everything above ran in English. This stage is the localization itself, and
            // it is driven the way a user drives it: a CLICK on the sidebar's language
            // button, then a real ENTER_FRAME -- because the mechanism under test is the
            // EPOCH LATCH (I18n.epoch() -> invalidate(Dirty.VALUE) + a layout re-solve in
            // UiApp.onEnterFrame), not a test-only shortcut. The click alone must change
            // nothing: it writes a locale and returns.
            this.model.pick("i18n");
            this.app.invalidate(Dirty.ALL);
            this.app.reflow();
            // The switcher's rect comes from the same constants its style uses, and it is
            // also what makes the index viewport (nav, asserted above) add up.
            this.problems = this.problems + this.rect("lang:en", 14, 68 + navH + 4,
                DocsStyle.LANG_W, DocsStyle.LANG_H);
            var zhBtn:UiNode = this.app.findByKey("lang:zh-CN");
            var arBtn:UiNode = this.app.findByKey("lang:ar");
            var enBtn:UiNode = this.app.findByKey("lang:en");
            if (zhBtn == null || arBtn == null || enBtn == null)
            {
                this.problems = this.problems + "the sidebar has no language switcher; ";
            }
            else
            {
                var enHead:String = this.tf("b0:h");
                var enGroup:String = this.tf("navg11");
                var enBlurb:String = this.tf("docBlurb");
                var enFoot:String = this.tf("foot");

                this.click(zhBtn);
                if (this.tf("b0:h") != enHead)
                {
                    this.problems = this.problems + "the click alone re-described the page; ";
                }
                this.stage.dispatchEvent(new Event(Event.ENTER_FRAME));
                this.app.reflow();
                var zhHead:String = this.tf("b0:h");
                var zhGroup:String = this.tf("navg11");
                var zhBlurb:String = this.tf("docBlurb");
                var zhFoot:String = this.tf("foot");
                this.report = this.report + "== i18n ==\n  zh-CN: '" + zhHead + "' / '"
                    + zhGroup + "' / '" + zhFoot + "'\n";
                if (I18n.locale() != "zh-CN")
                {
                    this.problems = this.problems + "the zh-CN button left the locale at "
                        + I18n.locale() + "; ";
                }
                // NOT ASCII: a heading that changed to a different ENGLISH string would
                // mean a missing row, not a translation.
                if (zhHead == enHead || !this.hasWide(zhHead))
                {
                    this.problems = this.problems + "the section heading did not follow the locale ('"
                        + zhHead + "'); ";
                }
                if (zhGroup == enGroup)
                {
                    this.problems = this.problems + "the index group heading stayed '" + zhGroup
                        + "' -- the MEMOIZED sidebar did not re-describe for the new epoch; ";
                }
                if (zhBlurb == enBlurb)
                {
                    this.problems = this.problems + "the page blurb stayed English; ";
                }
                if (zhFoot == enFoot)
                {
                    this.problems = this.problems + "the index footer stayed '" + zhFoot + "'; ";
                }
                // A NAME IS NOT A TRANSLATION: the page title is the factory's spelling and
                // the product name is a name.
                if (this.tf("docTitle") != "i18n" || this.tf("brand") != "asaot.ui")
                {
                    this.problems = this.problems + "the API / product name was translated (title '"
                        + this.tf("docTitle") + "' brand '" + this.tf("brand") + "'); ";
                }
                // ---- 8a. the same sweep, in Chinese --------------------------------
                // Block heights are DERIVED from wrapped line counts (DocsWrap for the
                // lines, DocSection.height() for the box), so another language is a new
                // input to that pair -- and exactly the kind of drift a single-locale
                // gate never sees. English is swept in stage 5; this is the same check
                // with 700 translated strings in place.
                var zhBad:int = 0;
                var zhBlocks:int = 0;
                var zhList:String = "";
                var allPages:Array = DocsCatalog.pages();
                for (var q:int = 0; q < allPages.length; q++)
                {
                    var qp:DocPage = DocPage(allPages[q]);
                    this.mark("8 zh " + qp.id);
                    try
                    {
                        this.model.pick(qp.id);
                        this.app.invalidate(Dirty.ALL);
                        this.app.reflow();
                        var za:Object = { total: 0, nullEng: 0, zero: 0, detached: 0, shown: 0, text: "" };
                        this.treeDiag(this.app.getRoot(), 0, za);
                        if (int(za.nullEng) > 0 || int(za.zero) > 0 || int(za.detached) > 0)
                        {
                            zhBad = zhBad + 1;
                            if (zhList.length < 480)
                                zhList = zhList + "  " + qp.id + ": " + za.zero + " zero-rect / "
                                    + za.nullEng + " without an engine node" + String(za.text) + "\n";
                        }
                        var zb:int = this.overflowingBlocks();
                        if (zb > 0)
                        {
                            zhBlocks = zhBlocks + zb;
                            if (zhList.length < 900)
                                zhList = zhList + "  overflow " + qp.id + " blocks=" + zb + " heading='"
                                    + this.tf("b0:h").substr(0, 24) + "'\n";
                        }
                    }
                    catch (zerr:Error)
                    {
                        zhBad = zhBad + 1;
                        if (zhList.length < 480) zhList = zhList + "  " + qp.id + ": threw " + zerr.message + "\n";
                    }
                }
                this.report = this.report + "  zh sweep: pages=" + allPages.length + " badPages="
                    + zhBad + " overflowingBlocks=" + zhBlocks + "\n" + zhList;
                if (zhBad > 0)
                {
                    this.problems = this.problems + zhBad + " page(s) failed the sweep in zh-CN; ";
                }
                if (zhBlocks > 0)
                {
                    this.problems = this.problems + zhBlocks + " block(s) overflow in zh-CN"
                        + " (a translated line count disagreed with DocSection.height()); ";
                }
                // Back to the page this stage is about, for the screenshot and for the
                // RTL assertions that follow (they read `b0:h`, which every page has,
                // but the mirror is what the picture is supposed to show).
                this.model.pick("i18n");
                this.app.invalidate(Dirty.ALL);
                this.app.reflow();
                this.stage.render(DocsStyle.W, DocsStyle.H, OUT + "-zh.png");

                // ---- 8b. ar: RTL mirrors the LAYOUT; the text falls back to English ----
                this.click(arBtn);
                this.stage.dispatchEvent(new Event(Event.ENTER_FRAME));
                this.app.reflow();
                var rtlSide:UiNode = this.app.findByKey("side");
                var rtlMain:UiNode = this.app.findByKey("main");
                this.report = this.report + "  ar: rtl=" + I18n.isRTL() + " side.x="
                    + (rtlSide == null ? -1 : rtlSide.absX) + " heading='" + this.tf("b0:h") + "'\n";
                if (!I18n.isRTL())
                {
                    this.problems = this.problems + "the ar locale did not report RTL; ";
                }
                // No Arabic prose table ships, so the prose must come back as ENGLISH:
                // mirroring and translation are two separate things, and this is the line
                // that keeps them from being confused for one another.
                if (this.tf("b0:h") != enHead)
                {
                    this.problems = this.problems + "ar did not fall back to the English heading ('"
                        + this.tf("b0:h") + "'); ";
                }
                if (rtlSide == null || rtlSide.absX != winW - DocsStyle.NAV_W)
                {
                    this.problems = this.problems + "the RTL sidebar is at x="
                        + (rtlSide == null ? -1 : rtlSide.absX) + ", expected "
                        + (winW - DocsStyle.NAV_W) + " (the window's other edge); ";
                }
                if (rtlMain == null || rtlMain.absX != 0)
                {
                    this.problems = this.problems + "the RTL content pane is at x="
                        + (rtlMain == null ? -1 : rtlMain.absX) + ", expected 0; ";
                }
                // Mirroring swaps the SIDES of the two panes; it resizes neither.
                this.problems = this.problems + this.rect("docScroll", DocsStyle.PAD_X, docY, docW, docH);
                this.stage.render(DocsStyle.W, DocsStyle.H, OUT + "-rtl.png");

                // ---- 8c. back to en: the whole shell has to land where it started -------
                this.click(enBtn);
                this.stage.dispatchEvent(new Event(Event.ENTER_FRAME));
                this.app.reflow();
                if (I18n.locale() != "en")
                {
                    this.problems = this.problems + "the EN button left the locale at " + I18n.locale() + "; ";
                }
                if (this.tf("b0:h") != enHead || this.tf("navg11") != enGroup)
                {
                    this.problems = this.problems + "switching back to en did not restore the English text; ";
                }
                this.problems = this.problems + this.rect("side", 0, 0, DocsStyle.NAV_W, winH);
                this.problems = this.problems + this.rect("main", DocsStyle.NAV_W, 0,
                    winW - DocsStyle.NAV_W, winH);
                this.problems = this.problems + this.rect("docScroll", docX, docY, docW, docH);
                this.problems = this.problems + this.rect("nav", 14, 68, 219, navH);
            }

            this.out(OUT + ".txt", this.report);
        }

        // Is any character in this string wide (non-ASCII)? Used to tell "translated"
        // from "changed to another English string": a locale switch that lands on ASCII
        // means a missing row, not a finished translation.
        private function hasWide(s:String):Boolean
        {
            for (var i:int = 0; i < s.length; i++)
            {
                if (s.charCodeAt(i) > 127) return true;
            }
            return false;
        }

        // ---- helpers -----------------------------------------------------------

        // Is the kind's above-content display object (scrollView's bars) the LAST
        // child of its backing? Anything below the content is covered by it.
        private function chromeOnTop(key:String):String
        {
            var n:UiNode = this.app.findByKey(key);
            if (n == null) return "the '" + key + "' scroll view is not mounted; ";
            if (n.shapeB == null) return "the '" + key + "' scroll view has no bar layer; ";
            if (n.shapeB.parent != n.backing)
            {
                return "the '" + key + "' bar layer is not on its own backing; ";
            }
            if (n.backing.getChildIndex(n.shapeB) != n.backing.numChildren - 1)
            {
                return "the '" + key + "' bars sit at display index "
                    + n.backing.getChildIndex(n.shapeB) + " of " + n.backing.numChildren
                    + ", so the content below them paints over the bars; ";
            }
            return "";
        }

        // Region memoization is tested by DESCRIPTION identity, not a private build
        // counter: a quote-only tick must retain static descriptions and replace the
        // sparkline; changing a region's declared input must replace exactly that region.
        private function liveRegions():void
        {
            var header:UiNode = this.app.findByKey("liveHead");
            var stats:UiNode = this.app.findByKey("liveStats");
            var controls:UiNode = this.app.findByKey("liveCtl");
            var footer:UiNode = this.app.findByKey("liveFoot");
            var row:UiNode = this.app.findByKey("liveRow:AURX");
            var spark:UiNode = this.app.findByKey("liveSp:AURX");
            if (header == null || stats == null || controls == null || footer == null
                || row == null || spark == null || row.children.length < 2)
            {
                this.problems = this.problems + "the live region probe could not find its nodes; ";
                return;
            }
            var identity:UiNode = row.children[0];
            var hd:Object = header.desc;
            var sd:Object = stats.desc;
            var cd:Object = controls.desc;
            var fd:Object = footer.desc;
            var id:Object = identity.desc;
            var spd:Object = spark.desc;

            this.view.market.step();
            this.model.notify(Dirty.VALUE);
            this.app.reflow();
            if (this.app.findByKey("liveHead").desc !== hd)
                this.problems = this.problems + "live header rebuilt on a quote-only tick; ";
            if (this.app.findByKey("liveStats").desc !== sd)
                this.problems = this.problems + "live stats rebuilt on a quote-only tick; ";
            if (this.app.findByKey("liveCtl").desc !== cd)
                this.problems = this.problems + "live controls rebuilt on a quote-only tick; ";
            if (this.app.findByKey("liveFoot").desc !== fd)
                this.problems = this.problems + "live footer rebuilt on a quote-only tick; ";
            if (this.app.findByKey("liveRow:AURX").children[0].desc !== id)
                this.problems = this.problems + "live identity rebuilt on a quote-only tick; ";
            if (this.app.findByKey("liveSp:AURX").desc === spd)
                this.problems = this.problems + "live sparkline did not follow its quote revision; ";

            sd = this.app.findByKey("liveStats").desc;
            fd = this.app.findByKey("liveFoot").desc;
            this.view.liveStatsVersion = this.view.liveStatsVersion + 1;
            this.model.notify(Dirty.VALUE);
            this.app.reflow();
            if (this.app.findByKey("liveStats").desc === sd)
                this.problems = this.problems + "live stats ignored their sample version; ";
            if (this.app.findByKey("liveFoot").desc === fd)
                this.problems = this.problems + "live footer ignored its sample version; ";

            cd = this.app.findByKey("liveCtl").desc;
            this.model.put("live.run", false);
            this.app.reflow();
            if (this.app.findByKey("liveCtl").desc === cd)
                this.problems = this.problems + "live controls ignored the pause state; ";
            this.model.put("live.run", true);
            this.app.reflow();

            var stock:Object = this.view.market.rows[0];
            var oldName:String = String(stock.name);
            id = this.app.findByKey("liveRow:AURX").children[0].desc;
            stock.name = "Version probe";
            this.model.notify(Dirty.VALUE);
            this.app.reflow();
            identity = this.app.findByKey("liveRow:AURX").children[0];
            if (identity.desc === id || TextNode(identity.children[1].desc).content != "Version probe")
                this.problems = this.problems + "live identity ignored a symbol name change; ";
            stock.name = oldName;
            this.model.notify(Dirty.VALUE);
            this.app.reflow();
        }

        // A RIGHT-ALIGNED NUMERIC COLUMN HAS TO CLEAR THE OVERLAY SCROLLBAR.
        //
        // The live board right-aligns LAST/CHG% inside a 160pt column, and the list it
        // scrolls is `scrollbarGutter: "stable"`, so the content box is barThickness (8)
        // narrower than the view and the track is PAINTED OVER the last 8pt. An alignment
        // that ignores that puts the digits under the bar -- half a glyph, on the one page
        // a reader sees first. Measured after the fact, not assumed: the row's padding is
        // what buys the clearance, and it was written [0, 14] (Edges.fromArray reads the
        // 2-element form as [horizontal, vertical]), i.e. 14pt of VERTICAL padding and none
        // horizontally, so the column ended exactly on the track.
        private function liveColumn():void
        {
            var list:UiNode = this.app.findByKey("liveScroll");
            if (list == null) { this.problems = this.problems + "the live board's list is not mounted; "; return; }
            var content:UiNode = (list.children.length > 0) ? list.children[0] : null;
            var rowN:UiNode = null;
            for (var i:int = 0; content != null && i < content.children.length; i++)
            {
                if (String(content.children[i].key).indexOf("liveRow:") == 0)
                {
                    rowN = content.children[i];
                    break;
                }
            }
            if (rowN == null) { this.problems = this.problems + "the live board mounted no row; "; return; }
            var priceCol:UiNode = rowN.children[rowN.children.length - 1];
            if (priceCol == null || priceCol.children.length == 0)
            {
                this.problems = this.problems + "the live board's row has no price column; ";
                return;
            }
            var lastT:UiNode = priceCol.children[0];
            var barW:Number = Number((list.desc as ScrollViewNode).barThickness);
            var track:Number = list.absX + list.absW - barW;
            var colRight:Number = priceCol.absX + priceCol.absW;
            this.report = this.report + "  price column ends at " + colRight + ", track at "
                + track + " (align " + lastT.resolved.text.textAlign + ", clearance "
                + (track - colRight) + ")\n";
            if (colRight > track - 2)
            {
                this.problems = this.problems + "the live board's price column ends at "
                    + colRight + ", under the scroll bar that starts at " + track
                    + " (its row lost the horizontal padding); ";
            }
        }

        // Sum of the blocks DocSection.height() produces, in the same order and with
        // the same inter-block gap the view uses.
        private function contentHeight(id:String):Number
        {
            var secs:Array = DocsCatalog.sections(this.view, id);
            // The SAME width the view wraps at (DocsStyle.docWrapW), so the sum below
            // is the height the pane actually has. The window is a fixed 1000x700 here
            // (asserted just above), which is why this can be derived rather than
            // measured from a solved rect.
            var wrapW:Number = DocsStyle.docWrapW(this.stage.stageWidth);
            var h:Number = 0;
            for (var i:int = 0; i < secs.length; i++)
            {
                if (i > 0) h = h + DocsStyle.SEC_GAP;
                h = h + DocSection(secs[i]).height(wrapW);
            }
            return h;
        }

        // How many children escape the box their author drew them in, plus how many
        // prose lines paint wider than their box. Two rect levels:
        // the block's own children (heading / prose / demo / source), and the demo
        // surface's children (what the example built). Deeper is not checked -- a
        // demo may legitimately paint outside its own parent (a badge at a negative
        // inset), and the arithmetic this guard exists for is exactly these two.
        private function overflowingBlocks():int
        {
            var bad:int = 0;
            var col:UiNode = this.app.findByKey("docCol");
            if (col == null) return 0;
            for (var i:int = 0; i < col.children.length; i++)
            {
                var b:UiNode = col.children[i];
                if (String(b.key).charAt(0) != "b") continue;
                var n:int = this.escapes(b, b.children);
                if (n > 0)
                {
                    bad = bad + n;
                    if (bad <= 3) this.report = this.report + "    overflow in " + String(b.key) + "\n";
                }
                for (var j:int = 0; j < b.children.length; j++)
                {
                    var d:UiNode = b.children[j];
                    if (String(d.key) != String(b.key) + ":demo") continue;
                    bad = bad + this.escapes(d, d.children);
                }
            }
            return bad + this.inkWide(col);
        }

        // A PROSE LINE THAT PAINTS WIDER THAN ITS OWN BOX.
        //
        // DocSection wraps prose at the reading width through DocsWrap. On the ASCII
        // path that means measuring candidate lines in a scratch TextField; a mixed
        // Chinese paragraph is filled by summing advances instead, because the same
        // measurement under-reports those runs. Whichever path produced the line, the
        // gate is the same: the ink must stay inside the box. When the measurement
        // disagrees with the renderer every RECT is still right (the node carries the
        // point width) and only the INK runs past it -- the line slides under the
        // scroll bar and off the pane, which is the reported defect and something
        // escapes() cannot see.
        //
        // A wrapped node cannot fail this by construction (the renderer broke it), so
        // the check is scoped to prose LINES: keys of the form `<block>:p<n>`.
        private function inkWide(root:UiNode):int
        {
            var bad:int = 0;
            var stack:Array = [root];
            while (stack.length > 0)
            {
                var n:UiNode = stack.pop();
                var k:String = String(n.key);
                if (n.tf != null && this.isProseLine(k) && n.tf.textWidth > n.absW + 0.5)
                {
                    bad = bad + 1;
                    if (bad <= 3)
                    {
                        this.report = this.report + "    prose line " + k + " paints "
                            + n.tf.textWidth + "pt of ink in a " + n.absW + "pt box\n";
                    }
                }
                for (var i:int = 0; i < n.children.length; i++) stack.push(n.children[i]);
            }
            return bad;
        }

        // `b3:p12` is a prose line. `b3:prose` (the column that holds them) is not,
        // which is why the tail has to be all digits and not just start with a p.
        private function isProseLine(k:String):Boolean
        {
            var ix:int = k.lastIndexOf(":p");
            if (ix < 0) return false;
            var tail:String = k.substring(ix + 2);
            if (tail.length == 0) return false;
            for (var i:int = 0; i < tail.length; i++)
            {
                var c:String = tail.charAt(i);
                if (c < "0" || c > "9") return false;
            }
            return true;
        }

        // Counts children of `box` whose solved rect is not inside it.
        private function escapes(box:UiNode, kids:Vector.<UiNode>):int
        {
            var bad:int = 0;
            for (var i:int = 0; i < kids.length; i++)
            {
                var c:UiNode = kids[i];
                if (c.absY + c.absH > box.absY + box.absH + 0.5
                    || c.absX + c.absW > box.absX + box.absW + 0.5
                    || c.absY < box.absY - 0.5 || c.absX < box.absX - 0.5)
                {
                    bad = bad + 1;
                    if (bad <= 2)
                    {
                        this.report = this.report + "    " + String(box.key) + "/" + String(c.key)
                            + " child#" + i + " " + c.absX + "," + c.absY + "," + c.absW + "," + c.absH
                            + " box " + box.absX + "," + box.absY + "," + box.absW + "," + box.absH
                            + " nKids " + kids.length + "\n";
                    }
                }
            }
            return bad;
        }

        // A press at a node's solved centre, through the stage's mouse pipeline.
        // The app routes a press by hit-testing the stage at a point, so dispatching
        // CLICK straight at the sprite would prove nothing about routing (and in fact
        // never reaches the handler).
        private function click(n:UiNode):void
        {
            var cx:Number = n.absX + n.absW / 2;
            var cy:Number = n.absY + n.absH / 2;
            this.stage.dispatchMouse(cx, cy, "mouseDown");
            this.stage.dispatchMouse(cx, cy, "mouseUp");
            // The runtime does NOT synthesise CLICK from a down+up pair: the window
            // glue sends "click" as its own type (src/emit.ts:25035) and the test
            // hook only dispatches whatever type it is given. UiNode installs its
            // handler on MouseEvent.CLICK, so the pair alone is a no-op.
            this.stage.dispatchMouse(cx, cy, "click");
        }

        private function tf(key:String):String
        {
            var n:UiNode = this.app.findByKey(key);
            if (n == null || n.tf == null) return "";
            return n.tf.text;
        }

        private function rect(key:String, x:Number, y:Number, w:Number, h:Number):String
        {
            var n:UiNode = this.app.findByKey(key);
            if (n == null) return key + " missing (expected " + x + "," + y + "," + w + "," + h + "); ";
            if (n.absX != x || n.absY != y || n.absW != w || n.absH != h)
            {
                return key + " is at " + n.absX + "," + n.absY + "," + n.absW + "," + n.absH
                    + ", expected " + x + "," + y + "," + w + "," + h + "; ";
            }
            return "";
        }

        // Counts the conditions that make a node silently unplaced (both measureSelf
        // and arrangeSelf early-return on a null engine node, so such a node reports
        // 0,0,0,0 and would otherwise pass every rect check). The first few OFFENDING
        // keys are kept in acc.text, because "3 zero-rect nodes" without names sends
        // you looking for them by hand.
        private function treeDiag(n:UiNode, depth:int, acc:Object):void
        {
            if (n == null) return;
            acc.total = int(acc.total) + 1;
            if (n.engineNode == null)
            {
                acc.nullEng = int(acc.nullEng) + 1;
            }
            else if (n.absW == 0 && n.absH == 0)
            {
                acc.zero = int(acc.zero) + 1;
                if (int(acc.zero) <= 4) acc.text = String(acc.text) + " zero[" + String(n.key) + ":" + n.kind + "]";
            }
            if (n.backing != null && n.backing.parent == null) acc.detached = int(acc.detached) + 1;
            for (var i:int = 0; i < n.children.length; i++) this.treeDiag(n.children[i], depth + 1, acc);
        }

        // Progress beacon: flush the report so far plus the current stage name, so a
        // crash mid-tour leaves evidence (an uncaught #1009 stops the frame loop and
        // the finished report is never written).
        private function mark(s:String):void
        {
            this.at = s;
            this.out(OUT + ".txt", this.report + "  [at " + s + "" + (this.problems == "" ? "" : "] problems: " + this.problems) + "]\n");
        }

        private function out(p:String, txt:String):void
        {
            var f:File = File.applicationDirectory.resolvePath(p);
            var fs:FileStream = new FileStream();
            fs.open(f, FileMode.WRITE);
            fs.writeUTFBytes(txt);
            fs.close();
        }
    }
}

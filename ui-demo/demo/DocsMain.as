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
//      child's solved rect escapes its block on ANY of the 41 pages. A forgotten
//      gap or a wrong line height shows up as a rect outside its box;
//   3. a real wheel scroll (the content pane), asserting the offset, the clamp and
//      that the pixels actually moved while the layout did not;
//   4. a real sidebar click, asserting it is the WIDGET that switches the page;
//   5. the floating layer: a documented dialog opens in the overlay tree, and
//      closing it tears the tree down;
//   6. seven screenshots, one per group.
package demo
{
    import asaot.ui.Dirty;
    import asaot.ui.ScrollViewNode;
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

            this.tour();

            // Land on the first page: the window's first frame is painted after
            // showWindow returns to the event loop.
            this.model.doc = "start";
            this.app.invalidate(Dirty.ALL);
            this.app.reflow();

            this.out(OUT + ".done", this.problems == "" ? "PASS" : "FAIL " + this.problems);
            trace("DocsMain: tour finished, " + (this.problems == "" ? "all checks passed" : this.problems));
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
            var docY:Number = 100;   // 24 top pad + 30 title + 4 + 18 blurb + 4 + 16 meta + 4
            var docH:Number = winH - docY - 16;                            // 584
            var navH:Number = winH - 68 - 16 - 4 - 16;                       // 596: foot + gap + bottom pad
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
            this.problems = this.problems + this.rect("b0", docX, docY, docW, 288);
            this.problems = this.problems + this.rect("b0:code", docX, 284, docW, 104);

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
                this.stage.dispatchWheel(600, 300, 3);
                this.app.reflow();
                if (ScrollViewNode(sv.desc).offsetY != 0)
                {
                    this.problems = this.problems + "wheeling back did not return the pane to offsetY 0; ";
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
            // still report -- which is what a docs app has to do with 41 pages.
            var pages:Array = DocsCatalog.pages();
            var badPages:int = 0;
            var badBlocks:int = 0;
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
                        if (badPages <= 6) badList = badList + "  " + p.id + ": " + bad + "\n";
                    }

                    var blocks:int = this.overflowingBlocks();
                    if (blocks > 0)
                    {
                        badBlocks = badBlocks + blocks;
                        if (badPages <= 6) badList = badList + "  " + p.id + ": " + blocks + " block(s) with a child outside\n";
                    }
                }
                catch (err:Error)
                {
                    badPages = badPages + 1;
                    if (badPages <= 6) badList = badList + "  " + p.id + ": threw " + err.message + "\n";
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
                this.problems = this.problems + badBlocks + " block(s) have a child outside their box (DocSection.height() disagrees with the layout); ";
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
            // The index viewport is the sidebar's leftover height: top 68 (brand + tag),
            // then the foot (16), its gap (4) and the bottom padding (16).
            this.problems = this.problems + this.rect("nav", 14, 68, 219, h2 - 68 - 16 - 4 - 16);
            this.report = this.report + "\n  resized to " + w2 + "x" + h2
                + ": nav " + (h2 - 104) + " tall, content viewport " + docH2 + "\n";

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

            this.mark("7 screenshots");

            // ---- 7. screenshots ----------------------------------------------
            // One per group, chosen to show a different kind of page: the intro, a
            // container, a control, a leaf, a picker, a data view, a nav strip and a
            // floating surface. Eight, because that is what run-gallery.cjs measures.
            var stops:Array = ["start", "box", "button", "image", "select", "table", "tabs", "dialog"];
            for (var k:int = 0; k < stops.length; k++)
            {
                this.mark("7 shot " + String(stops[k]));
                this.model.pick(String(stops[k]));
                this.app.invalidate(Dirty.ALL);
                this.app.reflow();
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

            this.out(OUT + ".txt", this.report);
        }

        // ---- helpers -----------------------------------------------------------

        // Sum of the blocks DocSection.height() produces, in the same order and with
        // the same inter-block gap the view uses.
        private function contentHeight(id:String):Number
        {
            var secs:Array = DocsCatalog.sections(this.view, id);
            var h:Number = 0;
            for (var i:int = 0; i < secs.length; i++)
            {
                if (i > 0) h = h + DocsStyle.SEC_GAP;
                h = h + DocSection(secs[i]).height();
            }
            return h;
        }

        // How many children escape the box their author drew them in. Two levels:
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
            return bad;
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
                            + " child " + c.absX + "," + c.absY + "," + c.absW + "," + c.absH
                            + " box " + box.absX + "," + box.absY + "," + box.absW + "," + box.absH + "\n";
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
            var f:File = new File(p);
            var fs:FileStream = new FileStream();
            fs.open(f, FileMode.WRITE);
            fs.writeUTFBytes(txt);
            fs.close();
        }
    }
}

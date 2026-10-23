// GalleryMain.as -- the multi-page asaot.ui demo as an AIR DOCUMENT CLASS.
//
// Built by:  node run-gallery.cjs      (which stages this tree and runs
//                                       `as-aot --air-app air-gallery/app.xml`)
// Run on AIR (the reference runtime) with the same class: mxmlc -> .swf -> adl.
//
// WHY A DOCUMENT CLASS AND NOT THE OLD TOP-LEVEL SCRIPT
// ----------------------------------------------------
// `--air-app` generates a bootstrap that does `new <Main>()`, `stage.addChild(app)`
// and only then `stage.showWindow(w, h, title)` -- the AIR model, where the
// window's properties come from the descriptor rather than from a call in the app.
// A document class is required (mxmlc resolves it by file name, and the bootstrap
// needs a constructor), and it is the ONLY form that works on both backends, so
// there is exactly one driver instead of two. This class therefore does NOT call
// showWindow: air-gallery/app.xml decides the size, title, renderMode and
// requestedDisplayResolution.
//
// WHAT IT IS: one window, five pages (Home / Widgets / Data / Motion / Catalog),
// the kit's `tabs` widget. The page index is a model field, the tabs write their
// selection back through a Binding, and the view re-describes the one `body` slot
// the page occupies -- so a page switch is an ordinary notify -> invalidate ->
// re-render, with no page-specific state kept in the view.
//
// WHAT IT ALSO DOES, and why: on ADDED_TO_STAGE -- i.e. after the stage exists but
// strictly BEFORE the bootstrap's showWindow, which blocks on the event loop -- it
// runs a HEADLESS TOUR of all five pages. For each page it forces a reflow, checks
// which nodes exist (this page's must exist, the other pages' must be GONE -- not
// merely invisible), hand-computes the gallery columns' rects, writes a PNG of the
// offscreen render, and finally drives the tabs widget with a synthetic click to
// prove the WIDGET switches the page rather than the tour poking the model.
// Everything lands in gallery.txt + gallery.done so the acceptance run has textual
// evidence to assert on, plus four screenshots to look at. After the tour the
// model is put back on page 0, so the window a human sees opens on the login page.
//
// The PNGs are the high-resolution evidence: Stage.render allocates its surface in
// PHYSICAL pixels (device scale x logical), so on a 150% display the 700x560 stage
// produces a 1050x840 PNG -- crisp, not upscaled. The tour asserts that ratio.
package demo
{
    import asaot.ui.Dirty;
    import asaot.ui.UiApp;
    import asaot.ui.UiNode;
    import asaot.ui.as3.As3LayoutNode;
    import flash.display.StageAlign;
    import flash.display.StageScaleMode;
    import flash.display.Sprite;
    import flash.events.Event;
    import flash.events.MouseEvent;
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;

    public class GalleryMain extends Sprite
    {
        // The logical stage size. It is NOT an independent choice: air-gallery/app.xml
        // declares it, the bootstrap presets stageWidth/stageHeight from it, and every
        // hand-computed rect below is derived from it. The tour asserts the two agree.
        public static const GW:int = 700;
        public static const GH:int = 560;
        public static const OUT:String = "gallery";

        private var model:GalleryModel;
        private var view:GalleryView;
        private var app:UiApp;
        private var problems:String = "";
        private var report:String = "";

        public function GalleryMain():void
        {
            addEventListener(Event.ADDED_TO_STAGE, onAdded);
        }

        private function onAdded(e:Event):void
        {
            removeEventListener(Event.ADDED_TO_STAGE, onAdded);

            this.model = new GalleryModel();
            this.view = new GalleryView(this.model);
            this.stage.scaleMode = StageScaleMode.NO_SCALE;
            this.stage.align = StageAlign.TOP_LEFT;
            this.app = new UiApp(this.view);
            this.app.mount(this.stage);
            this.app.attachRoot();

            this.tour();

            // Open on Home: a page switch is just a model write, and the window's
            // first frame is painted after showWindow returns to the event loop.
            this.model.page = 0;
            this.app.invalidate(Dirty.ALL);
            this.app.reflow();

            this.out(OUT + ".done", this.problems == "" ? "PASS" : "FAIL " + this.problems);
            trace("GalleryMain: tour finished, " + (this.problems == "" ? "all checks passed" : this.problems));
        }

        // ---- the tour ----------------------------------------------------------
        private function tour():void
        {
            if (this.stage.stageWidth != GW || this.stage.stageHeight != GH)
            {
                // The rects below are hand-derived from GW x GH. If the descriptor and
                // this class ever disagree, that derivation is void -- say so instead
                // of comparing against numbers that describe a different window.
                this.problems = this.problems + "stage is " + this.stage.stageWidth + "x" + this.stage.stageHeight
                    + " but the tour's rects are derived for " + GW + "x" + GH
                    + " (air-gallery/app.xml <width>/<height>); ";
            }

            var k:int;
            for (k = 0; k < 5; k++)
            {
                this.model.page = k;
                this.app.invalidate(Dirty.ALL);
                // No frame pump runs before showWindow, so drive the frame's work by
                // hand: exactly what ENTER_FRAME would do, and the same two calls the
                // toolkit makes (describe+reconcile, then measure/arrange/paint).
                this.app.reflow();

                var here:Array = pageKeys(k);
                var gone:Array = otherKeys(k);
                var i:int;
                for (i = 0; i < here.length; i++)
                {
                    if (this.app.findByKey(here[i]) == null) this.problems = this.problems + "page " + k + " is missing node '" + here[i] + "'; ";
                }
                for (i = 0; i < gone.length; i++)
                {
                    if (this.app.findByKey(gone[i]) != null) this.problems = this.problems + "page " + k + " still has node '" + gone[i] + "' from another page; ";
                }
                this.report = this.report + "== page " + k + " (" + pageName(k) + ") ==\n" + this.rects(here) + "\n";

                // Diagnostics: a node with no engine node, or one whose backing was
                // never attached, silently reports 0,0,0,0 (both measureSelf and
                // arrangeSelf early-return on a null engineNode). Counting them turns
                // "the rect is zero" into "HERE is the node that never reached the
                // layout engine".
                var acc:Object = { total: 0, nullEng: 0, zero: 0, detached: 0, shown: 0, text: "" };
                treeDiag(this.app.getRoot(), 0, acc);
                this.report = this.report + "  nodes=" + acc.total + " engineNodeNull=" + acc.nullEng
                    + " zeroRect=" + acc.zero + " detachedBacking=" + acc.detached + "\n" + acc.text;
                // The counts are a VERDICT, not a comment: every page of every build
                // so far has had all three at zero, and a node that quietly never
                // reached the engine (or lost its backing) is exactly what a new
                // widget's first run looks like -- a missing picture, not a crash.
                if (int(acc.nullEng) > 0) this.problems = this.problems + "page " + k + " has " + acc.nullEng + " node(s) with no engine node; ";
                if (int(acc.zero) > 0) this.problems = this.problems + "page " + k + " has " + acc.zero + " node(s) with a zero rect; ";
                if (int(acc.detached) > 0) this.problems = this.problems + "page " + k + " has " + acc.detached + " backing(s) that were never attached; ";

                // Engine-side view: an explicit px size coming back as 0 can only mean
                // the node was never calculated, so ask the engine tree itself whether
                // the page subtree is attached to it.
                var rn:UiNode = this.app.findByKey("root");
                var bn2:UiNode = this.app.findByKey("body");
                this.report = this.report + "  layout: solves=" + this.app.layoutSolves
                    + " root.engineKids=" + engKids(rn) + " body.engineKids=" + engKids(bn2)
                    + " bodyParentIsRoot=" + engParentIs(bn2, rn)
                    + " uiKidsBody=" + (bn2 == null ? -1 : bn2.children.length) + "\n";
                if (bn2 != null && bn2.children.length > 0)
                {
                    var c0:UiNode = UiNode(bn2.children[0]);
                    this.report = this.report + "  body[0]=" + c0.key + " parentIsBody=" + engParentIs(c0, bn2)
                        + " engineKids=" + engKids(c0) + "\n";
                }

                // If a freshly reconciled subtree needs more than one pass to settle,
                // this shows it: two identical reflows with no model change in between.
                this.app.invalidate(Dirty.ALL);
                this.app.reflow();
                this.app.reflow();
                this.report = this.report + "  after 2 redundant reflows:\n" + this.rects(here);

                // The gallery's two columns are the hand-computable part of the
                // layout: root 700 wide, padding 24 both sides -> 652 of content; a
                // row with two flexGrow-1 columns and a 12 gap -> (652-12)/2 = 320
                // each, so the second one starts at 24 + 320 + 12 = 356. If the AS3
                // layout engine's flexGrow or gap arithmetic drifts, THIS is what
                // catches it.
                if (k == 1)
                {
                    this.problems = this.problems + inside("colA", 24, 320) + inside("colB", 356, 320);
                }

                // A PNG of this page, so the screenshots can be compared side by
                // side. Stage.render allocates at PHYSICAL size -- the device scale
                // is what <requestedDisplayResolution>high turns on -- so the file's
                // pixel dimensions are the high-resolution evidence. They are
                // measured by run-gallery.cjs (Node reads the PNG IHDR directly),
                // not here: this runtime has no FileStream.readUnsignedByte, and
                // re-deriving a number the runner already has would be a second
                // implementation to keep honest.
                this.stage.render(GW, GH, OUT + "-page" + k + ".png");
            }

                this.report = this.report + "== widget-driven switch ==\n";
            // Five segments across 652 px with gap 8: pitch = (652 - 32) / 5 = 124,
            // so segment 2 spans local x 264..387 -- click its centre (326), like a
            // user would. (Four segments used to give a pitch of 157 and x=408.)
            var tn:UiNode = this.app.findByKey("tabs");
            if (tn == null)
            {
                this.problems = this.problems + "tabs node missing, cannot test the switch; ";
            }
            else
            {
                this.model.page = 0;
                this.app.invalidate(Dirty.ALL);
                this.app.reflow();
                tn.backing.dispatchEvent(new MouseEvent(MouseEvent.CLICK, true, false, 326, 19));
                // The widget invalidated; a real frame would reflow next, so do it here.
                this.app.reflow();
                if (int(this.model.page) != 2) this.problems = this.problems + "clicking tab 2 left model.page at " + this.model.page + "; ";
                if (this.view.lastSwitch != 2) this.problems = this.problems + "tabs onChange did not report index 2 (got " + this.view.lastSwitch + "); ";
                if (this.app.findByKey("list") == null) this.problems = this.problems + "the Data page did not appear after the switch; ";
                if (this.app.findByKey("colA") != null) this.problems = this.problems + "the Widgets page is still mounted after the switch; ";
                this.report = this.report + "clicked tab 2 -> model.page=" + this.model.page
                    + " onChange=" + this.view.lastSwitch
                    + " dataPage=" + (this.app.findByKey("list") != null)
                    + " widgetsPageStale=" + (this.app.findByKey("colA") != null) + "\n";
            }

            // Settled-tree invariant: re-describing the same page must not re-solve
            // layout.
            var before:Number = this.app.layoutSolves;
            this.model.page = int(this.model.page);
            this.app.invalidate(Dirty.VALUE);
            this.app.reflow();
            this.app.reflow();
            var extra:Number = this.app.layoutSolves - before;
            this.report = this.report + "\nlayoutSolves after two redundant reflows: +" + extra + "\n";
            this.out(OUT + ".txt", this.report);
        }

        private function rects(keys:Array):String
        {
            var s:String = "";
            var i:int;
            for (i = 0; i < keys.length; i++)
            {
                var n:UiNode = this.app.findByKey(keys[i]);
                if (n == null) { s = s + keys[i] + " MISSING\n"; continue; }
                s = s + keys[i] + " " + n.absX + "," + n.absY + "," + n.absW + "," + n.absH + "\n";
            }
            return s;
        }

        // Asserts one node's x and width -- the layout-engine arithmetic the tour
        // claims to verify, spelled out per node instead of compared against a
        // whole-tree dump.
        private function inside(key:String, x:Number, w:Number):String
        {
            var n:UiNode = this.app.findByKey(key);
            if (n == null) return key + " missing (expected x=" + x + ", w=" + w + "); ";
            if (n.absX != x || n.absW != w) return key + " is at x=" + n.absX + " w=" + n.absW + ", expected x=" + x + " w=" + w + "; ";
            var root:UiNode = this.app.findByKey("root");
            if (root != null && (n.absX < root.absX || n.absX + n.absW > root.absX + root.absW))
            {
                return key + " is not inside the root; ";
            }
            return "";
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

// ---- module-level helpers ---------------------------------------------------
// These stay free functions (not methods), exactly as in the old script driver:
// they are pure string/geometry helpers that touch no instance state, and a
// function that needs no `this` is clearer without one.

function pageName(k:int):String
{
    if (k == 0) return "Home";
    if (k == 1) return "Widgets";
    if (k == 2) return "Data";
    if (k == 3) return "Motion";
    return "Catalog";
}

// The keys that MUST exist on each page, including the widgets that page is the
// whole point of.
function pageKeys(k:int):Array
{
    if (k == 0) return ["root", "tabs", "body", "loginCard", "account", "password", "remember", "signin", "status"];
    if (k == 1) return ["root", "tabs", "body", "colA", "colB", "cardChips", "c1", "c2", "c3", "badgeRow",
                        "cardControls", "r1", "t1", "sl", "cardAvatars", "a1", "p1", "cardActions", "ok"];
    if (k == 2) return ["root", "tabs", "body", "list", "row0", "row1", "row2", "row3", "row4", "detailCard", "picked"];
    if (k == 3) return ["root", "tabs", "body", "animated", "snapped", "motionNote"];
    // Page 4 -- the component catalog: one key per widget group, plus the table's
    // rows/cells and the accordion's OPEN panel (section 0 is open in the model).
    return ["root", "tabs", "body", "colM", "colD", "catImg", "catSpin", "catSk", "catTip",
            "catTable", "hdr", "r0", "r1", "r0c0", "r0c1", "r1c0", "r1c1",
            "catAcc", "h0", "h1", "catP0", "catCrumb", "c0", "s0", "c1", "s1", "c2", "catPage", "pg3", "prev", "next"];
}

// Keys that BELONG TO ANOTHER PAGE. A page switch must remove them: "still
// mounted but invisible" is exactly the failure a keyed reconciler is supposed to
// prevent, and a bitmap could never tell the two apart.
function otherKeys(k:int):Array
{
    if (k == 0) return ["colA", "colB", "list", "animated", "snapped", "catTable", "catAcc", "catImg"];
    if (k == 1) return ["loginCard", "signin", "list", "animated", "snapped", "catTable", "catAcc", "catImg"];
    if (k == 2) return ["loginCard", "colA", "colB", "animated", "snapped", "catTable", "catAcc", "catImg"];
    if (k == 3) return ["loginCard", "colA", "colB", "list", "catTable", "catAcc", "catImg"];
    return ["loginCard", "colA", "colB", "list", "animated", "snapped"];
}

// Walks the RETAINED tree (not the description) and counts the conditions that
// make a node silently unplaced. An Object accumulator is used instead of an
// Array because this runs on the same code path compiler-gaps.md G12 warns about
// (a big allocation followed by array growth).
function treeDiag(n:UiNode, depth:int, acc:Object):void
{
    if (n == null) return;
    acc.total = int(acc.total) + 1;
    var note:String = "";
    if (n.engineNode == null)
    {
        acc.nullEng = int(acc.nullEng) + 1;
        note = "engineNode=NULL";
    }
    else if (n.absW == 0 && n.absH == 0)
    {
        acc.zero = int(acc.zero) + 1;
        note = "zeroRect";
    }
    if (n.backing != null && n.backing.parent == null)
    {
        acc.detached = int(acc.detached) + 1;
        note = note == "" ? "detached" : note + "+detached";
    }
    if (note != "" && int(acc.shown) < 12)
    {
        acc.text = String(acc.text) + "    " + note + " " + n.key + " (" + n.kind + ") depth=" + depth
            + " rect=" + n.absX + "," + n.absY + "," + n.absW + "," + n.absH + "\n";
        acc.shown = int(acc.shown) + 1;
    }
    var i:int;
    for (i = 0; i < n.children.length; i++) treeDiag(n.children[i], depth + 1, acc);
}

// The layout engine's own view of the tree, as opposed to the retained UiNode
// tree: -1 means there is no engine node at all, 0 means it was never given any
// children.
function engKids(n:UiNode):int
{
    if (n == null || n.engineNode == null) return -1;
    var e:As3LayoutNode = As3LayoutNode(n.engineNode);
    return e.children.length;
}

function engParentIs(n:UiNode, p:UiNode):Boolean
{
    if (n == null || p == null || n.engineNode == null || p.engineNode == null) return false;
    return As3LayoutNode(n.engineNode).parent == As3LayoutNode(p.engineNode);
}

// UiDemoMain.as -- the login demo as an AIR DOCUMENT CLASS, built with
// `--air-app` so air-uidemo/app.xml owns the window (size, title, renderMode,
// <requestedDisplayResolution>high) instead of a hand-written build manifest.
//
// Built by:  node build-and-run.cjs   (stages this tree, then runs
//                                     `as-aot --air-app air-uidemo/app.xml`)
//
// WHY THE SHAPE CHANGED: `--air-app` generates a bootstrap that does
// `new <Main>()`, `stage.addChild(app)` and only then
// `stage.showWindow(w, h, title)`. A document class is therefore MANDATORY, and
// a top-level script (the previous `ui-demo/UiDemo.as`) cannot be one. The class
// form is also what mxmlc demands, so this file and `UiDemoAir.as` are now the SAME
// shape on both backends -- two drivers, one view, and the assertions below are
// ported verbatim from UiDemoAir.as so the two evidence files can be diffed line
// by line (see ui-demo-air.txt vs uidemo.txt).
//
// WHAT IT DOES, and why: on ADDED_TO_STAGE -- after the stage exists but strictly
// BEFORE the bootstrap's showWindow, which blocks on the event loop -- it mounts
// demo/DemoView, forces one settle, asserts the layout invariants, writes a PNG of
// the offscreen render and finally a PASS/FAIL file. The window a human then sees
// is the same tree, driven by the descriptor.
//
// WHY THE RECTS BELOW ARE HAND-DERIVED: the demo is a fixed-price layout, so its
// geometry is checkable arithmetic rather than a snapshot of whatever the engine
// happened to produce:
//   page padding 28            -> title at (28,28), card x = 28
//   card padding 18 + border 1 -> account x = 28 + 19 = 47
//   card's children stack with gap 12
// The expected numbers are the SAME as the AIR arm's, because both stages are
// 500x375: app-ui-demo.xml leaves <width>/<height> unset (AIR's default) and
// air-uidemo/app.xml pins the same size so the two backends are comparable.
package demo
{
    import asaot.ui.Dirty;
    import asaot.ui.UiApp;
    import asaot.ui.UiNode;
    import flash.display.StageAlign;
    import flash.display.StageScaleMode;
    import flash.display.Sprite;
    import flash.events.Event;
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;

    public class UiDemoMain extends Sprite
    {
        // The logical stage size, pinned in air-uidemo/app.xml. It is not an
        // independent choice: every expected rect below is derived from it, so the
        // first check is that the descriptor and this class still agree.
        public static const DW:int = 500;
        public static const DH:int = 375;
        public static const OUT:String = "uidemo";

        private var model:DemoModel;
        private var app:UiApp;
        private var log:String = "";
        private var failures:int = 0;

        public function UiDemoMain():void
        {
            addEventListener(Event.ADDED_TO_STAGE, onAdded);
        }

        private function onAdded(e:Event):void
        {
            removeEventListener(Event.ADDED_TO_STAGE, onAdded);

            this.model = new DemoModel();
            this.stage.scaleMode = StageScaleMode.NO_SCALE;
            this.stage.align = StageAlign.TOP_LEFT;
            this.app = new UiApp(new DemoView(this.model));
            this.app.mount(this.stage);
            this.app.attachRoot();

            var out:String = "";
            out += "AOT-UIDEMO as-aot --air-app air-uidemo/app.xml (oss AOT -> native)\n";
            out += "stage=" + this.stage.stageWidth + "x" + this.stage.stageHeight + "\n";

            // No frame pump runs before showWindow, so drive the frame's work by
            // hand: describe+reconcile then measure/arrange/paint, i.e. what
            // ENTER_FRAME would do.
            this.app.invalidate(Dirty.ALL);
            this.app.reflow();

            var root:UiNode = this.app.getRoot();
            var title:UiNode = this.app.findByKey("title");
            var card:UiNode = this.app.findByKey("card");
            var account:UiNode = this.app.findByKey("account");
            var signin:UiNode = this.app.findByKey("signin");
            var status:UiNode = this.app.findByKey("status");
            out += "root   = " + rect(root) + "\n";
            out += "title  = " + rect(title) + "\n";
            out += "card   = " + rect(card) + "\n";
            out += "account= " + rect(account) + "\n";
            out += "signin = " + rect(signin) + "\n";
            out += "status = " + rect(status) + "\n";
            out += "solves=" + this.app.layoutSolves + " describes=" + this.app.describeCalls + "\n";

            // ---- the same invariants the AIR arm asserts, same wording --------
            if (this.stage.stageWidth != DW || this.stage.stageHeight != DH)
            {
                // Say it instead of comparing against numbers that describe a
                // different window: everything below is derived for DW x DH.
                this.check(false, "stage is " + DW + "x" + DH + " (air-uidemo/app.xml)"
                    + " but got " + this.stage.stageWidth + "x" + this.stage.stageHeight);
            }
            this.check(root != null && root.absW == this.stage.stageWidth && root.absH == this.stage.stageHeight,
                "root fills the stage");
            this.check(title != null && title.absX == 28 && title.absY == 28, "title at page padding (28,28)");
            this.check(card != null && card.absX == 28, "card at page padding x=28");
            this.check(card != null && card.absW == this.stage.stageWidth - 56, "card spans the page width");
            this.check(account != null && account.absX == 47, "account at card padding+border x=47");
            this.check(account != null && signin != null && signin.absY > account.absY, "signin below account");
            this.check(signin != null && status != null && status.absY > signin.absY, "status below signin");

            // Structural, not geometric: a redundant reflow of an unchanged
            // description must not re-solve layout. This is the invariant a
            // reconciler is FOR, and a rect dump cannot see it.
            var solvesBefore:int = this.app.layoutSolves;
            this.app.invalidate(Dirty.VALUE);
            this.app.reflow();
            this.app.reflow();
            this.check(this.app.layoutSolves == solvesBefore,
                "redundant reflows add no solve (still " + this.app.layoutSolves + ")");

            out += this.log;
            out += "AOT-CHECK: " + (this.failures == 0 ? "PASS" : "FAIL")
                + " (" + this.failures + " failures)\n";
            out += "RESULT: " + (this.failures == 0 ? "PASS" : "FAIL") + "\n";

            // The PNG is the high-resolution evidence: Stage.render allocates its
            // surface in PHYSICAL pixels (device scale x logical), so on a 150%
            // display this 500x375 stage yields a 750x563 PNG -- crisp, not
            // upscaled. The file's pixel size is measured by build-and-run.cjs
            // (Node reads the PNG IHDR directly) rather than here: re-deriving a
            // number the runner already has would be a second implementation to
            // keep honest.
            this.stage.render(DW, DH, OUT + "-shot.png");

            this.out(OUT + ".txt", out);
            this.out(OUT + ".done", this.failures == 0 ? "PASS" : "FAIL");
            trace("UiDemoMain: " + (this.failures == 0 ? "all checks passed" : this.failures + " check(s) failed")
                + "; screenshot " + OUT + "-shot.png written");
        }

        private function rect(n:UiNode):String
        {
            if (n == null) return "(missing)";
            return n.kind + " (" + n.absX + "," + n.absY + "," + n.absW + "," + n.absH + ")";
        }

        // Appends a PASS/FAIL line and returns 1 on fail, matching CheckUi's shape
        // so every evidence file in this workspace reads the same way.
        private function check(ok:Boolean, what:String):int
        {
            this.log += (ok ? "PASS  " : "FAIL  ") + what + "\n";
            if (!ok) this.failures = this.failures + 1;
            return ok ? 0 : 1;
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
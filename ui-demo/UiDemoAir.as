// asaot.ui demo -- the AIR driver (Deliverable 2, second backend).
//
// Same UI (demo/DemoView.as) mounted on AIR's real stage. AIR opens and shows
// its own window for the SWF, so there is no showWindow here; and it cannot be
// asked to "run until closed" from a test, so after the first frame we write
// evidence to a file and exit -- the air-check idiom (adl never self-exits; on
// Windows trace() does not reach adl.exe's stdout, so the file IS the result
// channel). The evidence file is SELF-CHECKING: it asserts the layout
// invariants and reports RESULT: PASS/FAIL, and exits non-zero on failure.
//
// Why a Sprite document class: mxmlc resolves the document class by file name and
// rejects a script with only top-level statements, and `--air-app`'s generated
// bootstrap needs a constructor to call. The AOT entry therefore has the SAME shape
// (demo/UiDemoMain.as), and it asserts the same hand-derived rects, so the two
// backends' evidence files can be diffed line by line. The UI code is shared, not
// duplicated.
package
{
    import asaot.ui.UiApp;
    import asaot.ui.UiNode;
    import demo.DemoModel;
    import demo.DemoView;

    import flash.desktop.NativeApplication;
    import flash.display.Sprite;
    import flash.events.Event;
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;

    public class UiDemoAir extends Sprite
    {
        private var app:UiApp;
        private var model:DemoModel;
        private var frames:int = 0;

        public function UiDemoAir():void
        {
            addEventListener(Event.ADDED_TO_STAGE, onAdded);
        }

        private function onAdded(e:Event):void
        {
            removeEventListener(Event.ADDED_TO_STAGE, onAdded);
            this.model = new DemoModel();
            this.app = new UiApp(new DemoView(this.model));
            this.app.mount(this.stage);
            this.app.attachRoot();
            addEventListener(Event.ENTER_FRAME, onFrame);
        }

        private function rect(n:UiNode):String
        {
            if (n == null) return "(missing)";
            return n.kind + " (" + n.absX + "," + n.absY + "," + n.absW + "," + n.absH + ")";
        }

        private function onFrame(e:Event):void
        {
            this.frames = this.frames + 1;
            // Give the toolkit a couple of frames (mount reflow + one steady frame)
            // before we read the settled rectangles.
            if (this.frames < 3) return;
            removeEventListener(Event.ENTER_FRAME, onFrame);

            var out:String = "";
            out += "AIR-UIDEMO air=" + NativeApplication.nativeApplication.runtimeVersion
                 + " (mxmlc -> adl)\n";
            var root:UiNode = this.app.getRoot();
            var title:UiNode = this.app.findByKey("title");
            var card:UiNode = this.app.findByKey("card");
            var account:UiNode = this.app.findByKey("account");
            var signin:UiNode = this.app.findByKey("signin");
            var status:UiNode = this.app.findByKey("status");
            out += "stage=" + this.stage.stageWidth + "x" + this.stage.stageHeight + "\n";
            out += "root   = " + rect(root) + "\n";
            out += "title  = " + rect(title) + "\n";
            out += "card   = " + rect(card) + "\n";
            out += "account= " + rect(account) + "\n";
            out += "signin = " + rect(signin) + "\n";
            out += "status = " + rect(status) + "\n";
            out += "solves=" + this.app.layoutSolves + " describes=" + this.app.describeCalls + "\n";

            // ---- the same invariants CheckUi pins on our AOT, here on AIR ----
            this.log = "";
            var fails:int = 0;
            fails += check(root.absW == this.stage.stageWidth && root.absH == this.stage.stageHeight,
                "root fills the stage");
            fails += check(title.absX == 28 && title.absY == 28, "title at page padding (28,28)");
            fails += check(card.absX == 28, "card at page padding x=28");
            fails += check(account.absX == 47, "account at card padding+border x=47");
            fails += check(signin.absY > account.absY, "signin below account");
            fails += check(status.absY > signin.absY, "status below signin");
            fails += check(this.app.layoutSolves == 1 && this.app.describeCalls == 1,
                "exactly one describe + one solve");
            out += this.log;
            out += "AIR-CHECK: " + (7 - fails) + " checks, " + fails + " failures\n";
            out += fails == 0 ? "RESULT: PASS\n" : "RESULT: FAIL\n";
            trace(out);
            writeOut(out);
            NativeApplication.nativeApplication.exit(fails);
        }

        private var log:String;

        // Appends a PASS/FAIL line (same shape as CheckUi) and returns 1 on fail.
        private function check(ok:Boolean, what:String):int
        {
            this.log += (ok ? "PASS  " : "FAIL  ") + what + "\n";
            return ok ? 0 : 1;
        }

        private function writeOut(text:String):void
        {
            var dir:String = File.applicationDirectory.nativePath;
            var f:File = new File(dir + File.separator + 'ui-demo-air.txt');
            var fs:FileStream = new FileStream();
            fs.open(f, FileMode.WRITE);
            fs.writeUTFBytes(text);
            fs.close();
        }
    }
}

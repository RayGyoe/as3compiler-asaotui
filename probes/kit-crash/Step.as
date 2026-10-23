// probes/kit-crash/Step.as -- binary-search a CRASH in the asaot.ui toolkit.
//
// WHY THIS EXISTS: ui-demo/CheckUi.exe dies with 0xC0000005 (EXCEPTION_ACCESS_
// VIOLATION) and prints NOTHING, so the failure is invisible from the console.
// Two suspects are separated here:
//
//   (1) does the process crash in the toolkit (kit/) at all, or only in the
//       CheckUi-specific test view?
//   (2) WHICH step crashes?
//
// The step trace goes to a FILE, one line per step, opened/written/closed every
// time -- a file handle is not buffered the way stdout is, so the last line in
// the log survives a segfault. `trace()` is deliberately NOT used: on this
// failure mode the console showed nothing at all.
//
// Steps are intentionally one-per-statement so the last logged line names the
// crashing statement exactly.
import asaot.ui.*;
import asaot.ui.style.*;
import flash.filesystem.File;
import flash.filesystem.FileMode;
import flash.filesystem.FileStream;

var LOGFILE:File = File.applicationDirectory.resolvePath("step.txt");
function step(msg:String):void
{
    var fs:FileStream = new FileStream();
    try { fs.open(LOGFILE, FileMode.APPEND); fs.writeUTFBytes(msg + "\n"); fs.close(); }
    catch (e:Error) { }
}

// The view has to be a View subclass (render() describes the tree). Kept to the
// smallest possible tree so a crash cannot be blamed on the test tree's shape.
class StepView extends View
{
    override public function render():Node
    {
        return column({ key: "root" }, [
            box({ key: "a", size: [100, 40] })
        ]);
    }
}

step("S0 file+imports ok");

var view:StepView = new StepView();
step("S1 new StepView ok");

var stage:Stage = new Stage();
step("S2 new Stage ok");

var app:UiApp = new UiApp(view);
step("S3 new UiApp ok");

app.mount(stage);
step("S4 mount ok  (describe=" + app.describeCalls + " solves=" + app.layoutSolves + ")");

app.attachRoot();
step("S5 attachRoot ok");

var root:UiNode = app.getRoot();
step("S6 getRoot ok  " + (root == null ? "root=null" : ("root=" + root.kind)));

var a:UiNode = app.findByKey("a");
step("S7 findByKey ok  " + (a == null ? "a=null"
     : ("a=" + a.absX + "," + a.absY + "," + a.absW + "," + a.absH)));

app.reflow();
step("S8 steady reflow ok (solves=" + app.layoutSolves + ")");

step("DONE all steps survived");

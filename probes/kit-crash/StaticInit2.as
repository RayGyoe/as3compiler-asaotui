// probes/kit-crash/StaticInit2.as -- reproduce CheckView's EXACT static-const set.
//
// StaticInit.as cleared the single-const shapes. What is left different between it
// and ui-demo/CheckUi.as is:
//
//   * FIVE static consts on one class (vs one), and
//   * literals that MIX value kinds: a String (`flexDirection: "column"`),
//     Numbers (`padding`, `gap`, `flexGrow`) and an Array (`size: [560, 460]`)
//     in the same object literal.
//
// So this probe copies CheckView's five constants verbatim and nothing else, then
// touches the class. If the log stops here, the trigger is one of those two
// differences and the const at the cut point names it.
import asaot.ui.*;
import asaot.ui.style.*;
import flash.filesystem.File;
import flash.filesystem.FileMode;
import flash.filesystem.FileStream;

var LOGFILE:File = File.applicationDirectory.resolvePath("static2.txt");
function step(msg:String):void
{
    var fs:FileStream = new FileStream();
    try { fs.open(LOGFILE, FileMode.APPEND); fs.writeUTFBytes(msg + "\n"); fs.close(); }
    catch (e:Error) { }
}

// ---- stage A: one const at a time, plain class, mixed literal ---------------
class MixedOne
{
    // a literal with a String, a Number and an Array together
    public static const A1:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", padding: 20, gap: 10, size: [560, 460]
    });
    public function MixedOne():void { }
}

step("U0 start");
var m:MixedOne = new MixedOne();
step("U1 new MixedOne ok (1 mixed const)");
var ra:StyleRefinement = MixedOne.A1;
step("U2 read MixedOne.A1 ok");

// ---- stage B: the FULL set of five, in CheckView's order -------------------
class FiveConsts extends View
{
    private static const SZ_520_60:StyleRefinement = StyleRefinement.from({ size: [520, 60] });
    private static const SZ_200_100:StyleRefinement = StyleRefinement.from({ size: [200, 100] });
    private static const GROW:StyleRefinement = StyleRefinement.from({ flexGrow: 1 });
    private static const LAYOUT_ROOT:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", padding: 20, gap: 10, size: [560, 460]
    });
    private static const LAYOUT_BODY:StyleRefinement = StyleRefinement.from({
        flexDirection: "row", gap: 10, size: [520, 100]
    });
    public var mode:String = "base";
    public static function getRoot_():StyleRefinement { return LAYOUT_ROOT; }
    override public function render():Node
    {
        return column({ key: "root" }, [
            box({ key: "a", size: [100, 40] }),
            box({ key: "b", size: [50, 20] })
        ]);
    }
}

step("U3 about to new FiveConsts()");
var f:FiveConsts = new FiveConsts();
step("U4 new FiveConsts ok (FIVE consts, CheckView exact set)");
var rf:StyleRefinement = FiveConsts.getRoot_();
step("U5 read LAYOUT_ROOT ok");

var stage:Stage = new Stage();
var app:UiApp = new UiApp(f);
app.mount(stage);
app.attachRoot();
step("U6 mount+attachRoot ok (solves=" + app.layoutSolves + ")");

step("DONE five-const shapes all survived");

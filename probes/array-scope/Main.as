// probes/array-scope/Main.as -- the reproducible witness for compiler gap G11 (see
// compiler-gaps.md). It was written to chase a different question and the chase is
// what produced the entry, so it keeps that role.
//
// G11 (codegen): the build itself fails, sometimes, on identical source -- the
// struct declares one spelling for a libc-colliding field and emit.ts's
// hand-written built-in body uses another. You will see errors pointing at code
// nobody wrote.
//
// G12 WAS REGISTERED HERE AND IS NOW CLOSED AS NOT-A-DEFECT. The history is worth
// keeping because the misreading was expensive: this program used to stop at
// `aFresh.push(1)` in churn 8, the process stayed alive, and the log stopped, which
// read as "a heap allocation hangs after a ~134 KB byte buffer". It never was. Three
// measurements settled it (reviews/probe-g12-2026-10-23.md):
//   * the same program with the 134400-byte allocation REMOVED fails identically
//     (so the big buffer is irrelevant -- it was a coincidence of statement order);
//   * wrapping the push in try/catch reports `TypeError #1009` -- `aFresh` was NULL;
//   * declaring the three containers BELOW `stage.showWindow(...)` is the bug: see
//     the SETUP ORDER block under the stage setup.
// So the failure was this probe misusing the backend, not the backend misbehaving.
//
// Each statement boundary is logged to a FILE, not to stdout: the window owns the
// process and its stdout is discarded, so on a failure the only surviving evidence
// is how far the log got. The last line names the statement that killed it. Both
// streams are discarded by this program, so the runtime's own
// "Uncaught exception: Error #1009 ..." line is INVISIBLE here -- that is why the
// defect looked like a silent hang for so long. tools/repro-array-scope.cjs now
// forwards stderr so the verdict can never hide an uncaught error again.
import asaot.ui.*;
import asaot.ui.style.*;
import flash.display.BitmapData;
import flash.display.Stage;
import flash.display.StageAlign;
import flash.display.StageScaleMode;
import flash.filesystem.File;
import flash.filesystem.FileMode;
import flash.filesystem.FileStream;
import flash.geom.Rectangle;
import flash.utils.ByteArray;
import flash.utils.setTimeout;

var OUT:String = 'array-scope';

class Bag
{
    public var v:int;
    public function Bag():void { this.v = 0; }
}

class TinyView extends View
{
    private static const ROOT:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", size: [80, 60], background: 0xFFFFFF });
    override public function render():Node
    {
        return column({ key: "root", style: ROOT }, [ box({ key: "b", style: StyleRefinement.from({ size: [40, 20] }) }) ]);
    }
}

function w(s:String):void
{
    var f:File = new File(OUT + ".log.txt");
    var fs:FileStream = new FileStream();
    fs.open(f, FileMode.APPEND);
    fs.writeUTFBytes(s + "\n");
    fs.close();
}

// script-scope containers, the shape that crashed
var aInts:Array = [];
var aObjs:Array = [];

var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(new TinyView());
app.mount(stage);
app.attachRoot();
w("boot: mounted");

// PLATFORM FACT (measured here, and the reason this probe first logged NOTHING):
// stage.showWindow() does not return until the window closes -- it hands the main
// thread to the frame/message loop. So every setup step AND every setTimeout that
// must fire has to be registered BEFORE it. A timer scheduled after showWindow
// never runs at all, which looks exactly like "my timers are broken".
//
// SETUP ORDER, the same fact seen from the variable side -- this is what G12
// actually was. A script-scope `var x = <initializer>` below showWindow never runs
// its initializer, so `x` stays at its zero value: NULL for an Array or any other
// reference type. Declaring aFresh down there and then calling `aFresh.push(1)` from
// a timer threw TypeError #1009, the timer callback died before re-arming itself,
// and the frame loop kept running -- i.e. exactly the "process alive, log stopped"
// signature that got filed as a runtime hang. Keep every container this program
// touches ABOVE showWindow.
var step:int = 0;
var aBuf:Array = [];
var aFresh:Array = [];
var bigBuf:ByteArray = null;
setTimeout(tick, 200);
w("boot: scheduled tick; handing the thread to the window loop now");

stage.showWindow(80, 60, "probe array-scope");

function tick():void
{
    step = step + 1;
    w("step " + step + " enter, frames=" + app.enterFrameTicks + " gcHeap?");
    if (step == 1)
    {
        aInts.push(11);
        w("step 1 OK aInts.length=" + aInts.length);
    }
    else if (step == 2)
    {
        aInts.push(22);
        w("step 2 OK aInts.length=" + aInts.length + " [0]=" + aInts[0] + " [1]=" + aInts[1]);
    }
    else if (step == 3)
    {
        var b:Bag = new Bag();
        b.v = 7;
        w("step 3 allocated Bag");
        aObjs.push(b);
        w("step 3 OK aObjs.length=" + aObjs.length);
    }
    else if (step == 4)
    {
        var back:Bag = Bag(aObjs[0]);
        w("step 4 OK read back aObjs[0].v=" + back.v);
    }
    else if (step == 5)
    {
        var local:Array = [];
        local.push(99);
        w("step 5 OK local array length=" + local.length);
    }
    else if (step == 6)
    {
        beep();
        w("step 6 OK aInts=" + aInts.length + " aObjs=" + aObjs.length);
    }
    else if (step == 7 || step == 8 || step == 9)
    {
        churn(step);
    }
    else if (step == 10)
    {
        w("DONE");
        var f:File = new File(OUT + ".done");
        var fs:FileStream = new FileStream();
        fs.open(f, FileMode.WRITE);
        fs.writeUTFBytes("PASS");
        fs.close();
        return;
    }
    setTimeout(tick, 60);
}

function beep():void
{
}

// Steps 7..9 chase the shape an animation probe used to freeze in: a 240x140
// getPixels hands back a 134400-byte ByteArray, and the statement after that push
// is where it stopped. The buffer is kept in the witness because it is the shape
// that triggered the hunt -- NOT because it causes anything: G12's A/B removed the
// 134400-byte allocation entirely and the program failed the same way (the real
// cause was aFresh being declared below showWindow; see the header).
function churn(n:int):void
{
    w("churn " + n + " enter, frames=" + app.enterFrameTicks);
    if (n == 7)
    {
        bigBuf = new ByteArray();
        bigBuf.length = 134400;          // the getPixels size: a big malloc'd buffer
        w("churn 7 allocated a 134400-byte ByteArray");
    }
    else if (n == 8)
    {
        // (a) a fresh, empty array's first push: proves script-scope containers work
        // at all from a timer callback (they do -- provided they are declared above
        // showWindow).
        aFresh.push(1);
        w("churn 8 OK pushed an INT into a fresh array, len=" + aFresh.length);
    }
    else
    {
        // (b) a big byte buffer as an array element.
        aBuf.push(bigBuf);
        w("churn 9 OK pushed the ByteArray, aBuf.length=" + aBuf.length);
    }
}

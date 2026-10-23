// probes/array-scope/Main.as -- the reproducible witness for compiler gaps G11 and
// G12 (see compiler-gaps.md). It was written to chase a different question and the
// chase is what produced the two entries, so it keeps both roles.
//
// G11 (codegen): the build itself fails, sometimes, on identical source -- the
// struct declares one spelling for a libc-colliding field and emit.ts's
// hand-written built-in body uses another. You will see errors pointing at code
// nobody wrote.
//
// G12 (runtime): once it does build, the process HANGS (it stays alive; the frame
// loop keeps ticking; nothing more is logged). The trigger is narrow and the
// culprit is NOT the array -- steps 1..6 push ints and class instances happily, and
// step 8 pushes a plain int into a brand-new array. What kills it is the ~134 KB
// byte buffer allocated in step 7: after a big byte-buffer allocation, the next
// heap allocation stops. The original symptom was an animation probe freezing at
// `mids.push(c)` right after a 240x140 getPixels, which is why the obvious (and
// wrong) first theory was "script-scope Arrays are broken".
//
// Each statement boundary is logged to a FILE, not to stdout: the window owns the
// process and its stdout is discarded, so on a hang the only surviving evidence
// is how far the log got. The last line names the statement that killed it.
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

var OUT:String = 'g12as';

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
var step:int = 0;
setTimeout(tick, 200);
w("boot: scheduled tick; handing the thread to the window loop now");

stage.showWindow(80, 60, "probe array-scope");

function tick():void
{
    try { tickBody(); }
    catch (err:Error) { w("TICK THREW: " + err.errorID + " " + err.message + " | " + err.toString()); }
}

function tickBody():void
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

// Steps 7..9 chase the EXACT shape of the hang that started this probe. The
// original animation probe's readAt() allocated a fresh BitmapData, drew the stage
// into it, pulled a 134400-byte getPixels ByteArray -- and then `push`ed into a
// script-scope Array, which is where everything stopped. Steps 1..6 above prove
// that pushing ints and class instances is fine, so the suspect is the BYTE BUFFER,
// not the array. Step 7 isolates the buffer with no BitmapData involved at all.
var aBuf:Array = [];
var aFresh:Array = [];
var bigBuf:ByteArray = null;

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
        // (a) the ALLOCATOR hypothesis: a fresh, empty array's first push forces a
        // gc_alloc after a big malloc. If THIS is what hangs, the element type is
        // irrelevant and the byte-buffer allocator has poisoned the GC heap.
        w("churn 8 about to push");
        try { aFresh.push(1); } catch (err:Error) { w("PUSH THREW: " + err.errorID + " " + err.message); throw err; }
        w("churn 8 push returned");
        w("churn 8 OK pushed an INT into a fresh array, len=" + aFresh.length);
    }
    else
    {
        // (b) the ELEMENT-TYPE hypothesis: a big byte buffer as an array element.
        aBuf.push(bigBuf);
        w("churn 9 OK pushed the ByteArray, aBuf.length=" + aBuf.length);
    }
}

// probes/perf/Main.as -- WHERE THE FRAME TIME GOES, measured, not asserted.
//
// Every widget probe so far pins CORRECTNESS. This one pins COST. It builds a
// tree of N keyed buttons and then times four operations that a real app hits:
//
//   idle      reflow() with nothing pending            (should be ~0)
//   describe  invalidate(VALUE) + reflow(), NO author change at all
//             -> the whole tree is re-described and re-diffed for nothing
//   layout    one button's label changes width         -> one solve
//   paint     markPaint(one node) + reflow()           -> one node repaints
//
// The counters (describeCalls / reconcileVisits / layoutSolves / paintPasses)
// are printed next to the milliseconds, so a fast-looking number cannot hide a
// whole-tree sweep. Output is perf.samples.txt (one line per phase, averaged
// over REPS) and perf.done = PASS. There is no pixel expectation here: a timing
// probe that asserts milliseconds would be a flaky gate, so this one REPORTS.
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
import flash.utils.getTimer;
import flash.utils.setTimeout;

var W:int = 800;
var H:int = 600;
var OUT:String = 'perf';
var N:int = 300;
var REPS:int = 10;

var log:String = "";
var problems:String = "";

class PerfView extends View
{
    private static const ROOT:StyleRefinement = StyleRefinement.from({
        size: [800, 600], background: 0xFFFFFF });
    private static const ROW:StyleRefinement = StyleRefinement.from({
        size: [120, 24] });

    public var label:String = "row";
    public var only:int = -1;
    public function PerfView():void { super(); }

    public override function render():Node
    {
        var kids:Array = [];
        for (var i:int = 0; i < N; i++)
        {
            kids.push(button({
                key: "b" + i,
                label: (this.only == i ? "a considerably longer row label" : this.label) + " " + i,
                style: ROW
            }));
        }
        return column({ key: "root", style: ROOT }, kids);
    }
}

function report(name:String, ms:Number, before:Array):void
{
    log = log + name + "  " + (ms / REPS) + " ms"
        + "  describe=" + (app.describeCalls - before[0])
        + " visits=" + (app.reconcileVisits - before[1])
        + " solves=" + (app.layoutSolves - before[2])
        + " paints=" + (app.paintPasses - before[3]) + "\n";
}

function counters():Array
{
    return [app.describeCalls, app.reconcileVisits, app.layoutSolves, app.paintPasses];
}

function run():void
{
    var v:PerfView = PerfView(app.view);
    var t:Number;
    var i:int;
    var c:Array;

    c = counters();
    t = getTimer();
    for (i = 0; i < REPS; i++) app.reflow();
    report("idle    ", getTimer() - t, c);

    c = counters();
    t = getTimer();
    for (i = 0; i < REPS; i++) { app.invalidate(Dirty.VALUE); app.reflow(); }
    var describeMs:Number = (getTimer() - t) / REPS;
    report("describe", getTimer() - t, c);
    // The ONE assertion in this probe, and it is deliberately loose: a no-change
    // describe of 300 keyed buttons measured 39.3ms when the duplicate-key check
    // was a nested loop, and 1.0ms with a seen-set. 15ms is 15x the good number
    // and still 2.6x under the bad one, so it cannot flap on a slow machine but
    // it DOES catch the quadratic coming back. Everything else here is a report.
    if (describeMs > 15) problems = problems + "a no-change describe took " + describeMs
        + "ms (the duplicate-key scan is quadratic again?); ";

    c = counters();
    t = getTimer();
    for (i = 0; i < REPS; i++)
    {
        v.label = (i % 2 == 0) ? "a considerably longer row label" : "row";
        app.invalidate(Dirty.VALUE);
        app.reflow();
    }
    report("layout  ", getTimer() - t, c);

    // Only ONE node's text changes. This is the shape a real keystroke has, and
    // it is what the measure cache is for: the other 299 fields must not be
    // re-shaped. (The phase above changes all 300, so it always misses.)
    c = counters();
    t = getTimer();
    for (i = 0; i < REPS; i++)
    {
        v.only = (i % 2 == 0) ? 7 : -1;
        app.invalidate(Dirty.VALUE);
        app.reflow();
    }
    report("one     ", getTimer() - t, c);
    v.only = -1;

    // The layout phase above is solve + a FULL-tree paintAll. Split them: this
    // is the engine alone, no measure pass, no arrange, no pixels.
    var engRoot:Object = app.getRoot().engineNode;
    t = getTimer();
    for (i = 0; i < REPS; i++) app.engine.calculate(engRoot, 800, 600, 1);
    log = log + "solve   " + ((getTimer() - t) / REPS) + " ms  (engine only)\n";

    // A theme switch: every node re-resolves, nothing re-describes twice.
    c = counters();
    t = getTimer();
    for (i = 0; i < REPS; i++)
    {
        staleAll(app.getRoot());
        app.invalidate(Dirty.THEME);
        app.reflow();
    }
    report("resolve ", getTimer() - t, c);

    var n:UiNode = app.findByKey("b7");
    c = counters();
    t = getTimer();
    for (i = 0; i < REPS; i++) { app.markPaint(n); app.reflow(); }
    report("paint   ", getTimer() - t, c);

    finish();
}

function staleAll(n:UiNode):void
{
    n.lastStyleStale = true;
    n.dirty |= Dirty.M_PAINT;
    for (var i:int = 0; i < n.children.length; i++) staleAll(n.children[i]);
}

function finish():void
{
    writeText(OUT + ".samples.txt", log);
    var bd:BitmapData = new BitmapData(W, H, false, 0xFFFFFF);
    bd.draw(app.stage);
    writeBmp(OUT + ".bmp", bd);
    writeText(OUT + ".done", problems == "" ? "PASS" : "FAIL " + problems);
}

function writeText(path:String, t:String):void
{
    var f:File = File.applicationDirectory.resolvePath(path);
    var fs:FileStream = new FileStream();
    fs.open(f, FileMode.WRITE);
    fs.writeUTFBytes(t);
    fs.close();
}

function writeBmp(path:String, bd:BitmapData):void
{
    var w:int = bd.width;
    var h:int = bd.height;
    var px:ByteArray = bd.getPixels(new Rectangle(0, 0, w, h));
    var imgSize:int = w * h * 4;
    var ba:ByteArray = new ByteArray();
    ba.writeByte(0x42); ba.writeByte(0x4D);
    ba.writeByte(54 + imgSize & 255); ba.writeByte((54 + imgSize) >> 8 & 255);
    ba.writeByte((54 + imgSize) >> 16 & 255); ba.writeByte((54 + imgSize) >> 24 & 255);
    ba.writeByte(0); ba.writeByte(0); ba.writeByte(0); ba.writeByte(0);
    ba.writeByte(54); ba.writeByte(0); ba.writeByte(0); ba.writeByte(0);
    ba.writeByte(40); ba.writeByte(0); ba.writeByte(0); ba.writeByte(0);
    ba.writeByte(w & 255); ba.writeByte(w >> 8 & 255); ba.writeByte(0); ba.writeByte(0);
    ba.writeByte(h & 255); ba.writeByte(h >> 8 & 255); ba.writeByte(0); ba.writeByte(0);
    ba.writeByte(1); ba.writeByte(0);
    ba.writeByte(32); ba.writeByte(0);
    ba.writeByte(0); ba.writeByte(0); ba.writeByte(0); ba.writeByte(0);
    ba.writeByte(imgSize & 255); ba.writeByte(imgSize >> 8 & 255);
    ba.writeByte(imgSize >> 16 & 255); ba.writeByte(imgSize >> 24 & 255);
    ba.writeByte(0); ba.writeByte(0); ba.writeByte(0); ba.writeByte(0);
    ba.writeByte(0); ba.writeByte(0); ba.writeByte(0); ba.writeByte(0);
    ba.writeByte(0); ba.writeByte(0); ba.writeByte(0); ba.writeByte(0);
    ba.writeByte(0); ba.writeByte(0); ba.writeByte(0); ba.writeByte(0);
    for (var y:int = h - 1; y >= 0; y--)
    {
        for (var x:int = 0; x < w; x++)
        {
            var i:int = (y * w + x) * 4;
            ba.writeByte(px[i + 3]);
            ba.writeByte(px[i + 2]);
            ba.writeByte(px[i + 1]);
            ba.writeByte(px[i]);
        }
    }
    var f:File = File.applicationDirectory.resolvePath(path);
    var fs:FileStream = new FileStream();
    fs.open(f, FileMode.WRITE);
    fs.writeBytes(ba, 0, 0);
    fs.close();
}

var view:PerfView = new PerfView();
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

setTimeout(run, 900);
stage.showWindow(W, H, "probe perf");

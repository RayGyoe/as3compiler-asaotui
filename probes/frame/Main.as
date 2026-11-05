// probes/frame/Main.as -- END-TO-END frame cost of a kit tree.
//
// The `perf` probe stops at the AS3 side: describe / solve / paint in
// milliseconds. It cannot see what the RUNTIME then does with those marks, and
// that is where a kit frame is actually spent: every `paintSelf` rewrites a
// Shape's path and a TextField's text, which makes the runtime repaint the
// whole tree (there is no per-node raster reuse unless the object is a bake
// boundary). So this probe measures WALL-CLOCK frame intervals through the
// runtime's own `ASC_FRAME_STATS` counter and pairs them with the kit counters.
//
// It asserts nothing (a timing probe that asserts milliseconds is a flaky gate).
// The runner `tools/frame-perf.cjs` builds this once and runs it once per case,
// writing `case.txt` in this directory beforehand.
//
// Cases, chosen to separate the kit's own work from the runtime's raster:
//   idle  -- nothing changes; the Present-skip / ENTER_FRAME floor
//   text  -- ONE button's label alternates every frame (a "keystroke" shape:
//            re-describe -> solve -> FULL paintAll -> runtime repaint)
//   move  -- ONE display object's x oscillates every frame (an "animation"
//            shape with NO kit work at all: pure runtime raster)
//   all   -- every label alternates (a resize/theme shape)
import asaot.ui.*;
import asaot.ui.style.*;
import flash.display.Stage;
import flash.display.StageAlign;
import flash.display.StageScaleMode;
import flash.events.Event;
import flash.filesystem.File;
import flash.filesystem.FileMode;
import flash.filesystem.FileStream;
import flash.utils.getTimer;

var W:int = 800;
var H:int = 600;
var FRAMES:int = 1100;
var N:int = 300;
var CASE:String = readCase();
var OUT:String = 'frame';

class FrameView extends View
{
    private static const ROOT:StyleRefinement = StyleRefinement.from({
        size: [800, 600], background: 0xFFFFFF });
    private static const ROW:StyleRefinement = StyleRefinement.from({
        size: [160, 24] });

    public var label:String = "row";
    public var only:int = -1;

    public function FrameView():void { super(); }

    public override function render():Node
    {
        var kids:Array = [];
        for (var i:int = 0; i < N; i++)
        {
            var text:String = (this.only == i ? "a considerably longer row label" : this.label) + " " + i;
            kids.push(button({ key: "b" + i, label: text, style: ROW }));
        }
        return column({ key: "root", style: ROOT }, kids);
    }
}

function readCase():String
{
    var f:File = File.applicationDirectory.resolvePath('case.txt');
    if (!f.exists) return "idle";
    var fs:FileStream = new FileStream();
    fs.open(f, FileMode.READ);
    var s:String = fs.readUTFBytes(fs.bytesAvailable);
    fs.close();
    s = s.replace("\r", "").replace("\n", "");
    // "case:N" overrides the row count, so one executable measures scaling.
    var colon:int = s.indexOf(":");
    if (colon >= 0)
    {
        N = int(s.substring(colon + 1));
        s = s.substring(0, colon);
    }
    return s;
}

function writeText(path:String, t:String):void
{
    var f:File = File.applicationDirectory.resolvePath(path);
    var fs:FileStream = new FileStream();
    fs.open(f, FileMode.WRITE);
    fs.writeUTFBytes(t);
    fs.close();
}

var view:FrameView = new FrameView();
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
// AIR's default frameRate is 24. Without this the probe measures the default
// clock (42 ms/frame) instead of the 60 Hz target the kit is judged on.
stage.frameRate = 60;
var app:UiApp = new UiApp(view);
UiApp.profile = true;
app.mount(stage);
app.attachRoot();

var frames:int = 0;
var t0:Number = 0;
var moving:Object = null;

function tick(e:Event):void
{
    frames++;
    if (frames == 2) t0 = getTimer();
    if (CASE == "text")
    {
        view.only = (frames % 2 == 0) ? 7 : -1;
        app.invalidate(Dirty.VALUE);
    }
    else if (CASE == "all")
    {
        view.label = (frames % 2 == 0) ? "a considerably longer row label" : "row";
        app.invalidate(Dirty.VALUE);
    }
    else if (CASE == "move")
    {
        if (moving == null) moving = app.findByKey("b7");
        if (moving != null) moving.backing.x = (frames % 2 == 0) ? 8 : 0;
    }
    if (frames >= FRAMES) finish();
}

function finish():void
{
    var ms:Number = getTimer() - t0;
    var log:String = "case=" + CASE
        + " frames=" + frames
        + " wall=" + ms + "ms"
        + " avg=" + (ms / (frames - 2)) + "ms/frame"
        + " describe=" + app.describeCalls
        + " visits=" + app.reconcileVisits
        + " solves=" + app.layoutSolves
        + " paints=" + app.paintPasses
        + " nodes=" + countNodes(app.getRoot()) + "\n"
        + "prof frames=" + app.profFrames
        + " render=" + app.profRenderMs
        + " reconcile=" + app.profReconcileMs
        + " measure=" + app.profMeasureMs
        + " solve=" + app.profSolveMs
        + " arrange=" + app.profArrangeMs
        + " paint=" + app.profPaintMs
        + " renderMax=" + app.profRenderMax + " measureMax=" + app.profMeasureMax + "\n";
    writeText(OUT + ".samples.txt", log);
    writeText(OUT + ".done", "PASS");
}

function countNodes(n:UiNode):int
{
    var c:int = 1;
    for (var i:int = 0; i < n.children.length; i++) c += countNodes(n.children[i]);
    return c;
}

stage.addEventListener(Event.ENTER_FRAME, tick);
stage.showWindow(W, H, "probe frame " + CASE);
// probes/widgets/chip/Main.as -- ★ REFERENCE PROBE for the Widget seam.
//
// Output prefix MUST equal the directory name (`chip`) because tools/probe.cjs
// derives the expected files from it.
//
// What it pins, and why each thing is here:
//   * the RECTS of three chips in a column with padding 20 / gap 8 -- positions
//     the author hand-computed, verified externally against expect.json;
//   * the exact PIXEL COLOUR 4px inside each pill's left edge (clear of the
//     centred label) -- one per tone, so a mis-wired tone table is caught;
//   * TWO things a bitmap cannot show: that the kind actually registered with
//     Widgets, and that a settled tree does NOT re-solve layout on later frames
//     (a widget that reflows every frame would look perfect and be wrong).
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

var W:int = 200;
var H:int = 190;
var OUT:String = 'chip';

class ChipProbe extends View
{
    private static const ROOT:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", padding: 20, gap: 8, size: [200, 190],
        background: 0xFFFFFF
    });
    private static const PILL:StyleRefinement = StyleRefinement.from({
        size: [120, 28], cornerRadii: 8
    });

    override public function render():Node
    {
        return column({ key: "root", style: ROOT }, [
            chip("alpha",  { key: "c1", style: PILL, tone: "neutral" }),
            chip("beta",   { key: "c2", style: PILL, tone: "info" }),
            chip("gamma",  { key: "c3", style: PILL, tone: "danger" }),
            row({ key: "autoRow", gap: 8 }, [
                chip("a", { key: "autoA" }),
                chip("b", { key: "autoB" })
            ])
        ]);
    }
}

var view:ChipProbe = new ChipProbe();
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

setTimeout(settle, 900);
stage.showWindow(W, H, "probe chip");

function settle():void
{
    var names:Array = ["c1", "c2", "c3"];
    var lines:String = "";
    var missing:int = 0;
    var i:int;
    for (i = 0; i < 3; i++)
    {
        var n:UiNode = app.findByKey(names[i]);
        if (n == null) { missing = missing + 1; lines = lines + names[i] + " MISSING\n"; continue; }
        lines = lines + names[i] + " " + n.absX + "," + n.absY + "," + n.absW + "," + n.absH + "\n";
    }
    writeText(OUT + ".rects.txt", lines);

    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    writeBmp(OUT + ".bmp", bd);

    solveAtSettle = app.layoutSolves;
    frame0 = app.enterFrameTicks;
    if (missing > 0) { writeText(OUT + ".done", "FAIL " + missing + " chip(s) missing"); return; }
    setTimeout(steady, 400);
}

var solveAtSettle:Number = 0;
var frame0:int = 0;

function steady():void
{
    var problems:String = "";
    if (!Widgets.has("chip")) problems = problems + "Widgets.has('chip') is false; ";
    var extraSolves:Number = app.layoutSolves - solveAtSettle;
    var extraFrames:int = app.enterFrameTicks - frame0;
    if (extraFrames < 2) problems = problems + "only " + extraFrames + " frame(s) elapsed; ";
    if (extraSolves > 0) problems = problems + "a settled tree re-solved layout " + extraSolves + " time(s); ";

    // Auto-sized chips must include their 8pt horizontal padding on BOTH sides,
    // and the row's 8pt gap must remain between the two solved pills.
    var a:UiNode = app.findByKey("autoA");
    var b:UiNode = app.findByKey("autoB");
    if (a == null || b == null) problems = problems + "auto-sized chips missing; ";
    else
    {
        if (a.absW != a.state.measuredW + 16)
            problems = problems + "auto chip width " + a.absW + " does not include 16pt horizontal padding; ";
        if (b.absX != a.absX + a.absW + 8)
            problems = problems + "auto chip gap is not 8pt; ";
        var cw:Number = a.absW - PaintKit.padH(a.resolved.padding);
        var cx:Number = PaintKit.insetX(a) + (cw - a.state.measuredW) / 2 - PaintKit.TEXT_GUTTER;
        if (a.tf == null || a.tf.x != cx) problems = problems + "auto chip label is not centred; ";
    }
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

// 32-bit bottom-up BMP written by hand: this runtime has BitmapData but no PNG
// encoder, and a raw frame buffer is BETTER evidence than an encoded image --
// it is a 1:1 copy of the compositor output, so the samplers can compare exact
// integers (see tools/probe.cjs).
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
    var y:int;
    var x:int;
    for (y = h - 1; y >= 0; y--)
    {
        for (x = 0; x < w; x++)
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
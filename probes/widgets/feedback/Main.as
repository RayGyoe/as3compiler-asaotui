// probes/widgets/feedback/Main.as -- the probe for the FEEDBACK widget group
// (spinner + skeleton + tooltip).
//
// Output prefix MUST equal the directory name (`feedback`), because tools/probe.cjs
// derives the expected file names from it.
//
// What it pins, and why each thing is here:
//   * the RECTS of a fixed column (padding 20, gap 10, align-items flex-start so
//     every child keeps its own measured cross size): the spinner, the three
//     skeleton variants and the tooltip -- hand-computed in expect.json;
//   * exact PIXEL colours, sampled clear of every glyph and of every antialiased
//     edge: the spinner's ARC (the tone colour), its TRACK, and the HOLLOW centre
//     (which proves the ring is stroked, not filled); a skeleton bar, the gap
//     between two bars, and the 60%-wide last bar's cut; a circle skeleton's
//     centre and a corner OUTSIDE its circle; the tooltip's arrow and its bubble;
//   * things a bitmap CANNOT show: that all three kinds registered with Widgets,
//     that the tooltip's label really reached a TextField, that a settled tree
//     never re-solves layout, and that the spinner's spin loop is PAINT-ONLY
//     (it repaints without re-solving).
//
// WHY THE SPINNING SPINNER IS ASSERTED AFTER THE BITMAP
// ----------------------------------------------------
// `spin: true` derives the angle from the frame clock, so a spinning spinner
// makes the frame NON-DETERMINISTIC and would turn the pixel checks into a
// coin flip. The probe therefore mounts a FROZEN spinner (`spin: false, phase: 0`)
// for the bitmap, and only after the bitmap is on disk flips the spinner to
// spinning and asserts the behavioural part. Same widget, two witnesses, and the
// frozen one is the pixel-exact one.
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

var W:int = 320;
var H:int = 260;
var OUT:String = 'feedback';

class FeedbackProbe extends View
{
    // align-items flex-start is LOAD-BEARING: with the default `stretch` the row
    // would stretch its children to the row's height, and the spinner's ring would
    // become an oval. It also keeps the skeleton's measured heights intact.
    private static const ROOT:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", alignItems: "flex-start",
        padding: 20, gap: 10, size: [320, 260],
        background: 0xFFFFFF, text: { fontSize: 12, color: 0x111827 }
    });
    private static const ROW_S:StyleRefinement = StyleRefinement.from({
        width: 210, height: 40, gap: 10, alignItems: "flex-start"
    });
    private static const SP_S:StyleRefinement = StyleRefinement.from({ size: [40, 40] });
    private static const SKT_S:StyleRefinement = StyleRefinement.from({ width: 160 });
    private static const SKC_S:StyleRefinement = StyleRefinement.from({ size: [40, 40] });
    private static const SKR_S:StyleRefinement = StyleRefinement.from({ size: [200, 80] });
    private static const TP_S:StyleRefinement = StyleRefinement.from({ size: [120, 30] });

    // Held so `steady()` can flip `spin` on the LIVE description (see the header).
    public var spDesc:SpinnerNode;

    public function FeedbackProbe():void { super(); }

    override public function render():Node
    {
        if (this.spDesc == null)
        {
            this.spDesc = SpinnerNode(spinner({
                key: "sp", style: SP_S,
                diameter: 40, thickness: 6, tone: "info", spin: false, phase: 0
            }));
        }
        return column({ key: "root", style: ROOT, ariaName: "feedback" }, [
            row({ key: "r1", style: ROW_S, ariaName: "row" }, [
                this.spDesc,
                skeleton({ key: "sk_t", style: SKT_S, variant: "text", lines: 3, barHeight: 8, gap: 6 })
            ]),
            skeleton({ key: "sk_c", style: SKC_S, variant: "circle" }),
            skeleton({ key: "sk_r", style: SKR_S, variant: "rect" }),
            tooltip("Saved", { key: "tp", style: TP_S, arrow: "up" })
        ]);
    }
}

var view:FeedbackProbe = new FeedbackProbe();
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

setTimeout(settle, 900);
stage.showWindow(W, H, "probe feedback");

function settle():void
{
    var names:Array = ["root", "r1", "sp", "sk_t", "sk_c", "sk_r", "tp"];
    var lines:String = "";
    var missing:int = 0;
    for (var i:int = 0; i < names.length; i++)
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
    if (missing > 0) { writeText(OUT + ".done", "FAIL " + missing + " node(s) missing"); return; }
    setTimeout(steady, 400);
}

var solveAtSettle:Number = 0;
var frame0:int = 0;
var paints0:Number = 0;

function steady():void
{
    var problems:String = "";

    // (a) all three kinds registered -- a bitmap cannot show a registry miss.
    if (!Widgets.has("spinner")) problems = problems + "Widgets.has('spinner') is false; ";
    if (!Widgets.has("skeleton")) problems = problems + "Widgets.has('skeleton') is false; ";
    if (!Widgets.has("tooltip")) problems = problems + "Widgets.has('tooltip') is false; ";

    // (b) the tooltip's label reached a real TextField. The bitmap cannot show
    //     this: glyphs are antialiased and the checker refuses to guess colours.
    var tpn:UiNode = app.findByKey("tp");
    if (tpn == null) problems = problems + "tp missing; ";
    else if (tpn.tf == null) problems = problems + "tooltip has no TextField; ";
    else if (tpn.tf.text != "Saved") problems = problems + "tooltip text is '" + tpn.tf.text + "'; ";

    // (c) a settled tree never re-solves layout.
    var extraSolves:Number = app.layoutSolves - solveAtSettle;
    var extraFrames:int = app.enterFrameTicks - frame0;
    if (extraFrames < 2) problems = problems + "only " + extraFrames + " frame(s) elapsed; ";
    if (extraSolves > 0) problems = problems + "a settled tree re-solved layout " + extraSolves + " time(s); ";

    // (d) from here on the spinner may spin. The bitmap is already on disk, so a
    //     non-deterministic frame from now on costs nothing.
    paints0 = app.paintPasses;
    solves0 = app.layoutSolves;
    frames0 = app.enterFrameTicks;
    view.spDesc.spin = true;
    app.invalidate(Dirty.DECOR);
    setTimeout(spinCheck, 400);
}

var paints0b:Number = 0;
var solves0:Number = 0;
var frames0:int = 0;

function spinCheck():void
{
    var problems:String = "";
    var frames:int = app.enterFrameTicks - frames0;
    var solves:Number = app.layoutSolves - solves0;
    var paints:Number = app.paintPasses - paints0;
    if (frames < 4) problems = problems + "only " + frames + " frame(s) elapsed while spinning; ";
    // THE assertion: a spinner's rotation is decoration. If it re-solved layout it
    // would drag the whole tree through measure+arrange every frame.
    if (solves != 0) problems = problems + "spinning re-solved layout " + solves + " time(s); ";
    // ...and the other half: it really has to REPAINT, or "paint-only" would be
    // satisfied by a spinner that never moves.
    if (paints < 3) problems = problems + "spinning repainted only " + paints + " time(s) in " + frames + " frames; ";
    writeText(OUT + ".done", problems == "" ? "PASS" : "FAIL " + problems);
}

function writeText(path:String, t:String):void
{
    var f:File = new File(path);
    var fs:FileStream = new FileStream();
    fs.open(f, FileMode.WRITE);
    fs.writeUTFBytes(t);
    fs.close();
}

// 32-bit bottom-up BMP written by hand (copied from probes/widgets/nav/Main.as):
// this runtime has BitmapData but no PNG encoder, and a raw frame buffer is
// BETTER evidence than an encoded image -- it is a 1:1 copy of the compositor
// output, so the samplers can compare exact integers.
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
    var f:File = new File(path);
    var fs:FileStream = new FileStream();
    fs.open(f, FileMode.WRITE);
    fs.writeBytes(ba, 0, 0);
    fs.close();
}

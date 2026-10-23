// probes/widgets/anim/Main.as -- animation / transition evidence.
//
// WHAT IS BEING TESTED: kit/asaot/ui/anim/ + Style.transitionMs. The seam is
// `UiNode.resolved`: every widget paints from it, so post-processing it animates
// every widget with no widget-file change.
//
// THE HARD PART IS THE ASSERTIONS, not the animation. A mid-tween colour is
// decided by WHEN the sample lands, which the test cannot control to the
// millisecond. So the mid-tween assertion is deliberately NOT an exact colour:
// it is "strictly between the two endpoints, component-wise, and equal to
// neither, and monotone toward the target". That still fails if the value jumps
// straight to the target (the mutation we care about) and it cannot flake on
// timing. The two ENDPOINTS, which ARE deterministic, are asserted EXACTLY.
//
// EVIDENCE IS THE FRAME BUFFER, not Anim.value: the program samples the real
// compositor output via bd.draw(stage), so "the tween is running" cannot be
// satisfied by a bookkeeping counter that never reaches the screen.
//
// Protocol (tools/probe.cjs): dir name == output prefix; write <OUT>.rects.txt,
// <OUT>.bmp, <OUT>.done (PASS | FAIL <reason>).
import asaot.ui.*;
import asaot.ui.style.*;
import asaot.ui.anim.Anim;
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

var W:int = 240;
var H:int = 140;
var OUT:String = 'anim';

class AnimModel extends Observable
{
    public var hover:Boolean = false;
}

// b1 rect (20,20,200,40) -> sample its middle at (120,40)
// b2 rect (20,70,200,40) -> sample its middle at (120,90)
var SX:int = 120;
var SY1:int = 40;
var SY2:int = 90;

class Rgb
{
    public var r:int;
    public var g:int;
    public var b:int;
    public function Rgb():void { this.r = 0; this.g = 0; this.b = 0; }
}

class AnimProbe extends View
{
    public var model:AnimModel;

    // The animated box: 400ms linear fade from 0x112233 to 0x112299 -- only the
    // BLUE channel moves (0x33 -> 0x99), so a mid value is unambiguous and every
    // other channel must stay put. Hand-computed endpoints:
    //   blue at t=0.5 is 0x33 + 0.5*(0x99-0x33) = 0x33 + 0x33 = 0x66
    private static const A_REST:StyleRefinement = StyleRefinement.from({
        size: [200, 40], transitionMs: 400, transitionEase: "linear", background: 0x112233 });
    private static const A_HOT:StyleRefinement = StyleRefinement.from({
        size: [200, 40], transitionMs: 400, transitionEase: "linear", background: 0x112299 });

    // The control box: NO transitionMs, so the default must still SNAP.
    private static const B_REST:StyleRefinement = StyleRefinement.from({
        size: [200, 40], background: 0x445566 });
    private static const B_HOT:StyleRefinement = StyleRefinement.from({
        size: [200, 40], background: 0x4455AA });

    private static const ROOT:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", padding: 20, gap: 10, size: [240, 140], background: 0xFFFFFF });

    public function AnimProbe(m:AnimModel):void
    {
        super();
        this.model = m;
    }

    override public function render():Node
    {
        var a:StyleRefinement = this.model.hover ? A_HOT : A_REST;
        var b:StyleRefinement = this.model.hover ? B_HOT : B_REST;
        return column({ key: "root", style: ROOT }, [
            box({ key: "b1", style: a }),
            box({ key: "b2", style: b })
        ]);
    }
}

var model:AnimModel = new AnimModel();
var view:AnimProbe = new AnimProbe(model);
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

var BOX:BitmapData = new BitmapData(W, H, true, 0xFF000000);
var problems:String = "";
var log:String = "";

function two(v:int):String
{
    return (v < 16 ? "0" : "") + v;
}

function say(s:String):void
{
    log = log + s + "\n";
    trace(s);
    // Append IMMEDIATELY, not at the end. If a callback throws, the runtime
    // discards stdout (the window owns the process) and an in-memory log dies
    // with it -- then "the probe never wrote its files" is all you learn. A file
    // written on every step turns that into "it stopped right after X".
    var f:File = new File(OUT + ".log.txt");
    var fs:FileStream = new FileStream();
    fs.open(f, FileMode.APPEND);
    fs.writeUTFBytes(s + "\n");
    fs.close();
}

function fail(s:String):void
{
    problems = problems + s + "; ";
}

function readAt(x:int, y:int):Rgb
{
    BOX = new BitmapData(W, H, true, 0xFF000000);
    BOX.draw(stage);
    var px:ByteArray = BOX.getPixels(new Rectangle(0, 0, W, H));
    var i:int = (y * W + x) * 4;
    var o:Rgb = new Rgb();
    o.r = px[i + 1];
    o.g = px[i + 2];
    o.b = px[i + 3];
    return o;
}

function isRgb(c:Rgb, r:int, g:int, b:int):Boolean
{
    return c.r == r && c.g == g && c.b == b;
}

function show(tag:String, c:Rgb):String
{
    return tag + "=#(" + two(c.r) + "," + two(c.g) + "," + two(c.b) + ")";
}

setTimeout(sampleAndStart, 900);
stage.showWindow(W, H, "probe anim");

// ---- the timeline ---------------------------------------------------------
var s0:Rgb = null;
var s1:Rgb = null;
var b0:Rgb = null;
var b1first:Rgb = null;
// NOTE: deliberately NOT an Array. A script-scope `Array` and `mids.push()` abort
// the process here (see reviews/probe-anim-*.md); five scalars are unaffected and
// this file is a probe, not the library.
var midMr:int = -1;
var midMg:int = -1;
var midB0:int = -1;
var midB1:int = -1;
var midB2:int = -1;
var midB3:int = -1;
var midB4:int = -1;
var midCount:int = 0;
var frames0:int = 0;
var activeBefore:Boolean = false;
var activeAfterSwitch:Boolean = false;
var activeAtEnd:Boolean = false;
var n1:UiNode = null;
var n2:UiNode = null;
var midTick:int = 0;

function storeMid(i:int, b:int):void
{
    if (i == 0) midB0 = b;
    else if (i == 1) midB1 = b;
    else if (i == 2) midB2 = b;
    else if (i == 3) midB3 = b;
    else midB4 = b;
}

function midAt(i:int):int
{
    if (i == 0) return midB0;
    if (i == 1) return midB1;
    if (i == 2) return midB2;
    if (i == 3) return midB3;
    return midB4;
}

// Named callbacks, not anonymous closures: this keeps the probe independent of
// how well the AOT handles capturing lambdas, so a failure here means the
// animation is wrong rather than the probe being exotic.
function midStep():void
{
    var c:Rgb = readAt(SX, SY1);
    if (midCount == 0) { midMr = c.r; midMg = c.g; }
    storeMid(midCount, c.b);
    midCount = midCount + 1;
    midTick = midTick + 1;
    if (midTick < 5) setTimeout(midStep, 60);
}

function diagStep():void
{
    // Logged one frame AFTER the switch, when the resolver has actually run.
    if (n1 != null)
    {
        var tms:Number = n1.resolved.transitionMs;
        var argb:Number = n1.resolved.background != null ? n1.resolved.background.argb : -1;
        var prevArgb:Number = n1.previous.background != null ? n1.previous.background.argb : -1;
        say("diag resolved.transitionMs=" + tms + " resolved.bg=" + argb + " previous.bg=" + prevArgb
            + " isActive=" + Anim.isActive(n1));
    }
}

function controlStep():void
{
    b1first = readAt(SX, SY2);
    say("control first-after-switch " + show("b2", b1first));
}

function sampleAndStart():void
{
    say("--- timeline starts ---");
    // (e-pre) the RESTING colour, sampled from the frame buffer, before anything
    // moves. Deterministic, so it is asserted exactly.
    s0 = readAt(SX, SY1);
    b0 = readAt(SX, SY2);
    say("rest " + show("b1", s0) + " " + show("b2", b0));
    if (!isRgb(s0, 0x11, 0x22, 0x33)) fail("resting b1 is " + show("", s0) + ", want #(11,22,33)");
    if (!isRgb(b0, 0x44, 0x55, 0x66)) fail("resting b2 is " + show("", b0) + ", want #(44,55,66)");

    n1 = app.findByKey("b1");
    n2 = app.findByKey("b2");
    if (n1 == null) fail("b1 not found");
    if (n2 == null) fail("b2 not found");
    if (n1 != null)
    {
        activeBefore = Anim.isActive(n1);
        if (activeBefore) fail("b1 is animating before anything changed");
    }

    frames0 = app.enterFrameTicks;

    model.hover = true;
    view.invalidate(Dirty.ALL);

    activeAfterSwitch = false;   // checked one frame later in diagStep: the
                                 // resolver has not run yet within this tick

    say("switched; scheduling samples");

    // MID SAMPLES: 5 reads at 60ms spacing, spread across the 400ms window.
    setTimeout(diagStep, 40);
    setTimeout(midStep, 60);
    // The control box must ALREADY be at its target on the first read after the
    // switch -- that is what "the default snaps" means.
    setTimeout(controlStep, 60);

    setTimeout(finish, 1100);
}

function finish():void
{
    say("finish enter");
    var sEnd:Rgb = readAt(SX, SY1);
    var bEnd:Rgb = readAt(SX, SY2);

    // (a) it LANDED exactly, not one step short
    if (!isRgb(sEnd, 0x11, 0x22, 0x99)) fail("b1 did not land on #(11,22,99); it is " + show("", sEnd));

    // (b/c) at least one sample strictly between, and monotone toward the target
    var i:int;
    var sawBetween:Boolean = false;
    var prevB:int = 0x33;
    if (midCount > 0 && (midMr != 0x11 || midMg != 0x22))
    {
        fail("a mid sample changed a channel that should be frozen: r=" + midMr + " g=" + midMg);
    }
    for (i = 0; i < midCount; i++)
    {
        var b:int = midAt(i);
        say("mid[" + i + "] blue=" + b);
        if (b < prevB) fail("mid[" + i + "] went BACKWARDS in blue: " + prevB + " -> " + b);
        prevB = b;
        if (b > 0x33 && b < 0x99) sawBetween = true;
    }
    say("mid samples = " + midCount + ", saw strictly-between = " + sawBetween);
    if (midCount < 3) fail("only " + midCount + " mid sample(s): the interpolation claim would be vacuous");
    if (!sawBetween) fail("no sample was strictly between blue 0x33 and 0x99: the value JUMPED instead of interpolating");
    if (midCount > 0 && midAt(midCount - 1) == 0x33) fail("the last mid sample is still the RESTING colour: nothing moved");

    // (d) the control box snapped
    if (b1first == null) fail("the control box was never sampled");
    else if (!isRgb(b1first, 0x44, 0x55, 0xAA)) fail("with transitionMs UNSET the change must snap, but the first sample is " + show("", b1first));
    if (!isRgb(bEnd, 0x44, 0x55, 0xAA)) fail("control box final is " + show("", bEnd));

    // (f) it stopped
    if (n1 != null)
    {
        activeAtEnd = Anim.isActive(n1);
        if (activeAtEnd) fail("b1 is still animating after the duration elapsed");
    }

    // (g) frames really did advance -- otherwise (c) could pass with one frame
    var frames:int = app.enterFrameTicks - frames0;
    say("frames during the tween = " + frames);
    if (frames < 4) fail("only " + frames + " frame(s) elapsed during the tween; the mid-sample claim needs real frames");

    // ---- dump the evidence -------------------------------------------------
    var lines:String = "";
    var names:Array = ["b1", "b2"];
    var keys:Array = ["b1", "b2"];
    for (i = 0; i < 2; i++)
    {
        var n:UiNode = app.findByKey(keys[i]);
        if (n == null) { lines = lines + keys[i] + " MISSING\n"; continue; }
        lines = lines + keys[i] + " " + n.absX + "," + n.absY + "," + n.absW + "," + n.absH + "\n";
    }
    writeText(OUT + ".rects.txt", lines);
    writeBmp(OUT + ".bmp", BOX);
    writeText(OUT + ".samples.txt", log);
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

// 32-bit bottom-up BMP, copied verbatim from probes/widgets/chip/Main.as.
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
    var f:File = new File(path);
    var fs:FileStream = new FileStream();
    fs.open(f, FileMode.WRITE);
    fs.writeBytes(ba, 0, 0);
    fs.close();
}
// probes/redraw/Main.as -- a paint-only change MUST reach the screen.
//
// THE BUG THIS PINS (found while writing the animation probe, 2026-10-23):
// UiApp.reflow() painted only when the LAYOUT had run, or when `_needsPaint` was
// set. `invalidate(Dirty.ALL)` sets neither (Dirty.ALL == 15 and does NOT contain
// M_PAINT == 64), so an author change that only affected decoration -- a
// background, a border colour, a chip tone -- re-described the tree, set the
// node's M_PAINT bit, and then never painted anything. The change was invisible
// until some unrelated reflow happened to repaint it. The animation code hid
// this: it calls markPaint() on every frame of a tween, so an animating app
// repainted continuously and looked correct.
//
// So the assertions here are deliberately TWO-SIDED, and the second side is the
// one that makes this a real pin rather than a colour test:
//   (1) the pixels MUST change to the new colours, and
//   (2) `app.layoutSolves` MUST NOT move -- the change is genuinely paint-only.
// A fix that "works" by re-solving layout would fail (2) and be rejected, and a
// fix that reflows but does not paint would fail (1).
//
// There is NO transition anywhere in this probe, which is what separates it from
// probes/widgets/anim/: nothing here can be excused by the animator's repaint.
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
var OUT:String = 'redraw';

class RedrawModel extends Observable
{
    public var hot:Boolean = false;
}

class Rgb3
{
    public var r:int;
    public var g:int;
    public var b:int;
    public function Rgb3():void { this.r = 0; this.g = 0; this.b = 0; }
}

class RedrawProbe extends View
{
    public var model:RedrawModel;

    // b: a plain box whose background changes. NOTHING else changes -- the size
    // is explicit and identical in both variants, so the diff is paint-only.
    private static const B_REST:StyleRefinement = StyleRefinement.from({
        size: [200, 40], background: 0x112233 });
    private static const B_HOT:StyleRefinement = StyleRefinement.from({
        size: [200, 40], background: 0x4455AA });

    // c: a chip. Its tone lives in the NODE payload, not in the style, so this is
    // the second, independent paint path: ChipWidget.payload sees the tone
    // change, sets Dirty.M_PAINT on the node and returns FALSE (no relayout).
    private static const C_STYLE:StyleRefinement = StyleRefinement.from({
        size: [200, 40], padding: 8, cornerRadii: 8 });

    private static const ROOT:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", padding: 20, gap: 10, size: [240, 140], background: 0xFFFFFF });

    public function RedrawProbe(m:RedrawModel):void
    {
        super();
        this.model = m;
    }

    override public function render():Node
    {
        return column({ key: "root", style: ROOT }, [
            box({ key: "b", style: this.model.hot ? B_HOT : B_REST }),
            chip("T", { key: "c", style: C_STYLE, tone: this.model.hot ? "danger" : "neutral" })
        ]);
    }
}

var model:RedrawModel = new RedrawModel();
var view:RedrawProbe = new RedrawProbe(model);
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

var BOX:BitmapData = new BitmapData(W, H, true, 0xFF000000);
var problems:String = "";
writeText(OUT + ".log.txt", "");   // probe.cjs does not clean this name; truncate it ourselves

function say(s:String):void
{
    trace(s);
    var f:File = File.applicationDirectory.resolvePath(OUT + ".log.txt");
    var fs:FileStream = new FileStream();
    fs.open(f, FileMode.APPEND);
    fs.writeUTFBytes(s + "\n");
    fs.close();
}

function fail(s:String):void { problems = problems + s + "; "; }

function readAt(x:int, y:int):Rgb3
{
    BOX = new BitmapData(W, H, true, 0xFF000000);
    BOX.draw(stage);
    var px:ByteArray = BOX.getPixels(new Rectangle(0, 0, W, H));
    var i:int = (y * W + x) * 4;
    var o:Rgb3 = new Rgb3();
    o.r = px[i + 1];
    o.g = px[i + 2];
    o.b = px[i + 3];
    return o;
}

function isRgb(c:Rgb3, r:int, g:int, b:int):Boolean
{
    return c.r == r && c.g == g && c.b == b;
}

function show(tag:String, c:Rgb3):String
{
    return tag + "=(" + c.r + "," + c.g + "," + c.b + ")";
}

// Three horizontal bands, each sampled in the middle of its own solid region and
// clear of glyphs:
//   b1 the box  rect (20,  20, 200, 40) -> (120, 40)
//   c  the chip rect (20,  70, 200, 40); with padding 8 the pill is
//      (28, 78, 184, 24), so (34, 90) is 6px inside the pill's left edge. The
//      label "T" is centred, so the middle would hit glyphs -- hence the 4px rule.
var BX:int = 120;
var BY:int = 40;
var CX:int = 34;
var CY:int = 90;

setTimeout(switchIt, 900);
stage.showWindow(W, H, "probe redraw");

var describe0:int = 0;
var solves0:Number = 0;
var bNode:UiNode = null;

function switchIt():void
{
    var b0:Rgb3 = readAt(BX, BY);
    var c0:Rgb3 = readAt(CX, CY);
    say("rest " + show("b", b0) + " " + show("c", c0));

    if (!isRgb(b0, 0x11, 0x22, 0x33)) fail("resting box is " + show("", b0) + ", want (17,34,51)");
    // chip neutral fill is 0xE5E7EB = (229,231,235)
    if (!isRgb(c0, 0xE5, 0xE7, 0xEB)) fail("resting chip is " + show("", c0) + ", want (229,231,235)");

    bNode = app.findByKey("b");
    if (bNode != null && Anim.isActive(bNode)) fail("the box is animating: this probe must not involve the animator");

    describe0 = app.describeCalls;
    solves0 = app.layoutSolves;

    // The author idiom: change the model, ask for a re-describe. Dirty.ALL is 15
    // and does NOT include M_PAINT, so this is exactly the authorising call that
    // used to be dropped on the floor.
    model.hot = true;
    view.invalidate(Dirty.ALL);

    setTimeout(finish, 500);
}

function finish():void
{
    var b1:Rgb3 = readAt(BX, BY);
    var c1:Rgb3 = readAt(CX, CY);
    say("after " + show("b", b1) + " " + show("c", c1));

    // (0) a re-describe really happened -- otherwise (1) could be satisfied by
    // the old pixels never having been re-rendered for an unrelated reason.
    var reDescribed:int = app.describeCalls - describe0;
    say("re-describes=" + reDescribed + " layoutSolves delta=" + (app.layoutSolves - solves0));
    if (reDescribed < 1) fail("the view was never re-described; invalidate(Dirty.ALL) did nothing");

    // (1) the paint-only change reached the screen. Box: style-driven.
    if (!isRgb(b1, 0x44, 0x55, 0xAA)) fail("box did not repaint: " + show("", b1) + ", want (68,85,170)");
    // Chip: payload-driven (ChipWidget.payload sets M_PAINT and returns false).
    // danger fill is 0xFEE2E2 = (254,226,226)
    if (!isRgb(c1, 0xFE, 0xE2, 0xE2)) fail("chip did not repaint: " + show("", c1) + ", want (254,226,226)");

    // (2) and it was genuinely PAINT-ONLY: the fix must not have bought the
    // repaint with a layout re-solve.
    var extraSolves:Number = app.layoutSolves - solves0;
    if (extraSolves > 0) fail("a paint-only change re-solved layout " + extraSolves + " time(s)");

    var lines:String = "";
    var keys:Array = ["b", "c"];
    var i:int = 0;
    while (i < 2)
    {
        var n:UiNode = app.findByKey(keys[i]);
        if (n == null) lines = lines + keys[i] + " MISSING\n";
        else lines = lines + keys[i] + " " + n.absX + "," + n.absY + "," + n.absW + "," + n.absH + "\n";
        i = i + 1;
    }
    writeText(OUT + ".rects.txt", lines);
    writeBmp(OUT + ".bmp", BOX);
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
    var f:File = File.applicationDirectory.resolvePath(path);
    var fs:FileStream = new FileStream();
    fs.open(f, FileMode.WRITE);
    fs.writeBytes(ba, 0, 0);
    fs.close();
}
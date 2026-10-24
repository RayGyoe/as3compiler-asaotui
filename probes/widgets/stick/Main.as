// probes/widgets/stick/Main.as -- ScrollView's `stickToBottom`: a log that follows the
// end of its own content, and lets go the moment the reader scrolls away.
//
// Output prefix MUST equal the directory name (`stick`).
//
// WHY THIS NEEDS ITS OWN PROBE. Every other scroll assertion is about a viewport whose
// content is FIXED -- the offset only ever changes because the user moved it. Here the
// offset must change because the CONTENT grew, and the whole contract is the answer to
// "was I at the end BEFORE it grew?":
//
//   * the question cannot be asked after `maxOffsetY` has been updated, because then
//     every offset is short of the new end and the view would never follow (mutation S3);
//   * "at the end" must be re-derived from the live offset every frame, or a reader who
//     scrolled up gets yanked back down on the next append (mutation S2);
//   * a fresh view counts as at-the-end, so a log opens on its NEWEST line, not its
//     oldest (mutation S4);
//   * the auto-scroll is a REAL move -- `onScroll` fires and `offsetY` is written back --
//     or an author's model silently disagrees with the screen.
//
// The drag logic in the parent probe already pins the bar; nothing here touches it.
//
// WHERE THE NUMBERS COME FROM (hand-computed before the run; window 240x220):
//   root  padding 10, alignItems flex-start -> the viewport is (10,10,120,100).
//   Bands are 120x30. After N bands the content is 30N tall and maxOffsetY = 30N - 100.
//     5 bands -> 150 tall, maxOffsetY 50.   A fresh view sits at the end: offsetY 50.
//       local y 15 shows content 65  -> band 2.
//       local y 90 shows content 140 -> band 4.
//     7 bands -> 210, max 110, follows to 110.  local 15 -> 125 = band 4,
//                                               local 90 -> 200 = band 6.
//     8 bands after scrolling UP 24px (offsetY 86, detached) -> max 140, offset STAYS 86.
//       local 15 -> 101 = band 3, local 90 -> 176 = band 5.
//     9 bands after putting the view back at the end (140) -> max 170, follows to 170.
//       local 15 -> 185 = band 6, local 90 -> 260 = band 8.
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

var W:int = 240;
var H:int = 220;
var OUT:String = "stick";

// The palette is written down HERE, before the run, and copied into expect.json by
// hand: deriving it from the widget would be the probe grading its own homework.
var C0:uint = 0xEE1111;
var C1:uint = 0x11EE11;
var C2:uint = 0x1111EE;
var C3:uint = 0xEEEE11;
var C4:uint = 0xEE11EE;
var C5:uint = 0x11EEEE;
var C6:uint = 0xEE8800;
var C7:uint = 0x8800EE;
var C8:uint = 0x00AA55;
var COLORS:Array = [C0, C1, C2, C3, C4, C5, C6, C7, C8];

var failures:String = "";
var scrolls:int = 0;         // how many times the widget reported a move
var lastY:Number = -1;       // the last offset it reported

class StickProbe extends View
{
    private static const ROOT:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", alignItems: "flex-start",
        padding: 10, size: [240, 220],
        background: 0xFFFFFF, text: { fontSize: 12, color: 0x111827 }
    });
    private static const SV:StyleRefinement = StyleRefinement.from({ size: [120, 100] });

    public var sv:ScrollViewNode;
    public var bands:int;

    public function StickProbe():void
    {
        super();
        this.bands = 0;
    }

    override public function render():Node
    {
        if (this.sv == null)
        {
            this.sv = ScrollViewNode(scrollView({
                key: "sv", style: SV, wheelStep: 24, stickToBottom: true,
                onScroll: function (x:Number, y:Number):void { note(x, y); }
            }));
            // FIVE bands to start. Growth appends to THIS list (see grow()): a scroll
            // view keeps its live offset only while its descriptor survives, so the
            // view is built once and its children are appended to, never rebuilt.
            this.addBand();
            this.addBand();
            this.addBand();
            this.addBand();
            this.addBand();
        }
        return column({ key: "root", style: ROOT, ariaName: "stick to bottom probe" }, [this.sv]);
    }

    // Appends one band whose colour is its index. Only ever GROWS, so the reconciler
    // mounts a new tail without disturbing the rows above it.
    //
    // The colour goes into the STYLE, not into a `background` shorthand option: when
    // `style` is present, OptionSupport.applyOpts builds the refinement from it and
    // ignores the shorthand keys -- so a band built with both is a band with no colour
    // at all (measured: every pixel in the viewport read white).
    public function addBand():void
    {
        var i:int = this.bands;
        this.bands = i + 1;
        var st:StyleRefinement = StyleRefinement.from({ size: [120, 30], background: uint(COLORS[i]) });
        this.sv.addChild(box({ key: "b" + i, style: st, ariaName: "" }));
    }
}

function note(x:Number, y:Number):void
{
    scrolls = scrolls + 1;
    lastY = y;
}

var view:StickProbe = new StickProbe();
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

// DECLARED BEFORE showWindow: a file-scope initializer is emitted in SOURCE ORDER
// between the top-level statements, and showWindow blocks for the life of the window.
setTimeout(settle, 900);
stage.showWindow(W, H, "probe stick");

// ---- phase 0: a fresh log opens on its newest line -------------------------
function settle():void
{
    stageMark("settle");
    writeText(OUT + ".rects.txt", "root " + rectOf(node("root")) + "\nsv " + rectOf(node("sv")) + "\n");
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    writeBmp(OUT + ".bmp", bd);

    var sv:ScrollViewNode = view.sv;
    expect(sv.contentH == 150, "content height is " + sv.contentH + ", want 150 (5 bands of 30)");
    expect(sv.maxOffsetY == 50, "maxOffsetY is " + sv.maxOffsetY + ", want 50 (150 - 100)");
    expect(sv.offsetY == 50, "a fresh sticky view sits at " + sv.offsetY + ", want 50 (its newest line)");
    expect(scrolls >= 1 && lastY == 50, "the opening move was not reported: " + scrolls + " call(s), last y " + lastY);
    expect(pixel(bd, 60, 25) == C2, "the top of the viewport shows " + hex(pixel(bd, 60, 25)) + ", want band 2 " + hex(C2));
    expect(pixel(bd, 60, 100) == C4, "the bottom of the viewport shows " + hex(pixel(bd, 60, 100)) + ", want band 4 " + hex(C4));
    setTimeout(grow, 250);
}

// ---- phase 1: two more bands -> the view follows the end -------------------
function grow():void
{
    stageMark("grow");
    view.addBand();
    view.addBand();
    app.invalidate(Dirty.STRUCTURE);
    app.reflow();
    setTimeout(afterGrow, 250);
}

function afterGrow():void
{
    var sv:ScrollViewNode = view.sv;
    expect(sv.maxOffsetY == 110, "maxOffsetY after the growth is " + sv.maxOffsetY + ", want 110 (210 - 100)");
    expect(sv.offsetY == 110, "the sticky view is at " + sv.offsetY + ", want 110 (it must follow)");
    expect(lastY == 110, "the follow was not reported: last y " + lastY);
    var bd:BitmapData = bitmap();
    expect(pixel(bd, 60, 25) == C4, "after the growth the top shows " + hex(pixel(bd, 60, 25)) + ", want band 4 " + hex(C4));
    expect(pixel(bd, 60, 100) == C6, "after the growth the bottom shows " + hex(pixel(bd, 60, 100)) + ", want band 6 " + hex(C6));
    stageMark("scroll up");
    // One notch UP (delta +1 is toward the START, see the parent probe): 110 - 24 = 86.
    sendWheel(60, 60, 1);
    setTimeout(afterScrollUp, 250);
}

// ---- phase 2: the reader scrolls up, then more content arrives -------------
function afterScrollUp():void
{
    var sv:ScrollViewNode = view.sv;
    expect(sv.offsetY == 86, "one notch up left the view at " + sv.offsetY + ", want 86 (110 - 24)");
    stageMark("grow while detached");
    view.addBand();
    app.invalidate(Dirty.STRUCTURE);
    app.reflow();
    setTimeout(afterDetached, 250);
}

function afterDetached():void
{
    var sv:ScrollViewNode = view.sv;
    expect(sv.maxOffsetY == 140, "maxOffsetY while detached is " + sv.maxOffsetY + ", want 140 (240 - 100)");
    // THE WHOLE POINT: the content grew by 30px and the reader's position did not move
    // by one pixel. A view that follows unconditionally would now be at 140.
    expect(sv.offsetY == 86, "content growth yanked the view to " + sv.offsetY + ", want 86 (the reader scrolled up)");
    var bd:BitmapData = bitmap();
    expect(pixel(bd, 60, 25) == C3, "the detached view's top shows " + hex(pixel(bd, 60, 25)) + ", want band 3 " + hex(C3));
    expect(pixel(bd, 60, 100) == C5, "the detached view's bottom shows " + hex(pixel(bd, 60, 100)) + ", want band 5 " + hex(C5));
    stageMark("back to the end");
    // Back to the end: an explicit request re-attaches, because the rule is re-derived
    // from the live offset every frame.
    sv.offsetY = 140;
    app.invalidate(Dirty.VALUE);
    setTimeout(afterReattach, 250);
}

// ---- phase 3: back at the end, the next growth follows again ---------------
function afterReattach():void
{
    var sv:ScrollViewNode = view.sv;
    expect(sv.offsetY == 140, "the explicit request left the view at " + sv.offsetY + ", want 140 (the end)");
    stageMark("grow reattached");
    view.addBand();
    app.invalidate(Dirty.STRUCTURE);
    app.reflow();
    setTimeout(afterReattached, 250);
}

function afterReattached():void
{
    var sv:ScrollViewNode = view.sv;
    expect(sv.maxOffsetY == 170, "maxOffsetY after re-attaching is " + sv.maxOffsetY + ", want 170 (270 - 100)");
    expect(sv.offsetY == 170, "a re-attached view is at " + sv.offsetY + ", want 170 (it must follow again)");
    expect(lastY == 170, "the second follow was not reported: last y " + lastY);
    var bd:BitmapData = bitmap();
    expect(pixel(bd, 60, 25) == C6, "the top shows " + hex(pixel(bd, 60, 25)) + ", want band 6 " + hex(C6));
    expect(pixel(bd, 60, 100) == C8, "the bottom shows " + hex(pixel(bd, 60, 100)) + ", want band 8 " + hex(C8));
    setTimeout(finish, 250);
}

function finish():void
{
    writeText(OUT + ".done", failures == "" ? "PASS" : "FAIL " + failures);
}

// ---- helpers --------------------------------------------------------------

function node(k:String):UiNode { return app.findByKey(k); }

function bitmap():BitmapData
{
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    return bd;
}

function pixel(bd:BitmapData, x:int, y:int):uint { return bd.getPixel(x, y) & 0xFFFFFF; }

function rectOf(n:UiNode):String
{
    if (n == null) return "MISSING";
    return n.absX + "," + n.absY + "," + n.absW + "," + n.absH;
}

function sendWheel(x:Number, y:Number, delta:Number):void
{
    try
    {
        stage.dispatchWheel(x, y, delta);
    }
    catch (err:Error)
    {
        failures = failures + "wheel at (" + x + "," + y + ") threw " + err.name + ": " + err.message + "; ";
    }
}

function expect(ok:Boolean, msg:String):void
{
    if (!ok) failures = failures + msg + "; ";
}

function hex(v:uint):String
{
    var s:String = (v & 0xFFFFFF).toString(16);
    while (s.length < 6) s = "0" + s;
    return "#" + s;
}

// The stage survives in `<name>.step`, never in `.done`: tools/probe.cjs only prints the
// breadcrumb when the verdict never arrived.
function stageMark(label:String):void
{
    writeText(OUT + ".step", label + "\n");
}

function writeText(path:String, t:String):void
{
    var f:File = new File(path);
    var fs:FileStream = new FileStream();
    fs.open(f, FileMode.WRITE);
    fs.writeUTFBytes(t);
    fs.close();
}

// 32-bit bottom-up BMP written by hand (this runtime has BitmapData but no PNG encoder).
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
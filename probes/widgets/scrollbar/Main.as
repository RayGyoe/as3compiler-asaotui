// probes/widgets/scrollbar/Main.as -- the probe for ScrollView's SCROLLBARS.
//
// Output prefix MUST equal the directory name (`scrollbar`).
//
// The bars are chrome painted over the viewport, so a bitmap is exactly the right
// instrument: a rect file cannot see them. What this pins:
//   * one BAR PER AXIS THAT OVERFLOWS, and NO bar on the axis that does not
//     (a vertical bar on a 40px-tall content would be a layout lie);
//   * the THUMB's colour, its TRACK's colour, and the thumb's POSITION tracking
//     the scroll offset;
//   * that a THUMB DRAG moves the content (press on the thumb, move 15px, release
//     -> offset 45: 15 * maxOffsetY / (track - thumb) = 15 * 160 / 53.333);
//   * that a click on the TRACK pages by one viewport, and the wheel still works;
//   * that the WHEEL FALLS BACK to the horizontal axis when there is no vertical
//     range -- and that a horizontal offset really SLIDES the pixels (the old
//     widget published offsetX but only ever put offsetY into the scrollRect);
//   * clamping to maxOffset on both axes.
//
// WHERE THE NUMBERS COME FROM (hand-computed, before the run):
//   sv1 (20,20,200,80), content 200x240 (three 80px bands) -> maxOffsetY 160.
//     bar thickness 10 -> the vertical track is local x 190..200 (stage 210..220).
//     thumb length = 80 * 80/240 = 26.667 -> the rect 2..24.667 in y, inset 2 ->
//     stage y 22..44.667. So (215,30) is the thumb and (215,90) is bare track.
//   sv2 (20,110,200,40), content 600x40 (six 100px cells in a row) -> maxOffsetX
//     400. The horizontal track is local y 30..40 (stage 140..150); the thumb is
//     200 * 200/600 = 66.667 long -> stage x 22..84.667. (30,145) is the thumb,
//     (150,145) is track.
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
var H:int = 200;
var OUT:String = 'scrollbar';

// The palette has to be written down here BEFORE the run and copied into
// expect.json by hand: deriving it from the widget would be the probe grading its
// own homework.
var THUMB:uint = 0xB9C2D0;
var TRACK:uint = 0xE8EDF5;

class ScrollProbe extends View
{
    private static const ROOT:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", alignItems: "flex-start",
        padding: 20, gap: 10, size: [320, 200],
        background: 0xFFFFFF, text: { fontSize: 12, color: 0x111827 }
    });
    // 200x80 viewport; three 80px bands make the content 240 tall.
    private static const SV1:StyleRefinement = StyleRefinement.from({ size: [200, 80] });
    private static const B1:StyleRefinement = StyleRefinement.from({ size: [200, 80], background: 0xEE1111 });
    private static const B2:StyleRefinement = StyleRefinement.from({ size: [200, 80], background: 0x11EE11 });
    private static const B3:StyleRefinement = StyleRefinement.from({ size: [200, 80], background: 0x1111EE });
    // 200x40 viewport that scrolls SIDEWAYS only: the strip is 600 wide and the
    // viewport is its full height, so maxOffsetY is 0 and the wheel must fall back
    // to the horizontal axis.
    private static const SV2:StyleRefinement = StyleRefinement.from({
        size: [200, 40], flexDirection: "row"
    });
    private static const STRIP:StyleRefinement = StyleRefinement.from({
        flexDirection: "row", size: [600, 40]
    });
    private static const R1:StyleRefinement = StyleRefinement.from({ size: [100, 40], background: 0xEE1111 });
    private static const R2:StyleRefinement = StyleRefinement.from({ size: [100, 40], background: 0x11EE11 });
    private static const R3:StyleRefinement = StyleRefinement.from({ size: [100, 40], background: 0x1111EE });
    private static const R4:StyleRefinement = StyleRefinement.from({ size: [100, 40], background: 0xEEEE11 });
    private static const R5:StyleRefinement = StyleRefinement.from({ size: [100, 40], background: 0x11EEEE });
    private static const R6:StyleRefinement = StyleRefinement.from({ size: [100, 40], background: 0xEE11EE });

    public var sv1:ScrollViewNode;
    public var sv2:ScrollViewNode;

    public function ScrollProbe():void { super(); }

    override public function render():Node
    {
        if (this.sv1 == null)
        {
            this.sv1 = ScrollViewNode(scrollView({ key: "sv1", wheelStep: 20, style: SV1 }, [
                box({ key: "b1", style: B1, ariaName: "band 1" }),
                box({ key: "b2", style: B2, ariaName: "band 2" }),
                box({ key: "b3", style: B3, ariaName: "band 3" })
            ]));
        }
        if (this.sv2 == null)
        {
            this.sv2 = ScrollViewNode(scrollView({ key: "sv2", wheelStep: 20, style: SV2 }, [
                row({ key: "strip", style: STRIP, ariaName: "strip" }, [
                    box({ key: "r1", style: R1, ariaName: "" }),
                    box({ key: "r2", style: R2, ariaName: "" }),
                    box({ key: "r3", style: R3, ariaName: "" }),
                    box({ key: "r4", style: R4, ariaName: "" }),
                    box({ key: "r5", style: R5, ariaName: "" }),
                    box({ key: "r6", style: R6, ariaName: "" })
                ])
            ]));
        }
        return column({ key: "root", style: ROOT, ariaName: "scrollbars" }, [this.sv1, this.sv2]);
    }
}

var view:ScrollProbe = new ScrollProbe();
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

setTimeout(settle, 900);
stage.showWindow(W, H, "probe scrollbar");

var carry:String = "";

// A breadcrumb, in the same spirit as the docs tour's mark(): record the stage that
// is ABOUT to run in `<probe>.step`, so a crash (which stops the frame loop and
// leaves no `.done` behind) is reported as the stage that died -- "TIMEOUT" alone
// says nothing about where. It MUST NOT be `.done`: the harness polls that file and
// takes the first content it sees, so a breadcrumb there would be read as the
// verdict (measured: three consecutive "died during settle checks" that were really
// the breadcrumb of a passing run).
function step(s:String):void
{
    writeText(OUT + ".step", s);
}

function settle():void
{
    step("settle checks");
    // A throw inside a frame is swallowed by the runtime's recovery point (the loop
    // carries on and nothing is written), so the first stage catches explicitly and
    // turns it into a verdict instead of a silent TIMEOUT.
    try { settleBody(); }
    catch (err:Error) { writeText(OUT + ".done", "FAIL settle threw #" + err.errorID + ": " + err.message); }
}

function settleBody():void
{
    var names:Array = ["root", "sv1", "b1", "b2", "b3", "sv2", "strip", "r1"];
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

    if (missing > 0) { writeText(OUT + ".done", "FAIL " + missing + " node(s) missing"); return; }

    var problems:String = "";
    if (view.sv1.contentH != 240)
        problems = problems + "sv1 content height is " + view.sv1.contentH + " not 240; ";
    if (view.sv1.maxOffsetY != 160)
        problems = problems + "sv1 maxOffsetY is " + view.sv1.maxOffsetY + " not 160; ";
    if (view.sv2.contentW != 600)
        problems = problems + "sv2 content width is " + view.sv2.contentW + " not 600; ";
    if (view.sv2.maxOffsetX != 400)
        problems = problems + "sv2 maxOffsetX is " + view.sv2.maxOffsetX + " not 400; ";
    if (view.sv2.maxOffsetY != 0)
        problems = problems + "sv2 reports a vertical range of " + view.sv2.maxOffsetY + " with a 40px content; ";
    carry = problems;
    setTimeout(wheelStage, 300);
}

// A wheel notch over sv1 must move the vertical axis by wheelStep 20 and not the
// horizontal one; then back to the top.
function wheelStage():void
{
    step("wheel");
    var problems:String = carry;
    stage.dispatchWheel(120, 60, -1);
    carry = problems;
    setTimeout(wheelCheck, 300);
}

function wheelCheck():void
{
    step("wheel check");
    var problems:String = carry;
    if (view.sv1.offsetY != 20)
        problems = problems + "a wheel notch left sv1.offsetY at " + view.sv1.offsetY + " not 20; ";
    if (view.sv1.offsetX != 0)
        problems = problems + "the wheel moved the horizontal axis to " + view.sv1.offsetX + "; ";
    // At offset 20 the window's local y=70 shows content row 90, i.e. b2.
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    problems = problems + expectStr(bd, 120, 90, 0x11EE11, "the vertical wheel did not slide b2 into view");
    // The thumb is at the top at offset 0; at 20/160 of the free track it has moved
    // 20/160 * (80 - 26.667) = 6.67px, so (215,30) is still the thumb.
    problems = problems + expectStr(bd, 215, 30, THUMB, "the vertical thumb after a notch");

    // Back to the top, so the drag stage starts from a known offset.
    stage.dispatchWheel(120, 60, 1);
    carry = problems;
    setTimeout(dragStage, 300);
}

// Press the vertical thumb and drag it 15 stage px down. The free track is
// 80 - 26.667 = 53.333 px for 160 px of content: 15 * 160/53.333 = 45.
function dragStage():void
{
    step("drag");
    var problems:String = carry;
    stage.dispatchMouse(215, 30, "mouseDown");
    stage.dispatchMouse(215, 45, "mouseMove");
    stage.dispatchMouse(215, 45, "mouseUp");
    // Clear the hover (the pointer ended over the thumb, which would keep it lit);
    // a move inside the viewport but off the bar is enough.
    stage.dispatchMouse(100, 30, "mouseMove");
    carry = problems;
    setTimeout(dragCheck, 300);
}

function dragCheck():void
{
    step("drag check");
    var problems:String = carry;
    // The drag maps the pointer through a DIVISION by the free track (53.333...),
    // so exact equality would be a coincidence of the chosen numbers -- the point
    // is 1:1 tracking, which this tolerance still pins (a thumb-length span yields
    // 41.86, i.e. 3.1px away, and the old widget never moved at all).
    if (!near(view.sv1.offsetY, 45))
        problems = problems + "dragging the thumb 15px left offsetY at " + view.sv1.offsetY
            + " not 45 (15 * 160 / 53.333); ";
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    // offset 45: local y=70 shows content row 115, inside b2.
    problems = problems + expectStr(bd, 120, 90, 0x11EE11, "the drag did not slide the content");
    // The thumb moved with it: local y = 45/160 * 53.333 = 15 .. 41.667 -> stage
    // 35..61.667. (215,50) is the thumb; (215,25) is now bare track.
    problems = problems + expectStr(bd, 215, 50, THUMB, "the thumb did not follow the drag");
    problems = problems + expectStr(bd, 215, 25, TRACK, "the track under the old thumb position");
    // No horizontal bar on an axis that does not overflow: at (170,95) the band is
    // still visible where a horizontal track would have been painted.
    problems = problems + expectStr(bd, 170, 95, 0x11EE11, "a horizontal bar appeared on a viewport with no horizontal overflow");
    // ... and no vertical bar on sv2, which is 40 tall with a 40 tall content.
    problems = problems + expectStr(bd, 215, 115, 0x11EE11, "a vertical bar appeared on a viewport with no vertical overflow");

    // Clamp: ask for far more than the content allows.
    view.sv1.offsetY = 9999;
    app.invalidate(Dirty.VALUE);
    carry = problems;
    setTimeout(clampCheck, 300);
}

function clampCheck():void
{
    step("clamp");
    var problems:String = carry;
    if (view.sv1.offsetY != 160)
        problems = problems + "clamped offsetY is " + view.sv1.offsetY + " not 160; ";
    // offset 160 = the very bottom: local y=70 shows content row 230, inside b3.
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    problems = problems + expectStr(bd, 120, 90, 0x1111EE, "the bottom of the content is not b3");
    // The thumb sits at the end of its track: local 80 - 26.667 = 53.333 -> stage
    // 73.333..100, so (215,95) is the thumb and (215,25) is bare track again.
    problems = problems + expectStr(bd, 215, 95, THUMB, "the thumb at the clamp");
    problems = problems + expectStr(bd, 215, 25, TRACK, "the track at the clamp");

    // The horizontal fallback: sv2 has no vertical range, so the wheel must move
    // offsetX. This is also the assertion the old widget would fail -- it clamped
    // and reported offsetX but only ever wrote offsetY into the scrollRect.
    stage.dispatchWheel(120, 130, -1);
    carry = problems;
    setTimeout(horizontalCheck, 300);
}

function horizontalCheck():void
{
    step("horizontal");
    var problems:String = carry;
    if (view.sv2.offsetX != 20)
        problems = problems + "the wheel over a horizontal-only viewport left offsetX at "
            + view.sv2.offsetX + " not 20; ";
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    // Stage x=110 is local 90; at offsetX 20 that is content x=110, inside r2.
    problems = problems + expectStr(bd, 110, 125, 0x11EE11, "a horizontal offset did not slide the content");
    // The horizontal thumb moved: 20/400 * (200 - 66.667) = 6.667 -> local 8.667,
    // i.e. stage 28.667..95.33. (50,145) is on it.
    problems = problems + expectStr(bd, 50, 145, THUMB, "the horizontal thumb after a notch");
    // ... and its track is still visible further along.
    problems = problems + expectStr(bd, 150, 145, TRACK, "the horizontal track beyond the thumb");

    view.sv2.offsetX = 9999;
    app.invalidate(Dirty.VALUE);
    carry = problems;
    setTimeout(horizontalClamp, 300);
}

function horizontalClamp():void
{
    step("horizontal clamp");
    var problems:String = carry;
    if (view.sv2.offsetX != 400)
        problems = problems + "clamped offsetX is " + view.sv2.offsetX + " not 400; ";
    writeText(OUT + ".done", problems == "" ? "PASS" : "FAIL " + problems);
}

function near(a:Number, b:Number):Boolean
{
    var d:Number = a - b;
    if (d < 0) d = -d;
    return d < 0.001;
}

function expectStr(bd:BitmapData, x:int, y:int, rgb:uint, what:String):String{
    var got:uint = bd.getPixel(x, y) & 0xFFFFFF;
    if (got == rgb) return "";
    return what + " is " + hex(got) + " not " + hex(rgb) + "; ";
}

function hex(v:uint):String
{
    var s:String = (v & 0xFFFFFF).toString(16);
    while (s.length < 6) s = "0" + s;
    return "#" + s;
}

function writeText(path:String, t:String):void
{
    var f:File = new File(path);
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
    var f:File = new File(path);
    var fs:FileStream = new FileStream();
    fs.open(f, FileMode.WRITE);
    fs.writeBytes(ba, 0, 0);
    fs.close();
}

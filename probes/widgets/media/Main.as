// probes/widgets/media/Main.as -- the probe for the MEDIA widget group
// (image + scrollView).
//
// Output prefix MUST equal the directory name (`media`).
//
// What it pins:
//   * the RECTS of a fixed column: three images (stretched, 1:1, and the DEFAULT
//     `fit`) and a scroll viewport with three 40px bands in it -- hand-computed in
//     expect.json;
//   * exact PIXEL colours for the four scale/placement modes' resting state;
//   * and, IN THE PROGRAM (a bitmap cannot show them): that the two kinds registered,
//     that the viewport really CLIPS (the band that slid above the window must not
//     paint over its neighbour), that a wheel notch arriving through the real
//     `Stage.dispatchWheel` path -- hit test, bubbling, listener -- slides the
//     content by exactly `wheelStep` px, and that swapping a scale mode re-arranges
//     the bitmap.
//
// THE LAYOUT RECTS ARE THE UNSCROLLED ONES. `scrollRect` slides pixels only; the
// engine's solved rects (which is what `<name>.rects.txt` reports) do not move. So
// the resting-state bitmap and the rect file agree, and the scrolled state is
// checked separately, by reading the frame back in the program.
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
var OUT:String = 'media';

// AN 8x8 SOLID SOURCE, built ONCE. A fresh BitmapData per render() would be a new
// object identity every frame, which the image widget would read as "these are new
// pixels" and re-measure for ever.
var SRC:BitmapData = new BitmapData(8, 8, false, 0x22AA55);
var modeProblems:String = "";

class MediaProbe extends View
{
    private static const ROOT:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", alignItems: "flex-start",
        padding: 20, gap: 10, size: [320, 260],
        background: 0xFFFFFF, text: { fontSize: 12, color: 0x111827 }
    });
    private static const IMG_STRETCH:StyleRefinement = StyleRefinement.from({ size: [80, 40] });
    private static const IMG_ONE:StyleRefinement = StyleRefinement.from({ size: [80, 40] });
    // The THIRD image declares no scaleMode at all, so it exercises the DEFAULT
    // ("fit"). Without it the default path -- the one every author gets for free --
    // was never measured: an 8x8 source in an 80x40 box fits at min(80/8, 40/8) = 5,
    // i.e. 40x40 centred, so 20px of white must survive on each side.
    private static const IMG_FIT:StyleRefinement = StyleRefinement.from({ size: [80, 40] });
    private static const SV:StyleRefinement = StyleRefinement.from({ size: [280, 60] });
    private static const B1:StyleRefinement = StyleRefinement.from({ size: [280, 40], background: 0xEE1111 });
    private static const B2:StyleRefinement = StyleRefinement.from({ size: [280, 40], background: 0x11EE11 });
    private static const B3:StyleRefinement = StyleRefinement.from({ size: [280, 40], background: 0x1111EE });

    public var scrollDesc:ScrollViewNode;
    public var imageDesc:ImageNode;
    public var scrolledX:Number = -1;
    public var scrolledY:Number = -1;

    public function MediaProbe():void { super(); }

    override public function render():Node
    {
        if (this.imageDesc == null)
        {
            this.imageDesc = ImageNode(image({ key: "img1", style: IMG_STRETCH,
                bitmapData: SRC, scaleMode: "stretch", smooth: false }));
        }
        if (this.scrollDesc == null)
        {
            this.scrollDesc = ScrollViewNode(scrollView({
                key: "sv", style: SV, wheelStep: 24,
                onScroll: function (x:Number, y:Number):void { noteScroll(x, y); }
            }, [
                box({ key: "b1", style: B1, ariaName: "band 1" }),
                box({ key: "b2", style: B2, ariaName: "band 2" }),
                box({ key: "b3", style: B3, ariaName: "band 3" })
            ]));
        }
        return column({ key: "root", style: ROOT, ariaName: "media" }, [
            this.imageDesc,
            image({ key: "img2", style: IMG_ONE, bitmapData: SRC, scaleMode: "none", smooth: false }),
            this.scrollDesc,
            image({ key: "img3", style: IMG_FIT, bitmapData: SRC, smooth: false })
        ]);
    }
}

var view:MediaProbe = new MediaProbe();
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

setTimeout(settle, 900);
stage.showWindow(W, H, "probe media");

function noteScroll(x:Number, y:Number):void
{
    view.scrolledX = x;
    view.scrolledY = y;
}

function settle():void
{
    var names:Array = ["root", "img1", "img2", "sv", "b1", "b2", "b3", "img3"];
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
var carry:String = "";

// ---- the behaviour stages -------------------------------------------------
// A bitmap can only show colours and rects; these check what it cannot: that both
// kinds registered, that a settled tree stops solving, that the content extent and
// scroll range were published, and that a real wheel event moves the content by
// exactly `wheelStep` and then clamps at the bottom.
function steady():void
{
    var problems:String = "";

    // (a) both kinds registered.
    if (!Widgets.has("image")) problems = problems + "Widgets.has('image') is false; ";
    if (!Widgets.has("scrollView")) problems = problems + "Widgets.has('scrollView') is false; ";

    // (b) a settled tree never re-solves layout.
    var extraSolves:Number = app.layoutSolves - solveAtSettle;
    var extraFrames:int = app.enterFrameTicks - frame0;
    if (extraFrames < 2) problems = problems + "only " + extraFrames + " frame(s) elapsed; ";
    if (extraSolves > 0) problems = problems + "a settled tree re-solved layout " + extraSolves + " time(s); ";

    // (c) the content extent and the scroll range were published by paint. The bands
    //     total 120 in a 60 viewport, so 60 is scrollable and nothing shrank them
    //     (a viewport that shrank its content would report contentH == 60).
    if (view.scrollDesc.contentH != 120)
        problems = problems + "scroll content height is " + view.scrollDesc.contentH + " not 120 (did the viewport shrink its content?); ";
    if (view.scrollDesc.maxOffsetY != 60)
        problems = problems + "scroll maxOffsetY is " + view.scrollDesc.maxOffsetY + " not 60; ";

    // (d) one wheel notch, through the REAL path: Stage.dispatchWheel hit-tests the
    //     point, dispatches a bubbling MOUSE_WHEEL, and the viewport's own listener
    //     moves the content. delta = -1 means "scroll toward the end".
    stage.dispatchWheel(160, 150, -1);
    carry = problems;
    setTimeout(wheelCheck, 300);
}

function wheelCheck():void
{
    var problems:String = carry;
    // 24px per notch.
    if (view.scrollDesc.offsetY != 24)
        problems = problems + "wheel moved the viewport to " + view.scrollDesc.offsetY + " not 24; ";
    if (view.scrolledY != 24)
        problems = problems + "onScroll reported " + view.scrolledY + " not 24; ";

    // The window is rows 120..179. Window row = 120 + (object row - offset), so after
    // one notch (offset 24) the window shows object rows 24..83:
    //   120..135  b1 (0..39)    red
    //   136..175  b2 (40..79)   green
    //   176..179  b3 (80..119)  blue
    // and row 119 -- the gap between img2 and the viewport -- must still be WHITE,
    // because b1 now spans object rows 0..39 and would have painted there without a
    // clip. That pixel is the clip assertion.
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    problems = problems + expectStr(bd, 160, 125, 0xEE1111, "b1 at the top of the window after +24");
    problems = problems + expectStr(bd, 160, 165, 0x11EE11, "b2 after +24");
    problems = problems + expectStr(bd, 160, 178, 0x1111EE, "b3 after +24");
    problems = problems + expectStr(bd, 160, 119, 0xFFFFFF, "the gap above the viewport was painted over (no clip)");
    problems = problems + expectStr(bd, 160, 118, 0xFFFFFF, "two rows above the viewport were painted over");

    // (e) clamping: ask for far more than the content allows and the view must stop
    //     at maxOffsetY, not scroll into empty space.
    view.scrollDesc.offsetY = 9999;
    app.invalidate(Dirty.VALUE);
    carry = problems;
    setTimeout(clampCheck, 300);
}

function clampCheck():void
{
    var problems:String = carry;
    if (view.scrollDesc.offsetY != 60)
        problems = problems + "clamped offset is " + view.scrollDesc.offsetY + " not 60; ";
    if (view.scrolledY != 60)
        problems = problems + "onScroll reported the clamp as " + view.scrolledY + " not 60; ";

    // offset 60 = the very bottom: the window's rows 120..139 show object rows
    // 60..79 (b2's tail) and 140..179 show object rows 80..119 (all of b3).
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    problems = problems + expectStr(bd, 160, 125, 0x11EE11, "the window top at the clamp (b2's tail)");
    problems = problems + expectStr(bd, 160, 140, 0x1111EE, "the bottom of the content is not b3");
    problems = problems + expectStr(bd, 160, 178, 0x1111EE, "the last row of the content is not b3");
    problems = problems + expectStr(bd, 160, 119, 0xFFFFFF, "the gap above the viewport was painted over at the clamp");

    // (f) swapping a scale mode re-arranges: "none" on img1 keeps the 8x8 source
    //     centred instead of filling 80x40, so a pixel inside the first image's rect
    //     but outside a centred 8x8 must stop being the source colour. This is the
    //     payload() -> relayout path for `mode`.
    problems = problems + expectStr(bd, 30, 25, 0x22AA55, "img1's stretched fill");
    view.imageDesc.scaleMode = "none";
    app.invalidate(Dirty.VALUE);
    carry = problems;
    setTimeout(modeCheck, 300);
}

function modeCheck():void
{
    var problems:String = carry;
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    problems = problems + expectStr(bd, 30, 25, 0xFFFFFF, "a scale-mode change did not re-arrange the bitmap");
    problems = problems + expectStr(bd, 60, 40, 0x22AA55, "the 1:1 bitmap is not where it was centred");
    writeText(OUT + ".done", problems == "" ? "PASS" : "FAIL " + problems);
}

function expectStr(bd:BitmapData, x:int, y:int, rgb:uint, what:String):String
{
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

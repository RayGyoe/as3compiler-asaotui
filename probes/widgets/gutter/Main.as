// probes/widgets/gutter/Main.as -- the probe for `scrollbarGutter: "stable"`.
//
// Output prefix MUST equal the directory name (`gutter`).
//
// WHY THIS PROBE IS MOSTLY RECTS. The bar is opaque, so a bitmap CANNOT tell "the
// content stops before the lane" from "the content runs under the bar" -- the bar
// paints over whichever it is. The lane is a LAYOUT fact (the bar's thickness folded
// into the node's padding), so the instrument is the solved rect of the content:
// 190 wide in a 200px stable viewport, 200 in an overlay one. The bitmap only proves
// the two modes still LOOK like themselves (a band, a thumb, a lane).
//
// WHAT THIS PINS:
//   * "stable" narrows the content by the bar thickness, "overlay" (the default)
//     does not -- the two modes side by side in one fixture;
//   * the lane is on the RIGHT for a vertical bar and on the BOTTOM for a horizontal
//     one, i.e. the reservation follows the axis the bar is on;
//   * reserving the lane does NOT invent a scroll range: contentW shrinks to the
//     content box and maxOffsetX/maxOffsetY stay 0, so a `pct(1)` child neither
//     overflows nor grows a spurious second bar;
//   * the bar itself still paints exactly where it did (the lane, right edge), so
//     "reserve" did not also move it.
//
// WHERE THE NUMBERS COME FROM (hand-computed, before the run):
//   root (320x200), column, align-items flex-start, padding 20, gap 10 -> content
//   starts at (20,20), each child is 200 wide.
//     svOver    (20,20,200,40)  overlay   ; band  (20,20,200,30)  <- full width
//     svStable  (20,70,200,40)  stable    ; band  (20,70,190,30)  <- 200 - 10 lane
//     svHoriz   (20,120,200,30) stable    ; band  (20,120,200,20) <- 30 - 10 lane
//   The vertical lane is local x 190..200 (stage 210..220); the drawn thumb is inset
//   2, so 212..218. The horizontal lane is local y 20..30 (stage 140..150); its
//   thumb is 142..148.
//
//   contentW/H and maxOffset are the widget's outputs for the same reason: with the
//   lane reserved a 190-wide content in a 200-wide box has NOTHING to scroll, which
//   is the whole point (a gutter that creates a range would trade an overlap for a
//   bar nobody asked for).
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
var OUT:String = 'gutter';

// Written down here BEFORE the run and copied into expect.json by hand: deriving
// them from the widget would be the probe grading its own homework.
var THUMB:uint = 0xB9C2D0;

class GutterProbe extends View
{
    private static const ROOT:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", alignItems: "flex-start",
        padding: 20, gap: 10, size: [320, 200],
        background: 0xFFFFFF, text: { fontSize: 12, color: 0x111827 }
    });
    private static const SV_OVER:StyleRefinement = StyleRefinement.from({ size: [200, 40] });
    private static const SV_STABLE:StyleRefinement = StyleRefinement.from({ size: [200, 40] });
    private static const SV_HORIZ:StyleRefinement = StyleRefinement.from({ size: [200, 30] });
    // `pct(1)` is what a reading pane uses, and what makes the reservation visible
    // as a rect: an explicit 200 would keep 200 and overflow the lane instead.
    private static const BAND:StyleRefinement = StyleRefinement.from({
        size: [Length.pct(1), Length.px(30)], background: 0xEE1111
    });
    private static const BAND_STABLE:StyleRefinement = StyleRefinement.from({
        size: [Length.pct(1), Length.px(30)], background: 0x11EE11
    });
    // 25 tall in a 30 tall viewport whose bottom 10 is the bar's lane: with the lane
    // the content box is 20 and the band OVERFLOWS by 5 (maxOffsetY 5). That overflow
    // IS the assertion -- an overlay build has 30 for the band and reports 0.
    private static const BAND_HORIZ:StyleRefinement = StyleRefinement.from({
        size: [Length.pct(1), Length.px(25)], background: 0x1111EE
    });

    public var svOver:ScrollViewNode;
    public var svStable:ScrollViewNode;
    public var svHoriz:ScrollViewNode;

    public function GutterProbe():void { super(); }

    override public function render():Node
    {
        // Built once and mutated-by-nobody: these three viewports never scroll, so
        // nothing here needs a live model.
        if (this.svOver == null)
        {
            this.svOver = ScrollViewNode(scrollView({ key: "over", style: SV_OVER }, [
                box({ key: "overc", style: BAND, ariaName: "overlay band" })
            ]));
        }
        if (this.svStable == null)
        {
            this.svStable = ScrollViewNode(scrollView({
                key: "stable", style: SV_STABLE, scrollbarGutter: "stable",
                scrollbarY: "always", scrollbarX: "never"
            }, [
                box({ key: "stablec", style: BAND_STABLE, ariaName: "stable band" })
            ]));
        }
        if (this.svHoriz == null)
        {
            this.svHoriz = ScrollViewNode(scrollView({
                key: "horiz", style: SV_HORIZ, scrollbarGutter: "stable",
                scrollbarX: "always", scrollbarY: "never"
            }, [
                box({ key: "horizc", style: BAND_HORIZ, ariaName: "horizontal band" })
            ]));
        }
        return column({ key: "root", style: ROOT, ariaName: "scrollbar gutter" },
            [this.svOver, this.svStable, this.svHoriz]);
    }
}

var view:GutterProbe = new GutterProbe();
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

setTimeout(settle, 900);
stage.showWindow(W, H, "probe gutter");

function step(s:String):void
{
    writeText(OUT + ".step", s);
}

function settle():void
{
    step("settle checks");
    try { settleBody(); }
    catch (err:Error) { writeText(OUT + ".done", "FAIL settle threw #" + err.errorID + ": " + err.message); }
}

function settleBody():void
{
    var names:Array = ["root", "over", "overc", "stable", "stablec", "horiz", "horizc"];
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
    // The lane is reserved, so the CONTENT box shrank -- and the content extent with
    // it. A gutter that reported 200 here would be a gutter that only moved pixels.
    if (view.svStable.contentW != 190)
        problems = problems + "stable content width is " + view.svStable.contentW + " not 190; ";
    if (view.svStable.maxOffsetX != 0)
        problems = problems + "reserving the lane invented a horizontal range of "
            + view.svStable.maxOffsetX + "; ";
    if (view.svStable.maxOffsetY != 0)
        problems = problems + "stable viewport reports a vertical range of "
            + view.svStable.maxOffsetY + " with a 30px content in 40; ";
    // The bottom lane is REAL SPACE the content is not laid out in: a 25 tall band in
    // a 30 tall viewport with a 10px lane leaves 20 of content box, so it overflows by
    // 5. (A percentage height is not used here: this engine resolves one against
    // something the probe could not name, which is a separate question.)
    if (view.svHoriz.contentH != 25)
        problems = problems + "horiz content height is " + view.svHoriz.contentH + " not 25; ";
    if (view.svHoriz.maxOffsetY != 5)
        problems = problems + "the bottom lane did not eat 10 of the 30 tall viewport: maxOffsetY is "
            + view.svHoriz.maxOffsetY + " not 5; ";
    if (view.svHoriz.contentW != 200)
        problems = problems + "a bottom lane narrowed the content to " + view.svHoriz.contentW + "; ";
    // ... and the default mode is untouched: the same 200px band in a 200px box.
    if (view.svOver.contentW != 200)
        problems = problems + "overlay content width is " + view.svOver.contentW + " not 200; ";
    if (view.svOver.maxOffsetX != 0)
        problems = problems + "overlay viewport reports a horizontal range of "
            + view.svOver.maxOffsetX + " for a fitting band; ";

    // The bitmap, so "stable" cannot degenerate into "no bar at all": the vertical
    // lane is still the bar's, and the overlay band still reaches under it.
    problems = problems + expectStr(bd, 215, 30, 0xEE1111,
        "the overlay band does not reach into the bar's lane");
    problems = problems + expectStr(bd, 205, 80, 0x11EE11,
        "the stable band does not stop before the lane");
    problems = problems + expectStr(bd, 215, 80, THUMB,
        "the stable viewport's vertical bar is not in its lane");
    problems = problems + expectStr(bd, 150, 105, 0xFFFFFF,
        "a horizontal bar appeared in the stable viewport (scrollbarX is never)");
    problems = problems + expectStr(bd, 30, 135, 0x1111EE,
        "the horizontal band is not above the bottom lane");
    problems = problems + expectStr(bd, 150, 145, THUMB,
        "the horizontal viewport's bar is not in its lane");

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

// probes/widgets/clip/Main.as -- `overflow` is a real clip window, not a style field
// that stops at the layout engine.
//
// Output prefix MUST equal the directory name (`clip`) because
// tools/probe.cjs derives the expected files from it.
//
// THE DEFECT THIS PINS (compiler-gaps G29, closed 2026-10-30): `overflow` had been
// accepted, validated and handed to the layout engine since the style layer existed,
// and NOTHING consumed it. A 200px strip inside a 120px `overflow: "hidden"` box
// painted all 200px and covered its neighbours -- the box's own background was not even
// visible under it. The compiler side was measured FIRST (adl 51.4.1 against our AOT,
// ten pixel cases, all bit-identical: as3compiler/temp/g29, skia.md 6.16) and it turned
// out to be NO compiler gap -- `scrollRect` and `mask` both clip, on both runtimes. The
// fix was therefore the library consuming a capability that already existed; this probe
// guards that it stays consumed.
//
// Three rows, same 120x28 box each, same 200x28 strip inside:
//   `hidden` / `scroll` -- must CLIP at the box's border box: the strip keeps its
//                          200px of LAYOUT and paints only 120 of them;
//   `visible`           -- the CONTROL: same geometry, no clip, so the strip paints
//                          all 200px. Without this row the first two prove nothing.
//
// What has to be asserted four different ways, because each one fails alone:
//   * a PIXEL inside the window (the clip must not eat what it should show);
//   * a PIXEL 4px PAST the window (the teeth: unclipped it is the strip's colour);
//   * the RECT of the strip (a clip must not be implemented by resizing the child);
//   * a CLICK past the window (the runtime's pick window is the same scrollRect, so
//     a spilling child stops being interactive -- CSS `overflow: hidden`), against a
//     control click INSIDE the window that must still reach the child.
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
var H:int = 160;
var OUT:String = 'clip';

class ClipProbe extends View
{
    // Root: column, padding 16, gap 12, explicit [320,160], white page.
    private static const ROOT:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", padding: 16, gap: 12, size: [320, 160],
        background: 0xFFFFFF
    });
    // The three 120-wide boxes. `size` is explicit, so every rect below is
    // hand-computable, and the child's 200px is the overflow under test.
    private static const HIDDEN:StyleRefinement = StyleRefinement.from({
        size: [120, 28], overflow: "hidden", background: 0xE2E8F0
    });
    private static const SCROLLED:StyleRefinement = StyleRefinement.from({
        size: [120, 28], overflow: "scroll", background: 0xE2E8F0
    });
    private static const VISIBLE:StyleRefinement = StyleRefinement.from({
        size: [120, 28], overflow: "visible", background: 0xE2E8F0
    });
    // `minSize` (NOT a flex field) is what keeps the strip 200 wide: a flex basis
    // field REPLACES the item's base size and the engine then resolves that basis
    // on the wrong axis (measured earlier: a 200x28 strip came out 200 TALL).
    private static function strip(w:uint, h:uint, c:uint):StyleRefinement
    {
        return StyleRefinement.from({
            size: [w, h], minSize: [w, h], background: c
        });
    }

    override public function render():Node
    {
        return column({ key: "root", style: ROOT }, [
            box({ key: "hidden", style: HIDDEN }, [
                box({ key: "hidden-strip", style: strip(200, 28, 0xFF0000) })
            ]),
            box({ key: "visible", style: VISIBLE }, [
                box({ key: "visible-strip", style: strip(200, 28, 0x2563EB) })
            ]),
            box({ key: "scrollv", style: SCROLLED }, [
                box({ key: "scroll-strip", style: strip(200, 28, 0xF59E0B) })
            ])
        ]);
    }
}

var view:ClipProbe = new ClipProbe();
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

var solveAtSettle:Number = 0;
var frame0:int = 0;
var clicksHidden:int = 0;
var clicksVisible:int = 0;

setTimeout(settle, 900);
stage.showWindow(W, H, "probe clip");

function settle():void
{
    var names:Array = ["hidden", "hidden-strip", "visible", "visible-strip", "scrollv", "scroll-strip"];
    var count:int = 6;
    var lines:String = "";
    var missing:int = 0;
    var i:int;
    for (i = 0; i < count; i++)
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

function steady():void
{
    var problems:String = "";

    // ---- 1. the clip is on the PARENT, and it is the border box -------------
    // (0,0,w,h) is the ONLY window `overflow` may install: x/y != 0 would SHIFT
    // the content (that is `scrollRect`'s other half, and `scrollView` owns it),
    // and a padding-box window would shave the node's own background.
    var hid:UiNode = app.findByKey("hidden");
    var vis:UiNode = app.findByKey("visible");
    var scr:UiNode = app.findByKey("scrollv");
    if (hid == null || vis == null || scr == null)
    {
        problems = problems + "a row is missing; ";
    }
    else
    {
        var sr:Rectangle = hid.backing.scrollRect;
        if (sr == null) problems = problems + "hidden has no scrollRect (no clip at all); ";
        else if (sr.x != 0 || sr.y != 0 || sr.width != 120 || sr.height != 28)
            problems = problems + "hidden clip is (" + sr.x + "," + sr.y + "," + sr.width + "," + sr.height
                + "), want (0,0,120,28); ";
        if (vis.backing.scrollRect != null)
            problems = problems + "overflow 'visible' installed a clip; ";
        var ss:Rectangle = scr.backing.scrollRect;
        if (ss == null || ss.width != 120 || ss.height != 28)
            problems = problems + "'scroll' does not clip like 'hidden'; ";

        // The CHILD keeps its own crop: the window belongs to the box, never to the
        // content (a `scrollView`/`image` inside a clipped card must keep working).
        if (hid.children.length != 1) problems = problems + "hidden has " + hid.children.length + " child(ren); ";
        else
        {
            var stripNode:UiNode = hid.children[0];
            if (stripNode.backing.scrollRect != null)
                problems = problems + "the CLIP was put on the child, not on the box; ";
            // 2. a clip is not a resize.
            if (stripNode.absW != 200) problems = problems + "the strip was resized to " + stripNode.absW + "; ";
        }
    }

    // ---- 3. no steady-state churn ----------------------------------------
    // The rectangle is cached in `extra` and rewritten only when an extent moves,
    // so a re-solve that lands on the same numbers must reuse the same object --
    // the scrollRect SETTER stores a copy, and allocating per arrange would dirty
    // every ancestor's auto-bake fingerprint.
    if (hid != null && hid.extra != null)
    {
        var cached:Rectangle = hid.extra["clipLast"] as Rectangle;
        app.invalidate(Dirty.ALL);
        app.reflow();
        var again:Rectangle = hid.extra["clipLast"] as Rectangle;
        if (cached == null) problems = problems + "no cached clip rectangle on the node; ";
        else if (again != cached) problems = problems + "a re-solve allocated a new clip rectangle; ";
    }

    // ---- 4. the pick window is the clip window ---------------------------
    // Clicks go through the RUNTIME's hit test (Stage.dispatchMouse), not straight
    // at a backing -- dispatching at `backing` bypasses the pick and would pass
    // even with no clip at all.
    var hs:UiNode = app.findByKey("hidden-strip");
    var vs:UiNode = app.findByKey("visible-strip");
    if (hs != null) hs.onClick = function():void { clicksHidden = clicksHidden + 1; };
    if (vs != null) vs.onClick = function():void { clicksVisible = clicksVisible + 1; };
    stage.dispatchMouse(130, 30, "click");      // inside the 120 window (16..136)
    stage.dispatchMouse(150, 30, "click");      // 14px past it, still inside the strip's 200
    app.reflow();
    if (clicksHidden != 1)
        problems = problems + "the spilling strip got " + clicksHidden + " click(s); want 1 (inside the window only); ";
    stage.dispatchMouse(150, 70, "click");      // same spill point on the UNCLIPPED control
    app.reflow();
    if (clicksVisible != 1)
        problems = problems + "the unclipped control got " + clicksVisible + " click(s); want 1 (the control point is wrong); ";

    var extraSolves:Number = app.layoutSolves - solveAtSettle;
    var extraFrames:int = app.enterFrameTicks - frame0;
    if (extraFrames < 2) problems = problems + "only " + extraFrames + " frame(s) elapsed; ";
    // One re-solve is expected above (the deliberate invalidate); anything beyond
    // that is a settled tree solving layout on its own.
    if (extraSolves > 1) problems = problems + "a settled tree re-solved layout " + extraSolves + " time(s); ";
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
    fs.writeBytes(ba);
    fs.close();
}
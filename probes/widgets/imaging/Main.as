// probes/widgets/imaging/Main.as -- an image whose pixels arrive ASYNCHRONOUSLY,
// through the runtime's own Loader.
//
// Output prefix MUST equal the directory name (`imaging`).
//
// WHY THIS PROBE EXISTS
// ---------------------
// `image()` used to take a BitmapData and nothing else: "I have a file name" -- the
// common case, and the only one that exercises the loader at all -- meant hand-rolling
// a Loader per call site. The widget now does it (`src`), and this probe pins the four
// things a loader can get wrong and a static image cannot:
//
//   1. THE INTRINSIC SIZE IS UNKNOWN UNTIL COMPLETE. `auto` is created with NO src and
//      NO size, so it measures as the 64x64 placeholder on the first frame (asserted
//      here, before any load exists); `st.src` is then set and the picture arrives. If
//      COMPLETE does not RE-MEASURE, the node keeps the placeholder box forever -- the
//      failure that makes every async image look broken while its properties are right.
//      Setting the src LATE is what makes this phase real: a src present from the first
//      describe is submitted during the first layout, and the runtime's own job then
//      lands before that first measure clears -- which hides exactly the bug above.
//   2. FITTING HAPPENS AFTER THE PIXELS. `pic` stretches a 16x16 into 60x20, `fit`
//      contains it into 80x20 (20x20, centred) -- sampled in the .bmp, so a widget that
//      painted before the load would show the placeholder box instead.
//   3. A FAILED LOAD IS NOT SILENT. `bad` names a file that does not exist: AIR reports
//      IOError 2035 on the LoaderInfo, and the widget forwards the message to `onError`
//      and to `UiNode.loadError`. No invented error chrome is painted.
//   4. THE COMPLETION CALLBACKS KEEP THEIR ARITY: `onLoad()` takes nothing,
//      `onError(msg)` takes one (tools/callback-arity.cjs grades the declaration side;
//      this probe EXECUTES them, which is the side that throws #1063).
//   5. "cover" IS A CROP, NOT AN OVERFLOW. A 16x16 into a 20x60 box must scale by
//      max(20/16, 60/16) = 3.75 on BOTH axes (60x60, aspect kept) and then show only
//      the middle 20px column of that 60px picture -- written as a scrollRect window
//      of exactly the content box, offset to (60-20)/2 = 20. Both halves are asserted:
//      the WINDOW (a number arithmetic can produce) and the PIXELS (the picture really
//      is cropped: with "fit" the same box would leave white above and below a 20x20
//      image). Then the mode is flipped to "fit" on the live node and the window must
//      be GONE, or the next mode is clipped to a box it never asked for.
//
// THE FIXTURE is `fixture.png`, written by a 20-line script (this runtime has no PNG
// encoder): 16x16, left half pure red, right half pure blue. Two colours, no gradients,
// so "did the pixels land, and where" is a single pixel read.
import asaot.ui.*;
import asaot.ui.style.*;
import flash.display.Bitmap;
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
var H:int = 320;
var OUT:String = 'imaging';

var checks:int = 0;
var failures:String = "";

// What the callbacks actually delivered. `loaded` counts onLoad; `err` is onError's one
// argument; `src` starts null so the auto-sized image can arrive LATE (see above).
var st:Object = { loaded: 0, err: null, polls: 0, src: null, cover: "cover" };

class ImagingProbe extends View
{
    private static const ROOT:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", padding: 10, gap: 8, size: [320, 320],
        background: 0xFFFFFF
    });
    // 60x20 for a 16x16 picture, so "stretch" and "fit" cannot both fill the box: 3.75x
    // horizontally is not 1.25x vertically.
    private static const PIC:StyleRefinement = StyleRefinement.from({ size: [60, 20] });
    private static const FIT:StyleRefinement = StyleRefinement.from({ size: [80, 20] });
    private static const BAD:StyleRefinement = StyleRefinement.from({ size: [40, 40] });
    // 24x48 against a 16x16 picture: cover scales by max(24/16, 48/16) = 3 on BOTH axes
    // (48x48, aspect kept) and the visible column is source x 4..12, so the fixture's
    // red/blue seam (source x=8) lands at box x=12. All integers -- 4/8/16 pop out of
    // the arithmetic instead of out of the program.
    private static const COVER:StyleRefinement = StyleRefinement.from({ size: [24, 48] });

    public function ImagingProbe():void { super(); }

    override public function render():Node
    {
        return column({ key: "root", style: ROOT, ariaName: "imaging probe" }, [
            image({
                key: "pic", src: "fixture.png", scaleMode: "stretch", style: PIC,
                onLoad: function ():void { st.loaded = st.loaded + 1; },
                onError: function (msg:String):void { st.err = "pic: " + msg; }
            }),
            image({
                key: "fit", src: "fixture.png", scaleMode: "fit", style: FIT,
                onLoad: function ():void { st.loaded = st.loaded + 1; },
                onError: function (msg:String):void { st.err = "fit: " + msg; }
            }),
            image({
                key: "bad", src: "no-such-file.png", style: BAD,
                onLoad: function ():void { st.loaded = st.loaded + 1; },
                onError: function (msg:String):void { st.err = msg; }
            }),
            // NO `size` and, at first, no `src` either: the intrinsic size is whatever
            // the load brings back, and that load starts only in phase A.
            image({
                key: "auto", src: st.src,
                onLoad: function ():void { st.loaded = st.loaded + 1; },
                onError: function (msg:String):void { st.err = "auto: " + msg; }
            }),
            image({
                key: "cov", src: "fixture.png", scaleMode: String(st.cover), style: COVER,
                onLoad: function ():void { st.loaded = st.loaded + 1; },
                onError: function (msg:String):void { st.err = "cov: " + msg; }
            })
        ]);
    }
}

var view:ImagingProbe = new ImagingProbe();
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

// DECLARED BEFORE showWindow: a file-scope initializer is emitted in SOURCE ORDER
// between the top-level statements, and showWindow blocks for the life of the window.
setTimeout(poll, 300);
stage.showWindow(W, H, "probe imaging");

// ---- phase A: the three loads that started with the first layout ----------
// Polling, not a fixed sleep: a load is a background job whose latency is the disk's.
// 300 ms x 40 is the ceiling; the poll exits the moment the picture is complete.
function poll():void
{
    st.polls = st.polls + 1;
    var bad:UiNode = app.findByKey("bad");
    // Ready = two successes (pic, fit) AND the failure reported. Deliberately NOT
    // "bad.loadError is set": that is one of the assertions, and a poll keyed on it
    // would turn a missing loadError into a 12-second wait instead of a named failure.
    var ready:Boolean = st.loaded >= 2 && st.err != null && bad != null;
    if (!ready && st.polls < 40)
    {
        setTimeout(poll, 300);
        return;
    }
    phaseReady();
}

function phaseReady():void
{
    stageMark("loads settled after " + st.polls + " poll(s)");
    expect(st.loaded == 3, "expected 3 successful loads before phase B, got " + st.loaded);

    // ---- 3: the failure path speaks -----------------------------------
    expect(st.err != null, "onError never ran for a missing file");
    expect(st.err != null && st.err.indexOf("2035") >= 0,
        "the IOError text does not carry AIR's number 2035: " + st.err);
    expect(st.err != null && st.err.indexOf("URL Not Found") >= 0,
        "the IOError text does not carry AIR's sentence: " + st.err);
    var bad:UiNode = app.findByKey("bad");
    expect(bad.loadError != null && bad.loadError.indexOf("2035") >= 0,
        "UiNode.loadError did not receive the message: " + (bad == null ? "MISSING NODE" : bad.loadError));
    // The healthy images must NOT carry an error, or `loadError` is not per-node.
    expect(app.findByKey("pic").loadError == null, "a successful image is marked as failed");

    // ---- 1a: the placeholder is what an image with no pixels measures as
    expect(rectOf(app.findByKey("auto")) == "10,114,64,64",
        "an image with no src is " + rectOf(app.findByKey("auto")) + ", not the 64x64 placeholder");

    expect(rectOf(app.findByKey("pic")) == "10,10,60,20", "pic rect " + rectOf(app.findByKey("pic")));
    expect(rectOf(app.findByKey("fit")) == "10,38,80,20", "fit rect " + rectOf(app.findByKey("fit")));
    expect(rectOf(app.findByKey("bad")) == "10,66,40,40", "bad rect " + rectOf(app.findByKey("bad")));
    expect(rectOf(app.findByKey("cov")) == "10,186,24,48", "cov rect " + rectOf(app.findByKey("cov")));

    // ---- 1b: now let the picture arrive, on a node that is already laid out
    stageMark("phase B: src appears late");
    st.src = "fixture.png";
    app.invalidate(Dirty.STRUCTURE);
    app.reflow();
    st.polls = 0;
    setTimeout(pollAuto, 300);
}

function pollAuto():void
{
    st.polls = st.polls + 1;
    if (st.loaded < 4 && st.polls < 40)
    {
        setTimeout(pollAuto, 300);
        return;
    }
    expect(st.loaded == 4, "the late src never loaded (" + st.loaded + " successes)");
    // The one that can only be right if COMPLETE re-measured.
    expect(rectOf(app.findByKey("auto")) == "10,114,16,16",
        "auto (no size) is " + rectOf(app.findByKey("auto")) + ", not the loaded 16x16");
    writeText(OUT + ".rects.txt",
        "pic " + rectOf(app.findByKey("pic")) + "\n"
        + "fit " + rectOf(app.findByKey("fit")) + "\n"
        + "bad " + rectOf(app.findByKey("bad")) + "\n"
        + "auto " + rectOf(app.findByKey("auto")) + "\n"
        + "cov " + rectOf(app.findByKey("cov")) + "\n");
    // One more frame so the re-measure reaches the display list before it is read.
    setTimeout(capture, 250);
}

function capture():void
{
    stageMark("capture");
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    writeBmp(OUT + ".bmp", bd);
    // ---- 2: the pixels landed where the fitted rect says --------------
    expect(pixelIs(bd, 20, 20, 255, 0, 0), "pic's left half is not red: " + pixelText(bd, 20, 20));
    expect(pixelIs(bd, 50, 20, 0, 0, 255), "pic's right half is not blue: " + pixelText(bd, 50, 20));
    // fit: 16x16 contained in 80x20 -> 20x20 centred, so x 30..50. Outside it the box is
    // EMPTY and the root's white shows through -- a stretched "fit" would paint there.
    expect(pixelIs(bd, 15, 48, 255, 255, 255), "fit painted outside the contained image: " + pixelText(bd, 15, 48));
    expect(pixelIs(bd, 45, 48, 255, 0, 0), "fit's left half is not red: " + pixelText(bd, 45, 48));
    expect(pixelIs(bd, 55, 48, 0, 0, 255), "fit's right half is not blue: " + pixelText(bd, 55, 48));
    // The failed image draws nothing: no invented error chrome.
    expect(pixelIs(bd, 30, 85, 255, 255, 255), "the failed image painted something: " + pixelText(bd, 30, 85));
    // auto: 16x16 at 10,114, red left / blue right, 1:1 (no scale mode given).
    expect(pixelIs(bd, 12, 120, 255, 0, 0), "auto's left half is not red: " + pixelText(bd, 12, 120));
    expect(pixelIs(bd, 24, 120, 0, 0, 255), "auto's right half is not blue: " + pixelText(bd, 24, 120));
    // ---- 5: cover crops instead of overflowing --------------------------
    coverChecks(bd);
    setTimeout(coverExit, 250);
}

function coverChecks(bd:BitmapData):void
{
    var cov:UiNode = app.findByKey("cov");
    if (cov == null) { expect(false, "cov missing"); return; }
    var bm:Bitmap = Bitmap(cov.extra["bmp"]);
    if (bm == null || bm.bitmapData == null) { expect(false, "cov has no bitmap"); return; }
    // Uniform scale, aspect kept: 48x48 for a 24x48 box (a stretch would be 24x48).
    expect(bm.width == 48 && bm.height == 48,
        "cover did not scale uniformly: " + bm.width + "x" + bm.height + ", not 48x48");
    // The window, in the bitmap's OWN units (3x scale -> 16 units across): the 24px box
    // is 8 source units wide, centred on the 16-unit picture, so x=4 and y=0.
    var sr:Rectangle = bm.scrollRect;
    expect(sr != null, "cover set no scrollRect -- the overflow is not clipped");
    expect(sr != null && sr.x == 4 && sr.y == 0 && sr.width == 8 && sr.height == 16,
        "cover window is " + (sr == null ? "null" : sr.x + "," + sr.y + "," + sr.width + "," + sr.height)
            + ", not 4,0,8,16");
    expect(bm.x == 0 && bm.y == 0, "cover moved the bitmap to " + bm.x + "," + bm.y + ", not 0,0");
    // The pixels: the 8-unit window covers source x 4..12, so the fixture's seam (source
    // x=8) sits at box x=12. Left red, right blue, and the TOP of the box is painted --
    // a "fit" into 24x48 would put a 24x24 with 12px of white above it.
    var cx:int = int(cov.absX);
    var cy:int = int(cov.absY);
    expect(pixelIs(bd, cx + 3, cy + 2, 255, 0, 0), "cover's top-left is not red: " + pixelText(bd, cx + 3, cy + 2));
    expect(pixelIs(bd, cx + 20, cy + 24, 0, 0, 255), "cover's right half is not blue: " + pixelText(bd, cx + 20, cy + 24));
    expect(pixelIs(bd, cx + 3, cy + 45, 255, 0, 0), "cover's bottom-left is not red: " + pixelText(bd, cx + 3, cy + 45));
    stageMark("cover: window " + sr.x + "," + sr.y + "," + sr.width + "," + sr.height);
}

// Leaving "cover" must drop the window and letterbox like any other "fit".
function coverExit():void
{
    var cov:UiNode = app.findByKey("cov");
    if (cov == null) { finish(); return; }
    // The VIEW is the source of truth: reflow re-runs render(), so poking the node's own
    // ImageNode would be overwritten by the description the view still holds.
    st.cover = "fit";
    app.invalidate(Dirty.STRUCTURE);
    app.reflow();
    setTimeout(function ():void
    {
        var bm:Bitmap = Bitmap(cov.extra["bmp"]);
        expect(bm != null && bm.scrollRect == null,
            "the scrollRect survived a switch to fit -- the next mode is clipped to it");
        expect(bm != null && bm.width == 24 && bm.height == 24,
            "fit after cover is " + (bm == null ? "MISSING" : bm.width + "x" + bm.height) + ", not 24x24");
        var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
        bd.draw(stage);
        var cx:int = int(cov.absX);
        var cy:int = int(cov.absY);
        // A 24x24 centred in the 24x48 box starts 12px down: above it the root's white.
        expect(pixelIs(bd, cx + 3, cy + 2, 255, 255, 255), "fit still fills the top: " + pixelText(bd, cx + 3, cy + 2));
        expect(pixelIs(bd, cx + 3, cy + 24, 255, 0, 0), "fit's left half is not red: " + pixelText(bd, cx + 3, cy + 24));
        expect(pixelIs(bd, cx + 20, cy + 24, 0, 0, 255), "fit's right half is not blue: " + pixelText(bd, cx + 20, cy + 24));
        writeBmp(OUT + ".bmp", bd);
        finish();
    }, 250);
}

function finish():void
{
    writeText(OUT + ".done", failures == "" ? "PASS" : "FAIL " + failures);
}

// ---- helpers --------------------------------------------------------------

function expect(ok:Boolean, msg:String):void
{
    checks = checks + 1;
    if (!ok) failures = failures + msg + "; ";
}

function rectOf(n:UiNode):String
{
    if (n == null) return "MISSING";
    return n.absX + "," + n.absY + "," + n.absW + "," + n.absH;
}

// BitmapData.draw(stage) gives ARGB rows in the same order as the buffer, so read the
// pixel straight out instead of walking the display list for a colour.
function pixelIs(bd:BitmapData, x:int, y:int, r:int, g:int, b:int):Boolean
{
    var px:ByteArray = bd.getPixels(new Rectangle(x, y, 1, 1));
    var a:int = px[0];
    return px[1] == r && px[2] == g && px[3] == b && a == 255;
}

function pixelText(bd:BitmapData, x:int, y:int):String
{
    var px:ByteArray = bd.getPixels(new Rectangle(x, y, 1, 1));
    return "#" + hex2(px[1]) + hex2(px[2]) + hex2(px[3]) + " a=" + px[0];
}

function hex2(v:int):String
{
    var s:String = v.toString(16);
    return s.length < 2 ? "0" + s : s;
}

// The stage survives in `<name>.step`, never in `.done`: tools/probe.cjs only prints the
// breadcrumb when the verdict never arrived.
function stageMark(label:String):void
{
    writeText(OUT + ".step", label + "\n");
}

function writeText(path:String, t:String):void
{
    var f:File = File.applicationDirectory.resolvePath(path);
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
    var f:File = File.applicationDirectory.resolvePath(path);
    var fs:FileStream = new FileStream();
    fs.open(f, FileMode.WRITE);
    fs.writeBytes(ba, 0, 0);
    fs.close();
}
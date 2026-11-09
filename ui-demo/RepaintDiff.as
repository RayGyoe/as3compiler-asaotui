// ui-demo/RepaintDiff.as -- the INCREMENTAL vs FULL repaint differential gate.
//
// THE FAILURE THIS EXISTS FOR
// ---------------------------
// `UiApp.reflow` paints in two different ways:
//   * `paintAll`    -- a full sweep, taken whenever layout ran (UiApp.as:1251);
//   * `paintDirty`  -- only nodes whose M_PAINT bit is set, taken on a
//                      decoration-only frame (UiApp.as:1263).
// The second one is the common animation/hover frame, and it is where a change
// can go missing: `UiApp.as` records a real incident where "the M_PAINT bits
// were never consumed, and the change silently never reached the screen".
//
// `tools/gates.cjs` has redraw MUTATIONS (deliberately break the scheduler, see
// the gate go red). A mutation only proves that the breakage we THOUGHT of is
// caught. This gate asserts the thing itself: after a decoration-only change, the
// incremental picture must equal the picture a from-scratch full repaint produces
// for the SAME state. Nothing about internals -- the picture is the oracle.
//
// THE THREE ASSERTIONS PER SCENARIO (and why one is not enough)
// ------------------------------------------------------------
//   (a) the change really took the INCREMENTAL path (`layoutSolves` did not move),
//   (b) the change really CHANGED pixels (pre-change picture differs from
//       post-change picture) -- without this the test is vacuously green,
//   (c) incremental picture == full-repaint picture             <- the gate.
// (a) alone would pass on an incremental path that does nothing; (c) alone would
// pass on a change that never happened. Both controls are the reason this file is
// longer than the assertion it makes.
//
// (b) IS A CONTROL ON THE SCENARIO, NOT ON THE SCHEDULER -- measured, not assumed.
// It compares the pre-change picture with the FULL repaint of the post-change
// state, so it fails only when the change produces no pixels at all (two identical
// colours), which is the way a differential test goes quietly green. It does NOT
// catch a dropped dirty bit: with `opacity` removed from `Style.diffFlags`, the
// change is still perfectly paintable, so (b) passes and it is (c) that fires. That
// separation is the point -- (b) says "this change is visible somewhere", (c) says
// "the incremental frame actually put it on screen".
//
// (d) A fourth check rides along because it is free: after the paint-only reflow,
// no node may still carry M_PAINT. That is exactly the state the UiApp comment
// describes -- a request raised and never consumed -- and it is invisible in the
// picture (the node just does not repaint).
//
// WHAT THIS IS NOT: it is not a screenshot test of the design. Every scene below
// is two flat colours, an opacity and a corner radius, chosen for one property:
// each is PAINT-ONLY, so the frame under test cannot accidentally become a layout
// frame (assertion (a) would then be the only witness, and it would fail loudly).
//
// RUN: node ui-demo/run-repaint-diff.cjs   (builds, runs, reads repaint-diff.done)
import asaot.ui.*;
import asaot.ui.style.*;
import flash.display.BitmapData;
import flash.display.Stage;
import flash.filesystem.File;
import flash.filesystem.FileMode;
import flash.filesystem.FileStream;
import flash.geom.Rectangle;
import flash.utils.ByteArray;
import flash.utils.setTimeout;

// ------------------------------------------------------------------ canvas
var W:int = 360;
var H:int = 260;

// ------------------------------------------------------------------ the scene
// Four variants, each changing ONE family of paint-only properties. The families
// are the ones `Style.diffFlags` classifies as `4 = decor` (paint only):
//   background, borderColor, cornerRadii, opacity      (style/Style.as:288-295)
// A `text` change is deliberately ABSENT: `diffFlags` returns `2 | 4` for it
// ("may need measure for auto-sizing controls"), so that frame legitimately
// re-solves layout and would make the incremental assertion vacuous.
//   variant 1: the page background (root node)
//   variant 2: the card's background AND border colour (two properties, one node)
//   variant 3: opacity of a sibling box
//   variant 4: corner radius of the card
// The baseline (`variant 0`) is shared, so every scenario is "0 -> k".
class DiffView extends View
{
    public var variant:int = 0;

    override public function render():Node
    {
        var v:int = this.variant;
        var pageBg:uint = (v == 1) ? 0x1E2430 : 0xF2F4F8;
        var cardBg:uint = (v == 2) ? 0x2E6FDB : 0xFFFFFF;
        var cardEdge:uint = (v == 2) ? 0xE0603C : 0xC9D2E0;
        var titleCol:uint = 0x223044;
        var ghostAlpha:Number = (v == 3) ? 0.35 : 1.0;
        var radius:Number = (v == 4) ? 18 : 6;

        return column({
            key: "root", size: [W, H], padding: 20, gap: 12, background: pageBg
        }, [
            box({
                key: "card", size: [320, 90], padding: 14,
                background: cardBg, border: 1, borderColor: cardEdge,
                cornerRadii: radius
            }, [
                label("incremental vs full repaint", {
                    key: "title", text: { color: titleCol, fontSize: 16 }
                })
            ]),
            box({ key: "ghost", size: [320, 60], background: 0x2FA84F, opacity: ghostAlpha })
        ]);
    }
}

// ------------------------------------------------------------------ harness
var checks:int = 0;
var fails:int = 0;
var log:String = "";

function note(msg:String):void
{
    trace(msg);
    log = log + msg + "\n";
}

function check(name:String, ok:Boolean, detail:String):void
{
    checks = checks + 1;
    if (ok) note("  OK   " + name);
    else { fails = fails + 1; note("  FAIL " + name + "  (" + detail + ")"); }
}

// Read the window's pixels back. `BitmapData.draw(stage)` rasterizes the CURRENT
// display list, so this is the state of the screen the scheduler produced -- not
// a fresh render of the description tree. That distinction is the whole gate:
// drawing a fresh tree would pass even when the retained display list is stale.
function pixels():ByteArray
{
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    return bd.getPixels(new Rectangle(0, 0, W, H));
}

// Byte-for-byte comparison, reporting the first differing PIXEL (x,y) rather than
// a byte offset -- a byte index is unreadable in a failure message.
function diffDetail(a:ByteArray, b:ByteArray):String
{
    if (a.length != b.length) return "buffer sizes differ " + a.length + " vs " + b.length;
    var n:int = a.length;
    a.position = 0;
    b.position = 0;
    var count:int = 0;
    var first:int = -1;
    for (var i:int = 0; i < n; i++)
    {
        if (a.readUnsignedByte() != b.readUnsignedByte())
        {
            count = count + 1;
            if (first < 0) first = i;
        }
    }
    if (count == 0) return "";
    var px:int = (first / 4) % W;
    var py:int = (first / 4) / W;
    return count + " of " + n + " bytes differ, first at (" + px + "," + py + ")";
}

// Any node still holding M_PAINT after a reflow raised a paint request that the
// pass never served. Walked from the public root; no internal access needed.
function leftoverPaint(n:UiNode):int
{
    var bad:int = ((n.dirty & Dirty.M_PAINT) != 0) ? 1 : 0;
    var kids:Vector.<UiNode> = n.children;
    for (var i:int = 0; i < kids.length; i++) bad = bad + leftoverPaint(kids[i]);
    return bad;
}

// The white-box lever: layout dirty on the ROOT makes the next reflow take the
// `layoutRan` branch, i.e. `paintAll`. It is public API (getRoot/dirty/reflow/
// markLayoutDirty), which is why this gate needs no test hook inside the kit.
function forceFullRepaint():void
{
    var r:UiNode = app.getRoot();
    r.dirty = r.dirty | Dirty.M_MEASURE | Dirty.M_ARRANGE;
    r.markLayoutDirty();
    app.reflow();
}

// BMP evidence, same encoding as layout-check/VisualDemo.as (32bpp BI_RGB,
// bottom-up) so tools/bmpdiff.cjs reads it unchanged.
function writeBmp(px:ByteArray, name:String):void
{
    var imgSize:int = W * H * 4;
    var ba:ByteArray = new ByteArray();
    ba.writeByte(0x42); ba.writeByte(0x4D);
    ba.writeByte((54 + imgSize) & 255); ba.writeByte(((54 + imgSize) >> 8) & 255);
    ba.writeByte(((54 + imgSize) >> 16) & 255); ba.writeByte(((54 + imgSize) >> 24) & 255);
    ba.writeByte(0); ba.writeByte(0); ba.writeByte(0); ba.writeByte(0);
    ba.writeByte(54); ba.writeByte(0); ba.writeByte(0); ba.writeByte(0);
    ba.writeByte(40); ba.writeByte(0); ba.writeByte(0); ba.writeByte(0);
    ba.writeByte(W & 255); ba.writeByte((W >> 8) & 255); ba.writeByte(0); ba.writeByte(0);
    ba.writeByte(H & 255); ba.writeByte((H >> 8) & 255); ba.writeByte(0); ba.writeByte(0);
    ba.writeByte(1); ba.writeByte(0);
    ba.writeByte(32); ba.writeByte(0);
    ba.writeByte(0); ba.writeByte(0); ba.writeByte(0); ba.writeByte(0);
    ba.writeByte(imgSize & 255); ba.writeByte((imgSize >> 8) & 255);
    ba.writeByte((imgSize >> 16) & 255); ba.writeByte((imgSize >> 24) & 255);
    for (var pad:int = 0; pad < 16; pad = pad + 1) ba.writeByte(0);
    var y:int;
    var x:int;
    for (y = H - 1; y >= 0; y--)
    {
        for (x = 0; x < W; x++)
        {
            var i:int = (y * W + x) * 4;
            ba.writeByte(px[i + 3]);
            ba.writeByte(px[i + 2]);
            ba.writeByte(px[i + 1]);
            ba.writeByte(px[i]);
        }
    }
    var f:File = File.applicationDirectory.resolvePath(name);
    var fs:FileStream = new FileStream();
    fs.open(f, FileMode.WRITE);
    fs.writeBytes(ba, 0, 0);
    fs.close();
}

// ------------------------------------------------------------------ the gate
var view:DiffView = new DiffView();
var stage:Stage = new Stage();
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

// A "decoration changed" frame, spelled the way an author does: mark the app
// dirty with a decoration bit, then reflow. `Dirty.DECOR` is chosen over
// `Dirty.ALL` on purpose -- ALL would also re-solve layout and turn the frame
// under test into a `paintAll` frame, i.e. it would test nothing.
function incrementalFrame(k:int):void
{
    view.variant = k;
    app.invalidate(Dirty.DECOR);
    app.reflow();
}

// A control frame: re-describe + reflow with NOTHING changed. If this re-solves
// layout, the harness itself is forcing a solve (a window-size settle, say) and
// the per-scenario assertion would be measuring that instead of the property.
// Ran once, up front, and reported -- never folded into the verdict (it is a
// property of the environment, not of the toolkit).
view.variant = 0;
forceFullRepaint();
var ctlSolves:int = app.layoutSolves;
app.invalidate(Dirty.DECOR);
app.reflow();
note("control: a no-change decor reflow moved layoutSolves by "
    + (app.layoutSolves - ctlSolves) + " (must be 0)");

var scenarios:Array = [1, 2, 3, 4];
var si:int;
for (si = 0; si < scenarios.length; si++)
{
    var k:int = int(scenarios[si]);
    note("scenario " + k);

    // Baseline: variant 0, painted the slow but unquestionable way.
    view.variant = 0;
    forceFullRepaint();
    var before:ByteArray = pixels();

    var solves0:int = app.layoutSolves;
    var paints0:int = app.paintPasses;
    var measures0:int = app.measurePasses;

    incrementalFrame(k);

    // (a) the frame under test must be an INCREMENTAL frame. If layout moved,
    //     `paintAll` ran and (c) would be trivially true -- the gate would be
    //     measuring nothing.
    check("scenario " + k + ": the change re-solved no layout (incremental path)",
        app.layoutSolves == solves0,
        "layoutSolves " + solves0 + " -> " + app.layoutSolves
        + ", measurePasses " + measures0 + " -> " + app.measurePasses);
    check("scenario " + k + ": a paint pass ran",
        app.paintPasses > paints0, "paintPasses " + paints0 + " -> " + app.paintPasses);

    // (d) no paint request may be left unconsumed.
    var left:int = leftoverPaint(app.getRoot());
    check("scenario " + k + ": every M_PAINT bit was consumed", left == 0,
        left + " node(s) still carry M_PAINT");
    if (app.getOverlayRoot() != null)
    {
        var leftOverlay:int = leftoverPaint(app.getOverlayRoot());
        check("scenario " + k + ": overlay consumed every M_PAINT bit", leftOverlay == 0,
            leftOverlay + " node(s) still carry M_PAINT");
    }

    var incPix:ByteArray = pixels();

    // (c) THE GATE: the same state, repainted from scratch, must land on the same
    //     pixels. `diffDetail` returns "" only on a byte-identical buffer.
    forceFullRepaint();
    var fullPix:ByteArray = pixels();
    var bad:String = diffDetail(incPix, fullPix);
    check("scenario " + k + ": incremental picture == full repaint", bad == "", bad);

    // (b) sensitivity: the change must actually be visible. Compare the FULL
    //     repaint against the pre-change baseline so a slow or missing paint on
    //     the incremental side cannot make this control pass by accident.
    var moved:String = diffDetail(before, fullPix);
    check("scenario " + k + ": the change is visible (control)", moved != "",
        "no pixel changed -- the scenario is vacuous");

    writeBmp(incPix, "repaint-inc-" + k + ".bmp");
    writeBmp(fullPix, "repaint-full-" + k + ".bmp");
}

// ------------------------------------------------------------- the verdict
var verdict:String = (fails == 0 ? "PASS " : "FAIL ") + (checks - fails) + "/" + checks;
note("REPAINT-DIFF: " + verdict);

var done:File = File.applicationDirectory.resolvePath("repaint-diff.done");
var dfs:FileStream = new FileStream();
dfs.open(done, FileMode.WRITE);
dfs.writeUTFBytes(log);
dfs.close();

// The window stays open (showWindow blocks) so a failure can be looked at; the
// driver closes it after reading the .done file. Throwing here is for the
// hand-run case (`--run`), where the exit code is the only signal left.
setTimeout(function ():void { }, 60000);
stage.showWindow(W, H, "asaot.ui -- incremental vs full repaint");

if (fails > 0) throw new Error("RepaintDiff FAILED: " + verdict);

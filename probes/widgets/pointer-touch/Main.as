// probes/widgets/pointer-touch/Main.as -- a TOUCH series drives the existing kinds,
// with no widget changed and no engine input at all.
//
// Output prefix MUST equal the directory name (`pointer-touch`).
//
// WHY THIS PROBE EXISTS
// ---------------------
// MOBILE.md M0 says the library gets a pointer abstraction plus a synthetic-mouse
// compatibility layer. Both halves are only worth having if a touch series makes a
// chip click, a switch react and a press inside a scroller wait -- and all three are
// claims that can be checked without a touch backend, by synthesizing the TouchEvent
// series a platform would send (G5 keeps the real input out of scope: the window
// backend dispatches none).
//
// WHAT IS AND IS NOT COVERED
//   * COVERED: the router's decisions (immediate vs delayed press, slop cancel,
//     tap -> click), the compat layer (synthetic MouseEvents reach UiNode.handleClick),
//     hover arbitration (hasHover=false means no hover), and the pick the router uses.
//   * NOT COVERED, ON PURPOSE: real platform touch, pressure, multi-touch gestures and
//     anything the engine does on its own mouse-down (TextField focus, ASC_mouse_down
//     bookkeeping). Those are G5 / MOBILE.md P3 and are not asserted here.
//
// THE PICK IS CHECKED AGAINST THE ENGINE, not against itself: phase 1 moves the REAL
// engine pointer to several points and asserts that `UiApp.pickAt` names the same node
// the engine's hover derivation lands on. Without that, `pickAt` would be a second
// definition of "under the finger" and could drift from the click's rule unnoticed.
import asaot.ui.*;
import asaot.ui.style.*;
import flash.display.BitmapData;
import flash.display.DisplayObject;
import flash.display.Stage;
import flash.display.StageAlign;
import flash.display.StageScaleMode;
import flash.events.TouchEvent;
import flash.filesystem.File;
import flash.filesystem.FileMode;
import flash.filesystem.FileStream;
import flash.geom.Rectangle;
import flash.utils.ByteArray;
import flash.utils.setTimeout;

var W:int = 320;
var H:int = 240;
var OUT:String = 'pointer-touch';

var checks:int = 0;
var failures:String = "";

// The model. Counters, not state: every assertion below is about how many times the
// library called back, which is exactly what a touch that "half works" gets wrong.
var st:Object = { chipClicks: 0, btnClicks: 0, rowClicks: 0, swChanges: 0 };

// The router's press counter when the scroller phase started: asserted as "exactly one
// more press after the delay", which is the difference between a delayed press and a
// second delivery of the same one.
var scrollerPressBase:int = 0;

class TouchProbe extends View
{
    private static const ROOT:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", padding: 10, gap: 8, size: [320, 240],
        background: 0xFFFFFF, text: { fontSize: 12, color: 0x111827 }
    });
    private static const CHIP:StyleRefinement = StyleRefinement.from({ size: [120, 32], background: 0xEEEEEE });
    private static const BTN:StyleRefinement = StyleRefinement.from({ size: [120, 32], background: 0x2563EB });
    private static const SW:StyleRefinement = StyleRefinement.from({ size: [80, 32], background: 0xDDDDDD });
    private static const SV:StyleRefinement = StyleRefinement.from({ size: [200, 60], background: 0xF5F5F5 });
    private static const ROW:StyleRefinement = StyleRefinement.from({ size: [200, 60], background: 0xCCCCCC });

    public function TouchProbe():void { super(); }

    override public function render():Node
    {
        return column({ key: "root", style: ROOT }, [
            chip("Tag", {
                key: "chip", style: CHIP,
                onClick: function ():void { st.chipClicks = st.chipClicks + 1; }
            }),
            button({
                key: "btn", label: "Go", style: BTN,
                onClick: function ():void { st.btnClicks = st.btnClicks + 1; }
            }),
            toggle("On", {
                key: "sw", style: SW,
                onChange: function (v:Boolean):void { st.swChanges = st.swChanges + 1; }
            }),
            scrollView({ key: "scroll", style: SV }, [
                // A BUTTON, not a box: `box`/`chip` answer wantsPress()==false (they paint
                // no pressed state), so a press assertion on them would measure the
                // widget's decoration policy instead of the router's delay.
                button({
                    key: "row", label: "Row", style: ROW,
                    onClick: function ():void { st.rowClicks = st.rowClicks + 1; }
                })
            ])
        ]);
    }
}

var view:TouchProbe = new TouchProbe();
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

// Declared before showWindow: a file-scope initializer is emitted in source order, and
// showWindow blocks for the life of the window.
setTimeout(settle, 900);
stage.showWindow(W, H, "probe pointer-touch");

function settle():void
{
    writeText(OUT + ".rects.txt",
        "root " + rectOf(app.findByKey("root")) + "\n"
        + "chip " + rectOf(app.findByKey("chip")) + "\n"
        + "btn " + rectOf(app.findByKey("btn")) + "\n"
        + "sw " + rectOf(app.findByKey("sw")) + "\n"
        + "scroll " + rectOf(app.findByKey("scroll")) + "\n"
        + "row " + rectOf(app.findByKey("row")) + "\n");
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    writeBmp(OUT + ".bmp", bd);
    setTimeout(phasePick, 250);
}

// ---- phase 1: does the router's pick agree with the ENGINE's? ---------------
//
// A real engine pointer move at (x,y) makes UiApp derive hover from the engine's own
// hit target. `pickAt(x,y)` must name the same node -- otherwise touch routing has
// quietly invented a second rule for "under the finger".
function phasePick():void
{
    stageMark("pick vs engine");
    var pts:Array = [[70, 26], [70, 66], [60, 150], [5, 5]];
    var i:int = 0;
    while (i < pts.length)
    {
        var p:Array = pts[i];
        var x:Number = Number(p[0]);
        var y:Number = Number(p[1]);
        try
        {
            stage.dispatchMouse(x, y, "mouseMove");
        }
        catch (err:Error)
        {
            failures = failures + "mouseMove at (" + x + "," + y + ") threw " + err.name + ": " + err.message + "; ";
        }
        var engineNode:UiNode = app.getHover();
        var pickNode:UiNode = app.pickAt(x, y);
        expect(engineNode == pickNode,
            "pick at (" + x + "," + y + ") is " + nameOf(pickNode) + " but the engine hovers " + nameOf(engineNode));
        i = i + 1;
    }
    // Sanity: the three control centres must not all be null (an empty pick would pass
    // the equality test above trivially).
    expect(app.pickAt(70, 26) != null, "the pick over the chip is null");
    expect(app.pickAt(60, 150) != null, "the pick over the scroll content is null");
    setTimeout(phaseTap, 250);
}

// ---- phase 2: a tap on a chip is a press + a click -------------------------
function phaseTap():void
{
    stageMark("tap chip");
    // A touch-first device: from here on there is no hover at all.
    app.setHasHover(false);
    expect(app.getHover() == null, "hasHover=false did not clear the hover chain");

    var before:int = st.btnClicks;
    var p:UiNode = app.findByKey("btn");
    touchAt(TouchEvent.TOUCH_BEGIN, 1, 70, 66);
    // Outside a scroller the press is IMMEDIATE: a button that waits 130ms feels dead.
    expect(p.state.pressed == 1, "the button is not pressed on touch-down");
    expect(app.router.pressCounts == 1, "the router did not report one press (" + app.router.pressCounts + ")");
    expect(app.router.delayedCounts == 0, "a press outside a scroller was delayed");
    expect(app.getHover() == null, "a touch produced hover on a hasHover=false window");

    touchAt(TouchEvent.TOUCH_END, 1, 70, 66);
    expect(p.state.pressed == 0, "the button stayed pressed after the touch ended");
    expect(st.btnClicks == before + 1, "the tap did not click the button (" + st.btnClicks + ")");
    expect(app.router.taps == 1, "the router did not report one tap");
    expect(app.router.lastTapNode == p, "the router's last tap was not the button");
    setTimeout(phaseSlop, 250);
}

// ---- phase 3: a finger that travels is a drag, not a tap ------------------
function phaseSlop():void
{
    stageMark("slop cancels");
    var before:int = st.btnClicks;
    var p:UiNode = app.findByKey("btn");
    touchAt(TouchEvent.TOUCH_BEGIN, 2, 70, 66);
    expect(p.state.pressed == 1, "the button is not pressed before the drag starts");
    touchAt(TouchEvent.TOUCH_MOVE, 2, 90, 66);      // 20pt > PRESS_SLOP_PT (8)
    touchAt(TouchEvent.TOUCH_END, 2, 90, 66);
    expect(st.btnClicks == before, "a dragged touch still clicked the button");
    expect(app.router.taps == 1, "a dragged touch was counted as a tap");
    expect(p.state.pressed == 0, "the button stayed pressed after a dragged touch");
    setTimeout(phaseScroller, 250);
}

// ---- phase 4: inside a scroller the press WAITS, then lands --------------
function phaseScroller():void
{
    stageMark("scroller press delay");
    var p:UiNode = app.findByKey("row");
    var presses:int = app.router.pressCounts;
    scrollerPressBase = presses;
    touchAt(TouchEvent.TOUCH_BEGIN, 3, 60, 150);
    // Same touch, two meanings: it may be the list scrolling, so nothing is pressed yet.
    expect(p.state.pressed == 0, "a press inside a scroller landed immediately");
    expect(app.router.delayedCounts == 1, "the scroller press was not counted as delayed");
    expect(app.router.pressCounts == presses, "the scroller press was delivered before the delay");
    setTimeout(phaseScrollerLate, 220);
}

function phaseScrollerLate():void
{
    stageMark("scroller press landed");
    var p:UiNode = app.findByKey("row");
    var before:int = st.rowClicks;
    expect(p.state.pressed == 1, "the delayed press never landed inside the scroller");
    expect(app.router.pressCounts == scrollerPressBase + 1,
        "the delayed press was not counted as a press (" + app.router.pressCounts + " vs " + (scrollerPressBase + 1) + ")");
    touchAt(TouchEvent.TOUCH_END, 3, 60, 150);
    expect(p.state.pressed == 0, "the row stayed pressed after the touch ended");
    expect(st.rowClicks == before + 1, "a tap inside a scroller did not click the row");
    expect(app.router.taps == 2, "the scroller tap was not counted as a tap");
    setTimeout(phaseCancel, 250);
}

// ---- phase 5: a CANCELLED series leaves no press behind -------------------
//
// The platform can revoke a touch series at any moment (incoming call, a gesture
// takeover). If the router keeps its press slot after that, every later touch is
// silently ignored for the rest of the session -- a failure that looks like "the UI
// froze", not like a pointer bug.
function phaseCancel():void
{
    stageMark("cancel");
    var p:UiNode = app.findByKey("btn");
    var before:int = st.btnClicks;
    touchAt(TouchEvent.TOUCH_BEGIN, 5, 70, 66);
    expect(p.state.pressed == 1, "the button is not pressed before the cancel");
    touchAt(InputConstants.TOUCH_CANCEL, 5, 70, 66);
    expect(app.router.cancelCounts == 1, "the router did not report one cancel");
    expect(p.state.pressed == 0, "a cancelled touch left the button painted pressed");
    expect(st.btnClicks == before, "a cancelled touch still clicked the button");

    // …and the slot is free again: the very next tap must work. A router that never
    // clears `press` on cancel passes everything above and fails exactly here.
    touchAt(TouchEvent.TOUCH_BEGIN, 6, 70, 66);
    expect(p.state.pressed == 1, "a tap after the cancel did not press the button");
    touchAt(TouchEvent.TOUCH_END, 6, 70, 66);
    expect(st.btnClicks == before + 1, "a tap after the cancel did not click");
    setTimeout(phaseHoverBack, 250);
}

// ---- phase 5: hover comes back when the platform says it has one ----------
function phaseHoverBack():void
{
    stageMark("hover back");
    app.setHasHover(true);
    try
    {
        stage.dispatchMouse(70, 66, "mouseMove");
    }
    catch (err:Error)
    {
        failures = failures + "mouseMove threw " + err.name + ": " + err.message + "; ";
    }
    var btn:UiNode = app.findByKey("btn");
    expect(app.getHover() == btn, "the engine pointer did not re-hover the button (" + nameOf(app.getHover()) + ")");
    expect(btn.state.hover == 1, "the button did not get hover state back");

    // A touch move must NOT re-derive hover from the node the router picked: that
    // would make the derived hover agree with itself by construction.
    touchAt(TouchEvent.TOUCH_BEGIN, 4, 70, 26);
    touchAt(TouchEvent.TOUCH_MOVE, 4, 80, 26);
    expect(app.getHover() == btn, "a synthetic touch move replaced the engine's hover (" + nameOf(app.getHover()) + ")");
    touchAt(TouchEvent.TOUCH_END, 4, 80, 26);
    setTimeout(finish, 250);
}

function finish():void
{
    writeText(OUT + ".done", failures == "" ? "PASS" : "FAIL " + failures);
}

// ---- helpers --------------------------------------------------------------

// One synthesized touch event. `localX/localY` are ROOT coordinates here -- the
// convention the router documents, and the only one available while G5 leaves the
// library without a platform that would target the event for us.
function touchAt(type:String, id:int, x:Number, y:Number):void
{
    try
    {
        stage.dispatchEvent(new TouchEvent(type, true, false, id, true, x, y, 1, 1, 0.5));
    }
    catch (err:Error)
    {
        failures = failures + type + " at (" + x + "," + y + ") threw " + err.name + ": " + err.message + "; ";
    }
}

function nameOf(n:UiNode):String
{
    if (n == null) return "<none>";
    var k:String = (n.key == null) ? "" : String(n.key);
    return n.kind + "[" + k + "]";
}

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

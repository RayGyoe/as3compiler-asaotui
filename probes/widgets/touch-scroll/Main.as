// probes/widgets/touch-scroll/Main.as -- a FINGER scrolls a viewport: 1:1 follow,
// axis lock, the press withdrawn without a click, and a coast that obeys wall time.
//
// Output prefix MUST equal the directory name (`touch-scroll`).
//
// WHY THIS PROBE EXISTS
// ---------------------
// MOBILE.md S1/S2 say a viewport follows the finger and keeps going after it lifts.
// Both are checkable without a touch backend (G5: the window backend dispatches no
// TouchEvent) by synthesizing the series a platform would send -- the same technique
// `probes/widgets/pointer-touch` uses for presses, one layer further along.
//
// The assertions are DELIBERATELY split into two kinds:
//   * EXACT geometry (offset after a drag is an integer the arithmetic predicts);
//   * COARSE physics (the coast moved FURTHER, it stayed inside the content, and it
//     stopped). A glide's exact distance is a function of the frame clock, and pinning
//     it would make a green probe depend on how busy the machine was -- the honest
//     claim is "wall time is integrated, the direction and the clamp are right", and
//     the deterministic half of that is the `momentum: false` viewport, which must stop
//     at EXACTLY the release offset.
//
// WHAT IS NOT COVERED, ON PURPOSE: paging/snap (S4), nested-scroller arbitration (S5)
// and anything a real platform does with a real finger (G5). Do not read this probe as
// "mobile scrolling works".
//
// OVERSCROLL (S3) IS COVERED, and the pair of numbers is the whole point: the AUTHOR'S
// offset stays clamped at the end while `overscrollY` (what the clip is drawn at) is
// ~40px past it, and the pixels prove the stretch reached the frame buffer (the bottom
// of the pane shows the pane's OWN background instead of content). Then the release
// must write EXACTLY zero -- M1's acceptance is "回位误差 < 1pt", and an exponential
// decay that is allowed to approach zero would repaint forever.
import asaot.ui.*;
import asaot.ui.style.*;
import flash.display.BitmapData;
import flash.display.Stage;
import flash.display.StageAlign;
import flash.display.StageScaleMode;
import flash.events.TouchEvent;
import flash.filesystem.File;
import flash.filesystem.FileMode;
import flash.filesystem.FileStream;
import flash.geom.Rectangle;
import flash.utils.ByteArray;
import flash.utils.getTimer;
import flash.utils.setTimeout;

var W:int = 320;
var H:int = 240;
var OUT:String = 'touch-scroll';

var checks:int = 0;
var failures:String = "";

// The model. Counters, because "did it click when it should not have" is the failure
// that makes a scrollable list unusable, and a counter cannot flatter itself.
var clicks:int = 0;
var glideAtRelease:Number = 0;
var dragBase:int = 0;

// The author-side offset of the first viewport, i.e. the model a real app keeps. It is
// 0 throughout except that the glide phase SETS it to 0 and re-describes, which is how an
// app scrolls programmatically ("back to top") -- and the whole point of that phase is
// that a request cancels a coast.
var svModelOffset:Number = 0;
var dbg:String = "";

// Case (A) of ScrollViewNode's contract: the model MIRRORS the viewport, and a
// programmatic scroll is a CHANGE in it (0 after the user scrolled to 120). The
// mirror is what makes "re-pass the model every render" harmless -- the description
// equals the last value the author declared, so it is not a new request.
function svScrolled(y:Number):void { svModelOffset = y; }

class ScrollProbe extends View
{
    private static const ROOT:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", padding: 10, gap: 8, size: [320, 240],
        background: 0xFFFFFF, text: { fontSize: 12, color: 0x111827 }
    });
    private static const SV:StyleRefinement = StyleRefinement.from({ size: [200, 60], background: 0xF5F5F5 });
    private static const ROW:StyleRefinement = StyleRefinement.from({ size: [200, 40], background: 0xCCCCCC });
    private static const ROWF:StyleRefinement = StyleRefinement.from({ size: [200, 40], background: 0xDDDDDD });

    public function ScrollProbe():void { super(); }

    override public function render():Node
    {
        return column({ key: "root", style: ROOT }, [
            // Six 40px rows in a 60px viewport: content 240, so the range is 180.
            scrollView({ key: "sv", style: SV, decelerationRate: 0.9, offsetY: svModelOffset,
                         onScroll: svScrolled }, [
                mkRow("s1", ROW), mkRow("s2", ROW), mkRow("s3", ROW),
                mkRow("s4", ROW), mkRow("s5", ROW), mkRow("s6", ROW)
            ]),
            scrollView({ key: "svf", style: SV, momentum: false, overscroll: "none" }, [
                mkRow("f1", ROWF), mkRow("f2", ROWF), mkRow("f3", ROWF),
                mkRow("f4", ROWF), mkRow("f5", ROWF), mkRow("f6", ROWF)
            ])
        ]);
    }
}

function mkRow(key:String, st:StyleRefinement):Node
{
    return button({
        key: key, label: key, style: st,
        onClick: function ():void { clicks = clicks + 1; }
    });
}

var view:ScrollProbe = new ScrollProbe();
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

// Declared before showWindow: a file-scope initializer is emitted in source order, and
// showWindow blocks for the life of the window.
setTimeout(settle, 900);
stage.showWindow(W, H, "probe touch-scroll");

function settle():void
{
    writeText(OUT + ".rects.txt",
        "root " + rectOf(app.findByKey("root")) + "\n"
        + "sv " + rectOf(app.findByKey("sv")) + "\n"
        + "svf " + rectOf(app.findByKey("svf")) + "\n"
        + "s1 " + rectOf(app.findByKey("s1")) + "\n"
        + "f1 " + rectOf(app.findByKey("f1")) + "\n");
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    writeBmp(OUT + ".bmp", bd);
    setTimeout(phaseInit, 250);
}

// ---- phase 1: what the layout says the range is ---------------------------
function phaseInit():void
{
    stageMark("init");
    var sv:ScrollViewNode = ScrollViewNode(app.findByKey("sv").desc);
    var svf:ScrollViewNode = ScrollViewNode(app.findByKey("svf").desc);
    // 6 rows x 40 = 240 of content in a 60px viewport. Hand arithmetic, not a reading
    // of the widget's own output: 240 - 60 = 180.
    expect(sv.contentH == 240, "content height is " + sv.contentH + ", want 240");
    expect(sv.maxOffsetY == 180, "max offset is " + sv.maxOffsetY + ", want 180");
    expect(sv.offsetY == 0, "the viewport did not start at the top (" + sv.offsetY + ")");
    expect(sv.maxOffsetX == 0, "a single-column list reports horizontal range (" + sv.maxOffsetX + ")");
    expect(svf.momentum == false, "the momentum:false viewport kept momentum");
    setTimeout(phaseTap, 150);
}

// ---- phase 2: a tap inside a viewport still clicks the row ---------------
function phaseTap():void
{
    stageMark("tap row");
    var before:int = clicks;
    var p:UiNode = app.findByKey("s1");
    touchAt(TouchEvent.TOUCH_BEGIN, 1, 100, 30);
    // Inside a scroller the press waits (it may become a drag): this is what makes a
    // tap in this probe mean something -- the row is pressed only after the delay.
    expect(p.state.pressed == 0, "the row was pressed before the scroller delay");
    touchAt(TouchEvent.TOUCH_END, 1, 100, 30);
    expect(clicks == before + 1, "a tap inside a viewport did not click the row");
    expect(app.router.taps == 1, "the tap was not counted as a tap (" + app.router.taps + ")");
    setTimeout(phaseDragHold, 250);
}

// ---- phase 3: the press lands, then the finger travels -> a DRAG ---------
function phaseDragHold():void
{
    stageMark("press delay, then drag");
    var p:UiNode = app.findByKey("s1");
    touchAt(TouchEvent.TOUCH_BEGIN, 2, 100, 30);
    setTimeout(phaseDragMove, 170);   // > PRESS_DELAY_MS (130)
}

function phaseDragMove():void
{
    stageMark("drag: slop crossing");
    var p:UiNode = app.findByKey("s1");
    var sv:ScrollViewNode = ScrollViewNode(app.findByKey("sv").desc);
    // The delayed press is a PRECONDITION here, not the subject: this probe asserts that
    // the drag below takes it away again.
    expect(p.state.pressed == 1, "the delayed press never landed (precondition)");
    touchAt(TouchEvent.TOUCH_MOVE, 2, 100, 10);      // 20pt up, past the 8pt slop
    // The press is WITHDRAWN when the viewport takes the series -- a row that stays lit
    // while its list scrolls is the glitch this half exists to prevent.
    expect(p.state.pressed == 0, "the row stayed pressed after the drag took over");
    expect(app.router.dragStarts == 1, "the router did not report a drag start (" + app.router.dragStarts + ")");
    // ... and the 20pt that proved "this is a drag" did NOT also scroll: the anchor is
    // where the slop was crossed.
    expect(sv.offsetY == 0, "the slop motion scrolled the list (" + sv.offsetY + ")");
    setTimeout(phaseDragMove2, 40);
}

function phaseDragMove2():void
{
    stageMark("drag: 1:1");
    var sv:ScrollViewNode = ScrollViewNode(app.findByKey("sv").desc);
    touchAt(TouchEvent.TOUCH_MOVE, 2, 100, -10);     // 20pt further up
    // 20pt of finger = 20px of content, exactly. Not 40 (the slop motion is not scroll),
    // not 19.6 (no smoothing).
    expect(sv.offsetY == 20, "a 20pt drag moved the content to " + sv.offsetY + ", want 20");
    setTimeout(phaseDragEnd, 40);
}

function phaseDragEnd():void
{
    stageMark("release: fling");
    touchAt(TouchEvent.TOUCH_END, 2, 100, -10);
    var sv:ScrollViewNode = ScrollViewNode(app.findByKey("sv").desc);
    expect(app.router.dragEnds == 1, "the router did not report a drag end (" + app.router.dragEnds + ")");
    expect(clicks == 1, "a scrolled list also clicked the row under the finger (" + clicks + ")");
    glideAtRelease = sv.offsetY;
    expect(glideAtRelease == 20, "the release offset is " + glideAtRelease + ", want 20");
    setTimeout(phaseGlide, 250);
}

// ---- phase 4: a coast, and what may stop it ---------------------------
function phaseGlide():void
{
    stageMark("coast");
    var sv:ScrollViewNode = ScrollViewNode(app.findByKey("sv").desc);
    // COARSE on purpose: the distance depends on the frame clock (see the header).
    // What must hold is that wall time was integrated at all, in the right direction
    // and inside the content: faster than 20, no further than the end.
    expect(sv.offsetY > glideAtRelease,
        "the release did not coast (still at " + sv.offsetY + ")");
    expect(sv.offsetY <= 180, "the coast left the content (" + sv.offsetY + " > 180)");
    // A FINGER ON A COASTING LIST STOPS IT -- on every mobile platform, and immediately:
    // not after the 130ms press delay and not after the slop. The glide is still running
    // 250ms after the release (rate 0.95 stops at ~690ms), so this is a mid-flight grab.
    touchAt(TouchEvent.TOUCH_BEGIN, 6, 100, 40);
    glideAtRelease = sv.offsetY;
    setTimeout(phasePressFreeze, 300);
}

function phasePressFreeze():void
{
    stageMark("press freezes the coast");
    var sv:ScrollViewNode = ScrollViewNode(app.findByKey("sv").desc);
    expect(sv.offsetY == glideAtRelease,
        "a finger on a coasting list did not stop it (" + sv.offsetY + " vs " + glideAtRelease + ")");
    // Drop that press: it was a grab, not a tap.
    touchAt(InputConstants.TOUCH_CANCEL, 6, 100, 40);
    expect(clicks == 1, "the grabbed press clicked a row (" + clicks + ")");
    // Flings 2 and 3, both from wherever the view is: one to show that a programmatic
    // scroll cancels a coast, one to watch a coast END on its own. Dispatched immediately
    // -- a finger that crosses the slop inside a viewport never waits for the press delay.
    touchAt(TouchEvent.TOUCH_BEGIN, 7, 100, 40);
    touchAt(TouchEvent.TOUCH_MOVE, 7, 100, 20);      // slop crossed, anchor here
    setTimeout(phaseFlingMid, 40);
}

function phaseFlingMid():void
{
    stageMark("second fling: 1:1");
    var sv:ScrollViewNode = ScrollViewNode(app.findByKey("sv").desc);
    glideAtRelease = sv.offsetY;
    touchAt(TouchEvent.TOUCH_MOVE, 7, 100, 0);
    // 20pt of finger = 20px, from wherever the view was (the drag is relative).
    expect(sv.offsetY == glideAtRelease + 20,
        "the second fling moved " + (sv.offsetY - glideAtRelease) + ", want 20");
    setTimeout(phaseFlingEnd, 40);
}

function phaseFlingEnd():void
{
    stageMark("second fling: release");
    expect(clicks == 1, "the second fling clicked a row (" + clicks + ")");
    touchAt(TouchEvent.TOUCH_END, 7, 100, 0);
    setTimeout(phaseCoastAgain, 250);
}

function phaseCoastAgain():void
{
    stageMark("request cancels the coast");
    var sv:ScrollViewNode = ScrollViewNode(app.findByKey("sv").desc);
    expect(sv.offsetY > glideAtRelease + 20,
        "the second release did not coast (still at " + sv.offsetY + ")");
    // A COAST IS NOT ABOVE THE AUTHOR: scrolling programmatically ("back to top") while
    // the list is still gliding must stop the glide, or the author's write and the glide
    // fight and the view drifts back down. This is a MID-FLIGHT cancel, on purpose.
    svModelOffset = 0;
    view.invalidate(Dirty.ALL);
    setTimeout(phaseRequestCancelled, 300);
}

function phaseRequestCancelled():void
{
    stageMark("request cancelled the coast");
    var sv:ScrollViewNode = ScrollViewNode(app.findByKey("sv").desc);
    expect(sv.offsetY == 0, "a programmatic scroll did not cancel the glide (at " + sv.offsetY + ")");
    touchAt(TouchEvent.TOUCH_BEGIN, 8, 100, 40);
    touchAt(TouchEvent.TOUCH_MOVE, 8, 100, 20);
    var dbgSv:ScrollViewNode = ScrollViewNode(app.findByKey("sv").desc);
    dbg = dbg + "fling3 after m1: model=" + svModelOffset
        + " desc=" + dbgSv.offsetY + " max=" + dbgSv.maxOffsetY
        + " content=" + dbgSv.contentH + " maxOverscroll=" + dbgSv.overscrollY
        + " drags=" + app.router.dragStarts + "\n";
    setTimeout(phaseFling3Mid, 40);
}

function phaseFling3Mid():void
{
    stageMark("third fling: 1:1");
    var sv:ScrollViewNode = ScrollViewNode(app.findByKey("sv").desc);
    touchAt(TouchEvent.TOUCH_MOVE, 8, 100, 0);
    expect(sv.offsetY == 20, "the third fling started at " + sv.offsetY + ", want 20");
    setTimeout(phaseFling3End, 40);
}

function phaseFling3End():void
{
    stageMark("third fling: release");
    expect(clicks == 1, "the third fling clicked a row (" + clicks + ")");
    touchAt(TouchEvent.TOUCH_END, 8, 100, 0);
    setTimeout(phaseCoastStops, 1200);
}

function phaseCoastStops():void
{
    stageMark("coast stops on its own");
    var sv:ScrollViewNode = ScrollViewNode(app.findByKey("sv").desc);
    expect(sv.offsetY > 20, "the third release did not coast (still at " + sv.offsetY + ")");
    expect(sv.offsetY <= 180, "the third coast left the content (" + sv.offsetY + " > 180)");
    glideAtRelease = sv.offsetY;
    setTimeout(phaseCoastStopped, 250);
}

function phaseCoastStopped():void
{
    stageMark("coast stopped");
    var sv:ScrollViewNode = ScrollViewNode(app.findByKey("sv").desc);
    // 1.2s after a 0.5px/ms flick: the glide must be OVER. A coast that never ends is a
    // repaint every frame for the rest of the session, which no pixel assertion would see.
    expect(sv.offsetY == glideAtRelease,
        "the coast was still moving after 1.2s (" + sv.offsetY + " vs " + glideAtRelease + ")");
    // Back to the top for the clamp phase, through the same request path.
    svModelOffset = 0;
    view.invalidate(Dirty.ALL);
    setTimeout(phaseNoMomentum, 250);
}

// ---- phase 5: `momentum:false` stops at exactly the release offset ------
function phaseNoMomentum():void
{
    stageMark("momentum:false drag");
    var svf:ScrollViewNode = ScrollViewNode(app.findByKey("svf").desc);
    var sv:ScrollViewNode = ScrollViewNode(app.findByKey("sv").desc);
    expect(sv.offsetY == 0, "the reset did not move the first viewport to 0 (" + sv.offsetY + ")");
    dragBase = app.router.dragStarts;
    touchAt(TouchEvent.TOUCH_BEGIN, 3, 100, 98);     // inside svf, row f1
    setTimeout(phaseNoMomentumMove, 170);
}

function phaseNoMomentumMove():void
{
    stageMark("momentum:false: slop + 1:1");
    var svf:ScrollViewNode = ScrollViewNode(app.findByKey("svf").desc);
    touchAt(TouchEvent.TOUCH_MOVE, 3, 100, 78);      // 20pt up: slop crossed, anchor here
    expect(svf.offsetY == 0, "the slop motion scrolled the momentum:false list (" + svf.offsetY + ")");
    touchAt(TouchEvent.TOUCH_MOVE, 3, 100, 58);      // 20pt further
    expect(svf.offsetY == 20, "the momentum:false list is at " + svf.offsetY + ", want 20");
    setTimeout(phaseNoMomentumEnd, 40);
}

function phaseNoMomentumEnd():void
{
    stageMark("momentum:false: release");
    touchAt(TouchEvent.TOUCH_END, 3, 100, 58);
    setTimeout(phaseNoMomentumCheck, 450);
}

function phaseNoMomentumCheck():void
{
    stageMark("momentum:false: must not coast");
    var svf:ScrollViewNode = ScrollViewNode(app.findByKey("svf").desc);
    // EXACT: with momentum off, the release ends the motion. One pixel of coast here is
    // the bug that makes a form jump under the finger.
    expect(svf.offsetY == 20, "the momentum:false list coasted to " + svf.offsetY + ", want 20");
    expect(app.router.dragStarts == dragBase + 1,
        "the momentum:false drag was not reported (" + app.router.dragStarts + " vs " + (dragBase + 1) + ")");
    setTimeout(phaseAxis, 150);
}

// ---- phase 6: a horizontal swipe does not nudge a vertical list --------
function phaseAxis():void
{
    stageMark("axis lock");
    var svf:ScrollViewNode = ScrollViewNode(app.findByKey("svf").desc);
    var before:int = clicks;
    touchAt(TouchEvent.TOUCH_BEGIN, 4, 100, 118);
    touchAt(TouchEvent.TOUCH_MOVE, 4, 160, 120);     // 60 across, 2 down: horizontal wins
    // A SECOND sample is required to see the lock at all: the move that CROSSES the slop
    // never scrolls (the anchor is there), so only motion after it can move anything. A
    // lock-less implementation lets this one nudge the column by its 6pt of vertical.
    touchAt(TouchEvent.TOUCH_MOVE, 4, 200, 126);
    // svf has NO horizontal range (a single column), so the dominant axis cannot scroll
    // and the series is consumed without moving anything. Without this rule a diagonal
    // finger nudges the column while the author swipes sideways.
    expect(svf.offsetY == 20, "a horizontal swipe moved the vertical list to " + svf.offsetY);
    expect(svf.offsetX == 0, "a horizontal swipe reported a horizontal offset (" + svf.offsetX + ")");
    touchAt(TouchEvent.TOUCH_END, 4, 200, 126);
    expect(clicks == before, "a consumed swipe still clicked the row (" + clicks + ")");
    setTimeout(phaseClamp, 250);
}

// ---- phase 7: a drag past the end clamps at the range ------------------
function phaseClamp():void
{
    stageMark("clamp at the end");
    var sv:ScrollViewNode = ScrollViewNode(app.findByKey("sv").desc);
    touchAt(TouchEvent.TOUCH_BEGIN, 5, 100, 50);
    touchAt(TouchEvent.TOUCH_MOVE, 5, 100, 40);      // cross the slop, anchor at 40
    touchAt(TouchEvent.TOUCH_MOVE, 5, 100, -360);    // 400pt further up: far past the end
    // 400pt of finger from offset 0 is 400px, the range is 180: the AUTHOR-FACING offset
    // is clamped (the stretch is a separate number -- see the next phase).
    expect(sv.offsetY == 180, "a drag past the end landed at " + sv.offsetY + ", want 180");
    touchAt(TouchEvent.TOUCH_END, 5, 100, -360);
    // Let the bounce that this release started finish before the next phase measures one.
    setTimeout(phaseOver, 500);
}

// ---- phase 7b: overscroll (S3) -- the stretch, its pixels, and the spring back ----
function phaseOver():void
{
    stageMark("overscroll: past the end stretches");
    var sv:ScrollViewNode = ScrollViewNode(app.findByKey("sv").desc);
    var node:UiNode = app.findByKey("sv");
    expect(sv.overscroll == "rubber", "the default overscroll mode is '" + sv.overscroll + "', want 'rubber'");
    expect(sv.overscrollY == 0, "the previous bounce had not settled (stretch " + sv.overscrollY + ")");
    touchAt(TouchEvent.TOUCH_BEGIN, 9, 100, 50);
    touchAt(TouchEvent.TOUCH_MOVE, 9, 100, 40);       // cross the slop, anchor at 40
    touchAt(TouchEvent.TOUCH_MOVE, 9, 100, -360);    // 400pt from 0: 220px past the range
    // THE AUTHOR'S OFFSET DOES NOT LEAVE THE RANGE. This is the contract that makes
    // `offsetY == maxOffsetY` keep meaning "at the end" while the pixels are elsewhere.
    expect(sv.offsetY == 180, "the stretch moved the AUTHOR's offset to " + sv.offsetY + ", want 180");
    // The stretch itself is published by PAINT (`overscrollY` is an output, like
    // `maxOffsetY`), so it cannot be read in the same tick as the event.
    setTimeout(phaseOverMeasure, 150);
}

function phaseOverMeasure():void
{
    stageMark("overscroll: the stretch, in numbers and in pixels");
    var sv:ScrollViewNode = ScrollViewNode(app.findByKey("sv").desc);
    var oy:Number = sv.overscrollY;
    // The iOS curve: f(x) = x*dim*c/(dim + c*x) with dim = 60 (the viewport) and c = 0.55,
    // so 220px of excess is 220*60*0.55/(60+0.55*220) = 40.1px of stretch. COARSE, because
    // the exact value is a curve constant: what matters is that it is damped (not 220),
    // bounded (not 0) and moves the pixels.
    expect(oy > 30 && oy < 50, "the stretch is " + oy + "px, want ~40 (damped, not the raw 220)");
    // The clip is drawn at offset + stretch, so the bottom of the pane has nothing to
    // show and its OWN background (0xF5F5F5, style SV) is revealed where content used
    // to be. Without the stretch this pixel is a row's #CCCCCC.
    var bd:BitmapData = frameShot();
    expect(rgbAt(bd, 30, 65) == 0xF5F5F5,
        "the bottom of the stretched pane is " + hex(rgbAt(bd, 30, 65)) + ", want the pane's #F5F5F5");
    // ... and the TOP still shows content (the stretch slid it, it did not blank it).
    expect(rgbAt(bd, 30, 15) == 0xCCCCCC,
        "the top of the stretched pane is " + hex(rgbAt(bd, 30, 15)) + ", want a row's #CCCCCC");
    setTimeout(phaseOverRelease, 100);
}

function phaseOverRelease():void
{
    stageMark("overscroll: release springs back");
    touchAt(TouchEvent.TOUCH_END, 9, 100, -360);
    // 40px at rate 0.72/frame is under the 0.5px floor in ~14 frames (~230ms). 700ms is
    // "long after" on purpose: the assertion is the END STATE, not the curve.
    setTimeout(phaseOverSettled, 700);
}

function phaseOverSettled():void
{
    stageMark("overscroll: settled exactly at the end");
    var sv:ScrollViewNode = ScrollViewNode(app.findByKey("sv").desc);
    // EXACT, and that is the M1 acceptance criterion: a spring that stops at 0.4px and
    // keeps asking for frames would pass 'offsetY == 180' and still be wrong.
    expect(sv.overscrollY == 0, "the pane did not return to the end (stretch " + sv.overscrollY + ")");
    expect(sv.offsetY == 180, "the pane landed at " + sv.offsetY + " after the bounce, want 180");
    var bd:BitmapData = frameShot();
    expect(rgbAt(bd, 30, 65) == 0xCCCCCC,
        "after the bounce the bottom of the pane is " + hex(rgbAt(bd, 30, 65)) + ", want a row's #CCCCCC");
    // ---- `overscroll: "none"` must not stretch at all ----
    var svf:ScrollViewNode = ScrollViewNode(app.findByKey("svf").desc);
    expect(svf.overscroll == "none", "the overscroll:'none' viewport reports '" + svf.overscroll + "'");
    touchAt(TouchEvent.TOUCH_BEGIN, 10, 100, 120);
    touchAt(TouchEvent.TOUCH_MOVE, 10, 100, 110);     // slop crossed, anchor at 110
    touchAt(TouchEvent.TOUCH_MOVE, 10, 100, -300);    // 410pt from offset 20: past the end
    expect(svf.offsetY == 180, "the 'none' viewport is at " + svf.offsetY + ", want 180 (clamped)");
    setTimeout(phaseNoneMeasure, 150);
}

function phaseNoneMeasure():void
{
    stageMark("overscroll:none -- clamped, and NO stretch");
    var svf:ScrollViewNode = ScrollViewNode(app.findByKey("svf").desc);
    expect(svf.overscrollY == 0, "overscroll:'none' still stretched by " + svf.overscrollY + "px");
    var bd:BitmapData = frameShot();
    expect(rgbAt(bd, 30, 135) == 0xDDDDDD,
        "the 'none' pane's bottom is " + hex(rgbAt(bd, 30, 135)) + ", want row #DDDDDD (nothing stretched)");
    touchAt(TouchEvent.TOUCH_END, 10, 100, -300);
    setTimeout(phaseValidate, 300);
}

// ---- phase 8: the rate is validated at factory time --------------------
function phaseValidate():void
{
    stageMark("decelerationRate validation");
    var threw:Boolean = false;
    try { scrollView({ decelerationRate: 1.5 }); }
    catch (e:Error) { threw = true; }
    expect(threw, "decelerationRate 1.5 (it would accelerate) was accepted");

    threw = false;
    try { scrollView({ decelerationRate: 0 }); }
    catch (e:Error) { threw = true; }
    expect(threw, "decelerationRate 0 (it would stop dead every frame) was accepted");

    threw = false;
    try
    {
        var ok:ScrollViewNode = ScrollViewNode(scrollView({ decelerationRate: 0.9 }));
        expect(ok.decelerationRate == 0.9, "a valid decelerationRate was not stored (" + ok.decelerationRate + ")");
    }
    catch (e:Error) { threw = true; }
    expect(!threw, "a valid decelerationRate was refused");

    threw = false;
    try { scrollView({ overscroll: "bounce" }); }
    catch (e:Error) { threw = true; }
    expect(threw, "overscroll 'bounce' (a mode that does not exist) was accepted");

    threw = false;
    try
    {
        var none:ScrollViewNode = ScrollViewNode(scrollView({ overscroll: "none" }));
        expect(none.overscroll == "none", "overscroll:'none' was not stored (" + none.overscroll + ")");
    }
    catch (e:Error) { threw = true; }
    expect(!threw, "overscroll:'none' was refused");

    setTimeout(finish, 150);
}

function finish():void
{
    writeText(OUT + ".dbg.txt", dbg);
    writeText(OUT + ".done", failures == "" ? "PASS" : "FAIL " + failures);
}

// ---- helpers --------------------------------------------------------------

// One synthesized touch event, at ROOT coordinates (the convention the router
// documents; with G5 there is no platform that would target the event for us).
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

// The frame buffer, read back 1:1 from the compositor output (no DPI scaling, no
// window chrome) -- the same source <OUT>.bmp is written from.
function frameShot():BitmapData
{
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    return bd;
}

function rgbAt(bd:BitmapData, x:int, y:int):uint
{
    return bd.getPixel(x, y) & 0xFFFFFF;
}

function hex(c:uint):String
{
    var s:String = c.toString(16);
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

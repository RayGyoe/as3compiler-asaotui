// probes/widgets/motion/Main.as -- LAYOUT animation, text-colour animation, and the
// floating layer's EXIT motion.
//
// Output prefix MUST equal the directory name (`motion`).
//
// WHY A SECOND ANIMATION PROBE. probes/widgets/anim proves the PAINT half of the
// animator (opacity / background, no reflow). This one proves the two things that
// were still missing:
//
//   A. LAYOUT fields animate. `sizer` grows 100 -> 240 wide and its corner radius
//      0 -> 12 in one 600ms linear tween; `pad` grows its padding 10 -> 20, which
//      moves its CHILD (`padc`) from x=30 to x=40. A layout tween must re-solve the
//      tree every frame -- that is the whole semantic difference -- so the probe
//      asserts BOTH the moving geometry and `app.layoutSolves` growing, and then
//      that it STOPS growing once the tween lands.
//
//   B. The floating layer can LEAVE. A dialog that closes used to vanish in one
//      frame. Now it runs the entrance motion backwards and hides on the landing
//      frame, so the probe samples mid-exit (still on screen, still visible) and
//      after landing (gone from the tree's `visible` AND from the frame buffer).
//
// The mid-tween numbers are RELATIONS (strictly between, monotone), never exact --
// the frame the sample lands on is not controllable to the millisecond. The
// ENDPOINTS are deterministic and are asserted exactly, both in-program and through
// expect.json's hand-computed rects/pixels.
//
// HAND ARITHMETIC (420x320 window, root column padding 20 / gap 10):
//   sizer  y = 20            rest [20,20,100,40]    final [20,20,240,40]
//   pad    y = 20+40+10 = 70 rest [20,70,200,60]    final same (padding is inside)
//   padc   rest  x = 20+10 = 30, y = 70+10 = 80     final x = 20+20 = 40, y = 90
//   label  y = 70+60+10 = 140 (auto height, font-dependent -- never pinned)
//
//   pixel (120,40)  inside sizer, away from every corner            -> #3366cc
//   pixel (20,20)   sizer's top-left corner -> BACKGROUND #ffffff at the end of the
//                   tween. This is a ROUNDED-CORNER assertion now: G19 was fixed in
//                   stage 267 (drawRoundRect builds a real SkRRect), so at radius 12
//                   the box corner (offset 0,0 from a 12px arc centred at 12,12) is
//                   fully outside the corner and the root's fill shows through. It
//                   used to pin #3366cc precisely so the fix would be noticed here;
//                   the rest-state pixel is the same corner with radius 0 (square),
//                   asserted by the radius check above rather than by this pixel.
//   pixel (35,95)   in `pad`'s padding at rest=10? no: x=35 is INSIDE padc at rest
//                   (padc spans 30..70 x 80..100) -> #22cc88; at final padding=20
//                   padc starts at 40, so (35,95) is the orange padding -> #ff9900
//   pixel (5,5)     root background -> #ffffff
//
// Protocol (tools/probe.cjs): dir name == output prefix; write <OUT>.rects.txt,
// <OUT>.bmp, <OUT>.done (PASS | FAIL <reason>).
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

var W:int = 420;
var H:int = 320;
var OUT:String = 'motion';

class MotionModel extends Observable
{
    public var hot:Boolean = false;    // rest -> final (size + padding + text colour)
    public var dlg:Boolean = false;    // the dialog's `open`
    // Bumped mid-exit to force a RE-RENDER while the surface is leaving. This is not
    // decoration: the description says `visible: false` the whole time the exit runs,
    // so a reconcile that happens during the motion is exactly the case where a
    // naive implementation re-hides the surface it is animating.
    public var tick:int = 0;
}

class MotionProbe extends View
{
    public var model:MotionModel;

    private static const ROOT:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", alignItems: "flex-start",
        padding: 20, gap: 10, size: [420, 320], background: 0xFFFFFF,
        text: { fontSize: 14, color: 0x111827 }
    });

    // 600ms linear: long enough that ~10 frames land inside it, so a mid sample
    // cannot miss the window even on a coarse timer.
    private static const SIZER_REST:StyleRefinement = StyleRefinement.from({
        size: [100, 40], background: 0x3366CC, cornerRadii: 0,
        transitionMs: 600, transitionEase: "linear" });
    private static const SIZER_HOT:StyleRefinement = StyleRefinement.from({
        size: [240, 40], background: 0x3366CC, cornerRadii: 12,
        transitionMs: 600, transitionEase: "linear" });

    private static const PAD_REST:StyleRefinement = StyleRefinement.from({
        size: [200, 60], padding: 10, background: 0xFF9900,
        transitionMs: 600, transitionEase: "linear" });
    private static const PAD_HOT:StyleRefinement = StyleRefinement.from({
        size: [200, 60], padding: 20, background: 0xFF9900,
        transitionMs: 600, transitionEase: "linear" });

    private static const CHILD:StyleRefinement = StyleRefinement.from({
        size: [40, 20], background: 0x22CC88 });

    private static const LABEL_REST:StyleRefinement = StyleRefinement.from({
        text: { fontSize: 32, fontWeight: "bold", color: 0x000000 },
        transitionMs: 600, transitionEase: "linear" });
    private static const LABEL_HOT:StyleRefinement = StyleRefinement.from({
        text: { fontSize: 32, fontWeight: "bold", color: 0xFFFFFF },
        transitionMs: 600, transitionEase: "linear" });

    public function MotionProbe(m:MotionModel):void
    {
        super();
        this.model = m;
    }

    override public function render():Node
    {
        return column({ key: "root", style: ROOT, ariaName: "motion probe" }, [
            box({ key: "sizer", style: model.hot ? SIZER_HOT : SIZER_REST, ariaName: "sizer" }),
            box({ key: "pad", style: model.hot ? PAD_HOT : PAD_REST, ariaName: "pad" }, [
                box({ key: "padc", style: CHILD, ariaName: "pad child" })
            ]),
            text("MOTION", { key: "label", style: model.hot ? LABEL_HOT : LABEL_REST, ariaName: "label" })
        ]);
    }

    override public function renderOverlay():Node
    {
        return overlay([
            dialog({ key: "dlg", open: model.dlg, title: "Closing", width: 240,
                     scrim: true, closeOnScrim: true }, [
                text("bye " + model.tick, { key: "dlg:body", ariaName: "body" })
            ])
        ]);
    }
}

var model:MotionModel = new MotionModel();
var view:MotionProbe = new MotionProbe(model);
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

var problems:String = "";
var log:String = "";
var REST_DARK:int = -1;
var MID_DARK:int = -1;
var SOLVES_REST:int = -1;
var SOLVES_MID:int = -1;
var SOLVES_FINAL:int = -1;
var DlgAtOpen:UiNode = null;

function say(s:String):void
{
    log = log + s + "\n";
    trace(s);
}

function fail(s:String):void
{
    problems = problems + s + "; ";
}

function frame():BitmapData
{
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    return bd;
}

function rgbAt(bd:BitmapData, x:int, y:int):uint
{
    return bd.getPixel(x, y) & 0xFFFFFF;
}

// Count pixel runs that are DARK (every channel < 128) inside a node's rect. The
// point is not a glyph shape (font rendering is out of scope) but a MONOTONE
// quantity: black text has many, grey text has fewer, white text has none.
function darkCount(bd:BitmapData, n:UiNode):int
{
    var x0:int = int(n.absX);
    var y0:int = int(n.absY);
    var x1:int = int(n.absX + n.absW);
    var y1:int = int(n.absY + n.absH);
    var count:int = 0;
    for (var y:int = y0; y < y1; y++)
    {
        for (var x:int = x0; x < x1; x++)
        {
            var c:uint = bd.getPixel(x, y) & 0xFFFFFF;
            var r:int = int((c >> 16) & 0xFF);
            var g:int = int((c >> 8) & 0xFF);
            var b:int = int(c & 0xFF);
            if (r < 128 && g < 128 && b < 128) count = count + 1;
        }
    }
    return count;
}

// The animated corner radius lives on the resolved style, not on a display object.
// Since G19 was fixed (stage 267) the radius is ALSO readable as a pixel: the
// sizer's own corner at radius 12 falls outside the arc and shows the background,
// which is what the final assertion below checks.
function radiusOf(n:UiNode):Number
{
    if (n == null || n.resolved == null || n.resolved.cornerRadii == null) return -1;
    return n.resolved.cornerRadii.topLeft;
}

function hex(c:uint):String
{
    var s:String = c.toString(16);
    while (s.length < 6) s = "0" + s;
    return "#" + s;
}

setTimeout(rest, 900);
stage.showWindow(W, H, "probe motion");

// ---- A: layout animation --------------------------------------------------
function rest():void
{
    var bd:BitmapData = frame();
    var sizer:UiNode = app.findByKey("sizer");
    var padc:UiNode = app.findByKey("padc");
    var label:UiNode = app.findByKey("label");
    if (sizer == null || padc == null || label == null) { fail("a node is missing"); finish(); return; }

    if (sizer.absX != 20 || sizer.absY != 20 || sizer.absW != 100 || sizer.absH != 40)
        fail("rest sizer is " + sizer.absX + "," + sizer.absY + "," + sizer.absW + "," + sizer.absH + " not 20,20,100,40");
    if (padc.absX != 30 || padc.absY != 80)
        fail("rest padc is at " + padc.absX + "," + padc.absY + " not 30,80 (padding 10)");
    if (radiusOf(sizer) != 0)
        fail("rest corner radius is " + radiusOf(sizer) + " not 0");
    // (35,95) is INSIDE the child at rest (child spans 30..70 x 80..100).
    if (rgbAt(bd, 35, 95) != 0x22CC88)
        fail("rest (35,95) is " + hex(rgbAt(bd, 35, 95)) + " not the child's #22cc88");

    REST_DARK = darkCount(bd, label);
    if (REST_DARK < 20) fail("the resting label has only " + REST_DARK + " dark pixel(s): the colour claim would be vacuous");
    SOLVES_REST = app.layoutSolves;
    say("rest: sizer=" + sizer.absW + " padc.x=" + padc.absX + " dark=" + REST_DARK + " solves=" + SOLVES_REST);

    model.hot = true;
    view.invalidate(Dirty.ALL);
    setTimeout(mid, 180);
    setTimeout(settled, 950);
}

function mid():void
{
    var sizer:UiNode = app.findByKey("sizer");
    var padc:UiNode = app.findByKey("padc");
    var label:UiNode = app.findByKey("label");
    if (sizer == null || padc == null || label == null) return;

    if (sizer.absW <= 100 || sizer.absW >= 240)
        fail("mid sizer width is " + sizer.absW + ", not strictly between 100 and 240 (it JUMPED)");
    if (padc.absX <= 30 || padc.absX >= 40)
        fail("mid padc.x is " + padc.absX + ", not strictly between 30 and 40 (the padding did not animate)");
    var r:Number = radiusOf(sizer);
    if (!(r > 0) || !(r < 12))
        fail("mid corner radius is " + r + ", not strictly between 0 and 12");
    MID_DARK = darkCount(frame(), label);
    SOLVES_MID = app.layoutSolves;
    say("mid: sizer=" + sizer.absW + " padc.x=" + padc.absX + " dark=" + MID_DARK + " solves=" + SOLVES_MID);
    if (MID_DARK <= 0 || MID_DARK >= REST_DARK)
        fail("mid label has " + MID_DARK + " dark pixel(s); want strictly between 0 and " + REST_DARK);
    // A LAYOUT tween must re-solve. If only `resolved` changed, the geometry above
    // could still be stale -- this is the assertion that separates the two.
    if (SOLVES_MID - SOLVES_REST < 3)
        fail("layout was solved only " + (SOLVES_MID - SOLVES_REST) + " time(s) during the tween; a layout animation must re-solve every frame");
    if (!Anim.isActive(sizer))
        fail("the sizer is not animating at the mid sample");
}

function settled():void
{
    var bd:BitmapData = frame();
    var sizer:UiNode = app.findByKey("sizer");
    var padc:UiNode = app.findByKey("padc");
    var label:UiNode = app.findByKey("label");
    if (sizer == null || padc == null || label == null) { fail("a node is missing at final"); finish(); return; }

    if (sizer.absX != 20 || sizer.absY != 20 || sizer.absW != 240 || sizer.absH != 40)
        fail("final sizer is " + sizer.absX + "," + sizer.absY + "," + sizer.absW + "," + sizer.absH + " not 20,20,240,40");
    if (padc.absX != 40 || padc.absY != 90)
        fail("final padc is at " + padc.absX + "," + padc.absY + " not 40,90 (padding 20)");
    if (radiusOf(sizer) != 12)
        fail("final corner radius is " + radiusOf(sizer) + " not 12");
    if (rgbAt(bd, 20, 20) != 0xFFFFFF)
        fail("final sizer corner is " + hex(rgbAt(bd, 20, 20)) + " -- expected the rounded-away background #ffffff at radius 12 (G19 fixed, stage 267); #3366cc here means drawRoundRect went back to drawing a plain rect");
    if (rgbAt(bd, 35, 95) != 0xFF9900)
        fail("final (35,95) is " + hex(rgbAt(bd, 35, 95)) + " not the padding's #ff9900");
    var dark:int = darkCount(bd, label);
    if (dark != 0) fail("final label has " + dark + " dark pixel(s): the text colour did not reach white");
    if (Anim.isActive(sizer)) fail("the sizer is still animating after 950ms of a 600ms tween");
    SOLVES_FINAL = app.layoutSolves;
    say("final: sizer=" + sizer.absW + " padc.x=" + padc.absX + " dark=" + dark + " solves=" + SOLVES_FINAL);
    setTimeout(idle, 150);
}

// The re-solve must STOP when the tween lands -- otherwise "animate by re-solving"
// would mean the app re-solves forever.
function idle():void
{
    if (app.layoutSolves != SOLVES_FINAL)
        fail("layout kept re-solving after the tween landed: " + SOLVES_FINAL + " -> " + app.layoutSolves);
    model.dlg = true;
    view.invalidate(Dirty.ALL);
    setTimeout(dlgShown, 320);
}

// ---- B: the exit motion ---------------------------------------------------
function dlgShown():void
{
    var dlg:UiNode = app.findByKey("dlg");
    if (dlg == null) { fail("the dialog never mounted"); finish(); return; }
    if (!dlg.visible) fail("the open dialog is not visible");
    var bd:BitmapData = frame();
    var scrim:uint = rgbAt(bd, 10, 10);
    say("dialog open: visible=" + dlg.visible + " scrim=" + hex(scrim));
    if (scrim != 0x999999) fail("the open dialog's scrim is " + hex(scrim) + " not #999999 (0x66 black over white)");

    DlgAtOpen = dlg;
    model.dlg = false;
    view.invalidate(Dirty.ALL);
    setTimeout(exitMid, 22);
}

function exitMid():void
{
    var dlg:UiNode = app.findByKey("dlg");
    if (dlg == null) { fail("the closing dialog disappeared from the tree"); finish(); return; }
    var bd:BitmapData = frame();
    var scrim:uint = rgbAt(bd, 10, 10);
    say("exit mid: visible=" + dlg.visible + " running=" + OverlayMotion.exitRunning(dlg) + " scrim=" + hex(scrim));
    // ONE FRAME IS NOT ENOUGH: the whole point is that the surface is still being
    // painted while it leaves.
    if (!dlg.visible) fail("the closing dialog is already invisible " + 55 + "ms in: it vanished instead of leaving");
    if (!OverlayMotion.exitRunning(dlg)) fail("no exit motion is running after the dialog closed");
    if (scrim == 0xFFFFFF) fail("the frame buffer is already empty mid-exit: nothing was painted while leaving");

    // Force a re-render in the middle of the motion. The dialog's description still
    // says `visible: false`, so this reconcile is the one that would re-hide it.
    model.tick = model.tick + 1;
    view.invalidate(Dirty.ALL);
    setTimeout(exitReconciled, 30);
}

function exitReconciled():void
{
    var dlg:UiNode = app.findByKey("dlg");
    if (dlg == null) { fail("the closing dialog left the tree on a mid-exit re-render"); finish(); return; }
    var scrim:uint = rgbAt(frame(), 10, 10);
    say("exit reconciled: sameNode=" + (dlg === DlgAtOpen) + " hold=" + dlg.visibleHold + " visible=" + dlg.visible + " running=" + OverlayMotion.exitRunning(dlg) + " scrim=" + hex(scrim));
    if (!dlg.visible) fail("the closing dialog disappeared mid-exit when the tree re-rendered: the exit was cancelled by the description's `visible: false`");
    if (!OverlayMotion.exitRunning(dlg)) fail("the mid-exit re-render stopped the motion");
    if (scrim == 0x999999) fail("the scrim is still at full strength after the re-render: the fade was reset");
    if (scrim == 0xFFFFFF) fail("the surface is already gone after the re-render: the fade was cut short");
    setTimeout(exitEnd, 500);
}

function exitEnd():void
{
    var dlg:UiNode = app.findByKey("dlg");
    if (dlg == null) { fail("the closed dialog disappeared from the tree"); finish(); return; }
    var bd:BitmapData = frame();
    var scrim:uint = rgbAt(bd, 10, 10);
    say("exit end: visible=" + dlg.visible + " running=" + OverlayMotion.exitRunning(dlg) + " scrim=" + hex(scrim));
    if (dlg.visible) fail("the dialog is still visible after the exit landed");
    if ((dlg.backing != null) && dlg.backing.visible) fail("the dialog's backing is still on screen after the exit landed");
    if (OverlayMotion.exitRunning(dlg)) fail("the exit motion never finished");
    if (scrim != 0xFFFFFF) fail("the frame buffer still shows " + hex(scrim) + " where the scrim was");
    finish();
}

function finish():void
{
    var bd:BitmapData = frame();
    var lines:String = "";
    var names:Array = ["root", "sizer", "pad", "padc", "label", "dlg"];
    for (var i:int = 0; i < names.length; i++)
    {
        var n:UiNode = app.findByKey(names[i]);
        if (n == null) { lines = lines + names[i] + " MISSING\n"; continue; }
        lines = lines + names[i] + " " + n.absX + "," + n.absY + "," + n.absW + "," + n.absH + "\n";
    }
    writeText(OUT + ".rects.txt", lines);
    writeText(OUT + ".samples.txt", log);
    writeBmp(OUT + ".bmp", bd);
    writeText(OUT + ".done", problems == "" ? "PASS" : "FAIL " + problems);
}

function writeText(path:String, t:String):void
{
    var f:File = new File(path);
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
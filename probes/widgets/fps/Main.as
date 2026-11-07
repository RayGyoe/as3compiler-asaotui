// probes/widgets/fps/Main.as -- UiApp.showFps(): the frame-rate HUD in the library's
// THIRD retained tree.
//
// Output prefix MUST equal the directory name (`fps`).
//
// WHAT IS BEING MEASURED (everything here is a property the HUD has to have, not a
// picture of it):
//
//   (a) IT IS ITS OWN ROOT -- `showFps` adds exactly ONE stage child, and that is
//       the LAST one. That ordering IS the "nothing can cover it" guarantee: this
//       engine has no z-index, so the display list is the stacking order.
//
//   (b) IT IS NOT CLICKABLE. A button is placed UNDER the HUD, with exactly the
//       same rect, and a click at the HUD's centre must reach the BUTTON. This is
//       the one failure mode a screenshot cannot show: a HUD that looks like an
//       overlay but eats every click in the corner of the window.
//
//   (c) IT MEASURES THE REAL CADENCE. `stage.frameRate = 60` is asked for, the
//       probe waits for sampling windows to close, and the published numbers are
//       then compared with each other (`avg * fps == 1000`) and with the request.
//       A HUD that printed a constant would fail (b) of the arithmetic, a HUD
//       driven by a Timer instead of by frames would fail the band.
//
//   (d) IT PAINTS OVER THE BUTTON -- read from the frame buffer at a pixel inside
//       the panel that is inside the green button underneath it.
//
//   (e) IT COMES AND GOES COMPLETELY -- `hideFps()` leaves the stage with exactly
//       the children it had before `showFps`, and showing it again restores them.
//       A HUD that leaked a display object would make every later count wrong.
//
//   (g) NOTHING COVERS IT. The view turns on an author overlay (a full-window dark
//       scrim, which is what a dialog looks like from the display list's point of
//       view) while the HUD is up. The HUD must still be the LAST child and its
//       pixels must still win over the scrim. This is the requirement in one line:
//       "the monitor must never be covered by other content".
//
// Hand arithmetic (window 320x240, root column, padding 12, alignItems flex-end):
//
//   button  (204, 12, 104, 73)      -- 320 - 12 - 104 = 204, at the top
//   HUD     (204, 12, 104, ~73)     -- inset 12 from the top and the right
//   click   (256, 40)               -- the centre of BOTH
//
// Protocol (tools/probe.cjs): dir name == output prefix; write <OUT>.rects.txt,
// <OUT>.bmp, <OUT>.done (PASS | FAIL <reason>).
import asaot.ui.*;
import asaot.ui.style.StyleRefinement;
import flash.display.BitmapData;
import flash.display.Sprite;
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
var H:int = 240;
var OUT:String = "fps";
var BTN_BG:uint = 0x00FF00;
var PAD:Number = 12;
var HUD_W:Number = 104;

var picks:int = 0;

class FpsView extends View
{
    private static const ROOT:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", alignItems: "flex-end",
        size: [320, 240], padding: 12, background: 0xFFFFFF
    });
    private static const BTN:StyleRefinement = StyleRefinement.from({
        size: [104, 73], background: 0x00FF00, cornerRadii: 6,
        text: { fontSize: 11, color: 0xFFFFFF }
    });
    private static const SCRIM:StyleRefinement = StyleRefinement.from({
        position: "absolute", inset: 0, background: 0x112233
    });

    public var overlayOn:Boolean = false;

    public function FpsView():void { super(); }

    override public function render():Node
    {
        return column({ key: "root", style: ROOT }, [
            button({ key: "btn", label: "under", style: BTN,
                     onClick: function ():void { picks = picks + 1; } })
        ]);
    }

    // A stand-in for a dialog: the author's overlay root, full-window, opaque enough
    // that "who painted last" is answerable from one pixel.
    override public function renderOverlay():Node
    {
        if (!overlayOn) return null;
        return overlay([
            column({ key: "ovScrim", style: SCRIM }, [])
        ]);
    }
}

var stage:Stage = new Stage();
var view:FpsView = new FpsView();
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();
// The HUD's cadence, asked for explicitly so the measured band has a meaning.
stage.frameRate = 60;
var baseKids:int = stage.numChildren;
app.showFps("top-right");

var problems:String = "";
var log:String = "";

function say(s:String):void { log = log + s + "\n"; }
function fail(s:String):void { problems = problems + s + "; "; }
function check(cond:Boolean, s:String):void { if (!cond) fail(s); }

function frame():BitmapData
{
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    return bd;
}

function rgbAt(bd:BitmapData, x:int, y:int):uint { return bd.getPixel(x, y) & 0xFFFFFF; }

function hex(c:uint):String
{
    var s:String = c.toString(16);
    while (s.length < 6) s = "0" + s;
    return "#" + s;
}

function rectOf(n:UiNode):String
{
    return n.absX + "," + n.absY + "," + n.absW + "," + n.absH;
}

setTimeout(ready, 1200);
stage.showWindow(W, H, "probe fps");

function ready():void
{
    // (a) ONE NEW ROOT, ON TOP.
    var p:FpsPanel = app.fpsPanel();
    if (p == null) { fail("showFps() published no panel"); finish(); return; }
    check(stage.numChildren == baseKids + 1,
        "the stage holds " + stage.numChildren + " objects with the HUD shown, want "
        + (baseKids + 1));
    var top:Object = stage.numChildren > 0 ? stage.getChildAt(stage.numChildren - 1) : null;
    check(top is Sprite, "the last stage child is not the HUD's backing");

    // (b) THE BACKING IS OUT OF THE HIT TEST -- both flags, see UiApp.markFpsChrome.
    var hud:Sprite = app.getFpsRoot() == null ? null : app.getFpsRoot().backing;
    check(hud != null, "getFpsRoot() is null while the HUD is shown");
    if (hud != null)
    {
        check(hud.mouseEnabled == false, "the HUD backing still takes the mouse (mouseEnabled)");
        check(hud.mouseChildren == false, "the HUD backing still hit-tests its children (mouseChildren)");
        check(stage.getChildIndex(hud) == stage.numChildren - 1,
            "the HUD backing is at index " + stage.getChildIndex(hud) + " of "
            + stage.numChildren + ", want the last");
    }

    // The panel is in its own tree, so it is NOT found through the main root's keys;
    // the probe reads it by key through findByKey, which searches all three roots.
    var panel:UiNode = app.findByKey("fpsPanel");
    if (panel == null) { fail("the panel node 'fpsPanel' is not reachable by key"); }
    else
    {
        check(panel.absX == W - PAD - HUD_W,
            "the panel is at x=" + panel.absX + ", want " + (W - PAD - HUD_W)
            + " (12 from the right edge)");
        check(panel.absY == PAD, "the panel is at y=" + panel.absY + ", want 12");
        check(panel.absW == HUD_W, "the panel is " + panel.absW + " wide, want " + HUD_W);
        // The height is a text-metric sum (head 20 + sub 13 + spark 20 + gaps +
        // padding), not a constant: pinned as a band so a font-size change is a
        // deliberate edit here rather than a silent one.
        check(panel.absH >= 66 && panel.absH <= 82,
            "the panel is " + panel.absH + " tall, want 66..82 (the metric sum)");
        say("panel " + rectOf(panel));
    }

    // (c) THE CLICK GOES THROUGH THE HUD TO THE BUTTON UNDER IT.
    stage.dispatchMouse(256, 40, "click");
    setTimeout(afterClick, 150);
}

function afterClick():void
{
    check(picks == 1, "a click inside the HUD reported " + picks
        + " picks from the button underneath, want 1 (the HUD must not be clickable)");

    // (d) THE HUD IS PAINTED OVER THE BUTTON. Green is 0x00FF00: its G channel is
    // 255 and the panel's slate is ~41, so "G < 100" separates the two without
    // depending on the exact composite of the 95%-opaque background.
    var bd:BitmapData = frame();
    var over:uint = rgbAt(bd, 250, 20);
    check(((over >> 8) & 0xFF) < 100, "the pixel inside the panel is " + hex(over)
        + ", want the panel's dark background (the green button must be covered)");
    var beside:uint = rgbAt(bd, 40, 200);
    check(beside == 0xFFFFFF, "the page background at (40,200) is " + hex(beside)
        + ", want #FFFFFF");

    // (e) THE NUMBERS ARE A MEASUREMENT, NOT A CONSTANT.
    var p:FpsPanel = app.fpsPanel();
    check(p.sampled, "the panel never sampled a window");
    check(p.fps >= 45 && p.fps <= 75, "fps is " + p.fps
        + ", want 45..75 for stage.frameRate = 60");
    if (p.fps > 0)
    {
        var implied:Number = 1000 / p.fps;
        check(Math.abs(implied - p.avgMs) <= implied * 0.25 + 1,
            "the published fps (" + p.fps + ") and avgMs (" + p.avgMs
            + ") disagree: 1000/fps = " + implied);
    }
    check(p.peakMs >= p.avgMs - 0.001, "peakMs " + p.peakMs + " is below avgMs " + p.avgMs);
    say("fps " + p.fps + " avg " + p.avgMs + " peak " + p.peakMs);

    // (e2) MOVING THE PANEL KEEPS THE MEASUREMENT. The corner is an inset, not a
    // different instrument: the second showFps() must re-place the SAME panel where
    // `inset` says -- and this is the case that caught the resolver's per-component
    // `inset` merge (a naive re-describe left the old bottom/left pinned and produced
    // a 104x216 slab in the wrong corner).
    app.showFps("bottom-left");
    var moved:UiNode = app.findByKey("fpsPanel");
    check(moved != null, "showFps(bottom-left) mounted no panel");
    if (moved != null)
    {
        check(moved.absX == PAD, "the bottom-left panel is at x=" + moved.absX + ", want 12");
        check(Math.abs(moved.absY + moved.absH - (H - PAD)) <= 1,
            "the bottom-left panel ends at y=" + (moved.absY + moved.absH)
            + ", want " + (H - PAD));
        check(moved.absH >= 66 && moved.absH <= 82,
            "the moved panel is " + moved.absH + " tall, want 66..82 (not stretched)");
        say("corner " + rectOf(moved));
    }
    check(app.fpsPanel().sampled, "changing the corner threw the measurement away");
    app.showFps("top-right");

    // (g) A DIALOG OPENS UNDER IT. The HUD is chrome: the author's overlay may cover
    // the page, and must still not cover the monitor.
    view.overlayOn = true;
    app.invalidate(Dirty.ALL);
    app.reflow();
    var ov:DisplayObject = app.overlayDisplay();
    var hud2:Sprite = app.getFpsRoot() == null ? null : app.getFpsRoot().backing;
    check(ov != null, "the overlay root was not mounted");
    check(stage.numChildren == baseKids + 2, "the stage holds " + stage.numChildren
        + " objects with the HUD and an overlay, want " + (baseKids + 2));
    if (ov != null && hud2 != null)
    {
        check(stage.getChildIndex(hud2) == stage.numChildren - 1,
            "the HUD is at display index " + stage.getChildIndex(hud2)
            + " with a dialog open, want the last");
        check(stage.getChildIndex(hud2) > stage.getChildIndex(ov),
            "the dialog is drawn after the HUD (HUD " + stage.getChildIndex(hud2)
            + ", overlay " + stage.getChildIndex(ov) + ")");
    }
    var bd3:BitmapData = frame();
    // (290,22) is inside the panel's empty head-row slack, (150,120) is scrim only.
    check(rgbAt(bd3, 290, 22) == Theme.tokens().surfaceInverse,
        "with a dialog open the panel's own pixel is " + hex(rgbAt(bd3, 290, 22))
        + ", want the panel background " + hex(Theme.tokens().surfaceInverse)
        + " (the HUD is painted under the dialog)");
    check(rgbAt(bd3, 150, 120) == 0x112233, "the scrim pixel at (150,120) is "
        + hex(rgbAt(bd3, 150, 120)) + ", want #112233");
    say("overlay kids " + stage.numChildren + " hudIdx " + stage.getChildIndex(hud2)
        + " ovIdx " + stage.getChildIndex(ov));
    // ... and back to no overlay, so the hide/re-show counts below are the baseline.
    view.overlayOn = false;
    app.invalidate(Dirty.ALL);
    app.reflow();

    // (f) HIDE -> the stage is back to its baseline; the button is visible again.
    app.hideFps();
    check(app.fpsPanel() == null, "hideFps() left a panel object behind");
    check(app.getFpsRoot() == null, "hideFps() left a retained root behind");
    check(stage.numChildren == baseKids, "the stage holds " + stage.numChildren
        + " objects after hideFps, want " + baseKids);
    var bd2:BitmapData = frame();
    var uncovered:uint = rgbAt(bd2, 250, 20);
    check(uncovered == BTN_BG, "after hideFps the pixel inside the button is "
        + hex(uncovered) + ", want " + hex(BTN_BG));

    // ... and a click still works (the button was never disabled, only covered).
    stage.dispatchMouse(256, 40, "click");
    setTimeout(afterShow, 150);
}

function afterShow():void
{
    check(picks == 2, "a click after hideFps reported " + picks + " picks, want 2");
    // Show it again: one new stage child, and it is the last one again.
    app.showFps("top-right");
    check(stage.numChildren == baseKids + 1, "after re-showing, the stage holds "
        + stage.numChildren + " objects, want " + (baseKids + 1));
    // An unknown corner is an ERROR, never a silent fallback to a default.
    var threw:Boolean = false;
    try { app.showFps("middle"); }
    catch (e:Error) { threw = true; }
    check(threw, "showFps(\"middle\") did not throw");
    // ... and the panel is still there, in the corner that was last ACCEPTED, so the
    // BMP shows the HUD with real numbers where the demo puts it.
    var panel:UiNode = app.findByKey("fpsPanel");
    check(panel != null, "the rejected corner unmounted the panel");
    if (panel != null) check(panel.absX == W - PAD - HUD_W,
        "the panel is at x=" + panel.absX + " after a rejected corner, want "
        + (W - PAD - HUD_W));
    // Let one sampling window close, so the BMP is the HUD as a user sees it --
    // with numbers and a sparkline, not the unsampled dashes.
    setTimeout(done, 400);
}

function done():void
{
    var p:FpsPanel = app.fpsPanel();
    check(p != null && p.sampled, "the re-shown panel never sampled a window");
    if (p != null) say("reshown fps " + p.fps);
    // (h) IT FOLLOWS THE STAGE, IT DOES NOT ECHO THE REQUEST. Half the frame rate,
    // half the number -- the one assertion a HUD that printed `stage.frameRate`
    // back (or a constant 60) cannot pass.
    stage.frameRate = 30;
    setTimeout(at30, 1000);
}

function at30():void
{
    var q:FpsPanel = app.fpsPanel();
    check(q != null && q.fps >= 20 && q.fps <= 40, "at stage.frameRate = 30 the HUD reads "
        + (q == null ? "nothing" : String(q.fps))
        + ", want 20..40 (an echo of the request would still say 60)");
    if (q != null) say("30Hz fps " + q.fps + " avg " + q.avgMs);
    stage.frameRate = 60;
    setTimeout(at60, 700);
}

function at60():void
{
    var r:FpsPanel = app.fpsPanel();
    if (r != null) say("back at 60Hz: " + r.fps);
    finish();
}

function finish():void
{
    var bd:BitmapData = frame();
    var lines:String = "";
    var root:UiNode = app.getRoot();
    if (root != null) lines = lines + "root " + rectOf(root) + "\n";
    var btn:UiNode = app.findByKey("btn");
    if (btn != null) lines = lines + "btn " + rectOf(btn) + "\n";
    var panel:UiNode = app.findByKey("fpsPanel");
    if (panel != null) lines = lines + "fps " + rectOf(panel) + "\n";
    writeText(OUT + ".rects.txt", lines);
    writeText(OUT + ".samples.txt", log);
    writeBmp(OUT + ".bmp", bd);
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
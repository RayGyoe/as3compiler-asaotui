// probes/widgets/reduced-motion -- the global reduced-motion PATH (2026-11-15).
//
// Output prefix MUST equal the directory name (`reduced-motion`).
//
// WHAT THIS PROVES (theme-tokens-vs-cui.md §2.4: "every animation has a
// reduced-motion path, and that path keeps the final state and the feedback"):
//   1. DEFAULT IS UNCHANGED. With Motion.reducedMotion=false a retarget with a real
//      duration STARTS a tween (isActive true, displayed value mid-flight).
//   2. TOGGLING ON MID-FLIGHT LANDS. Setting reducedMotion=true and advancing snaps
//      every live tween to its exact target (final state preserved, travel removed).
//   3. A FRESH CHANGE UNDER reduced-motion SNAPS. retarget writes the target into
//      `resolved` immediately and never arms a tween -- the feedback (the new colour)
//      is still there, only the interpolation is gone.
//   4. OVERLAY ENTRANCE/EXIT HONOUR IT. start() does not arm (isRunning false) and
//      startExit() returns false (caller hides immediately) when reducedMotion=true;
//      with it false and a running frame clock they arm as before.
//
// The checks drive the two static mechanisms (anim/Anim, OverlayMotion) directly on a
// mounted node, so they are deterministic and do not depend on frame timing beyond a
// running ENTER_FRAME clock for the overlay arm.
//
// Protocol (tools/probe.cjs): dir name == output prefix; write <OUT>.rects.txt,
// <OUT>.bmp, <OUT>.done (PASS | FAIL <reason>).
import asaot.ui.*;
import asaot.ui.anim.Anim;
import asaot.ui.anim.Motion;
import asaot.ui.style.StyleRefinement;
import flash.display.BitmapData;
import flash.display.Stage;
import flash.display.StageAlign;
import flash.display.StageScaleMode;
import flash.filesystem.File;
import flash.filesystem.FileMode;
import flash.filesystem.FileStream;
import flash.geom.Rectangle;
import flash.utils.ByteArray;
import flash.utils.getTimer;
import flash.utils.setTimeout;

var W:int = 200;
var H:int = 120;
var OUT:String = "reduced-motion";

var A:uint = 0xFF102030;
var B:uint = 0xFF405060;
var C:uint = 0xFF708090;
var curBg:uint = A;

var problems:String = "";
var log:String = "";

class RMProbe extends View
{
    override public function render():Node
    {
        return column({ key: "root", style: StyleRefinement.from({
            size: [200, 120], padding: 10, background: 0xFFFFFFFF }) }, [
            box({ key: "box", style: StyleRefinement.from({ size: [180, 100], background: curBg, transitionMs: 200 }) })
        ]);
    }
    public function RMProbe():void { super(); }
}

var view:RMProbe = new RMProbe();
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

setTimeout(run, 600);
stage.showWindow(W, H, "probe reduced-motion");

function say(s:String):void { log = log + s + String.fromCharCode(10); trace(s); }
function bad(s:String):void { problems = problems + s + "; "; }
function check(cond:Boolean, s:String):void { if (!cond) bad(s); }

function bgOf(n:UiNode):Number
{
    return n.resolved.background != null ? n.resolved.background.argb : NaN;
}

function run():void
{
    app.reflow();
    var n:UiNode = app.findByKey("box");
    if (n == null) { bad("no box node"); finish(); return; }

    // ---- 1. default still animates (drive the REAL resolve seam) --------
    Motion.reducedMotion = false;
    curBg = B;
    app.invalidate(Dirty.ALL);
    app.reflow();
    check(Anim.isActive(n), "default: a 200ms style change did not start a tween");
    check(bgOf(n) != B, "default: the displayed value already equals the target (no travel)");
    say("default: active=" + Anim.isActive(n) + " bg=" + bgOf(n));

    // ---- 2. toggling on mid-flight lands exactly on target --------------
    Motion.reducedMotion = true;
    Anim.advance(getTimer() + 50);
    Anim.advance(getTimer() + 51);   // second call reaps the landed tween
    check(!Anim.isActive(n), "reduced: a live tween survived advance (did not land)");
    check(bgOf(n) == B, "reduced: mid-flight snap left bg=" + bgOf(n) + ", want " + B);
    say("mid-flight snap: bg=" + bgOf(n));

    // ---- 3. a fresh change under reduced-motion snaps (and paints) ------
    curBg = C;
    app.invalidate(Dirty.ALL);
    app.reflow();
    check(!Anim.isActive(n), "reduced: a fresh retarget armed a tween (travel not removed)");
    check(bgOf(n) == C, "reduced: fresh retarget left bg=" + bgOf(n) + ", want " + C
        + " (final state must be preserved)");
    say("fresh snap: bg=" + bgOf(n));

    // ---- 4. overlay entrance / exit -------------------------------------
    if (app.enterFrameTicks > 0)
    {
        Motion.reducedMotion = true;
        OverlayMotion.cancelExit(n);
        OverlayMotion.start(n);
        check(!OverlayMotion.isRunning(n), "reduced: overlay entrance armed (should appear at final pose)");
        check(!OverlayMotion.startExit(n), "reduced: startExit should return false (hide immediately)");

        Motion.reducedMotion = false;
        OverlayMotion.start(n);
        check(OverlayMotion.isRunning(n), "default: overlay entrance did not arm with a running clock");
        check(OverlayMotion.startExit(n), "default: startExit did not arm with a running clock");
        OverlayMotion.cancelExit(n);
    }
    else
    {
        bad("no ENTER_FRAME clock; overlay arm untestable");
    }

    // leave the switch at the ship default so the bitmap is the settled scene
    Motion.reducedMotion = false;
    finish();
}

function finish():void
{
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    var keys:Array = ["root", "box"];
    var lines:String = "";
    for (var i:int = 0; i < keys.length; i++)
    {
        var n:UiNode = app.findByKey(String(keys[i]));
        if (n == null) { lines = lines + keys[i] + " MISSING" + String.fromCharCode(10); continue; }
        lines = lines + keys[i] + " " + n.absX + "," + n.absY + "," + n.absW + "," + n.absH + String.fromCharCode(10);
    }
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
            var o:int = (y * w + x) * 4;
            ba.writeByte(px[o + 3]);
            ba.writeByte(px[o + 2]);
            ba.writeByte(px[o + 1]);
            ba.writeByte(px[o]);
        }
    }
    var f:File = File.applicationDirectory.resolvePath(path);
    var fs:FileStream = new FileStream();
    fs.open(f, FileMode.WRITE);
    fs.writeBytes(ba);
    fs.close();
}
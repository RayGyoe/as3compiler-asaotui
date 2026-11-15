// probes/widgets/theme-transition -- the opt-in animated theme swap (A1, 2026-11-15).
//
// Output prefix MUST equal the directory name (`theme-transition`).
//
// WHAT THIS PROVES:
//   1. CIRCLE reveal is PROGRESSIVE: at begin the click point still shows the OLD
//      palette (radius 0); mid-flight progress is strictly between 0 and 1 and the
//      click point has flipped to the NEW palette; at end the transition is gone and
//      the whole window is the NEW palette.
//   2. FADE: old covers at begin (alpha 1), new shows at end (alpha 0).
//   3. SWEEP: the left edge reveals before the right edge.
//   4. REDUCED MOTION collapses setThemeAnimated to the instant swap (active false,
//      new palette immediately) -- no animation behind the accessibility switch.
//   5. The plain Theme.setTheme path never arms a transition.
//
// The reveal is driven by the REAL ENTER_FRAME clock (setTimeout phases), and the
// progressive claim is pinned by the eased `themeTransitionProgress` getter rather
// than by pixel-perfect frame timing.
//
// Protocol (tools/probe.cjs): dir name == output prefix; write <OUT>.rects.txt,
// <OUT>.bmp, <OUT>.done (PASS | FAIL <reason>).
import asaot.ui.*;
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
import flash.utils.setTimeout;

var W:int = 240;
var H:int = 160;
var OUT:String = "theme-transition";

// Two witness points: P1 inside the button fill (left of the centred label), P2 on
// the root surface below the button. Both are palette-driven, so both flip with the
// theme and can witness a reveal.
var P1X:int = 35; var P1Y:int = 40;
var P2X:int = 220; var P2Y:int = 140;

var LIGHT_CTRL:uint = 0xF1F3F5;
var DARK_CTRL:uint = 0x1F2937;
var LIGHT_SURF:uint = 0xFFFFFF;
var DARK_SURF:uint = 0x111827;

var problems:String = "";
var log:String = "";

class TTProbe extends View
{
    override public function render():Node
    {
        var pal:ThemeTokens = Theme.tokens();
        return column({ key: "root", style: StyleRefinement.from({
            size: [240, 160], padding: 20, background: pal.surface }) }, [
            button({ key: "btn", label: "Theme", style: StyleRefinement.from({ size: [200, 60] }) })
        ]);
    }
    public function TTProbe():void { super(); }
}

var view:TTProbe = new TTProbe();
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

setTimeout(ready, 600);
stage.showWindow(W, H, "probe theme-transition");

function say(s:String):void { log = log + s + String.fromCharCode(10); trace(s); }
function bad(s:String):void { problems = problems + s + "; "; }
function check(cond:Boolean, s:String):void { if (!cond) bad(s); }

function pixel(x:int, y:int):uint
{
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    var c:uint = bd.getPixel(x, y);
    bd.dispose();
    return c;
}
function hex(c:uint):String { return "0x" + c.toString(16); }

function ready():void
{
    Motion.reducedMotion = false;
    Theme.setTheme(ThemeTokens.light());
    app.invalidate(Dirty.ALL);
    app.reflow();
    check(pixel(P1X, P1Y) == LIGHT_CTRL, "baseline: button fill is not light controlSurface (got " + hex(pixel(P1X, P1Y)) + ")");
    check(!app.themeTransitionActive, "plain setTheme armed a transition");

    // ---- 1. circle reveal ------------------------------------------------
    app.setThemeAnimated(ThemeTokens.dark(), { type: "circle", ms: 600, originX: P1X, originY: P1Y });
    check(app.themeTransitionActive, "circle: transition did not arm");
    check(app.themeTransitionProgress == 0, "circle: progress not 0 at begin");
    check(pixel(P1X, P1Y) == LIGHT_CTRL, "circle: click point already new at begin (radius must be 0)");
    say("circle begin: active=" + app.themeTransitionActive + " p=" + app.themeTransitionProgress + " P1=" + hex(pixel(P1X, P1Y)));
    setTimeout(circleMid, 150);
}

function circleMid():void
{
    var p:Number = app.themeTransitionProgress;
    check(app.themeTransitionActive, "circle: ended too early (mid still active)");
    check(p > 0.05 && p < 0.95, "circle: mid progress not strictly between 0 and 1 (p=" + p + ")");
    check(pixel(P1X, P1Y) == DARK_CTRL, "circle: click point not revealed mid-flight (got " + hex(pixel(P1X, P1Y)) + ")");
    say("circle mid: p=" + p + " P1=" + hex(pixel(P1X, P1Y)));
    setTimeout(circleEnd, 700);
}

function circleEnd():void
{
    check(!app.themeTransitionActive, "circle: still active after ms elapsed");
    check(pixel(P1X, P1Y) == DARK_CTRL, "circle: button not dark at end");
    check(pixel(P2X, P2Y) == DARK_SURF, "circle: root surface not dark at end (got " + hex(pixel(P2X, P2Y)) + ")");
    say("circle end: P1=" + hex(pixel(P1X, P1Y)) + " P2=" + hex(pixel(P2X, P2Y)));

    // ---- 2. fade back to light -------------------------------------------
    app.setThemeAnimated(ThemeTokens.light(), { type: "fade", ms: 600 });
    check(app.themeTransitionActive, "fade: did not arm");
    check(pixel(P1X, P1Y) == DARK_CTRL, "fade: old (dark) must cover at begin");
    setTimeout(fadeMid, 150);
}

function fadeMid():void
{
    var p:Number = app.themeTransitionProgress;
    var c:uint = pixel(P1X, P1Y);
    check(app.themeTransitionActive, "fade: ended too early");
    check(p > 0.05 && p < 0.95, "fade: mid progress not in (0,1) (p=" + p + ")");
    // The old overlay is partially transparent, so the witness must be a BLEND of
    // dark and light -- neither endpoint. A fade whose alpha never falls stays pure
    // dark here (and only "looks" fine at the end because the layer is removed).
    check(c != DARK_CTRL && c != LIGHT_CTRL, "fade: mid pixel is not a blend (got " + hex(c) + "; alpha never fell)");
    say("fade mid: p=" + p + " P1=" + hex(c));
    setTimeout(fadeEnd, 700);
}

function fadeEnd():void
{
    check(!app.themeTransitionActive, "fade: still active after ms");
    check(pixel(P1X, P1Y) == LIGHT_CTRL, "fade: not light at end (got " + hex(pixel(P1X, P1Y)) + ")");
    say("fade end: P1=" + hex(pixel(P1X, P1Y)));

    // ---- 3. sweep left -> right ------------------------------------------
    app.setThemeAnimated(ThemeTokens.dark(), { type: "sweep", ms: 600 });
    check(app.themeTransitionActive, "sweep: did not arm");
    check(pixel(P1X, P1Y) == LIGHT_CTRL, "sweep: left edge already new at begin (rect must be 0)");
    setTimeout(sweepMid, 150);
}

function sweepMid():void
{
    var p:Number = app.themeTransitionProgress;
    check(app.themeTransitionActive, "sweep: ended too early");
    check(p > 0.05 && p < 0.95, "sweep: mid progress not in (0,1) (p=" + p + ")");
    check(pixel(P1X, P1Y) == DARK_CTRL, "sweep: left edge not revealed mid-flight");
    say("sweep mid: p=" + p + " P1=" + hex(pixel(P1X, P1Y)));
    setTimeout(sweepEnd, 700);
}

function sweepEnd():void
{
    check(!app.themeTransitionActive, "sweep: still active after ms");
    check(pixel(P2X, P2Y) == DARK_SURF, "sweep: right edge not dark at end");
    say("sweep end: P2=" + hex(pixel(P2X, P2Y)));

    // ---- 4. reduced motion collapses to the instant swap -----------------
    Motion.reducedMotion = true;
    app.setThemeAnimated(ThemeTokens.light(), { type: "circle", ms: 600, originX: P1X, originY: P1Y });
    check(!app.themeTransitionActive, "reduced: setThemeAnimated still animated (must be instant)");
    check(pixel(P1X, P1Y) == LIGHT_CTRL, "reduced: not light immediately after the instant swap");
    Motion.reducedMotion = false;
    say("reduced: instant light, active=" + app.themeTransitionActive);

    // leave the settled scene LIGHT for the bitmap
    app.invalidate(Dirty.ALL);
    app.reflow();
    finish();
}

function finish():void
{
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    var keys:Array = ["root", "btn"];
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
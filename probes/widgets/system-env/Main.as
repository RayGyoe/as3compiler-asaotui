// probes/widgets/system-env -- follow the system appearance / reduced-motion (A2).
//
// Output prefix MUST equal the directory name (`system-env`).
//
// WHAT THIS PROVES (Env.isDark / Env.reduceMotion were DELIVERED but not consumed):
//   1. DEFAULT OFF: with followSystem=false, an Env dark/reduceMotion change touches
//      neither the palette nor Motion.reducedMotion -- the author still owns both.
//   2. FOLLOW ON: setFollowSystem(true) makes Env.isDark drive Theme (light<->dark)
//      and Env.reduceMotion drive Motion.reducedMotion, each honoured on the next
//      frame without the app calling back.
//   3. FOLLOW OFF AGAIN: turning it off hands control back to the author.
//
// The fold is latched and runs at a frame boundary (UiApp.onEnterFrame), so each Env
// write below is followed by a real-frame wait before it is asserted.
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
var OUT:String = "system-env";
var P1X:int = 35; var P1Y:int = 40;
var LIGHT_CTRL:uint = 0xF1F3F5;
var DARK_CTRL:uint = 0x1F2937;

var problems:String = "";
var log:String = "";
var fake:EnvBase;

class SEProbe extends View
{
    override public function render():Node
    {
        var pal:ThemeTokens = Theme.tokens();
        return column({ key: "root", style: StyleRefinement.from({
            size: [240, 160], padding: 20, background: pal.surface }) }, [
            button({ key: "btn", label: "Theme", style: StyleRefinement.from({ size: [200, 60] }) })
        ]);
    }
    public function SEProbe():void { super(); }
}

var view:SEProbe = new SEProbe();
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();
fake = new EnvBase();
app.bindEnv(fake);

setTimeout(ready, 600);
stage.showWindow(W, H, "probe system-env");

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
function isDarkNow():Boolean { return Theme.isTheme(ThemeTokens.dark()); }

function ready():void
{
    Motion.reducedMotion = false;
    Theme.setTheme(ThemeTokens.light());
    app.invalidate(Dirty.ALL);
    app.reflow();
    check(!app.followSystem, "followSystem should default to false");
    // ---- 1. default off: Env changes touch nothing -----------------------
    fake.setDark(true);
    fake.setReduceMotion(true);
    setTimeout(p1, 120);
}

function p1():void
{
    check(!isDarkNow(), "follow OFF: Env.isDark=true changed the palette");
    check(pixel(P1X, P1Y) == LIGHT_CTRL, "follow OFF: button went dark (got " + hex(pixel(P1X, P1Y)) + ")");
    check(!Motion.reducedMotion, "follow OFF: Env.reduceMotion=true changed Motion");
    say("off: dark=" + isDarkNow() + " reduced=" + Motion.reducedMotion);
    fake.setDark(false);
    fake.setReduceMotion(false);
    app.setFollowSystem(true);
    setTimeout(p2, 120);
}

function p2():void
{
    check(app.followSystem, "setFollowSystem(true) did not stick");
    check(!isDarkNow(), "follow ON: should still be light (Env is light)");
    check(!Motion.reducedMotion, "follow ON: should still be full motion (Env false)");
    fake.setDark(true);
    setTimeout(p3, 120);
}

function p3():void
{
    check(isDarkNow(), "follow ON: Env.isDark=true did not switch to dark");
    check(pixel(P1X, P1Y) == DARK_CTRL, "follow ON: button not dark (got " + hex(pixel(P1X, P1Y)) + ")");
    say("on dark: P1=" + hex(pixel(P1X, P1Y)));
    fake.setReduceMotion(true);
    setTimeout(p4, 120);
}

function p4():void
{
    check(Motion.reducedMotion, "follow ON: Env.reduceMotion=true did not set Motion");
    fake.setReduceMotion(false);
    setTimeout(p5, 120);
}

function p5():void
{
    check(!Motion.reducedMotion, "follow ON: Env.reduceMotion=false did not clear Motion");
    fake.setDark(false);
    setTimeout(p6, 120);
}

function p6():void
{
    check(!isDarkNow(), "follow ON: Env.isDark=false did not switch back to light");
    check(pixel(P1X, P1Y) == LIGHT_CTRL, "follow ON: button not light again (got " + hex(pixel(P1X, P1Y)) + ")");
    say("on light: P1=" + hex(pixel(P1X, P1Y)));
    app.setFollowSystem(false);
    fake.setDark(true);
    setTimeout(p7, 120);
}

function p7():void
{
    check(!isDarkNow(), "follow OFF again: Env.isDark=true changed the palette");
    check(!Motion.reducedMotion, "follow OFF again: Motion disturbed");
    fake.setDark(false);
    Motion.reducedMotion = false;
    app.invalidate(Dirty.ALL);
    app.reflow();
    say("off again: dark=" + isDarkNow());
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
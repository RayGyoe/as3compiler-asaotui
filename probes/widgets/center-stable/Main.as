// probes/widgets/center-stable -- a centred demo row must not slide when its
// readout label changes width (2026-11-15).
//
// Output prefix MUST equal the directory name (`center-stable`).
//
// THE BUG THIS PINS: the docs demo boxes are columns with alignItems:center, which
// centres their content on the HORIZONTAL axis. The "Theme swap" row ends in a
// readout whose text changes with the swap ("light · idle" / "dark · running" /
// "dark · idle"). A readout sized to its text makes the whole row wider/narrower as
// the label changes, so the centred row -- and the Fade/Circle/Sweep buttons in it
// -- slides left/right mid-swap (the reported "jitter"). Pinning the readout to a
// FIXED width keeps the row width constant, so the centred row never moves.
//
// WHAT THIS PROVES (drives the REAL layout seam, no frame timing):
//   1. SENSITIVE: with a text-sized readout, changing the label MOVES the button
//      (|dx| > 1px). If this ever stops moving, the probe has lost its teeth.
//   2. FIXED: with a fixed-width readout slot, the same label changes leave the
//      button exactly where it was (|dx| < 0.5px) for every label.
//
// The settled bitmap is the fixed-width row carrying the LONGEST label
// ("light · running"), so a clipped readout would also be visible there.
//
// Protocol (tools/probe.cjs): dir name == output prefix; write <OUT>.rects.txt,
// <OUT>.bmp, <OUT>.done (PASS | FAIL <reason>).
import asaot.ui.*;
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

var W:int = 400;
var H:int = 200;
var OUT:String = "center-stable";

var fixed:Boolean = true;
var label:String = "light · running";

var problems:String = "";
var log:String = "";

class CSProbe extends View
{
    override public function render():Node
    {
        var rs:StyleRefinement = StyleRefinement.from({
            text: { fontFamily: "Courier New", fontSize: 11, color: 0x64748B } });
        if (fixed)
        {
            rs = rs.withPatch(StyleRefinement.from({ size: [Length.px(110), Length.px(14)] }));
        }
        // A column with alignItems:center centres the row HORIZONTALLY -- exactly
        // the docs DEMO box. The row itself only centres its children vertically.
        return column({ key: "root", style: StyleRefinement.from({
            size: [400, 200], padding: 12, background: 0xFFFFFF,
            flexDirection: "column", alignItems: "center" }) }, [
            row({ key: "row", style: StyleRefinement.from({ gap: 12, alignItems: "center" }) }, [
                box({ key: "sw", style: StyleRefinement.from({ size: [96, 44], background: 0xF1F3F5 }) }, []),
                box({ key: "btn", style: StyleRefinement.from({ size: [128, 36], background: 0x2563EB }) }, []),
                text(label, { key: "readout", style: rs, ariaName: "" })
            ])
        ]);
    }
    public function CSProbe():void { super(); }
}

var view:CSProbe = new CSProbe();
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

setTimeout(run, 400);
stage.showWindow(W, H, "probe center-stable");

function bad(s:String):void { problems = problems + s + "; "; }
function check(cond:Boolean, s:String):void { if (!cond) bad(s); }
function say(s:String):void { log = log + s + String.fromCharCode(10); trace(s); }

function btnX():Number
{
    var n:UiNode = app.findByKey("btn");
    return n == null ? NaN : n.absX;
}

function setLabel(s:String):void
{
    label = s;
    app.invalidate(Dirty.ALL);
    app.reflow();
}

function run():void
{
    app.reflow();

    // ---- 1. SENSITIVE: a text-sized readout slides the centred row --------
    fixed = false;
    setLabel("light · idle");
    var v1:Number = btnX();
    setLabel("dark · running");
    var v2:Number = btnX();
    check(Math.abs(v1 - v2) > 1, "sensitive: text-sized readout did NOT move the button (dx="
        + (v1 - v2) + "); the probe lost its teeth");
    say("variable: x(light·idle)=" + v1 + " x(dark·running)=" + v2 + " dx=" + (v1 - v2));

    // ---- 2. FIXED: a pinned readout slot keeps the button put -------------
    fixed = true;
    setLabel("light · idle");
    var f1:Number = btnX();
    setLabel("dark · running");
    var f2:Number = btnX();
    setLabel("light · running");
    var f3:Number = btnX();
    check(Math.abs(f1 - f2) < 0.5, "fixed: button moved between idle/running (dx=" + (f1 - f2) + ")");
    check(Math.abs(f1 - f3) < 0.5, "fixed: button moved to the longest label (dx=" + (f1 - f3) + ")");
    say("fixed: x(light·idle)=" + f1 + " x(dark·running)=" + f2 + " x(light·running)=" + f3);

    // leave the longest label in the fixed slot for the settled bitmap
    fixed = true;
    label = "light · running";
    app.invalidate(Dirty.ALL);
    app.reflow();
    finish();
}

function finish():void
{
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    var keys:Array = ["root", "sw", "btn", "readout"];
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
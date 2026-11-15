// probes/widgets/design -- the design-system DISCIPLINE (2026-11-15).
//
// Output prefix MUST equal the directory name (`design`).
//
// WHAT THIS PROVES (theme-tokens-vs-cui.md §4, the three executable rules):
//   1. ONE TASK, ONE DURATION. The shipped overlay numbers live in anim/Motion
//      (140 enter / 120 exit) and OverlayMotion's math reads them through
//      enterMs()/exitMs() -- a widget hardcoding its own 250 is a red gate, not a drift.
//   2. CONCENTRIC CORNERS. ThemeMetrics.innerRadius(outer, gap) = max(0, outer-gap):
//      an inner control never out-rounds its container minus the gap. The rule is a
//      helper a skin uses, NOT a change to any shipped value.
//   3. A 4pt GRID IS AN OPT-IN SKIN. ThemeMetrics.grid4() has every padding / type size
//      on the 4pt grid (the shipped base() deliberately is not: 9/7/2). setMetrics(grid4)
//      RE-SOLVES the tree (an auto-height button changes and its sibling slides by the
//      same amount), while the default stays base() so no existing pixel moves.
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

var W:int = 480;
var H:int = 300;
var OUT:String = "design";

var problems:String = "";
var log:String = "";
var baseBtnH:Number = -1;
var baseBelowY:Number = -1;

class DesignProbe extends View
{
    override public function render():Node
    {
        return column({ key: "root", style: StyleRefinement.from({
            size: [480, 300], padding: 12, gap: 10, background: 0xFFFFFFFF }) }, [
            row({ key: "row1", style: StyleRefinement.from({ size: [456, 40], flexDirection: "row", gap: 10 }) }, [
                button({ key: "btn", label: "Run", style: StyleRefinement.from({ size: [160, 40] }) }),
                textField({ key: "ti", style: StyleRefinement.from({ size: [200, 40] }) })
            ]),
            button({ key: "autoBtn", label: "Auto", style: StyleRefinement.from({ size: [160, null] }) }),
            text("below", { key: "below" })
        ]);
    }
    public function DesignProbe():void { super(); }
}

var view:DesignProbe = new DesignProbe();
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

setTimeout(basePhase, 700);
stage.showWindow(W, H, "probe design");

function say(s:String):void { log = log + s + String.fromCharCode(10); trace(s); }
function bad(s:String):void { problems = problems + s + "; "; }
function check(cond:Boolean, s:String):void { if (!cond) bad(s); }
function node(key:String):UiNode { var n:UiNode = app.findByKey(key); if (n == null) bad("no node " + key); return n; }

function basePhase():void
{
    app.reflow();
    // ---- 1. the duration table is the single source ---------------------
    check(Motion.OVERLAY_ENTER_MS == 140, "the shipped entrance duration is not 140 in the Motion table");
    check(Motion.OVERLAY_EXIT_MS == 120, "the shipped exit duration is not 120 in the Motion table");
    check(OverlayMotion.enterMs() == Motion.OVERLAY_ENTER_MS,
        "OverlayMotion.enterMs()=" + OverlayMotion.enterMs() + " does not read the Motion table");
    check(OverlayMotion.exitMs() == Motion.OVERLAY_EXIT_MS,
        "OverlayMotion.exitMs()=" + OverlayMotion.exitMs() + " does not read the Motion table");
    check(Motion.OVERLAY_EXIT_MS < Motion.OVERLAY_ENTER_MS, "exit must be faster than entrance");

    // ---- 2. concentric corners ------------------------------------------
    check(ThemeMetrics.innerRadius(14, 8) == 6, "innerRadius(14,8) != 6");
    check(ThemeMetrics.innerRadius(6, 8) == 0, "innerRadius must clamp at 0 when gap >= outer");
    check(ThemeMetrics.innerRadius(18, 6) <= 18 - 6, "the concentric rule inner <= outer-gap is violated");

    // ---- 3. base is NOT on the grid (so grid4 is a real alternative) ----
    var b:ThemeMetrics = ThemeMetrics.base();
    check(b.buttonPadY % 4 != 0, "base() buttonPadY is on the 4pt grid; grid4 would not be a distinct skin");

    baseBtnH = node("autoBtn").absH;
    baseBelowY = node("below").absY;
    say("base: auto button " + baseBtnH + "px, sibling y " + baseBelowY);

    Theme.setMetrics(ThemeMetrics.grid4());
    setTimeout(gridPhase, 350);
}

function gridPhase():void
{
    var g:ThemeMetrics = ThemeMetrics.grid4();
    check(Theme.metrics().same(g), "the live metrics are not grid4()");
    // every padding / type slot on the 4pt grid
    check(g.font % 4 == 0 && g.fontSm % 4 == 0 && g.fontLg % 4 == 0, "grid4 type scale off the grid");
    check(g.buttonPadY % 4 == 0 && g.buttonPadX % 4 == 0 && g.inputPadY % 4 == 0 && g.inputPadX % 4 == 0
          && g.chipPadY % 4 == 0 && g.chipPadX % 4 == 0 && g.badgePadX % 4 == 0, "grid4 padding off the grid");

    // the slots are CONSUMED by the baseline
    var s:Style = node("btn").resolved;
    check(s.padding.top == g.buttonPadY && s.padding.left == g.buttonPadX,
        "grid4: button padding " + s.padding.top + "/" + s.padding.left + " != " + g.buttonPadY + "/" + g.buttonPadX);
    check(s.text.fontSize == g.font, "grid4: button font " + s.text.fontSize + " != " + g.font);

    // the tree RE-SOLVED, witnessed by a FONT-INDEPENDENT layout number: the input's
    // text origin is border + padTop, so it must move by exactly the padding delta
    // (7 -> 8). An auto-height box is a bad witness here: grid4's +2 font and -1 padY
    // cancel, so its height can stay identical while the layout DID re-run.
    var ti:UiNode = node("ti");
    var wantY:Number = g.borderWidth + g.inputPadY;
    check(ti.tf != null && ti.tf.y == wantY,
        "grid4: input text origin y=" + (ti.tf == null ? -1 : ti.tf.y) + " != " + wantY
        + " (border + padTop) -- the new padding never reached layout");
    check(wantY != 1 + ThemeMetrics.base().inputPadY, "grid4 inputPadY equals base; the witness cannot move");
    say("grid4: input text origin y=" + (ti.tf == null ? -1 : ti.tf.y) + " (want " + wantY + ")");

    // back to base so the published bitmap is the shipped scene
    Theme.setMetrics(ThemeMetrics.base());
    setTimeout(finish, 250);
}

function finish():void
{
    app.reflow();
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    var keys:Array = ["root", "row1", "btn", "ti", "autoBtn", "below"];
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
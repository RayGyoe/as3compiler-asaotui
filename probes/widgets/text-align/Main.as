// probes/widgets/text-align/Main.as -- `textAlign` ON A RUN THAT DOES NOT WRAP.
//
// Output prefix MUST equal the directory name (`text-align`).
//
// WHAT WAS BROKEN: a text node's field is created with `autoSize = "left"`, so it is
// exactly as wide as its run. `textAlign` is then resolved into the TextFormat and
// the field has no slack to move the line within, so the alignment was silently a
// no-op: a 160pt right-aligned node painted its run at x 5..30, and the tab bar's
// centred labels sat at the LEFT edge of their cells (reported as "why isn't the
// tabbar text horizontally centred?"). Only a WRAPPED node ever got a field wider
// than its run. kit/asaot/ui/kind/TextWidget.as now lines the run up inside the
// content box in `arrange`, the same idiom PaintKit.centerText uses.
//
// WHAT IS BEING MEASURED, in pixels (a rect check cannot see this: the box is right
// in every failing case; the RUN is what moves):
//
//   * left     -- the run starts at the box's left edge (the control: unchanged);
//   * center   -- the run's ink centre is the box's centre;
//   * right    -- the run's ink ends at the box's right edge inside;
//   * the three runs are the SAME WIDTH (one string, three boxes), so the three
//     positions really are positions and not three differently-shaped runs;
//   * the shift is large, not a rounding artefact.
//
// Hand arithmetic (window 240x120, root column, white, padding 10, gap 6, three
// 160x17 nodes):
//
//   root         (0,0,240,120)
//   l  (10,10,160,17)    box centre 90, box right 170 -- ink LEFT  of ~20
//   c  (10,33,160,17)    ink centre 90 +/- 1.5
//   r  (10,56,160,17)    ink RIGHT of ~164
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

var W:int = 240;
var H:int = 120;
var OUT:String = "text-align";
var LABEL:String = "Hamburg";
var BOX_W:Number = 160;
var BOX_H:Number = 17;

class AlignView extends View
{
    private static const ROOT:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", alignItems: "flex-start", gap: 6,
        size: [240, 120], padding: 10, background: 0xFFFFFF
    });

    public function AlignView():void { super(); }

    private function line(al:String):StyleRefinement
    {
        return StyleRefinement.from({
            size: [Length.px(BOX_W), Length.px(BOX_H)],
            text: { fontSize: 13, color: 0x111111, textAlign: al }
        });
    }

    override public function render():Node
    {
        return column({ key: "root", style: ROOT }, [
            text(LABEL, { key: "l", style: line("left") }),
            text(LABEL, { key: "c", style: line("center") }),
            text(LABEL, { key: "r", style: line("right") })
        ]);
    }
}

var view:AlignView = new AlignView();
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

var problems:String = "";
var log:String = "";
var checks:int = 0;

function say(s:String):void { log = log + s + "\n"; }

function fail(s:String):void
{
    problems = problems + s + "; ";
    say("FAIL " + s);
}

function check(cond:Boolean, s:String):void
{
    checks = checks + 1;
    if (!cond) fail(s); else say("ok " + s);
}

function frame():BitmapData
{
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    return bd;
}

function rgbAt(bd:BitmapData, x:int, y:int):uint
{
    if (x < 0 || y < 0 || x >= W || y >= H) return 0;
    return bd.getPixel(x, y) & 0xFFFFFF;
}

function hex(c:uint):String
{
    var s:String = c.toString(16).toUpperCase();
    while (s.length < 6) s = "0" + s;
    return "#" + s;
}

function node(k:String):UiNode
{
    return app.findByKey(k);
}

function rectOf(n:UiNode):String
{
    return n.absX + "," + n.absY + "," + n.absW + "," + n.absH;
}

function want(what:String, n:UiNode, x:Number, y:Number, w:Number, h:Number):void
{
    if (n == null) { fail(what + " is missing"); return; }
    if (n.absX != x || n.absY != y || n.absW != w || n.absH != h)
        fail(what + " is " + rectOf(n) + " not " + x + "," + y + "," + w + "," + h);
}

// The ink extent of a row, clipped to the node's own box: the background is white,
// so any non-white pixel is a glyph pixel. Returns [lo, hi] or null when the row is
// blank (which is a failure -- a blank row would make every assertion vacuous).
function ink(bd:BitmapData, n:UiNode):Array
{
    var y:int = int(n.absY + n.absH / 2);
    var x0:int = int(n.absX);
    var x1:int = int(n.absX + n.absW) - 1;
    var lo:int = -1;
    var hi:int = -1;
    for (var x:int = x0; x <= x1; x++)
    {
        if (rgbAt(bd, x, y) != 0xFFFFFF) { if (lo < 0) lo = x; hi = x; }
    }
    return (lo < 0) ? null : [lo, hi];
}

setTimeout(ready, 900);
stage.showWindow(W, H, "probe text-align");

function ready():void
{
    var l:UiNode = node("l");
    var c:UiNode = node("c");
    var r:UiNode = node("r");
    if (l == null || c == null || r == null) { fail("a line never mounted"); finish(); return; }

    // The boxes: three identical rows, so any difference below is the RUN's position.
    want("l", l, 10, 10, 160, 17);
    want("c", c, 10, 33, 160, 17);
    want("r", r, 10, 56, 160, 17);

    var bd:BitmapData = frame();
    var il:Array = ink(bd, l);
    var ic:Array = ink(bd, c);
    var ir:Array = ink(bd, r);
    if (il == null || ic == null || ir == null) { fail("a line painted no ink"); finish(); return; }

    var loL:int = int(il[0]), hiL:int = int(il[1]);
    var loC:int = int(ic[0]), hiC:int = int(ic[1]);
    var loR:int = int(ir[0]), hiR:int = int(ir[1]);

    // ONE STRING, THREE RUNS: the widths must agree, otherwise the three positions
    // below are not comparable and the probe proves nothing. Tolerance 2px: the ink
    // is sampled at WHOLE pixels while the run's origin is fractional (the centred
    // one starts at a half-pixel of slack), so an edge can gain or lose a pixel.
    var wL:int = hiL - loL, wC:int = hiC - loC, wR:int = hiR - loR;
    check(Math.abs(wL - wC) <= 2 && Math.abs(wC - wR) <= 2,
        "the three runs are " + wL + "/" + wC + "/" + wR
        + "px wide -- they hold one string, so the widths must agree");

    // (1) LEFT is the control: the run starts at the box's left edge. Ink starts a
    // couple of pixels in (the field sits at -2, the glyph's own side bearing).
    check(loL >= 10 && loL <= 22, "the left-aligned run starts at x=" + loL
        + ", want 10..22 (the box's left edge)");

    // (2) CENTRE: ink centre == box centre (10 + 160/2 = 90).
    var centreC:Number = (loC + hiC) / 2;
    check(Math.abs(centreC - 90) <= 1.5, "the centred run's ink centre is " + centreC
        + ", want 90 (the box's centre)");

    // (3) RIGHT: ink ends at the box's right edge inside (170), give or take the
    // glyph's own bearing.
    check(hiR >= 164 && hiR <= 170, "the right-aligned run ends at x=" + hiR
        + ", want 164..170 (the box's right edge)");

    // (4) THE SHIFT IS REAL: if a future change collapsed the three into the same
    // place, (2) and (3) would have to be wrong -- but state it, so a probe that
    // silently stopped measuring (e.g. one node) cannot pass.
    check(centreC - (loL + hiL) / 2 > 40,
        "the centred run sits only " + (centreC - (loL + hiL) / 2)
        + "px right of the left-aligned one -- the two boxes are 160 wide");

    say("ink l=" + loL + ".." + hiL + " c=" + loC + ".." + hiC + " r=" + loR + ".." + hiR);
    finish();
}

function finish():void
{
    say("checks " + checks + " problems [" + problems + "]");
    var bd:BitmapData = frame();
    var names:Array = ["root", "l", "c", "r"];
    var lines:String = "";
    for (var i:int = 0; i < names.length; i++)
    {
        var n:UiNode = app.findByKey(names[i]);
        if (n == null) { lines = lines + names[i] + " MISSING\n"; continue; }
        lines = lines + names[i] + " " + rectOf(n) + "\n";
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
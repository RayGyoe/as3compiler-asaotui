// probes/widgets/icon/Main.as -- the icon channel: SVG path data drawn by ONE Shape,
// and the exact refusals that keep it honest.
//
// Output prefix MUST equal the directory name (`icon`).
//
// WHY THIS NEEDS ITS OWN PROBE. Three things an icon can get wrong and no rectangle
// assertion can see:
//
//   1. THE CURVE. Most icon data is CUBIC (`C`), and the engine has only a QUADRATIC
//      `curveTo` (compiler-gaps.md G26), so the widget converts. `expect.json` samples
//      the cubic's OWN t = 0.5 point -- the one point the first subdivision split lands
//      on exactly -- so a chord masquerading as a curve shows up as a missing pixel.
//   2. THE SCALE. A stroke width is authored in VIEWBOX units, so it must be multiplied
//      by the render scale: the same glyph at 48 and at 24 has a 4px and a 2px outline,
//      and a 12-viewBox glyph at 48 has an 8px one. All three are pixels in expect.json.
//   3. THE REFUSALS. `A` (arc) and unknown commands must THROW rather than approximate,
//      and `icon()` must refuse at DESCRIBE time rather than inside a paint pass. A
//      probe that only draws good data cannot see a silent fallback, so this file drives
//      both through try/catch and checks the message.
//
// The pixels and the rects live in expect.json (hand-computed, see its comment); the
// structural half -- implicit repeats, relative commands, the S/T reflection rules, the
// three refusals -- lives here, because a raster cannot show which commands were parsed.
//
// WHERE THE PIXELS COME FROM (hand-computed before the run; window 300x240):
//   root padding 12, gap 12, alignItems flex-start, row gap 12.
//   row 1 at y = 12, row 2 at y = 12 + 48 + 12 = 72.
//   sq  (12,12,48,48) "M4 12 H20"  scale 2 -> y = 12 + 24 = 36, stroke 2*2 = 4 -> rows 34..37
//   cu  (72,12,48,48) "M2 2 C2 22 22 22 22 2"  cubic t=0.5 -> (12,17) -> (96,46), stroke 4
//   qd  (132,12,48,48) "M2 22 Q12 2 22 22"    quad t=0.5 -> (12,12) -> (156,36), stroke 4
//   fl  (192,12,48,48) "M12 2 L22 22 L2 22 Z" filled: (12,16) inside -> (216,44);
//                      (5,6) outside (the edges at y=6 are x 10..14) -> (202,24) white
//   df  (252,12,24,24) no size -> the viewBox (24), scale 1 -> y = 12 + 12 = 24, stroke 2
//   st  (12,72,48,48)  strokeWidth 6 -> 12px: y = 72 + 24 = 96, rows 90..101
//   vb12(72,72,48,48)  viewBox 12 -> scale 4: y = 72 + 6*4 = 96, stroke 2*4 = 8 -> rows 92..99
//   col2(132,72,48,48) same as sq but #DC2626 -> (156,96)
import asaot.ui.*;
import asaot.ui.style.*;
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

// The path data is written HERE, as literal icon-file strings, because that is exactly
// how an author uses the channel -- and because data derived from the widget's own
// output would be the probe grading its own homework.
var P_LINE:String = "M4 12 H20";
var P_CUBIC:String = "M2 2 C2 22 22 22 22 2";
var P_QUAD:String = "M2 22 Q12 2 22 22";
var P_TRI:String = "M12 2 L22 22 L2 22 Z";
var P_SMALL:String = "M2 6 H10";

var W:int = 300;
var H:int = 240;
var OUT:String = "icon";

var BLUE:uint = 0x2563EB;
var RED:uint = 0xDC2626;

var failures:String = "";

class IconProbe extends View
{
    private static const ROOT:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", alignItems: "flex-start",
        padding: 12, gap: 12, size: [300, 240],
        background: 0xFFFFFF, text: { fontSize: 12, color: 0x111827 }
    });
    private static const ROW:StyleRefinement = StyleRefinement.from({
        flexDirection: "row", gap: 12, alignItems: "flex-start"
    });
    private static const BOX:StyleRefinement = StyleRefinement.from({ size: [48, 48] });

    public function IconProbe():void
    {
        super();
    }

    override public function render():Node
    {
        var sq:Node = icon(P_LINE, { key: "sq", style: BOX, strokeWidth: 2, color: BLUE });
        var cu:Node = icon(P_CUBIC, { key: "cu", style: BOX, strokeWidth: 2, color: BLUE });
        var qd:Node = icon(P_QUAD, { key: "qd", style: BOX, strokeWidth: 2, color: BLUE });
        var fl:Node = icon(P_TRI, { key: "fl", style: BOX, fill: true, stroke: false, color: BLUE });
        // No size at all: the intrinsic box must be the viewBox itself.
        var df:Node = icon(P_LINE, { key: "df", strokeWidth: 2, color: BLUE });

        var st:Node = icon(P_LINE, { key: "st", style: BOX, strokeWidth: 6, color: BLUE });
        var vb:Node = icon(P_SMALL, { key: "vb12", style: BOX, viewBox: 12, strokeWidth: 2, color: BLUE });
        var c2:Node = icon(P_LINE, { key: "col2", style: BOX, strokeWidth: 2, color: RED });

        return column({ key: "root", style: ROOT, ariaName: "icon probe" }, [
            row({ key: "r1", style: ROW }, [sq, cu, qd, fl, df]),
            row({ key: "r2", style: ROW }, [st, vb, c2])
        ]);
    }
}

var view:IconProbe = new IconProbe();
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

// DECLARED BEFORE showWindow: a file-scope initializer is emitted in SOURCE ORDER
// between the top-level statements, and showWindow blocks for the life of the window.
setTimeout(settle, 900);
stage.showWindow(W, H, "probe icon");

function settle():void
{
    stageMark("settle");
    writeText(OUT + ".rects.txt",
        "root " + rectOf(node("root")) + "\n" +
        "r1 " + rectOf(node("r1")) + "\n" +
        "r2 " + rectOf(node("r2")) + "\n" +
        "sq " + rectOf(node("sq")) + "\n" +
        "cu " + rectOf(node("cu")) + "\n" +
        "qd " + rectOf(node("qd")) + "\n" +
        "fl " + rectOf(node("fl")) + "\n" +
        "df " + rectOf(node("df")) + "\n" +
        "st " + rectOf(node("st")) + "\n" +
        "vb12 " + rectOf(node("vb12")) + "\n" +
        "col2 " + rectOf(node("col2")) + "\n");
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    writeBmp(OUT + ".bmp", bd);
    pathChecks();
    writeText(OUT + ".done", failures == "" ? "PASS" : "FAIL " + failures);
}

// ---- the data layer, driven directly --------------------------------------
//
// These are structural, and they are the half a raster cannot reach: implicit repeats,
// relative commands, the S/T reflection rules -- and the three refusals.
function pathChecks():void
{
    var a:Array = PathData.parse("M2 12 22 12", 0.25);
    expect(a.length == 2, "an implicit lineto after a moveto produced " + a.length + " command(s), want 2");
    expect(int(a[1][0]) == PathData.LINE && Number(a[1][1]) == 22 && Number(a[1][2]) == 12,
        "the implicit lineto ends at " + a[1][1] + "," + a[1][2] + ", want 22,12");

    var b:Array = PathData.parse("m2 12 l20 0", 0.25);
    expect(b.length == 2, "the relative pair produced " + b.length + " command(s), want 2");
    expect(Number(b[0][1]) == 2 && Number(b[0][2]) == 12, "the relative moveto is " + b[0][1] + "," + b[0][2] + ", want 2,12");
    expect(Number(b[1][1]) == 22 && Number(b[1][2]) == 12, "the relative lineto is " + b[1][1] + "," + b[1][2] + ", want 22,12");

    // T mirrors the PREVIOUS quadratic control through the current point:
    // Q5 10 10 0 puts the control at (5,10) and the end at (10,0), so T's control is
    // (2*10-5, 2*0-10) = (15,-10).
    var t:Array = PathData.parse("M0 0 Q5 10 10 0 T20 0", 0.25);
    expect(t.length == 3, "Q..T produced " + t.length + " command(s), want 3");
    expect(Number(t[2][1]) == 15 && Number(t[2][2]) == -10,
        "T's reflected control is " + t[2][1] + "," + t[2][2] + ", want 15,-10");
    expect(Number(t[2][3]) == 20 && Number(t[2][4]) == 0, "T ends at " + t[2][3] + "," + t[2][4] + ", want 20,0");

    // S is the cubic version of the same reflection; the reflection only moves the
    // CONTROL, so the endpoint is what can be asserted structurally.
    var s:Array = PathData.parse("M0 0 C0 10 10 10 10 0 S20 -10 20 0", 0.25);
    var last:Array = s[s.length - 1];
    expect(Number(last[last.length - 2]) == 20 && Number(last[last.length - 1]) == 0,
        "S ends at " + last[last.length - 2] + "," + last[last.length - 1] + ", want 20,0");
    expect(s.length > 4, "C..S became " + s.length + " command(s) -- the two cubics would be chords");

    var z:Array = PathData.parse("M0 0 L10 0 Z", 0.25);
    expect(z.length == 3 && int(z[2][0]) == PathData.CLOSE, "Z did not produce a CLOSE");

    // One quadratic cannot stay within a quarter-pixel of this cubic, so the converter
    // must split: a single quad here IS the chord the whole class exists to avoid.
    var cub:Array = PathData.parse(P_CUBIC, 0.25);
    expect(cub.length > 2, "the cubic became " + cub.length + " command(s), want a subdivided run");

    // ---- the refusals ---------------------------------------------------
    var arcMsg:String = "";
    try { PathData.parse("M0 0 A10 10 0 0 0 20 20", 0.25); }
    catch (e1:Error) { arcMsg = e1.message; }
    expect(arcMsg.indexOf("G26") >= 0, "an 'A' arc did not throw naming G26; message was '" + arcMsg + "'");

    var junkMsg:String = "";
    try { PathData.parse("M0 0 X1 1", 0.25); }
    catch (e2:Error) { junkMsg = e2.message; }
    expect(junkMsg.indexOf("unexpected") >= 0, "an unknown command did not throw; message was '" + junkMsg + "'");

    // And the factory refuses at DESCRIBE time, not inside a paint pass, so the author
    // gets the stack frame they wrote.
    var fMsg:String = "";
    try { icon("M0 0 A5 5 0 0 0 10 10"); }
    catch (e3:Error) { fMsg = e3.message; }
    expect(fMsg.indexOf("G26") >= 0, "icon() accepted an arc; message was '" + fMsg + "'");
}

// ---- helpers --------------------------------------------------------------

function node(k:String):UiNode { return app.findByKey(k); }

function rectOf(n:UiNode):String
{
    if (n == null) return "MISSING";
    return n.absX + "," + n.absY + "," + n.absW + "," + n.absH;
}

function expect(ok:Boolean, msg:String):void
{
    if (!ok) failures = failures + msg + "; ";
}

// The stage survives in `<name>.step`, never in `.done`: tools/probe.cjs only prints the
// breadcrumb when the verdict never arrived.
function stageMark(label:String):void
{
    writeText(OUT + ".step", label + "\n");
}

function writeText(path:String, t:String):void
{
    var f:File = new File(path);
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
    var f:File = new File(path);
    var fs:FileStream = new FileStream();
    fs.open(f, FileMode.WRITE);
    fs.writeBytes(ba, 0, 0);
    fs.close();
}
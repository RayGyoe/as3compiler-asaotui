// probes/widgets/icon/Main.as -- the icon channel: SVG path data drawn by ONE Shape,
// and the exact refusals that keep it honest.
//
// Output prefix MUST equal the directory name (`icon`).
//
// WHY THIS NEEDS ITS OWN PROBE. Three things an icon can get wrong and no rectangle
// assertion can see:
//
//   1. THE CURVE. Most icon data is CUBIC (`C`), and a cubic is the one shape whose
//      middle a chord or a single quadratic can approximate convincingly. `expect.json`
//      samples the cubic's OWN t = 0.5 point AND the point of maximum deviation from the
//      best single quadratic (t = 0.789): the first catches a straight line, the second
//      catches "approximated by a quadratic", which is what this channel used to do
//      before compiler-gaps.md G26 gave the engine a real `cubicCurveTo`.
//   2. THE SCALE. A stroke width is authored in VIEWBOX units, so it must be multiplied
//      by the render scale: the same glyph at 48 and at 24 has a 4px and a 2px outline,
//      and a 12-viewBox glyph at 48 has an 8px one. All three are pixels in expect.json.
//   3. THE ARC. `A` is not a bezier and no AIR API draws one, so it is the one place a
//      curve is still converted rather than passed through. A wrong centre or a chord
//      instead of an arc both still paint SOMETHING, so the ring is sampled at 0deg,
//      45deg, and at its empty middle. (Before G26 this command threw; the refusal is
//      gone and the geometry is pinned instead.)
//
// The pixels and the rects live in expect.json (hand-computed, see its comment); the
// structural half -- implicit repeats, relative commands, the S/T reflection rules, the
// arc's command translation, the refusals -- lives here, because a raster cannot show
// which commands were parsed.
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
//   ar  (192,72,48,48) viewBox 24, scale 2: a circle from two 180deg arcs, local centre
//                      (12,12) r=10 -> absolute centre (216,96) r=20, stroke 4 -> ring
//                      18..22. (236,96) is 3 o'clock on the ring, (230,81) is 45deg,
//                      (216,96) is the hole and (194,74) is outside it.
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
// A full circle built from two 180deg arcs -- the shape no chord can fake.
var P_ARC:String = "M12 2 A10 10 0 1 0 12 22 A10 10 0 1 0 12 2";

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
        var ar:Node = icon(P_ARC, { key: "ar", style: BOX, strokeWidth: 2, color: BLUE });

        return column({ key: "root", style: ROOT, ariaName: "icon probe" }, [
            row({ key: "r1", style: ROW }, [sq, cu, qd, fl, df]),
            row({ key: "r2", style: ROW }, [st, vb, c2, ar])
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
        "col2 " + rectOf(node("col2")) + "\n" +
        "ar " + rectOf(node("ar")) + "\n");
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
    var a:Array = PathData.parse("M2 12 22 12");
    expect(a.length == 2, "an implicit lineto after a moveto produced " + a.length + " command(s), want 2");
    expect(int(a[1][0]) == PathData.LINE && Number(a[1][1]) == 22 && Number(a[1][2]) == 12,
        "the implicit lineto ends at " + a[1][1] + "," + a[1][2] + ", want 22,12");

    var b:Array = PathData.parse("m2 12 l20 0");
    expect(b.length == 2, "the relative pair produced " + b.length + " command(s), want 2");
    expect(Number(b[0][1]) == 2 && Number(b[0][2]) == 12, "the relative moveto is " + b[0][1] + "," + b[0][2] + ", want 2,12");
    expect(Number(b[1][1]) == 22 && Number(b[1][2]) == 12, "the relative lineto is " + b[1][1] + "," + b[1][2] + ", want 22,12");

    // T mirrors the PREVIOUS quadratic control through the current point:
    // Q5 10 10 0 puts the control at (5,10) and the end at (10,0), so T's control is
    // (2*10-5, 2*0-10) = (15,-10).
    var t:Array = PathData.parse("M0 0 Q5 10 10 0 T20 0");
    expect(t.length == 3, "Q..T produced " + t.length + " command(s), want 3");
    expect(Number(t[2][1]) == 15 && Number(t[2][2]) == -10,
        "T's reflected control is " + t[2][1] + "," + t[2][2] + ", want 15,-10");
    expect(Number(t[2][3]) == 20 && Number(t[2][4]) == 0, "T ends at " + t[2][3] + "," + t[2][4] + ", want 20,0");

    // S is the cubic version of the same reflection. C0 10 10 10 10 0 leaves (10,0) with
    // a second control at (10,10), so S's first control is (2*10-10, 2*0-10) = (10,-10).
    // ONE command per segment: a cubic is passed through, not subdivided.
    var s:Array = PathData.parse("M0 0 C0 10 10 10 10 0 S20 -10 20 0");
    expect(s.length == 3, "C..S produced " + s.length + " command(s), want MOVE + 2 CUBIC");
    if (s.length == 3)
    {
        expect(int(s[1][0]) == PathData.CUBIC && int(s[2][0]) == PathData.CUBIC, "C and S are not CUBIC commands");
        expect(Number(s[2][1]) == 10 && Number(s[2][2]) == -10,
            "S's reflected control is " + s[2][1] + "," + s[2][2] + ", want 10,-10");
        expect(Number(s[2][5]) == 20 && Number(s[2][6]) == 0,
            "S ends at " + s[2][5] + "," + s[2][6] + ", want 20,0");
    }

    var z:Array = PathData.parse("M0 0 L10 0 Z");
    expect(z.length == 3 && int(z[2][0]) == PathData.CLOSE, "Z did not produce a CLOSE");

    // The cubic reaches the list WHOLE: same controls, same end point, one command. (It
    // used to arrive as a run of quadratics, which is why this assertion used to want
    // "more than 2" commands; see G26 in compiler-gaps.md.)
    var cub:Array = PathData.parse(P_CUBIC);
    expect(cub.length == 2 && int(cub[1][0]) == PathData.CUBIC,
        "a C produced " + cub.length + " command(s) of kind "
        + (cub.length == 2 ? int(cub[1][0]) : -1) + ", want MOVE + one CUBIC");
    if (cub.length == 2)
    {
        expect(Number(cub[1][1]) == 2 && Number(cub[1][2]) == 22
            && Number(cub[1][3]) == 22 && Number(cub[1][4]) == 22
            && Number(cub[1][5]) == 22 && Number(cub[1][6]) == 2,
            "the C controls were not passed through unchanged");
    }

    // An arc becomes CUBIC commands that END where the data says. (0,0)->(20,20) with
    // r=10 is a chord longer than the diameter, so F.6.6 scales the radii up to 14.142
    // and the sweep is exactly 180deg -> two 90deg pieces.
    var arc:Array = PathData.parse("M0 0 A10 10 0 0 0 20 20");
    expect(arc.length == 3, "the arc produced " + arc.length + " command(s), want MOVE + 2 CUBIC");
    if (arc.length == 3)
    {
        expect(int(arc[1][0]) == PathData.CUBIC && int(arc[2][0]) == PathData.CUBIC, "the arc is not made of CUBICs");
        expect(Number(arc[2][5]) == 20 && Number(arc[2][6]) == 20,
            "the arc ends at " + arc[2][5] + "," + arc[2][6] + ", want 20,20 (the data's own end point)");
    }

    // Flags are ONE character each, so the compact form (no separators) must parse to the
    // same end point. A general "read a number" would read "011" as eleven and then run
    // out of data.
    var cpt:Array = null;
    try { cpt = PathData.parse("M0 0 a10 10 0 011 1"); }
    catch (e5:Error) { }
    expect(cpt != null, "the compact-flag arc did not parse (flags read as numbers?)");
    if (cpt != null)
    {
        var clast:Array = cpt[cpt.length - 1];
        expect(Number(clast[5]) == 1 && Number(clast[6]) == 1,
            "the compact-flag arc ends at " + clast[5] + "," + clast[6] + ", want 1,1");
    }

    // ---- the refusals ---------------------------------------------------
    var junkMsg:String = "";
    try { PathData.parse("M0 0 X1 1"); }
    catch (e2:Error) { junkMsg = e2.message; }
    expect(junkMsg.indexOf("unexpected") >= 0, "an unknown command did not throw; message was '" + junkMsg + "'");

    var shortMsg:String = "";
    try { PathData.parse("M0 0 A10 10 0 0 0 20"); }
    catch (e4:Error) { shortMsg = e4.message; }
    expect(shortMsg.indexOf("expected a number") >= 0, "a truncated arc did not throw; message was '" + shortMsg + "'");

    // The factory still validates at DESCRIBE time -- and an arc is now VALID data, so
    // this must not throw (it used to be the third refusal).
    icon("M0 0 A5 5 0 0 0 10 10");
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
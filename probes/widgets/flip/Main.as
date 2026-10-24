// probes/widgets/flip/Main.as -- the probe for the OVERFLOW FLIP.
//
// Output prefix MUST equal the directory name (`flip`).
//
// A 400x260 window, a plain column at padding 20 / gap 10, and THREE anchored
// popovers: one whose panel FITS below its anchor, one that would fall off the bottom
// edge and must therefore flip above it, and one anchored to the right edge that must
// flip to the anchor's left side (and then be clamped back inside the window).
//
//   root column:  top 20,20,120,32   filler 20,62,120,90   low 20,162,120,32
//                 rgt 260,204,120,32  (alignSelf flex-end)
//   (content 32+10+90+10+32+10+32 = 216 + 40 padding = 256 <= 260, so nothing is
//    flex-shrunk -- a shrunk column would give every assertion a fractional rect)
//   popT (below `top`):    52 + 6 = 58;   58 + 66 = 124 <= 260  -> stays
//   popB (below `low`):    194 + 6 = 200; 200 + 66 = 266 > 260 -> flips above,
//      162 - 6 - 66 = 90 >= 0, so y = 90 and its bottom edge is 156
//   popR (right of `rgt`): 380 + 6 = 386; 386 + 120 = 506 > 400 -> flips to the
//      anchor's left: 260 - 6 - 120 = 134, and y = clampY(204, 66, 260) = 190
//      (204 + 66 = 270 > 260 - EDGE_MARGIN, so the flip's own result is pulled
//      back in, leaving the 4px margin at the bottom: bottom edge 256)
//
// Panel 66 tall = 1 + 12 + 40 + 12 + 1 (border, padding, body, padding, border), the
// same arithmetic the overlay probe uses; 120 wide as requested. The flip uses the
// PREVIOUS frame's solved size, so the number that lands is the steady-state one.
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

var W:int = 400;
var H:int = 260;
var OUT:String = 'flip';

class FlipProbe extends View
{
    private static const ROOT:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", alignItems: "flex-start",
        padding: 20, gap: 10, size: [400, 260],
        background: 0xF3F4F6, text: { fontSize: 12, color: 0x111827 }
    });
    private static const ANCHOR:StyleRefinement = StyleRefinement.from({
        size: [120, 32], background: 0xE0E7FF
    });
    private static const FILLER:StyleRefinement = StyleRefinement.from({ size: [120, 90] });
    private static const BODY:StyleRefinement = StyleRefinement.from({ size: [100, 40] });
    // `alignSelf: flex-end` pins it to the column's right edge (x = 400 - 20 - 120).
    private static const RGT:StyleRefinement = StyleRefinement.from({
        alignSelf: "flex-end", size: [120, 32], background: 0xE0E7FF
    });

    public function FlipProbe():void { super(); }

    override public function render():Node
    {
        return column({ key: "root", style: ROOT, ariaName: "flip probe" }, [
            box({ key: "top", style: ANCHOR, ariaName: "top anchor" }),
            box({ key: "filler", style: FILLER, ariaName: "filler" }),
            box({ key: "low", style: ANCHOR, ariaName: "low anchor" }),
            box({ key: "rgt", style: RGT, ariaName: "right anchor" })
        ]);
    }

    override public function renderOverlay():Node
    {
        return overlay([
            popover({ key: "popT", open: true, anchorKey: "top", placement: "bottom", offset: 6, width: 120 },
                    [ box({ key: "popT:body", style: BODY, ariaName: "fits" }) ]),
            popover({ key: "popB", open: true, anchorKey: "low", placement: "bottom", offset: 6, width: 120 },
                    [ box({ key: "popB:body", style: BODY, ariaName: "overflows" }) ]),
            popover({ key: "popR", open: true, anchorKey: "rgt", placement: "right", offset: 6, width: 120 },
                    [ box({ key: "popR:body", style: BODY, ariaName: "overflows sideways" }) ])
        ]);
    }
}

var view:FlipProbe = new FlipProbe();
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

setTimeout(settle, 900);
stage.showWindow(W, H, "probe flip");

function settle():void
{
    var names:Array = ["root", "top", "filler", "low", "rgt", "popT", "popB", "popR",
                       "popT:body", "popB:body", "popR:body"];
    var lines:String = "";
    var missing:int = 0;
    for (var i:int = 0; i < names.length; i++)
    {
        var n:UiNode = app.findByKey(names[i]);
        if (n == null) { missing = missing + 1; lines = lines + names[i] + " MISSING\n"; continue; }
        lines = lines + names[i] + " " + n.absX + "," + n.absY + "," + n.absW + "," + n.absH + "\n";
    }
    writeText(OUT + ".rects.txt", lines);

    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    writeBmp(OUT + ".bmp", bd);
    if (missing > 0) { writeText(OUT + ".done", "FAIL " + missing + " node(s) missing"); return; }

    var problems:String = "";

    // The panel that FITS keeps the requested edge...
    var t:UiNode = app.findByKey("popT");
    if (t.absY != 58) problems = problems + "the fitting popover moved to y=" + t.absY + " (it must stay below its anchor at 58); ";
    // ...and the one that does not fit is flipped ABOVE it, on the anchor's left edge.
    var b:UiNode = app.findByKey("popB");
    if (b.absY != 90) problems = problems + "the overflowing popover is at y=" + b.absY + " not 90 (anchor 162 - 6 - 66); ";
    if (b.absY + b.absH > H) problems = problems + "the flipped popover still overflows the window (" + (b.absY + b.absH) + " > " + H + "); ";
    if (b.absX != 20) problems = problems + "the flipped popover is at x=" + b.absX + " not 20 (the anchor's left edge); ";
    // The flipped panel must sit ABOVE the anchor: its bottom edge is 172-6 = 166.
    if (b.absY + b.absH != 156) problems = problems + "the flipped popover's bottom edge is " + (b.absY + b.absH) + " not 156; ";
    // ---- the SIDEWAYS flip ----
    // `rgt` spans x 260..380, so `right` wants 386 and 386+120 > 400: it must come
    // out on the anchor's left, 260-6-120 = 134.
    var r:UiNode = app.findByKey("popR");
    if (r.absX != 134) problems = problems + "the right-anchored popover is at x=" + r.absX + " not 134 (anchor left 260 - 6 - 120); ";
    if (r.absX + r.absW > W) problems = problems + "the sideways-flipped popover still overflows the window (" + (r.absX + r.absW) + " > " + W + "); ";
    // ...and then the CLAMP pulls it back inside: 214 + 66 = 280 > 260, so the top is
    // 260-66 = 194 and the bottom edge lands exactly on the window edge.
    if (r.absY != 190) problems = problems + "the sideways-flipped popover is at y=" + r.absY + " not 190 (clampY: 260 - 4 - 66); ";
    if (r.absY + r.absH != H - 4) problems = problems + "the clamped popover's bottom edge is " + (r.absY + r.absH) + " not " + (H - 4) + " (the clamp keeps a 4px margin); ";
    // Both panels paint (a flip must not hide the surface).
    var px:uint = bd.getPixel(30, 140) & 0xFFFFFF;
    if (px != 0xFFFFFF) problems = problems + "the flipped panel's padding is #" + px.toString(16) + " not white; ";
    var px2:uint = bd.getPixel(30, 68) & 0xFFFFFF;
    if (px2 != 0xFFFFFF) problems = problems + "the unflipped panel's padding is #" + px2.toString(16) + " not white; ";
    var px3:uint = bd.getPixel(140, 200) & 0xFFFFFF;
    if (px3 != 0xFFFFFF) problems = problems + "the sideways-flipped panel's padding is #" + px3.toString(16) + " not white; ";
    // The page itself paints, so "white" above really is the PANEL and not an
    // unpainted window: the root is grey and a bare spot must stay grey.
    var px4:uint = bd.getPixel(10, 250) & 0xFFFFFF;
    if (px4 != 0xF3F4F6) problems = problems + "the page background is #" + px4.toString(16) + " not #f3f4f6 (the panels above would prove nothing); ";

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
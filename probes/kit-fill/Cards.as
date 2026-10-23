// probes/kit-fill/Cards.as -- bisect the missing background fill INSIDE the kit.
//
// Cleared so far, each by measurement rather than reading:
//   * Graphics is innocent -- probes/graphics-order/Order2.as: all four combos of
//     {drawRect, drawRoundRect} x {fill-first, line-first} paint fill AND border;
//   * style resolution is innocent -- probes/silent-null/AlphaValue.as: the demo's
//     CARD resolves to background argb 0xFFF9FAFB, rgb 0xF9FAFB, alpha 1;
//   * the demo really does lose the fill -- tools/pngread.cjs on
//     ui-demo/UiDemo-shot-3.png: the card interior is #ffffff.
//
// So the loss happens between "a resolved Style that says background=#F9FAFB" and
// "pixels". This probe closes that gap by driving the real toolkit (View -> UiApp
// -> Reconciler -> UiNode) with four cards that differ ONLY in their style, and
// dumping the framebuffer. Each card is 360x50 in a 400x300 window, so the sample
// points are fixed and the answer is per-card:
//
//   card1  background #F9FAFB + border 1 + cornerRadii 12   <- the demo's CARD
//   card2  background #2563EB + border 1
//   card3  background #2563EB
//   card4  background #2563EB + cornerRadii 8
//
// Whichever card paints and whichever does not names the trigger. The rects the
// engine produced are written next to the BMP, so the sample points are derived
// from the engine's own output instead of assumed.
import asaot.ui.*;
import asaot.ui.style.*;
import flash.display.BitmapData;
import flash.display.StageAlign;
import flash.display.StageScaleMode;
import flash.filesystem.File;
import flash.filesystem.FileMode;
import flash.filesystem.FileStream;
import flash.geom.Rectangle;
import flash.utils.ByteArray;
import flash.utils.setTimeout;

var W:int = 400;
var H:int = 300;
var OUT:String = 'cards.bmp';

class CardView extends View
{
    private static const ROOT:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", padding: 20, gap: 10, size: [400, 300]
    });
    private static const C1:StyleRefinement = StyleRefinement.from({
        size: [360, 50], background: 0xF9FAFB, border: 1, borderColor: 0xE5E7EB, cornerRadii: 12
    });
    private static const C2:StyleRefinement = StyleRefinement.from({
        size: [360, 50], background: 0x2563EB, border: 1, borderColor: 0x1D4ED8
    });
    private static const C3:StyleRefinement = StyleRefinement.from({
        size: [360, 50], background: 0x2563EB
    });
    private static const C4:StyleRefinement = StyleRefinement.from({
        size: [360, 50], background: 0x2563EB, cornerRadii: 8
    });

    override public function render():Node
    {
        return column({ key: "root", style: ROOT }, [
            box({ key: "c1", style: C1 }),
            box({ key: "c2", style: C2 }),
            box({ key: "c3", style: C3 }),
            box({ key: "c4", style: C4 })
        ]);
    }
}

var view:CardView = new CardView();
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

setTimeout(after, 900);
stage.showWindow(W, H, "kit-fill cards");

function after():void
{
    // Rects from the engine, so the sampler's coordinates come from the program
    // rather than from the author's belief about where things are.
    var names:Array = ["c1", "c2", "c3", "c4"];
    var lines:String = "";
    var i:int;
    for (i = 0; i < 4; i++)
    {
        var n:UiNode = app.findByKey(names[i]);
        if (n == null) { lines = lines + names[i] + " MISSING\n"; continue; }
        lines = lines + names[i] + " " + n.absX + "," + n.absY + "," + n.absW + "," + n.absH + "\n";
    }
    writeText(OUT + ".rects.txt", lines);

    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    writeBmp(OUT, bd);
    writeText(OUT + ".log", "cards: wrote " + OUT + "\n");
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
    var y:int;
    var x:int;
    for (y = h - 1; y >= 0; y--) {
        for (x = 0; x < w; x++) {
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
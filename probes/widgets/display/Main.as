// probes/widgets/display/Main.as -- the probe for the divider / badge / avatar /
// card widgets.
//
// Output prefix MUST equal the directory name (`display`) because
// tools/probe.cjs derives the expected files from it.
//
// What it pins, and why each thing is here:
//   * the RECTS of all nine nodes (explicit sizes, so every coordinate is
//     hand-computable) -- including the CARD'S CHILD, whose position proves the
//     card is a real container;
//   * one exact PIXEL per visual state: each badge tone, each avatar tone, the
//     horizontal and the vertical hairline, the card surface and the page;
//   * THREE things a bitmap cannot show: that all four kinds registered with
//     Widgets, that a card's child is laid out INSIDE the card's rect, and that
//     a settled tree does NOT re-solve layout on later frames.
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

var W:int = 320;
var H:int = 460;
var OUT:String = 'display';

class DisplayProbe extends View
{
    private static const ROOT:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", padding: 20, gap: 10, size: [320, 460],
        background: 0xFFFFFF
    });
    private static const HAIRLINE:StyleRefinement = StyleRefinement.from({
        size: [280, 1], background: 0x112233
    });
    private static const VHAIRLINE:StyleRefinement = StyleRefinement.from({
        size: [1, 40], background: 0x112233
    });
    private static const PILL:StyleRefinement = StyleRefinement.from({
        size: [40, 16], cornerRadii: 8
    });
    private static const CIRCLE:StyleRefinement = StyleRefinement.from({
        size: [48, 48]
    });
    private static const CARD:StyleRefinement = StyleRefinement.from({
        size: [280, 120], padding: 12, border: 1, borderColor: 0xDDDDDD,
        cornerRadii: 8, background: 0xF5F5F5, flexDirection: "column"
    });
    private static const CARD_BOX:StyleRefinement = StyleRefinement.from({
        size: [100, 30], background: 0x99DDFF
    });

    override public function render():Node
    {
        return column({ key: "root", style: ROOT }, [
            divider({ key: "d1", style: HAIRLINE, orientation: "horizontal" }),
            divider({ key: "d2", style: VHAIRLINE, orientation: "vertical" }),
            badge("3",   { key: "b1", style: PILL, tone: "neutral" }),
            badge("99+", { key: "b2", style: PILL, tone: "info" }),
            badge("7",   { key: "b3", style: PILL, tone: "danger" }),
            avatar("Ada Lovelace", { key: "a1", style: CIRCLE, tone: "neutral" }),
            avatar("Grace Hopper", { key: "a2", style: CIRCLE, tone: "info" }),
            card({ key: "card", title: "Card title", style: CARD }, [
                box({ key: "card-child", style: CARD_BOX })
            ])
        ]);
    }
}

var view:DisplayProbe = new DisplayProbe();
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

var solveAtSettle:Number = 0;
var frame0:int = 0;

setTimeout(settle, 900);
stage.showWindow(W, H, "probe display");

function settle():void
{
    var names:Array = ["d1", "d2", "b1", "b2", "b3", "a1", "a2", "card", "card-child"];
    var count:int = 9;
    var lines:String = "";
    var missing:int = 0;
    var i:int;
    for (i = 0; i < count; i++)
    {
        var n:UiNode = app.findByKey(names[i]);
        if (n == null) { missing = missing + 1; lines = lines + names[i] + " MISSING\n"; continue; }
        lines = lines + names[i] + " " + n.absX + "," + n.absY + "," + n.absW + "," + n.absH + "\n";
    }
    writeText(OUT + ".rects.txt", lines);

    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    writeBmp(OUT + ".bmp", bd);

    solveAtSettle = app.layoutSolves;
    frame0 = app.enterFrameTicks;
    if (missing > 0) { writeText(OUT + ".done", "FAIL " + missing + " node(s) missing"); return; }
    setTimeout(steady, 400);
}

function steady():void
{
    var problems:String = "";
    if (!Widgets.has("divider")) problems = problems + "Widgets.has('divider') is false; ";
    if (!Widgets.has("badge")) problems = problems + "Widgets.has('badge') is false; ";
    if (!Widgets.has("avatar")) problems = problems + "Widgets.has('avatar') is false; ";
    if (!Widgets.has("card")) problems = problems + "Widgets.has('card') is false; ";

    // A card is a REAL container: its child must be solved INSIDE the card's
    // rect by the layout engine (a hand-placed box would not be).
    var card:UiNode = app.findByKey("card");
    var kid:UiNode = app.findByKey("card-child");
    if (card == null || kid == null)
    {
        problems = problems + "card/card-child not found; ";
    }
    else
    {
        var inside:Boolean = kid.absX >= card.absX && kid.absY >= card.absY
            && kid.absX + kid.absW <= card.absX + card.absW
            && kid.absY + kid.absH <= card.absY + card.absH;
        if (!inside) problems = problems + "card-child not inside card; ";

        // ANOTHER thing a bitmap cannot show: the card's title is an INTERNAL
        // TextField (not a UiNode), so it must carry the title text and sit at
        // the content-box origin (border 1 + padding 12 = 13). The glyphs are
        // unreadable in a 320x460 sample, so this has to be asserted directly.
        if (card.tf == null)
        {
            problems = problems + "card has no title field; ";
        }
        else
        {
            if (card.tf.text != "Card title") problems = problems + "card title text wrong; ";
            if (card.tf.x != 13 || card.tf.y != 13)
            {
                problems = problems + "card title not at content origin (" + card.tf.x + "," + card.tf.y + "); ";
            }
        }
    }

    var extraSolves:Number = app.layoutSolves - solveAtSettle;
    var extraFrames:int = app.enterFrameTicks - frame0;
    if (extraFrames < 2) problems = problems + "only " + extraFrames + " frame(s) elapsed; ";
    if (extraSolves > 0) problems = problems + "a settled tree re-solved layout " + extraSolves + " time(s); ";
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

// 32-bit bottom-up BMP written by hand: this runtime has BitmapData but no PNG
// encoder, and a raw frame buffer is BETTER evidence than an encoded image --
// it is a 1:1 copy of the compositor output, so the samplers can compare exact
// integers (see tools/probe.cjs).
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

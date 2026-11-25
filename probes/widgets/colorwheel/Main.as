// probes/widgets/colorwheel/Main.as -- pins the public colorWheel kind.
// Dark theme; one 72x72 wheel at (10,10), value 0 / spread 0 (dot at centre).
// Samples: inner disc (46,30) = tokens.surfaceSunken #0D1424; dot (46,46) = knob #FFFFFF.
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

var W:int = 100;
var H:int = 100;
var OUT:String = 'colorwheel';

class CWProbe extends View
{
    override public function render():Node
    {
        return column({ key: "root", style: StyleRefinement.from({ padding: 10, size: [100, 100], background: 0xFFFFFF }) }, [
            colorWheel("shadows", { key: "cw", value: 0, spread: 0, size: [72, 72] })
        ]);
    }
}

Theme.setTheme(ThemeTokens.dark());
var view:CWProbe = new CWProbe();
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

setTimeout(settle, 900);
stage.showWindow(W, H, "probe colorwheel");

function settle():void
{
    var n:UiNode = app.findByKey("cw");
    var lines:String = "";
    if (n == null) lines = "cw MISSING\n";
    else lines = "cw " + n.absX + "," + n.absY + "," + n.absW + "," + n.absH + "\n";
    writeText(OUT + ".rects.txt", lines);
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    writeBmp(OUT + ".bmp", bd);
    solveAtSettle = app.layoutSolves; frame0 = app.enterFrameTicks;
    if (n == null) { writeText(OUT + ".done", "FAIL cw missing"); return; }
    setTimeout(steady, 400);
}
var solveAtSettle:Number = 0; var frame0:int = 0;
function steady():void
{
    var problems:String = "";
    if (!Widgets.has("colorWheel")) problems += "Widgets.has('colorWheel') false; ";
    if (app.layoutSolves - solveAtSettle > 0) problems += "settled tree re-solved; ";
    writeText(OUT + ".done", problems == "" ? "PASS" : "FAIL " + problems);
}
function writeText(path:String, t:String):void
{
    var f:File = File.applicationDirectory.resolvePath(path);
    var fs:FileStream = new FileStream(); fs.open(f, FileMode.WRITE); fs.writeUTFBytes(t); fs.close();
}
function writeBmp(path:String, bd:BitmapData):void
{
    var w:int = bd.width; var h:int = bd.height;
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
    ba.writeByte(1); ba.writeByte(0); ba.writeByte(32); ba.writeByte(0);
    ba.writeByte(0); ba.writeByte(0); ba.writeByte(0); ba.writeByte(0);
    ba.writeByte(imgSize & 255); ba.writeByte(imgSize >> 8 & 255);
    ba.writeByte(imgSize >> 16 & 255); ba.writeByte(imgSize >> 24 & 255);
    ba.writeByte(0); ba.writeByte(0); ba.writeByte(0); ba.writeByte(0);
    ba.writeByte(0); ba.writeByte(0); ba.writeByte(0); ba.writeByte(0);
    ba.writeByte(0); ba.writeByte(0); ba.writeByte(0); ba.writeByte(0);
    ba.writeByte(0); ba.writeByte(0); ba.writeByte(0); ba.writeByte(0);
    for (var y:int = h - 1; y >= 0; y--)
        for (var x:int = 0; x < w; x++)
        {
            var i:int = (y * w + x) * 4;
            ba.writeByte(px[i + 3]); ba.writeByte(px[i + 2]); ba.writeByte(px[i + 1]); ba.writeByte(px[i]);
        }
    var f:File = File.applicationDirectory.resolvePath(path);
    var fs:FileStream = new FileStream(); fs.open(f, FileMode.WRITE); fs.writeBytes(ba, 0, 0); fs.close();
}
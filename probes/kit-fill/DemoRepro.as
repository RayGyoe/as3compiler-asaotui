// probes/kit-fill/DemoRepro.as -- run the DEMO'S OWN VIEW through a framebuffer dump.
//
// Everything the toolkit could be blamed for has been cleared by measurement:
// probes/graphics-order/Order2.as (Graphics: fill+border in all four call orders
// and shapes), probes/silent-null/AlphaValue.as (style resolution: CARD/SIGNIN
// backgrounds resolve to alpha 1), probes/kit-fill/Cards2.as (six cards driven
// through the real View -> UiApp -> Reconciler -> UiNode path, INCLUDING c5/c6
// which are the demo's CARD and SIGNIN literals verbatim, all six paint).
//
// The one thing none of those share with the demo is the demo's own view and its
// own window. This file closes that last gap without touching a single file that
// another worker owns: it imports `DemoView`/`DemoModel` FROM ui-demo/ (read-only,
// passed on the compiler command line) and drives them through THIS probe's own
// dump, so the pixels are written by code we control and cannot be a stale
// artifact of somebody else's build.
//
// Measurement, not impression: the framebuffer is written to demo-repro.bmp and
// sampled at the rectangles the ENGINE reports, so the expected colours are
// derived from the program's own output.
//
//   card  background #F9FAFB -> expect #f9fafb inside, #e5e7eb on its border
//   signin background #2563EB -> expect #2563eb inside, #1d4ed8 on its border
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

var W:int = 560;
var H:int = 460;
var OUT:String = 'demo-repro.bmp';

var model:DemoModel = new DemoModel();
var view:DemoView = new DemoView(model);

var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

setTimeout(after, 900);
stage.showWindow(W, H, "kit-fill demo-repro");

function after():void
{
    var names:Array = ["root", "card", "signin", "title", "status"];
    var lines:String = "";
    var i:int;
    for (i = 0; i < names.length; i++)
    {
        var n:UiNode = app.findByKey(names[i]);
        if (n == null) { lines = lines + names[i] + " MISSING\n"; continue; }
        lines = lines + names[i] + " " + n.absX + "," + n.absY + "," + n.absW + "," + n.absH + "\n";
    }
    writeText(OUT + ".rects.txt", lines);

    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    writeBmp(OUT, bd);
    writeText(OUT + ".log", "demo-repro: wrote " + OUT + "\n");
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
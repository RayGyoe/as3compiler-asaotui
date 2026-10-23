// probes/graphics-order/Order.as -- minimal repro for a Graphics state bug.
//
// WHY: the demo's card and sign-in button paint their border but not their fill
// (measured pixel-by-pixel: ui-demo/UiDemo-shot-3.png row y=284 is #1d4ed8 at
// x=47 then #ffffff for 465 px). Diffing the two painters in the SAME file,
// asaot.ui.UiNode, the only structural difference is the ORDER of the two
// Graphics calls:
//
//   drawBox()       beginFill(...); lineStyle(...); draw...   -> FILL LOST
//   paintCheckbox() lineStyle(...); beginFill(...); draw...   -> fill renders
//
// In Flash/AIR the two state machines are independent -- the language reference
// for Graphics.beginFill says nothing about lineStyle resetting it, and drawing a
// bordered filled box in that order is completely ordinary authoring. So this is
// expected to be OUR bug, not the toolkit's, and the repro is deliberately as
// small as it can be: ONE window, TWO identical squares, differing only in call
// order. The framebuffer is written to a BMP and read back with exact integer
// colours, so the result is measured, not eyeballed.
//
// Expected if Graphics is correct: BOTH squares are solid #2563EB in the middle.
// Actual (see the review): only the lineStyle-first square is.
import flash.display.Shape;
import flash.display.BitmapData;
import flash.display.StageAlign;
import flash.display.StageScaleMode;
import flash.filesystem.File;
import flash.filesystem.FileMode;
import flash.filesystem.FileStream;
import flash.geom.Rectangle;
import flash.utils.ByteArray;
import flash.utils.setTimeout;

var OUT:String = "order.bmp";
var W:int = 200;
var H:int = 100;

var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;

var bg:Shape = new Shape();
bg.graphics.beginFill(0x203040);
bg.graphics.drawRect(0, 0, W, H);
bg.graphics.endFill();
stage.addChild(bg);

// Square A -- beginFill THEN lineStyle (what UiNode.drawBox does).
var a:Shape = new Shape();
a.graphics.beginFill(0x2563EB);
a.graphics.lineStyle(1, 0x1D4ED8, 1.0);
a.graphics.drawRect(20, 20, 60, 60);
a.graphics.endFill();
a.x = 0;
stage.addChild(a);

// Square B -- lineStyle THEN beginFill (what UiNode.paintCheckbox does).
var b:Shape = new Shape();
b.graphics.lineStyle(1, 0x1D4ED8, 1.0);
b.graphics.beginFill(0x2563EB);
b.graphics.drawRect(0, 0, 60, 60);
b.graphics.endFill();
b.x = 120;
b.y = 20;
stage.addChild(b);

setTimeout(dump, 900);
stage.showWindow(W, H, "graphics-order");

function dump():void
{
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    writeBmp(OUT, bd);
    var f:File = new File(OUT + ".log");
    var fs:FileStream = new FileStream();
    fs.open(f, FileMode.WRITE);
    fs.writeUTFBytes("order: wrote " + OUT + "\n");
    fs.close();
    // Leave the window open so the harness can read the BMP; it kills the process.
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
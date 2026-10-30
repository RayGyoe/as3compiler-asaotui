// probes/graphics-order/Order2.as -- the second hypothesis, after the first died.
//
// HYPOTHESIS 1 (WRONG, kept as a record): "lineStyle after beginFill discards the
// pending fill". Order.as disproved it -- both call orders produced a solid
// #2563eb centre. What that probe DID turn up is that neither square painted its
// 1px border, which is the other half of the demo's symptom and points elsewhere.
//
// HYPOTHESIS 2: it is `drawRoundRect`, not the call order. Both broken pieces in
// the demo carry a corner radius (`card: cornerRadii 12`, `signin: cornerRadii 8`)
// and both go through `Graphics.drawRoundRect(0, 0, w, h, r*2, r*2)`, whereas the
// control that DOES paint (the checkbox) also uses drawRoundRect -- so a plain
// "drawRoundRect is broken" would not explain it either. What the two work/break
// groups differ in on the toolkit side is the ARGUMENT: the checkbox draws a
// 16x16 box with radius 3 (small), the card a 504x234 box with radius 12, the
// button a 466x46 box with radius 8.
//
// This probe crosses the two variables that are still live -- drawRect vs
// drawRoundRect, and the call order -- over four identical 60x60 squares, each
// with fill #2563EB and border #1D4ED8, and reports centre + all four borders.
// Whatever differs between the square that paints correctly and the one that does
// not names the trigger.
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

var OUT:String = "order2.bmp";
var W:int = 400;
var H:int = 100;
var BOX:int = 60;
var RAD:int = 24;          // drawRoundRect's ellipseWidth, as drawBox passes r*2

var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;

var bg:Shape = new Shape();
bg.graphics.beginFill(0x203040);
bg.graphics.drawRect(0, 0, W, H);
bg.graphics.endFill();
stage.addChild(bg);

// tag, x, round?, borderFirst?
make("A rect      fill-first", 20, false, false);
make("B roundRect fill-first", 120, true, false);
make("C rect      line-first", 220, false, true);
make("D roundRect line-first", 320, true, true);

function make(tag:String, x:Number, round:Boolean, borderFirst:Boolean):void
{
    var sh:Shape = new Shape();
    if (borderFirst) sh.graphics.lineStyle(1, 0x1D4ED8, 1.0);
    sh.graphics.beginFill(0x2563EB);
    if (!borderFirst) sh.graphics.lineStyle(1, 0x1D4ED8, 1.0);
    if (round) sh.graphics.drawRoundRect(0, 0, BOX, BOX, RAD, RAD);
    else sh.graphics.drawRect(0, 0, BOX, BOX);
    sh.graphics.endFill();
    sh.x = x;
    sh.y = 20;
    stage.addChild(sh);
}

setTimeout(dump, 900);
stage.showWindow(W, H, "graphics-order 2");

function dump():void
{
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    writeBmp(OUT, bd);
    var f:File = File.applicationDirectory.resolvePath(OUT + ".log");
    var fs:FileStream = new FileStream();
    fs.open(f, FileMode.WRITE);
    fs.writeUTFBytes("order2: wrote " + OUT + "\n");
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
    var f:File = File.applicationDirectory.resolvePath(path);
    var fs:FileStream = new FileStream();
    fs.open(f, FileMode.WRITE);
    fs.writeBytes(ba, 0, 0);
    fs.close();
}
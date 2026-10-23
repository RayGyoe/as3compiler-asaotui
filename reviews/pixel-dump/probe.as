// temp/pixdump/Dump.as -- probe: can a WINDOWED native build rasterize its own
// display list into a BitmapData and write the pixels to a file?
//
// Why: air-check/README.md records that adl.exe on Windows has no stdout, so the
// AIR arm must write its evidence to a file. If OUR native arm can write pixels
// too, then both arms can dump the SAME pixels and we can diff images -- a far
// stronger check than "looks right in a screenshot".
//
// Shape of the probe: draw two known rectangles, open a real window, and from a
// timer (the event loop is running inside showWindow) rasterize the stage into a
// BitmapData, getPixels() -> ARGB bytes (emit.ts BitmapData_getPixels writes
// A,R,G,B per pixel, row-major), wrap them in a 32-bit BMP and write it, then
// exit. Deliberately no pixel assertions here -- this probe only answers
// "does the channel work", the assertions belong in the real demo.
import flash.display.Shape;
import flash.display.BitmapData;
import flash.filesystem.File;
import flash.filesystem.FileMode;
import flash.filesystem.FileStream;
import flash.desktop.NativeApplication;
import flash.utils.setTimeout;
import flash.geom.Rectangle;

var OUT:String = "C:/Users/rayle/Desktop/as3compiler-aot/as3compiler/temp/pixdump/dump.bmp";
var W:int = 200;
var H:int = 120;

var stage:Stage = new Stage();

var bg:Shape = new Shape();
bg.graphics.beginFill(0x203040);
bg.graphics.drawRect(0, 0, W, H);
bg.graphics.endFill();
stage.addChild(bg);

var red:Shape = new Shape();
red.graphics.beginFill(0xFF0000);
red.graphics.drawRect(10, 10, 60, 40);
red.graphics.endFill();
stage.addChild(red);

var green:Shape = new Shape();
green.graphics.beginFill(0x00FF00);
green.graphics.drawRect(100, 60, 50, 30);
green.graphics.endFill();
stage.addChild(green);

function be32(n:Number):Number { return n; }

function writeBmp(path:String, bd:BitmapData):void {
  var w:int = bd.width;
  var h:int = bd.height;
  var px:ByteArray = bd.getPixels(new Rectangle(0, 0, w, h));
  var imgSize:int = w * h * 4;
  var ba:ByteArray = new ByteArray();
  // BITMAPFILEHEADER (little-endian)
  ba.writeByte(0x42); ba.writeByte(0x4D);                      // 'BM'
  ba.writeByte(54 + imgSize & 255); ba.writeByte((54 + imgSize) >> 8 & 255);
  ba.writeByte((54 + imgSize) >> 16 & 255); ba.writeByte((54 + imgSize) >> 24 & 255);
  ba.writeByte(0); ba.writeByte(0); ba.writeByte(0); ba.writeByte(0);   // reserved
  ba.writeByte(54); ba.writeByte(0); ba.writeByte(0); ba.writeByte(0);  // pixel offset
  // BITMAPINFOHEADER
  ba.writeByte(40); ba.writeByte(0); ba.writeByte(0); ba.writeByte(0);
  ba.writeByte(w & 255); ba.writeByte(w >> 8 & 255); ba.writeByte(0); ba.writeByte(0);
  ba.writeByte(h & 255); ba.writeByte(h >> 8 & 255); ba.writeByte(0); ba.writeByte(0);
  ba.writeByte(1); ba.writeByte(0);           // planes
  ba.writeByte(32); ba.writeByte(0);          // bpp
  ba.writeByte(0); ba.writeByte(0); ba.writeByte(0); ba.writeByte(0);   // BI_RGB
  ba.writeByte(imgSize & 255); ba.writeByte(imgSize >> 8 & 255);
  ba.writeByte(imgSize >> 16 & 255); ba.writeByte(imgSize >> 24 & 255);
  ba.writeByte(0); ba.writeByte(0); ba.writeByte(0); ba.writeByte(0);   // x ppm
  ba.writeByte(0); ba.writeByte(0); ba.writeByte(0); ba.writeByte(0);   // y ppm
  ba.writeByte(0); ba.writeByte(0); ba.writeByte(0); ba.writeByte(0);   // palette
  ba.writeByte(0); ba.writeByte(0); ba.writeByte(0); ba.writeByte(0);   // important
  // pixels: BMP wants bottom-up BGRA; getPixels gave us top-down ARGB
  var y:int;
  var x:int;
  for (y = h - 1; y >= 0; y--) {
    for (x = 0; x < w; x++) {
      var i:int = (y * w + x) * 4;
      ba.writeByte(px[i + 3]);   // B
      ba.writeByte(px[i + 2]);   // G
      ba.writeByte(px[i + 1]);   // R
      ba.writeByte(px[i]);       // A
    }
  }
  var f:File = new File(path);
  var fs:FileStream = new FileStream();
  fs.open(f, FileMode.WRITE);
  fs.writeBytes(ba, 0, 0);
  fs.close();
  trace("pixdump: wrote " + path + " (" + w + "x" + h + ", " + (54 + imgSize) + " bytes)");
}

function after():void {
  var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
  bd.draw(stage);
  writeBmp(OUT, bd);
  trace("pixdump: done, exiting");
  NativeApplication.nativeApplication.exit();
}

setTimeout(after, 900);
trace("pixdump: opening window");
stage.showWindow(W, H, "pixdump probe");
trace("pixdump: window closed");
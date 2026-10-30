// air-check/PixelDump.as -- the AIR twin of the native pixel-dump probe.
//
// WHY: reviews/probe-pixel-dump-2026-10-22.md proved our AOT windowed build can
// rasterize its own display list into a BMP. If the AIR arm can produce a BMP
// from the SAME drawing sequence, the AOT<->AIR comparison stops being "the
// layout numbers agree" and becomes "the resulting PIXELS agree".
//
// The only difference from the AOT probe is the prologue, and it is forced by
// the platform, not chosen: AIR's Stage has no public constructor, so the root
// has to be a Sprite subclass and the Stage is reached through `stage` after
// addChild. Everything from the drawing sequence down to the BMP writer is the
// same text as as3compiler/temp/pixdump/Dump.as.
//
// mxmlc resolves the document class by FILE NAME and only accepts the class
// form (a file of top-level statements fails with "cannot load the SWF's root
// class" -- our own AOT accepts both, AIR does not). Hence the package block.
package
{
    import flash.display.Sprite;
    import flash.display.Shape;
    import flash.display.BitmapData;
    import flash.display.StageAlign;
    import flash.display.StageScaleMode;
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;
    import flash.desktop.NativeApplication;
    import flash.geom.Rectangle;
    import flash.utils.ByteArray;
    import flash.utils.setTimeout;

    public class PixelDump extends Sprite
    {
        // Relative to the swf/app dir on AIR and to the app dir on our AOT (both are this
        // folder), so the air arm and the AOT arm write the same file name.
        public static var OUT:String = "air-dump.bmp";
        public static var W:int = 200;
        public static var H:int = 120;

        public function PixelDump()
        {
            stage.scaleMode = StageScaleMode.NO_SCALE;
            stage.align = StageAlign.TOP_LEFT;
            build();
            setTimeout(after, 900);
        }

        // ---- the shared drawing sequence (same shapes, same order) ----
        private function build():void
        {
            var bg:Shape = new Shape();
            bg.graphics.beginFill(0x203040);
            bg.graphics.drawRect(0, 0, W, H);
            bg.graphics.endFill();
            addChild(bg);

            var red:Shape = new Shape();
            red.graphics.beginFill(0xFF0000);
            red.graphics.drawRect(10, 10, 60, 40);
            red.graphics.endFill();
            addChild(red);

            var green:Shape = new Shape();
            green.graphics.beginFill(0x00FF00);
            green.graphics.drawRect(100, 60, 50, 30);
            green.graphics.endFill();
            addChild(green);
        }

        public function after():void
        {
            var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
            bd.draw(stage);
            writeBmp(OUT, bd);
            writeText(OUT + ".log", "pixdump: wrote " + OUT + " (" + bd.width + "x" + bd.height + ")\n");
            NativeApplication.nativeApplication.exit();
        }

        private function writeText(path:String, text:String):void
        {
            var f:File = File.applicationDirectory.resolvePath(path);
            var fs:FileStream = new FileStream();
            fs.open(f, FileMode.WRITE);
            fs.writeUTFBytes(text);
            fs.close();
        }

        private function writeBmp(path:String, bd:BitmapData):void
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
    }
}
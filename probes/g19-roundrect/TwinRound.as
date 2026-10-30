package
{
    // What does AIR actually paint for Graphics.drawRoundRect? (G19, stage 267)
    //
    // Each case draws ONE filled rounded rect into a 40x40 BitmapData through
    // BitmapData.draw and reports, per row, the first and last pixel whose alpha is
    // >= 128 (the AA edge is ignored) plus the number of such pixels. That is enough
    // to pin the corner ellipse: a right-angle rect gives left=0 on every row, a
    // rounded one gives left=0..R depending on y.
    //
    // Runs on BOTH runtimes from this single source (temp/g16g19g20/ab-round.cjs):
    // our AOT compiles it as an ordinary class, and mxmlc+adl run it as the document
    // class. Edges may differ by one pixel where the two rasterizers disagree about
    // AA, so the comparison allows +-1 and says so.
    import flash.desktop.NativeApplication;
    import flash.display.Bitmap;
    import flash.display.BitmapData;
    import flash.display.Shape;
    import flash.display.Sprite;
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;

    public class Round extends Sprite
    {
        private var path:String;

        public function Round()
        {
            path = File.applicationDirectory.nativePath + File.separator + "round.txt";

            // 1: 40x40, ellipse 12x12 -> corner radius (6,6)
            caseOne(1, 40, 40, 12, 12);
            // 2: 40x40, ellipse 20x10 -> radius (10,5): the horizontal and vertical
            //    radii are independent, which is the whole point of two parameters
            caseOne(2, 40, 40, 20, 10);
            // 3: 40x40, ellipse 80x80 -> AIR clamps to half the box (radius 20,20)
            caseOne(3, 40, 40, 80, 80);
            // 4: ellipse 0x0 -> plain rectangle
            caseOne(4, 40, 40, 0, 0);
            // 5: ellipseWidth 100, ellipseHeight 4 -> clamped x, flat y
            caseOne(5, 40, 40, 100, 4);
            // 6: ellipse wider than half but height fine (40x12)
            caseOne(6, 40, 40, 40, 12);
            // 7: negative ellipse (AIR: drawn as a rect, no corner)
            caseOne(7, 40, 40, -8, -8);
            // 8: ellipseHeight OMITTED (AS3 default NaN) -- does it fall back to ew?
            caseShort(8, 40, 40, 12);
            // 9: ellipseHeight explicitly NaN (case 10 -- both NaN -- belongs to
            // RoundArgs, where the expected #2004 is the point and does not abort
            // this sweep halfway).
            caseOne(9, 40, 40, 12, Math.sqrt(-1));

            NativeApplication.nativeApplication.exit();
        }

        private function caseShort(id:int, w:Number, h:Number, ew:Number):void
        {
            var s:Shape = new Shape();
            s.graphics.beginFill(0x3366CC, 1.0);
            s.graphics.drawRoundRect(0, 0, w, h, ew);
            s.graphics.endFill();
            var bd:BitmapData = new BitmapData(int(w), int(h), true, 0x00000000);
            bd.draw(s, null, null, null, null, false);
            sweep(id, bd, w, h);
        }

        private function caseOne(id:int, w:Number, h:Number, ew:Number, eh:Number):void
        {
            var s:Shape = new Shape();
            s.graphics.beginFill(0x3366CC, 1.0);
            s.graphics.drawRoundRect(0, 0, w, h, ew, eh);
            s.graphics.endFill();
            var bd:BitmapData = new BitmapData(int(w), int(h), true, 0x00000000);
            bd.draw(s, null, null, null, null, false);

            sweep(id, bd, w, h);
        }

        private function sweep(id:int, bd:BitmapData, w:Number, h:Number):void
        {
            var y:int = 0;
            while (y < int(h))
            {
                var left:int = -1;
                var right:int = -1;
                var count:int = 0;
                var x:int = 0;
                while (x < int(w))
                {
                    var px:uint = bd.getPixel32(x, y);
                    var a:uint = (px >> 24) & 0xFF;
                    if (a >= 128)
                    {
                        if (left < 0) left = x;
                        right = x;
                        count++;
                    }
                    x++;
                }
                emit("row " + id + " " + y + " l=" + left + " r=" + right + " n=" + count);
                y++;
            }
        }

        private function emit(line:String):void
        {
            var f:File = File.applicationDirectory.resolvePath(path);
            var st:FileStream = new FileStream();
            st.open(f, FileMode.APPEND);
            st.writeUTFBytes(line + "\n");
            st.close();
        }
    }
}var _driverRound:Round = new Round();

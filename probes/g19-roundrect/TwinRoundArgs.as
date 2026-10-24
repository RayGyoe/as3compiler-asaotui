package
{
    // Graphics.drawRoundRect argument contract (G19, stage 267).
    //
    // The pixel sweep in Round.as pins the GEOMETRY of a valid call; this pins what
    // AIR does with the awkward arguments, because each of those is a branch our
    // emitter has to decide about and a wrong guess is silent:
    //   - ellipseHeight omitted or NaN  (AS3 default is NaN)
    //   - ellipseWidth NaN
    //   - a negative ellipse
    //   - an infinite ellipse
    //   - a negative / zero width or height
    //
    // Every call is drawn into a 60x60 BitmapData through a +10,+10 matrix so an
    // inverted rect stays inside the bitmap, and the report is either the thrown
    // error or the ink bounding box (alpha >= 128). Same source runs on adl and on
    // our AOT build (temp/g16g19g20/ab-round.cjs).
    import flash.desktop.NativeApplication;
    import flash.display.BitmapData;
    import flash.display.Shape;
    import flash.display.Sprite;
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;
    import flash.geom.Matrix;

    public class RoundArgs extends Sprite
    {
        private var path:String;

        public function RoundArgs()
        {
            path = File.applicationDirectory.nativePath + File.separator + "round-args.txt";

            var nan:Number = Math.sqrt(-1);
            var inf:Number = 1.0 / 0.0;

            probe("ewNaN", 0, 0, 40, 40, nan, 12);
            probe("ehNaN", 0, 0, 40, 40, 12, nan);
            probe("bothNaN", 0, 0, 40, 40, nan, nan);
            probeOmitEh("omitEh", 0, 0, 40, 40, 12);
            probeRows("negEw", 0, 0, 40, 40, -8, 12);
            probeRows("negEh", 0, 0, 40, 40, 12, -8);
            probeRows("negBoth", 0, 0, 40, 40, -8, -8);
            probe("infEw", 0, 0, 40, 40, inf, 12);
            probe("infEh", 0, 0, 40, 40, 12, inf);
            probe("negW", 40, 40, -30, -30, 12, 12);
            probe("negWonly", 40, 10, -30, 30, 12, 12);
            probe("zeroW", 0, 0, 0, 40, 12, 12);
            probe("zeroH", 0, 0, 40, 0, 12, 12);

            NativeApplication.nativeApplication.exit();
        }

        private function probe(id:String, x:Number, y:Number, w:Number, h:Number, ew:Number, eh:Number):void
        {
            try
            {
                draw(id, x, y, w, h, ew, eh, true, false);
            }
            catch (e:Error)
            {
                emit("arg " + id + " throw " + e.name + " #" + e.errorID + " " + e.message);
            }
        }

        private function probeRows(id:String, x:Number, y:Number, w:Number, h:Number, ew:Number, eh:Number):void
        {
            try
            {
                draw(id, x, y, w, h, ew, eh, true, true);
            }
            catch (e:Error)
            {
                emit("arg " + id + " throw " + e.name + " #" + e.errorID);
            }
        }

        private function probeOmitEh(id:String, x:Number, y:Number, w:Number, h:Number, ew:Number):void
        {
            try
            {
                draw(id, x, y, w, h, ew, 0, false, false);
            }
            catch (e:Error)
            {
                emit("arg " + id + " throw " + e.name + " #" + e.errorID + " " + e.message);
            }
        }

        private function draw(id:String, x:Number, y:Number, w:Number, h:Number,
                             ew:Number, eh:Number, withEh:Boolean, dumpRows:Boolean):void
        {
            var s:Shape = new Shape();
            s.graphics.beginFill(0x3366CC, 1.0);
            if (withEh) s.graphics.drawRoundRect(x, y, w, h, ew, eh);
            else s.graphics.drawRoundRect(x, y, w, h, ew);
            s.graphics.endFill();
            var bd:BitmapData = new BitmapData(60, 60, true, 0x00000000);
            var m:Matrix = new Matrix();
            m.translate(10, 10);
            bd.draw(s, m, null, null, null, false);

            var minx:int = -1, miny:int = -1, maxx:int = -1, maxy:int = -1;
            var rowL:int = -1, rowR:int = -1;
            var yy:int = 0;
            while (yy < 60)
            {
                if (dumpRows) { rowL = -1; rowR = -1; }
                var xx:int = 0;
                while (xx < 60)
                {
                    var a:uint = (bd.getPixel32(xx, yy) >> 24) & 0xFF;
                    if (a >= 128)
                    {
                        if (minx < 0 || xx < minx) minx = xx;
                        if (maxx < 0 || xx > maxx) maxx = xx;
                        if (miny < 0) miny = yy;
                        maxy = yy;
                        if (dumpRows) { if (rowL < 0) rowL = xx; rowR = xx; }
                    }
                    xx++;
                }
                if (dumpRows) emit("row " + id + " " + yy + " l=" + rowL + " r=" + rowR);
                yy++;
            }
            emit("arg " + id + " ok box=" + minx + "," + miny + "," + maxx + "," + maxy);
        }

        private function emit(line:String):void
        {
            var f:File = new File(path);
            var st:FileStream = new FileStream();
            st.open(f, FileMode.APPEND);
            st.writeUTFBytes(line + "\n");
            st.close();
        }
    }
}var _driverRoundArgs:RoundArgs = new RoundArgs();

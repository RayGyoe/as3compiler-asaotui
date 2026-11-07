// probes/g31-space/AirMain.as -- AIR arm of the G31 A/B (compiler-gaps.md G31).
//
// Identical instrument to the AOT arm: 12 pt Arial, draw the field, count the empty
// columns between ink runs. Same strings, same order, so the two output files can be
// diffed line by line.
//
// Writes to File.userDirectory, NOT applicationDirectory: under `adl` the app
// directory is read-only (SecurityError: fileWriteResource, measured), and the storage
// directory's path depends on the platform. The runner knows the home directory.
package
{
    import flash.display.BitmapData;
    import flash.display.Sprite;
    import flash.desktop.NativeApplication;
    import flash.events.Event;
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;
    import flash.text.TextField;
    import flash.text.TextFormat;

    public class AirMain extends Sprite
    {
        private static const W:int = 200;
        private static const H:int = 26;

        public function AirMain()
        {
            addEventListener(Event.ADDED_TO_STAGE, run);
        }

        private function run(e:Event):void
        {
            var lines:Array = ["A |", "b |", "X |", "T |", "V |", "Q |", "1 |",
                               "A box", "Abox", "A  box", "A card is a box"];
            var rep:String = "# G31 AIR arm -- ink gaps, Arial 12\n# text\tink\n";
            for (var i:int = 0; i < lines.length; i++)
            {
                rep = rep + String(lines[i]) + "\t" + gaps(String(lines[i])) + "\n";
            }
            rep = rep + "# AIR " + NativeApplication.nativeApplication.runtimeVersion + "\n";
            var f:FileStream = new FileStream();
            f.open(File.userDirectory.resolvePath("g31-air.txt"), FileMode.WRITE);
            f.writeUTFBytes(rep);
            f.close();
            NativeApplication.nativeApplication.exit();
        }

        private function gaps(text:String):String
        {
            var bd:BitmapData = new BitmapData(W, H, false, 0xFFFFFF);
            var tf:TextField = new TextField();
            var fmt:TextFormat = new TextFormat();
            fmt.font = "Arial";
            fmt.size = 12;
            tf.defaultTextFormat = fmt;
            tf.multiline = false;
            tf.wordWrap = false;
            tf.width = W;
            tf.height = H;
            tf.text = text;
            tf.setTextFormat(fmt);
            bd.draw(tf);
            var cols:Array = [];
            var first:int = -1;
            var last:int = -1;
            for (var x:int = 0; x < W; x++)
            {
                var n:int = 0;
                for (var y:int = 0; y < H; y++)
                {
                    var c:uint = bd.getPixel32(x, y) & 0xFFFFFF;
                    var r:int = (c >> 16) & 255;
                    var g:int = (c >> 8) & 255;
                    var b:int = c & 255;
                    if ((r + g + b) / 3 < 200) n++;
                }
                cols.push(n);
                if (n > 0) { if (first < 0) first = x; last = x; }
            }
            bd.dispose();
            if (first < 0) return "NO INK";
            var gs:int = -1;
            var list:String = "";
            for (var k:int = first; k <= last; k++)
            {
                if (int(cols[k]) == 0) { if (gs < 0) gs = k; }
                else if (gs >= 0) { list = list + " " + (k - gs); gs = -1; }
            }
            return "span=" + (last - first + 1) + " gaps=[" + list + " ]";
        }
    }
}
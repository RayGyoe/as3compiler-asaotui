// probes/g31-space/src/Main.as -- AOT arm of the G31 A/B (compiler-gaps.md G31).
//
// QUESTION: is the space after "A" narrower than the space after other letters?
// AIR says no (uniform 4 px ink gap at 12 pt Arial -- see the README's table, measured
// with the AIR arm of this probe). This arm asks the same question of our runtime with
// the same instrument: draw a TextField at 12 pt Arial and count the EMPTY columns
// between ink runs.
//
// WHY THE INK COLUMNS AND NOT `textWidth`: textWidth needs no reference and both
// sides can disagree about it for reasons unrelated to the defect. Ink columns are
// the thing a reader actually sees.
//
// The measurement runs on the first ENTER_FRAME, not in the constructor: text only
// shapes once the window's render context exists. `visible=true` with a 120x40 window
// is what --air-app generates for every app; the process exits on that same frame.
package g31
{
    import flash.desktop.NativeApplication;
    import flash.display.BitmapData;
    import flash.display.Sprite;
    import flash.events.Event;
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;
    import flash.text.TextField;
    import flash.text.TextFormat;

    public class Main extends Sprite
    {
        private static const W:int = 200;
        private static const H:int = 26;
        private var done:Boolean = false;

        public function Main()
        {
            // ADDED_TO_STAGE, like the gallery tour: that is the one hook that runs BEFORE
            // showWindow blocks the thread, and it is where the gallery already draws into
            // BitmapData successfully.
            addEventListener(Event.ADDED_TO_STAGE, once);
        }

        private function once(e:Event):void
        {
            if (this.done) return;
            this.done = true;
            var lines:Array = ["A |", "b |", "X |", "T |", "V |", "Q |", "1 |",
                               "A box", "Abox", "A  box", "A card is a box"];
            var rep:String = "# G31 AOT arm -- ink gaps, Arial 12\n# text\tink\n";
            for (var i:int = 0; i < lines.length; i++)
            {
                rep = rep + String(lines[i]) + "\t" + this.gaps(String(lines[i])) + "\n";
            }
            var f:FileStream = new FileStream();
            f.open(File.applicationDirectory.resolvePath("g31-aot.txt"), FileMode.WRITE);
            f.writeUTFBytes(rep);
            f.close();
            NativeApplication.nativeApplication.exit();
        }

        private function gaps(text:String):String
        {
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
            this.addChild(tf);
            var bd:BitmapData = new BitmapData(W, H, false, 0xFFFFFF);
            bd.draw(this.stage);
            this.removeChild(tf);
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
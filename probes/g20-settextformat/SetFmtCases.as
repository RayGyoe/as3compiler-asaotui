package
{
    // What does TextField.setTextFormat() do to a range that ALREADY has formatting?
    // (G20, stage 268)
    //
    // The gap: our emitter APPENDS a run to TextField._runs and never trims the old
    // ones, while the layout side (sk_textlayout_new_runs) walks the runs in order and
    // copies text[start..end) for EACH of them. Two runs over the same range therefore
    // lay the same characters out twice, so a field that re-applies its format on every
    // repaint grows linearly with the number of repaints ("the typed text gets copied
    // once more"; the reported symptom was textWidth 28.88 -> 56.73 -> 84).
    //
    // AIR's contract (ActionScript 3.0 reference, TextField.setTextFormat): the format
    // applies to the range, i.e. it REPLACES whatever was there -- applying the same
    // format twice is the same as applying it once, and applying a format to a
    // sub-range leaves the rest of the text as it was.
    //
    // Everything below is relational (equality between two fields measured in the SAME
    // process), never an absolute width: AIR and this build use different text engines,
    // so their absolute metrics differ, but "applying twice == applying once" is a
    // property of the semantics and must hold on both.
    //
    // Drivers: AotMain.as (top-level) and AirMain.as (document class) both call report().
    import flash.display.BitmapData;
    import flash.display.Sprite;
    import flash.text.TextField;
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;
    import flash.text.TextFieldAutoSize;
    import flash.text.TextFormat;

    public class SetFmtCases
    {
        public static function report(fileName:String):void
        {
            // `new File("x")` is ArgumentError #2004 under the AIR debug launcher, so
            // the app directory is the anchor (it IS the probe dir under `adl app.xml`).
            var path:String = File.applicationDirectory.nativePath + File.separator + fileName;
            emit(path, "raw file " + path);

            // ---- A) the same full-range format, applied 1 / 2 / 3 times ----
            var one:TextField = mk("1111");
            one.setTextFormat(fmt(24, 0xFF0000));
            var tw1:Number = one.textWidth;
            var ink1:int = ink(one);

            var two:TextField = mk("1111");
            two.setTextFormat(fmt(24, 0xFF0000));
            two.setTextFormat(fmt(24, 0xFF0000));
            var tw2:Number = two.textWidth;

            var three:TextField = mk("1111");
            three.setTextFormat(fmt(24, 0xFF0000));
            three.setTextFormat(fmt(24, 0xFF0000));
            three.setTextFormat(fmt(24, 0xFF0000));
            var tw3:Number = three.textWidth;
            var ink3:int = ink(three);

            emit(path, "raw tw1=" + tw1 + " tw2=" + tw2 + " tw3=" + tw3 + " ink1=" + ink1 + " ink3=" + ink3);
            out(path, 1, tw1 > 0);
            out(path, 2, tw2 == tw1);
            out(path, 3, tw3 == tw1);
            out(path, 4, ink3 == ink1);
            out(path, 5, three.text == "1111");
            out(path, 6, three.text.length == 4);

            // ---- B) a sub-range format, applied 3 times, must not stack either ----
            var p1:TextField = mk("1111");
            p1.setTextFormat(fmt(24, 0xFF0000), 0, 2);
            var pt1:Number = p1.textWidth;

            var p3:TextField = mk("1111");
            p3.setTextFormat(fmt(24, 0xFF0000), 0, 2);
            p3.setTextFormat(fmt(24, 0xFF0000), 0, 2);
            p3.setTextFormat(fmt(24, 0xFF0000), 0, 2);
            var pt3:Number = p3.textWidth;
            emit(path, "raw sub tw1=" + pt1 + " tw3=" + pt3);
            out(path, 7, pt3 == pt1);

            // ---- C) a full-range format REPLACES a sub-range one ----
            var over:TextField = mk("1111");
            over.setTextFormat(fmt(24, 0xFF0000), 0, 2);
            over.setTextFormat(fmt(20, 0x0000FF));
            var freshFull:TextField = mk("1111");
            freshFull.setTextFormat(fmt(20, 0x0000FF));
            emit(path, "raw override=" + over.textWidth + " fresh=" + freshFull.textWidth);
            out(path, 8, over.textWidth == freshFull.textWidth);

            // ---- D) two disjoint ranges survive, in either application order ----
            var ab:TextField = mk("1111");
            ab.setTextFormat(fmt(24, 0xFF0000), 0, 2);
            ab.setTextFormat(fmt(24, 0x00FF00), 2, 4);
            var ba:TextField = mk("1111");
            ba.setTextFormat(fmt(24, 0x00FF00), 2, 4);
            ba.setTextFormat(fmt(24, 0xFF0000), 0, 2);
            emit(path, "raw ab=" + ab.textWidth + " ba=" + ba.textWidth);
            out(path, 9, ab.textWidth == ba.textWidth);

            // ---- E) the LAST write in a range wins (AIR: read it back) ----
            // ---- E2) ...and a run must actually TAKE EFFECT: without this, a build that
            // silently installs no run at all would still satisfy every equality above.
            var plain:TextField = mk("1111");
            emit(path, "raw plain=" + plain.textWidth + " formatted=" + one.textWidth);
            out(path, 14, one.textWidth > plain.textWidth);
            // ---- F) a NARROWER range must SPLIT the run it lands in ----
            var narrow:TextField = mk("1111");
            narrow.setTextFormat(fmt(24, 0xFF0000));
            narrow.setTextFormat(fmt(12, 0x0000FF), 0, 2);
            var narrowFresh:TextField = mk("1111");
            narrowFresh.setTextFormat(fmt(12, 0x0000FF), 0, 2);
            narrowFresh.setTextFormat(fmt(24, 0xFF0000), 2, 4);
            emit(path, "raw splitTail=" + narrow.textWidth + " fresh=" + narrowFresh.textWidth);
            out(path, 12, narrow.textWidth == narrowFresh.textWidth);

            var mid:TextField = mk("1111");
            mid.setTextFormat(fmt(24, 0xFF0000));
            mid.setTextFormat(fmt(12, 0x0000FF), 1, 3);
            var midFresh:TextField = mk("1111");
            midFresh.setTextFormat(fmt(24, 0xFF0000), 0, 1);
            midFresh.setTextFormat(fmt(12, 0x0000FF), 1, 3);
            midFresh.setTextFormat(fmt(24, 0xFF0000), 3, 4);
            emit(path, "raw splitMid=" + mid.textWidth + " fresh=" + midFresh.textWidth);
            out(path, 13, mid.textWidth == midFresh.textWidth);
            // getTextFormat() ignores the runs in this build (it answers with
            // defaultTextFormat) -- a SEPARATE, registered deviation (G21), kept here
            // so a fix is noticed. Values are the AIR ones plus our current ones.
            three.setTextFormat(fmt(30, 0x0000FF));
            var tf2:TextFormat = three.getTextFormat();
            emit(path, "raw color=" + tf2.color + " size=" + tf2.size);
            out(path, 10, tf2.color == 0x0000FF);
            out(path, 11, tf2.size == 30);
        }

        private static function mk(text:String):TextField
        {
            var f:TextField = new TextField();
            f.defaultTextFormat = new TextFormat("Arial", 20, 0x000000);
            f.autoSize = TextFieldAutoSize.LEFT;
            f.text = text;
            return f;
        }

        private static function fmt(size:Number, color:uint):TextFormat
        {
            return new TextFormat("Arial", size, color);
        }

        // Rightmost inked column + 1 (0 = nothing drawn). A repaint that duplicated the
        // text shows up here as ink running past one copy's width.
        private static function ink(f:TextField):int
        {
            var bd:BitmapData = new BitmapData(400, 60, true, 0x00000000);
            bd.draw(f);
            var right:int = 0;
            var x:int = 0;
            while (x < 400)
            {
                var y:int = 0;
                while (y < 60)
                {
                    if (((bd.getPixel32(x, y) >> 24) & 0xFF) > 0) { right = x + 1; break; }
                    y++;
                }
                x++;
            }
            return right;
        }

        private static function out(path:String, id:int, ok:Boolean):void
        {
            emit(path, "id=" + id + " " + ok);
        }

        private static function emit(path:String, line:String):void
        {
            var f:File = new File(path);
            var st:FileStream = new FileStream();
            st.open(f, FileMode.APPEND);
            st.writeUTFBytes(line + "\n");
            st.close();
        }
    }
}

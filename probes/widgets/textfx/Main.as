// probes/widgets/textfx/Main.as -- the five surfaces added in one batch, each pinned
// by the pixel or property that CANNOT be faked:
//
//   1. boxShadow  -- the runtime renders a DropShadowFilter, and the shadow lands on
//                    the node's BACKGROUND SHAPE (not the backing, which would shade
//                    the children too). With blur 0 the shadow is a hard copy of the
//                    box offset by (x,y), so a grey pixel exactly 4px BELOW the box
//                    and a white pixel ABOVE it is an exact statement about where the
//                    filter went -- no kernel-dependent tolerance needed above the
//                    box, and a range below it (alpha 0.5 over white is 127/128).
//   2. gradient   -- `background: [dark, light]` really paints a ramp: the left edge is
//                    near black, the right edge near white, the middle strictly between
//                    them. A solid fill (the pre-batch behaviour) would make all three
//                    equal, which is what this refuses.
//   3. wrap       -- whiteSpace "normal" publishes the WRAPPED height, compared against
//                    a reference node carrying the SAME string unwrapped, so the
//                    assertion is font-independent (a multiple, not a number).
//   4. ellipsis   -- textOverflow "ellipsis" shortens the painted run to the box AND
//                    ends it with U+2026. Asserted on the string the field really
//                    holds, plus textWidth <= box, plus the node's own width.
//   5. textArea   -- multi-line: `rows` lines tall, and Return INSERTS. The decisive
//                    half is the negative: Enter must NOT commit (in a single-line
//                    field it does), so onCommit stays empty until the blur.
//
// Hand arithmetic (window 460x520, root column, padding 20, gap 12, alignItems
// flex-start, white, text 12px):
//
//   sh (20,20,120,60)   gr (20,92,160,40)   92 = 20 + 60 + 12
//   then ref / wr / el / ta, each auto-height, in that order.
//
//   sh's shadow is the box offset by (0,8): it covers y 28..88, so y=84 is inside it
//   and y=14 is above it (white). x=80 is the box's own mid-column.
//
// Protocol (tools/probe.cjs): dir name == output prefix; writes <OUT>.rects.txt,
// <OUT>.bmp, <OUT>.done (PASS | FAIL <reason>) and a running <OUT>.samples.txt.
import asaot.ui.*;
import asaot.ui.style.StyleRefinement;
import flash.display.BitmapData;
import flash.display.Stage;
import flash.display.StageAlign;
import flash.display.StageScaleMode;
import flash.filesystem.File;
import flash.filesystem.FileMode;
import flash.filesystem.FileStream;
import flash.geom.Rectangle;
import flash.text.TextField;
import flash.utils.ByteArray;
import flash.utils.setTimeout;

var W:int = 460;
var H:int = 520;
var OUT:String = 'textfx';

// 90 characters: ~540px at 12px, so it wraps to three lines at 200px and is far too
// long for the 120px ellipsis box.
var S:String = "The quick brown fox jumps over the lazy dog while the compiler measures every single line.";

var st:Object = {
    changed: 0,
    committed: "",
    last: ""
};

class TextFxProbe extends View
{
    private static const ROOT:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", alignItems: "flex-start",
        padding: 20, gap: 12, size: [460, 520],
        background: 0xFFFFFF, text: { fontSize: 12, color: 0x111827 }
    });
    // blur 0 + a pure downward offset: the shadow is a hard rectangle 8px below the
    // box, which is what makes the pixel assertions exact instead of approximate.
    private static const SHADOW:StyleRefinement = StyleRefinement.from({
        size: [120, 60], background: 0xFFFFFF, cornerRadii: 8,
        boxShadow: { x: 0, y: 8, blur: 0, color: 0x000000, alpha: 0.5 }
    });
    private static const GRAD:StyleRefinement = StyleRefinement.from({
        size: [160, 40], background: [0x000000, 0xFFFFFF]
    });
    private static const REF:StyleRefinement = StyleRefinement.from({
        text: { fontSize: 12 }
    });
    private static const WRAP:StyleRefinement = StyleRefinement.from({
        size: [200, null], text: { fontSize: 12, whiteSpace: "normal" }
    });
    private static const ELL:StyleRefinement = StyleRefinement.from({
        size: [120, null], text: { fontSize: 12, textOverflow: "ellipsis" }
    });
    private static const AREA:StyleRefinement = StyleRefinement.from({
        size: [220, null]
    });

    public function TextFxProbe():void { super(); }

    override public function render():Node
    {
        return column({ key: "root", style: ROOT, ariaName: "text effects probe" }, [
            box({ key: "sh", style: SHADOW }),
            box({ key: "gr", style: GRAD }),
            // The same string, unwrapped: this is the ruler the wrapped node is compared
            // against, so no font metric is hard-coded anywhere.
            text(S, { key: "ref", style: REF, ariaName: "" }),
            text(S, { key: "wr", style: WRAP, ariaName: "" }),
            text(S, { key: "el", style: ELL, ariaName: "" }),
            textArea({ key: "ta", rows: 3, value: st.last, style: AREA,
                onChange: function (t:String):void
                {
                    st.last = t;
                    st.changed = int(st.changed) + 1;
                },
                onCommit: function (t:String):void { st.committed = t; } })
        ]);
    }
}

var view:TextFxProbe = new TextFxProbe();
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

var problems:String = "";
var log:String = "";

function say(s:String):void
{
    log = log + s + "\n";
    trace(s);
    writeText(OUT + ".samples.txt", log);
}

function fail(s:String):void
{
    problems = problems + s + "; ";
}

function frame():BitmapData
{
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    return bd;
}

function pixel(bd:BitmapData, x:int, y:int):uint
{
    return bd.getPixel(x, y) & 0xFFFFFF;
}

function hex(c:uint):String
{
    var s:String = c.toString(16);
    while (s.length < 6) s = "0" + s;
    return "#" + s;
}

function rOf(c:uint):int { return (c >> 16) & 0xFF; }

function node(key:String):UiNode
{
    return app.findByKey(key);
}

// U+2026 as an escape: the generated C carries string literals byte-for-byte, so a
// source-encoded glyph would depend on how this file was saved.
//
// SEARCHED, not compared against the last CHARACTER: this runtime indexes strings by
// BYTE, so charAt(length-1) of a UTF-8 ellipsis is a lone continuation byte (measured:
// the first version of this probe failed on exactly that). The contract is "the
// truncated run carries an ellipsis", and indexOf states it on either encoding.
function hasEllipsis(s:String):Boolean
{
    return s.indexOf("\u2026") >= 0;
}

function hasBreak(s:String):Boolean
{
    return s.indexOf("\n") >= 0 || s.indexOf("\r") >= 0;
}

// ==================== phase 1: the painted surfaces =========================
function phaseSurface(bd:BitmapData):void
{
    var sh:UiNode = node("sh");
    var gr:UiNode = node("gr");
    if (sh == null || gr == null) { fail("sh/gr missing"); return; }
    if (sh.absX != 20 || sh.absY != 20 || sh.absW != 120 || sh.absH != 60)
        fail("sh is " + sh.absX + "," + sh.absY + "," + sh.absW + "," + sh.absH + " not 20,20,120,60");
    if (gr.absX != 20 || gr.absY != 92 || gr.absW != 160 || gr.absH != 40)
        fail("gr is " + gr.absX + "," + gr.absY + "," + gr.absW + "," + gr.absH + " not 20,92,160,40");

    // ---- box shadow -------------------------------------------------------
    var above:uint = pixel(bd, 80, 14);     // above the box: no shadow may bleed up
    var inside:uint = pixel(bd, 80, 50);    // the box's own white face
    var below:uint = pixel(bd, 80, 84);     // 4px under it: inside the (0,8) shadow
    if (above != 0xFFFFFF) fail("shadow bled ABOVE the box: (80,14) is " + hex(above));
    if (inside != 0xFFFFFF) fail("the box face is " + hex(inside) + " not #ffffff");
    var r:int = rOf(below);
    if (r <= 0x28 || r >= 0xD8)
        fail("no shadow below the box: (80,84) is " + hex(below)
            + " (alpha 0.5 over white must land near #808080)");
    say("shadow: above=" + hex(above) + " face=" + hex(inside) + " below=" + hex(below));

    // ---- gradient ---------------------------------------------------------
    var y:int = gr.absY + 20;
    var l:uint = pixel(bd, gr.absX + 3, y);
    var m:uint = pixel(bd, gr.absX + 80, y);
    var rr:uint = pixel(bd, gr.absX + 157, y);
    if (rOf(l) > 0x20) fail("gradient left edge is " + hex(l) + ", expected near black");
    if (rOf(rr) < 0xE0) fail("gradient right edge is " + hex(rr) + ", expected near white");
    if (!(rOf(l) < rOf(m) && rOf(m) < rOf(rr)))
        fail("the gradient is not a ramp: " + hex(l) + " -> " + hex(m) + " -> " + hex(rr));
    say("gradient: " + hex(l) + " -> " + hex(m) + " -> " + hex(rr));
}

// ==================== phase 2: the text surfaces ============================
function phaseText():void
{
    var ref:UiNode = node("ref");
    var wr:UiNode = node("wr");
    var el:UiNode = node("el");
    if (ref == null || wr == null || el == null) { fail("ref/wr/el missing"); return; }
    var lineH:Number = ref.absH;
    if (!(lineH > 0)) { fail("the reference line measured " + lineH); return; }
    if (!(wr.absH >= lineH * 2.5))
        fail("the wrapped node is " + wr.absH + " tall, under 2.5 lines (" + lineH
            + " each) -- it did not wrap");
    if (wr.absW != 200) fail("the wrapped node is " + wr.absW + " wide, not the 200 it asked for");
    if (el.absW != 120) fail("the ellipsis node is " + el.absW + " wide, not 120");
    if (el.tf == null) { fail("the ellipsis node has no field"); return; }
    var t:String = el.tf.text;
    if (t.length >= S.length)
        fail("the ellipsis node still holds all " + t.length + " characters");
    if (!hasEllipsis(t)) fail("the truncated run holds no U+2026: '" + t + "'");
    if (el.tf.textWidth > 120)
        fail("the ellipsised run is " + el.tf.textWidth + "px wide, past its 120px box");
    say("text: lineH=" + lineH + " refH=" + ref.absH + " wrH=" + wr.absH + " wrW=" + wr.absW
        + " elW=" + el.absW + " elLen=" + t.length + "/" + S.length + " elTw=" + el.tf.textWidth);
}

// ==================== phase 3: the multi-line field =========================
function phaseArea():void
{
    var ta:UiNode = node("ta");
    if (ta == null) { fail("ta missing"); return; }
    if (ta.tf == null) { fail("ta has no field"); return; }
    if (!ta.tf.multiline) fail("the text area's field is NOT multiline");
    if (!ta.tf.wordWrap) fail("the text area's field does not word-wrap");
    var ref:UiNode = node("ref");
    if (ref != null && ta.tf.height < ref.absH * 2.5)
        fail("the text area's content box is " + ta.tf.height + " tall, under 3 lines");
    say("area: rect " + ta.absX + "," + ta.absY + "," + ta.absW + "," + ta.absH
        + " tfH=" + ta.tf.height + " rows=3");

    // Focus it the way a user does, then type "ab", press Return, type "cd".
    var cx:int = int(ta.absX) + 40;
    var cy:int = int(ta.absY) + 20;
    stage.dispatchMouse(cx, cy, "mouseDown");
    stage.dispatchMouse(cx, cy, "mouseUp");
    stage.dispatchText("a");
    stage.dispatchText("b");
    // mod 0. In a MULTILINE field the runtime inserts a break; the widget must not
    // consume 13 (that is the single-line contract).
    stage.dispatchKey("keyDown", 13, 13, 0);
    stage.dispatchText("c");
    stage.dispatchText("d");
    var got:String = ta.tf.text;
    say("area typed: '" + got + "' len=" + got.length + " breaks=" + hasBreak(got)
        + " model='" + String(st.last) + "' changed=" + int(st.changed));
    if (got.length < 5)
        fail("after 'ab' + Return + 'cd' the field holds " + got.length + " characters ('" + got + "')");
    if (!hasBreak(got)) fail("Return did NOT insert a line break in a multiline field");
    if (String(st.committed) != "")
        fail("Return COMMITTED in a text area ('" + String(st.committed) + "') -- it must insert instead");
    if (int(st.changed) < 4)
        fail("onChange ran " + int(st.changed) + " times for 5 edits");
}

// ==================== phase 4: blur commits ================================
function phaseBlur():void
{
    var ta:UiNode = node("ta");
    if (ta == null || ta.tf == null) return;
    stage.dispatchMouse(80, 50, "mouseDown");   // the sh box: focusable by nobody
    stage.dispatchMouse(80, 50, "mouseUp");
    say("blur: committed='" + String(st.committed) + "' focusGone=" + (stage.focus != ta.tf));
    if (String(st.committed) == "")
        fail("blurring the text area did not fire onCommit");
    else if (String(st.committed) != ta.tf.text)
        fail("onCommit got '" + String(st.committed) + "' but the field holds '" + ta.tf.text + "'");
}

setTimeout(ready, 900);
stage.showWindow(W, H, "probe textfx");

function ready():void
{
    var bd:BitmapData = frame();
    var root:UiNode = node("root");
    if (root == null) { fail("the page did not mount"); finish(); return; }
    if (root.absW != 460 || root.absH != 520)
        fail("root is " + root.absW + "x" + root.absH + " not 460x520");
    phaseSurface(bd);
    phaseText();
    phaseArea();
    setTimeout(function ():void { phaseBlur(); setTimeout(finish, 240); }, 240);
}

function finish():void
{
    var bd:BitmapData = frame();
    phaseSurface(bd);
    var lines:String = "";
    var names:Array = ["root", "sh", "gr", "ref", "wr", "el", "ta"];
    for (var i:int = 0; i < names.length; i++)
    {
        var m:UiNode = node(names[i]);
        if (m == null) { lines = lines + names[i] + " MISSING\n"; continue; }
        lines = lines + names[i] + " " + m.absX + "," + m.absY + "," + m.absW + "," + m.absH + "\n";
    }
    writeText(OUT + ".rects.txt", lines);
    writeText(OUT + ".samples.txt", log);
    writeBmp(OUT + ".bmp", bd);
    writeText(OUT + ".done", problems == "" ? "PASS" : "FAIL " + problems);
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
    var pxv:ByteArray = bd.getPixels(new Rectangle(0, 0, w, h));
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
    for (var y:int = h - 1; y >= 0; y--)
    {
        for (var x:int = 0; x < w; x++)
        {
            var i:int = (y * w + x) * 4;
            ba.writeByte(pxv[i + 3]);
            ba.writeByte(pxv[i + 2]);
            ba.writeByte(pxv[i + 1]);
            ba.writeByte(pxv[i]);
        }
    }
    var f:File = new File(path);
    var fs:FileStream = new FileStream();
    fs.open(f, FileMode.WRITE);
    fs.writeBytes(ba, 0, 0);
    fs.close();
}
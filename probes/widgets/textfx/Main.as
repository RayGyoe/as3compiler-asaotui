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
//   6. decoration -- `textDecoration: "underline" | "line-through"` drawn by US (the
//                    runtime's renderer never paints TextFormat.underline; see
//                    compiler-gaps G28), from the field's own line metrics. The
//                    assertion is geometric and glyph-independent: the string is
//                    "H    H", the sample point sits in the four-space GAP where no
//                    glyph can put ink, so "this pixel is the text colour" can only
//                    mean the LINE, and "one row above/below is white" can only mean
//                    it is one pixel thick. Where it lands is derived from
//                    getLineMetrics here, in the probe, NOT copied from the kit.
//   7. text bg   -- a text node owns a PAINT BOX (background/border/radius) like every
//                   other kind. It did not: TextWidget never created a shapeA, so
//                   PaintKit.paintBox returned early and `background` on a text node was
//                   accepted and silently unpainted. Magenta on white makes it a two-pixel
//                   question -- filled inside the box, white in the gap above it.
//
// Hand arithmetic (window 460x520, root column, padding 20, gap 12, alignItems
// flex-start, white, text 12px):
//
//   sh (20,20,120,60)   gr (20,92,160,40)   92 = 20 + 60 + 12
//   then ref / wr / el / ta / ul / stn / bg, each auto-height, in that order.
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
import flash.text.TextLineMetrics;
import flash.utils.ByteArray;
import flash.utils.setTimeout;

var W:int = 460;
var H:int = 520;
var OUT:String = 'textfx';

// 90 characters: ~540px at 12px, so it wraps to three lines at 200px and is far too
// long for the 120px ellipsis box.
var S:String = "The quick brown fox jumps over the lazy dog while the compiler measures every single line.";
// The decorated string: see UL_S for why the gap matters.
var DEC:String = "H    H";

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
    // "H    H": two capitals with four spaces between them. At 24px the gap is wide
    // enough (>= 20px) to sample INSIDE it, where the glyphs cannot reach -- that is
    // what makes "is this pixel the line?" a question about the decoration alone.
    private static const UL_S:StyleRefinement = StyleRefinement.from({
        text: { fontSize: 24, color: 0x111827, textDecoration: "underline" }
    });
    private static const ST_S:StyleRefinement = StyleRefinement.from({
        text: { fontSize: 24, color: 0x111827, textDecoration: "line-through" }
    });
    // A text node that carries a PAINT field. Every other kind owns a Shape for these and
    // draws it through PaintKit.paintBox; text used to own none, so `background` on a text
    // node was accepted and painted nothing (found by the docs audit, where three tinted
    // alignment lines came out untinted). Magenta because nothing else in this window is:
    // "the box is filled" and "the fill stops at the box" are then two pixel questions
    // with no ambiguity, and the string is short so the right half of the box is bare fill.
    private static const BG_S:StyleRefinement = StyleRefinement.from({
        size: [120, 20], background: 0xFF00FF, text: { color: 0xFFFFFF }
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
                onCommit: function (t:String):void { st.committed = t; } }),
            text(DEC, { key: "ul", style: UL_S, ariaName: "" }),
            text(DEC, { key: "stn", style: ST_S, ariaName: "" }),
            text("HH", { key: "bg", style: BG_S, ariaName: "" })
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

// ==================== phase 5: the decoration lines =========================
// The geometry is re-derived HERE from the field's own metrics (getLineMetrics),
// which is the anchor the kit also uses: the renderer paints the paragraph at (2,2)
// inside the field and each line box is one (ascent+descent+leading) stride lower.
// If the kit's rule changes, these numbers do not follow it -- they disagree, which
// is the point of writing the formula twice.
var DEC_INSET:Number = 2;       // AIR's field text inset (the renderer's 2.0)
var DEC_STRIKE:Number = 0.36;   // of the ascent, above the baseline

function phaseDecor(bd:BitmapData):void
{
    var ul:UiNode = node("ul");
    var stn:UiNode = node("stn");
    if (ul == null || stn == null) { fail("ul/stn missing"); return; }
    if (ul.tf == null || stn.tf == null) { fail("a decorated node has no field"); return; }

    var lm:TextLineMetrics = ul.tf.getLineMetrics(0);
    var lm2:TextLineMetrics = stn.tf.getLineMetrics(0);
    var asc:Number = Number(lm.ascent);
    if (!(asc > 0)) { fail("the decorated line reports ascent " + asc); return; }
    var topAbs:Number = ul.absY + ul.tf.y + DEC_INSET;
    var x0:int = Math.round(ul.absX + ul.tf.x + lm.x);
    var w:int = Math.round(lm.width);
    // Inside the four-space gap: the first H is ~17px wide at 24px, the run is ~62px,
    // so x0+30 is in the middle of nothing.
    var gapX:int = x0 + 30;

    // ---- underline: one row under the baseline, spanning the LINE (not the box) ---
    var ulY:int = Math.round(topAbs + asc + 1);
    var onLine:uint = pixel(bd, gapX, ulY);
    if (onLine != 0x111827)
        fail("no underline at (" + gapX + "," + ulY + "): " + hex(onLine) + " not #111827");
    if (pixel(bd, gapX, ulY - 1) != 0xFFFFFF)
        fail("the underline is thicker than 1px upward: (" + gapX + "," + (ulY - 1) + ") is "
            + hex(pixel(bd, gapX, ulY - 1)));
    if (pixel(bd, gapX, ulY + 1) != 0xFFFFFF)
        fail("the underline is thicker than 1px downward: (" + gapX + "," + (ulY + 1) + ") is "
            + hex(pixel(bd, gapX, ulY + 1)));
    // The line starts where the LINE starts (the field's 2px inset), not at x=0 of the
    // node -- a full-width rule would also be "an underline" to a looser probe.
    if (pixel(bd, x0 - 1, ulY) != 0xFFFFFF)
        fail("the underline starts before the line: (" + (x0 - 1) + "," + ulY + ") is "
            + hex(pixel(bd, x0 - 1, ulY)));
    if (pixel(bd, x0 + w + 3, ulY) != 0xFFFFFF)
        fail("the underline runs past the line's advance width: (" + (x0 + w + 3) + "," + ulY + ") is "
            + hex(pixel(bd, x0 + w + 3, ulY)));

    // ---- line-through: inside the glyph band, so only the GAP can prove it ------
    var stY:int = Math.round(stn.absY + stn.tf.y + DEC_INSET + Number(lm2.ascent)
        - Number(lm2.ascent) * DEC_STRIKE);
    var stX:int = Math.round(stn.absX + stn.tf.x + lm2.x) + 30;
    var onStrike:uint = pixel(bd, stX, stY);
    if (onStrike != 0x111827)
        fail("no line-through at (" + stX + "," + stY + "): " + hex(onStrike) + " not #111827");
    if (pixel(bd, stX, stY - 3) != 0xFFFFFF)
        fail("the line-through is not a thin line: (" + stX + "," + (stY - 3) + ") is "
            + hex(pixel(bd, stX, stY - 3)));
    if (pixel(bd, stX, stY + 3) != 0xFFFFFF)
        fail("the line-through is not a thin line: (" + stX + "," + (stY + 3) + ") is "
            + hex(pixel(bd, stX, stY + 3)));

    // ---- the negative: an undecorated node has no line where this one does -----
    var ref:UiNode = node("ref");
    if (ref != null)
    {
        var rlm:TextLineMetrics = ref.tf.getLineMetrics(0);
        var refY:int = Math.round(ref.absY + ref.tf.y + DEC_INSET + Number(rlm.ascent) + 1);
        var refX:int = Math.round(ref.absX + ref.tf.x + rlm.x) + 6;
        // #ref is "The quick..." -- the pixel under its baseline must stay white.
        if (pixel(bd, refX, refY) != 0xFFFFFF)
            fail("an UNDECORATED node drew a line at (" + refX + "," + refY + "): "
                + hex(pixel(bd, refX, refY)));
        say("decor: ulY=" + ulY + " asc=" + asc + " x0=" + x0 + " w=" + w
            + " strikeY=" + stY + " refY=" + refY);
    }
}

// ==================== phase 3b: the text PAINT box ===========================
function phaseTextBg(bd:BitmapData):void
{
    // ---- a text node's OWN paint box --------------------------------------
    // Sampled relative to the node's solved rect, so a font change cannot move the
    // question: the box must be filled where no glyph can reach, and the GAP ABOVE
    // it must still be the page white -- the second half is what proves the fill
    // belongs to the node's box and not to the whole row it sits in.
    var bg:UiNode = node("bg");
    if (bg == null) { fail("bg missing"); return; }
    if (bg.absX != 20 || bg.absW != 120 || bg.absH != 20)
        fail("bg is " + bg.absX + "," + bg.absY + "," + bg.absW + "," + bg.absH
            + " -- the box should be 120x20 at x=20");
    var face:uint = pixel(bd, bg.absX + 110, bg.absY + 10);
    var aboveBg:uint = pixel(bd, bg.absX + 110, bg.absY - 4);
    if (face != 0xFF00FF)
        fail("the text node paints no background: inside its box is " + hex(face)
            + ", expected #ff00ff (PaintKit.paintBox needs a shapeA to draw into)");
    if (aboveBg != 0xFFFFFF)
        fail("the text background escaped its box: " + hex(aboveBg) + " at y-4 above it");
    say("text bg: face=" + hex(face) + " above=" + hex(aboveBg)
        + " at " + bg.absX + "," + bg.absY + "," + bg.absW + "," + bg.absH);
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
    phaseDecor(bd);
    phaseTextBg(bd);
    setTimeout(function ():void { phaseBlur(); setTimeout(finish, 240); }, 240);
}

function finish():void
{
    var bd:BitmapData = frame();
    phaseSurface(bd);
    var lines:String = "";
    var names:Array = ["root", "sh", "gr", "ref", "wr", "el", "ta", "ul", "stn", "bg"];
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
// probes/widgets/typing/Main.as -- the single-line field, driven through the REAL
// runtime paths (Stage.dispatchMouse for the click/focus walk, Stage.dispatchText for
// every keystroke). It pins the two defects the gallery reported:
//
//   a. THE GHOST STAYED WHILE TYPING. The placeholder layer is shown only while the
//      model is empty AND the field is not focused. Both halves matter: a focused
//      EMPTY field draws a caret exactly where the ghost text is.
//   b. THE TEXT RENDERED TWICE after blur -> refocus. `paint` used to call
//      setTextFormat on every repaint; the runtime APPENDED a run per call instead
//      of replacing the range, and its run-to-paragraph builder emits the string
//      once per run -- so N repaints painted the same text N times (the field
//      visibly doubled). That emitter defect is compiler-gaps G20, FIXED in stage
//      268; this probe still pins the WIDGET side of the rule (time never holds
//      more than one copy of a string), which is why it outlives the bug.
//
// WHY THE PIXELS, NOT JUST THE PROPERTIES. `textWidth` is compared against a FRESH
// reference field carrying the same defaultTextFormat and the same string, so the
// assertion is font-independent (a doubled run makes it a multiple). On top of that
// every phase counts INK -- pixels inside the field that differ from its own
// background -- because the defect was visible, not structural: the ghost's ink must
// be absent while typing and present again after an empty blur, and the typed glyph
// run must not extend past one copy's width.
//
// HAND ARITHMETIC (window 420x320; root column, padding 20, gap 10, alignItems
// flex-start, white; children: the field (width 200, background 0xFEF3C7) then a
// button (size [140,32])):
//
//   inp   (20,20,200,32)     a field with no explicit height gets the 32pt default
//   other (20,62,140,32)     62 = 20 + 32 + 10
//
//   The placeholder is LONG and the typed text is SHORT, so the band x 110..216 is
//   inside the ghost and outside the typing: ink there means the ghost is on screen,
//   and nothing else can put ink there. (The band stops at 216 because a FOCUSED field
//   paints a 2px accent ring on its border box -- a decoration that is not text.)
//
// Protocol (tools/probe.cjs): dir name == output prefix; write <OUT>.rects.txt,
// <OUT>.bmp, <OUT>.done (PASS | FAIL <reason>).
import asaot.ui.*;
import asaot.ui.style.StyleRefinement;
import flash.display.BitmapData;
import flash.display.Stage;
import flash.display.StageAlign;
import flash.display.StageScaleMode;
import flash.events.MouseEvent;
import flash.filesystem.File;
import flash.filesystem.FileMode;
import flash.filesystem.FileStream;
import flash.geom.Rectangle;
import flash.text.TextField;
import flash.text.TextFormat;
import flash.utils.ByteArray;
import flash.utils.setTimeout;

var W:int = 420;
var H:int = 320;
var OUT:String = 'typing';

// The placeholder's measured glyphs have to reach past GHOST_X0 with a comfortable
// margin; the typed text stays far below it (see the header).
var GHOST_X0:int = 110;

var st:Object = {
    name: "",
    committed: "",
    changes: 0
};

class TypingProbe extends View
{
    private static const ROOT:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", alignItems: "flex-start",
        padding: 20, gap: 10, size: [420, 320],
        background: 0xFFFFFF, text: { fontSize: 12, color: 0x111827 }
    });
    private static const FIELD:StyleRefinement = StyleRefinement.from({
        size: [200, null], background: 0xFEF3C7, borderWidths: 1,
        borderColor: 0xD97706, padding: 8
    });
    private static const BTN:StyleRefinement = StyleRefinement.from({
        size: [140, 32], background: 0xE0E7FF
    });

    public function TypingProbe():void { super(); }

    override public function render():Node
    {
        return column({ key: "root", style: ROOT, ariaName: "typing probe" }, [
            textField({
                key: "inp", value: st.name, placeholder: "Placeholder text goes right here",
                style: FIELD,
                // DELIBERATELY NO invalidate() HERE. The field owes the screen its own
                // repaint (that is defect a): an author who stores the value and nothing
                // else is the modest case this probe must hold the widget to.
                onChange: function (v:String):void
                {
                    st.name = v;
                    st.changes = int(st.changes) + 1;
                },
                onCommit: function (v:String):void { st.committed = v; }
            }),
            button({ key: "other", label: "Other", style: BTN })
        ]);
    }
}

var view:TypingProbe = new TypingProbe();
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
    // Flushed on EVERY line on purpose: when a phase throws (#2025 and friends) the
    // chain dies before finish(), and this file is then the only record of how far it got.
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

function rgbAt(bd:BitmapData, x:int, y:int):uint
{
    return bd.getPixel(x, y) & 0xFFFFFF;
}

function hex(c:uint):String
{
    var s:String = c.toString(16);
    while (s.length < 6) s = "0" + s;
    return "#" + s;
}

function field():UiNode
{
    return app.findByKey("inp");
}

function ghostVisible():Boolean
{
    var n:UiNode = field();
    if (n == null) return false;
    var p:TextField = TextField(n.extra["placeholderField"]);
    return p == null ? false : p.visible;
}

// Ink = anything that is not the field's own background, inside its interior. The
// border is 1px and the band is kept 4px away from the rect edges, so a scan here can
// only ever see TEXT or the caret.
function inkCount(bd:BitmapData, x0:int, y0:int, x1:int, y1:int, bg:uint):int
{
    var c:int = 0;
    for (var y:int = y0; y <= y1; y++)
    {
        for (var x:int = x0; x <= x1; x++)
        {
            if (rgbAt(bd, x, y) != bg) c++;
        }
    }
    return c;
}

function ghostInk(bd:BitmapData):int
{
    // The field is (20,20,200,32) with a 2px FOCUS RING on its border box while the
    // field has the focus (the ring is the theme accent 0x2563EB, and it replaces the
    // declared 1px 0xD97706 edge), so the scan starts 3px inside that ring.
    return inkCount(bd, GHOST_X0, 23, 216, 49, 0xFEF3C7);
}

function inkRight(bd:BitmapData):int
{
    var right:int = -1;
    for (var x:int = 23; x <= 216; x++)
    {
        for (var y:int = 23; y <= 49; y++)
        {
            if (rgbAt(bd, x, y) != 0xFEF3C7) { right = x; break; }
        }
    }
    return right;
}

// A FRESH field with the live field's own default format: one copy of `t` measures
// exactly this, so any run accumulation shows up as a multiple.
function cleanTw(t:String):Number
{
    var n:UiNode = field();
    if (n == null || n.tf == null) return -1;
    var ref:TextField = new TextField();
    ref.defaultTextFormat = n.tf.defaultTextFormat;
    ref.text = t;
    return ref.textWidth;
}

// The doubling pin, in one place: the live field's width must equal a fresh field
// carrying the same string, and the painted glyphs must not reach past one copy.
function checkSingleCopy(bd:BitmapData, tag:String):void
{
    var n:UiNode = field();
    if (n == null) { fail(tag + ": the field is gone"); return; }
    var want:Number = cleanTw(n.tf.text);
    if (n.tf.textWidth != want)
        fail(tag + ": textWidth is " + n.tf.textWidth + " for '" + n.tf.text
            + "', a fresh field measures " + want + " (more than one copy of the string)");
    var left:Number = 20 + n.tf.x;
    var right:Number = inkRight(bd);
    if (right < 0)
        fail(tag + ": no glyphs painted at all for '" + n.tf.text + "'");
    else if (right > left + want + 8)
        fail(tag + ": the glyphs run to x=" + right + ", past one copy's "
            + (left + want) + " (duplicated text)");
    say(tag + ": text='" + n.tf.text + "' tw=" + n.tf.textWidth + " fresh=" + want
        + " inkRight=" + right + " left=" + left);
}

// The ghost pin, in one place: `shouldSee` is what the DESCRIPTOR logic promises --
// shown only while the model is empty and the field is not focused.
function checkGhost(bd:BitmapData, tag:String, shouldSee:Boolean):void
{
    var vis:Boolean = ghostVisible();
    var ink:int = ghostInk(bd);
    if (vis != shouldSee)
        fail(tag + ": the ghost is " + (vis ? "visible" : "hidden") + ", expected "
            + (shouldSee ? "visible" : "hidden"));
    if (shouldSee && ink <= 0)
        fail(tag + ": the ghost claims to be visible but painted no ink at x>=" + GHOST_X0);
    if (!shouldSee && ink > 0)
        fail(tag + ": the ghost painted " + ink + " ink pixel(s) at x>=" + GHOST_X0
            + " while it should be hidden");
    say(tag + ": ghost=" + (vis ? "on" : "off") + " ghostInk=" + ink
        + " model='" + String(st.name) + "' focus=" + (stage.focus == field().tf));
}

function clickField():void
{
    stage.dispatchMouse(120, 36, "mouseDown");
    stage.dispatchMouse(120, 36, "mouseUp");
}

function clickOther():void
{
    stage.dispatchMouse(90, 78, "mouseDown");
    stage.dispatchMouse(90, 78, "mouseUp");
}

function typeText(t:String):void
{
    for (var i:int = 0; i < t.length; i++) stage.dispatchText(t.charAt(i));
}

setTimeout(ready, 900);
stage.showWindow(W, H, "probe typing");

// ==================== phase 0: the untouched field ===========================
function ready():void
{
    var bd:BitmapData = frame();
    var root:UiNode = app.findByKey("root");
    var n:UiNode = field();
    var other:UiNode = app.findByKey("other");
    if (root == null || n == null || other == null) { fail("the page did not mount"); finish(); return; }
    if (root.absX != 0 || root.absY != 0 || root.absW != 420 || root.absH != 320)
        fail("root is " + root.absX + "," + root.absY + "," + root.absW + "," + root.absH);
    if (n.absX != 20 || n.absY != 20 || n.absW != 200 || n.absH != 32)
        fail("the field is " + n.absX + "," + n.absY + "," + n.absW + "," + n.absH
            + " not 20,20,200,32");
    if (other.absX != 20 || other.absY != 62 || other.absW != 140 || other.absH != 32)
        fail("the button is " + other.absX + "," + other.absY + "," + other.absW + "," + other.absH
            + " not 20,62,140,32");
    checkGhost(bd, "mount", true);
    say("mount: field " + n.absX + "," + n.absY + "," + n.absW + "," + n.absH
        + " tf " + n.tf.x + "," + n.tf.y + "," + n.tf.width + "," + n.tf.height);
    setTimeout(phaseFocus, 120);
}

// ==================== phase 1: focused and empty ============================
function phaseFocus():void
{
    clickField();
    setTimeout(function ():void {
        var bd:BitmapData = frame();
        if (!(stage.focus == field().tf))
            fail("clicking the field did not give its TextField the stage focus");
        // DEFECT a, first half: an empty FOCUSED field shows a caret exactly where the
        // ghost text sits, so the ghost must already be hidden here.
        checkGhost(bd, "focused", false);
        typeText("1111");
        setTimeout(phaseTyped, 320);
    }, 220);
}

// ==================== phase 2: four characters ==============================
function phaseTyped():void
{
    var bd:BitmapData = frame();
    var n:UiNode = field();
    if (n.tf.text != "1111") fail("typed text is '" + n.tf.text + "' not '1111'");
    if (String(st.name) != "1111") fail("the model is '" + String(st.name) + "' not '1111'");
    if (int(st.changes) != 4) fail("onChange ran " + int(st.changes) + " times, not 4");
    if (n.value != "1111") fail("the node's value is '" + n.value + "' not '1111'");
    // DEFECT a, second half: the FIRST keystroke already hides the ghost.
    checkGhost(bd, "typed", false);
    checkSingleCopy(bd, "typed");
    // ... and it must stay that way when the frame repaints for other reasons.
    repaintThen(checkRepainted, 3);
}

// A dirty frame with no model change: the state that used to append a run per paint.
function repaintThen(next:Function, times:int):void
{
    if (times <= 0) { next(); return; }
    view.invalidate(Dirty.ALL);
    setTimeout(function ():void { repaintThen(next, times - 1); }, 220);
}

function checkRepainted():void
{
    var bd:BitmapData = frame();
    checkGhost(bd, "repainted", false);
    checkSingleCopy(bd, "repainted");
    clickOther();
    setTimeout(afterBlur, 320);
}

// ==================== phase 3: blurred with text ============================
function afterBlur():void
{
    var bd:BitmapData = frame();
    if (stage.focus == field().tf) fail("clicking the button did not blur the field");
    if (String(st.committed) != "1111")
        fail("onCommit got '" + String(st.committed) + "' not '1111'");
    checkGhost(bd, "blurred", false);
    checkSingleCopy(bd, "blurred");
    clickField();
    setTimeout(afterRefocus, 320);
}

// ==================== phase 4: refocus and type one more ====================
function afterRefocus():void
{
    var n:UiNode = field();
    if (n.tf.text != "1111")
        fail("refocusing changed the text to '" + n.tf.text + "' (the caret reset is fine, a rewrite is not)");
    typeText("9");
    setTimeout(afterNine, 320);
}

function afterNine():void
{
    var bd:BitmapData = frame();
    var n:UiNode = field();
    if (n.tf.text != "11119") fail("after refocus + '9' the text is '" + n.tf.text + "' not '11119'");
    if (int(st.changes) != 5) fail("onChange ran " + int(st.changes) + " times, not 5");
    // DEFECT b: this is exactly the frame that used to show the text twice.
    checkGhost(bd, "afterNine", false);
    checkSingleCopy(bd, "afterNine");
    repaintThen(checkNineRepainted, 2);
}

function checkNineRepainted():void
{
    var bd:BitmapData = frame();
    checkSingleCopy(bd, "nineRepainted");

    // ---- the caret must survive a repaint -------------------------------------
    // The field may only be rewritten when it DISAGREES with the model: assigning
    // `text` re-creates it, and the caret lands at the end of the inserted run. The
    // frame loop repaints, so clicking into the MIDDLE of the text and then letting
    // several dirty frames pass is the cheapest way to see whether the field is being
    // rewritten behind the user's back. (Comparing before/after keeps this exact in
    // any font -- only the drift matters, not where the click landed.)
    stage.dispatchMouse(39, 36, "mouseDown");
    stage.dispatchMouse(39, 36, "mouseUp");
    setTimeout(afterCaretClick, 300);
}

function afterCaretClick():void
{
    var n:UiNode = field();
    var c:int = n.tf.caretIndex;
    if (n.tf.text != "11119") fail("the click changed the text to '" + n.tf.text + "'");
    if (c >= 5)
    {
        // A vacuous test is worse than none: the click was supposed to land inside the
        // glyphs, which also proves the click->caret walk still works.
        fail("clicking inside the text left the caret at " + c + " (idle, so the repaint test would prove nothing)");
        afterCaretRepaint(c);
        return;
    }
    say("caretClicked: " + c + " of '" + n.tf.text + "'");
    repaintThen(function ():void { afterCaretRepaint(c); }, 3);
}

function afterCaretRepaint(c0:int):void
{
    var n:UiNode = field();
    if (n.tf.caretIndex != c0)
        fail("the caret moved from " + c0 + " to " + n.tf.caretIndex
            + " across a repaint (the field was rewritten although it already matched the model)");
    checkSingleCopy(frame(), "caretRepainted");
    // Emptied from the MODEL, while the field still has the focus.
    st.name = "";
    view.invalidate(Dirty.ALL);
    setTimeout(phaseEmptyFocused, 320);
}

// ==================== phase 5: empty while focused ==========================
function phaseEmptyFocused():void
{
    var bd:BitmapData = frame();
    var n:UiNode = field();
    if (n.tf.text != "") fail("clearing the model left '" + n.tf.text + "' in the field");
    checkGhost(bd, "emptyFocused", false);
    clickOther();
    setTimeout(afterEmptyBlur, 320);
}

// ==================== phase 6: empty after a blur ===========================
function afterEmptyBlur():void
{
    var bd:BitmapData = frame();
    if (stage.focus == field().tf) fail("the field kept the focus after clicking away");
    // The ghost comes BACK: an empty, unfocused field is the one case that shows it.
    checkGhost(bd, "emptyBlurred", true);
    st.name = "11119";
    view.invalidate(Dirty.ALL);
    setTimeout(finish, 320);
}

function finish():void
{
    var bd:BitmapData = frame();
    var n:UiNode = field();
    if (n.tf.text != "11119") fail("the final frame shows '" + n.tf.text + "' not '11119'");
    checkGhost(bd, "final", false);

    var lines:String = "";
    var names:Array = ["root", "inp", "other"];
    for (var i:int = 0; i < names.length; i++)
    {
        var m:UiNode = app.findByKey(names[i]);
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
    var f:File = File.applicationDirectory.resolvePath(path);
    var fs:FileStream = new FileStream();
    fs.open(f, FileMode.WRITE);
    fs.writeUTFBytes(t);
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
    for (var y:int = h - 1; y >= 0; y--)
    {
        for (var x:int = 0; x < w; x++)
        {
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
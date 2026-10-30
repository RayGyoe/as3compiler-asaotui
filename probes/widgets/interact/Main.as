// probes/widgets/interact/Main.as -- the probe for the INTERACTION group
// (element state -> pixels, the text-field write-back, and the UiApp keyboard /
// focus pipeline).
//
// Output prefix MUST equal the directory name (`interact`).
//
// EVERY EXPECTED NUMBER BELOW IS ARITHMETIC FROM A HANDFUL OF CONSTANTS:
//
//   root column, padding 20, gap 10, alignItems flex-start, 760x560
//     btnA  button  140x32  background 0x2563EB   -> 20,20
//     btnD  button  140x32  disabled               -> 20,62
//     inp   textField 200x32                        -> 20,104
//     nxt   button  140x32                          -> 20,146
//
//   PaintKit.HOVER_LIFT = 8% toward white, PRESS_SINK = 12% toward black, and
//   mixRGB rounds each channel:
//     0xE0E7FF hovered  = (224+2, 231+2, 255+0) = 0xE2E9FF
//     0xE0E7FF pressed  = (224-27, 231-28, 255-31) = 0xC5CBE0
//   (0xE0=224, 0xE7=231, 0xFF=255; (255-224)*.08=2.48->2, (255-231)*.08=1.92->2,
//    0*.08=0; 224*.12=26.88->27, 231*.12=27.72->28, 255*.12=30.6->31)
//
//   DISABLED_ALPHA = 0.45, FOCUS_RING = 0x2563EB, FOCUS_RING_W = 2 (so the ring's
//   left bar covers x = 20..21, i.e. the single pixel (21,36) is the ring).
//
// The scene is staged in FOUR phases because a hover, a press and a focus are all
// transient: each one is asserted against the pixel it must change AND against the
// pixel it must restore, then the next phase starts.
import asaot.ui.*;
import asaot.ui.style.*;
import flash.display.BitmapData;
import flash.display.Stage;
import flash.display.StageAlign;
import flash.display.StageScaleMode;
import flash.events.Event;
import flash.events.KeyboardEvent;
import flash.events.MouseEvent;
import flash.filesystem.File;
import flash.filesystem.FileMode;
import flash.filesystem.FileStream;
import flash.geom.Rectangle;
import flash.utils.ByteArray;
import flash.utils.setTimeout;

var W:int = 760;
var H:int = 560;
var OUT:String = 'interact';

// The fill is DELIBERATELY not the accent colour: the focus ring is 0x2563EB, and a
// ring pixel that happens to equal the fill would make the ring assertion vacuous
// (the interact mutation run found exactly that).
var SERIF:uint = 0xE0E7FF;
var HOVERED:uint = 0xE2E9FF;
var PRESSED:uint = 0xC5CBE0;
var RING:uint = 0x2563EB;      // PaintKit.FOCUS_RING

var st:Object = {
    aDis: false,
    name: "",
    committed: "",
    clicks: 0,
    deadClicks: 0
};

class InteractProbe extends View
{
    private static const ROOT:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", alignItems: "flex-start",
        padding: 20, gap: 10, size: [760, 560],
        background: 0xFFFFFF, text: { fontSize: 12, color: 0x111827 }
    });
    private static const BTN:StyleRefinement = StyleRefinement.from({
        size: [140, 32], background: 0xE0E7FF
    });

    public function InteractProbe():void { super(); }

    override public function render():Node
    {
        return column({ key: "root", style: ROOT, ariaName: "interaction probe" }, [
            button({
                key: "btnA", label: "Live", style: BTN, disabled: st.aDis,
                onClick: function ():void { st.clicks = st.clicks + 1; }
            }),
            button({
                key: "btnD", label: "Dead", style: BTN, disabled: true,
                onClick: function ():void { st.deadClicks = st.deadClicks + 1; }
            }),
            textField({
                key: "inp", value: st.name, placeholder: "Type here", width: 200,
                onChange: function (v:String):void { st.name = v; },
                onCommit: function (v:String):void { st.committed = v; }
            }),
            button({
                key: "nxt", label: "Next", style: BTN,
                onClick: function ():void { st.clicks = st.clicks + 1; }
            })
        ]);
    }
}

var view:InteractProbe = new InteractProbe();
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

setTimeout(settle, 900);
stage.showWindow(W, H, "probe interact");

var carry:String = "";

// ---- phase 0: the idle scene ------------------------------------------------
function settle():void
{
    var names:Array = ["root", "btnA", "btnD", "inp", "nxt"];
    var lines:String = "";
    var missing:int = 0;
    for (var i:int = 0; i < names.length; i++)
    {
        var n:UiNode = app.findByKey(names[i]);
        if (n == null) { missing = missing + 1; lines = lines + names[i] + " MISSING\n"; continue; }
        lines = lines + names[i] + " " + n.absX + "," + n.absY + "," + n.absW + "," + n.absH + "\n";
    }
    writeText(OUT + ".rects.txt", lines);

    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    writeBmp(OUT + ".bmp", bd);
    if (missing > 0) { writeText(OUT + ".done", "FAIL " + missing + " node(s) missing"); return; }

    var problems:String = "";

    // (a) the interaction state is DECLARED, mirrored and defaulted.
    var a:UiNode = app.findByKey("btnA");
    var d:UiNode = app.findByKey("btnD");
    if (a.state.disabled != 0) problems = problems + "the live button starts disabled; ";
    if (d.state.disabled == 0) problems = problems + "the disabled button did not mirror `disabled`; ";

    // (b) DISABLED IS AN ALPHA, not a colour: it has to dim the label and the
    //     border too, so it is applied to the backing (UiNode), not the fill.
    if (d.backing.alpha != 0.45) problems = problems + "a disabled node's backing alpha is " + d.backing.alpha + " not 0.45; ";
    if (a.backing.alpha != 1) problems = problems + "a live node's backing alpha is " + a.backing.alpha + " not 1; ";
    // ...and the SAME surface must therefore render differently. The exact dimmed
    // value is (0x25*0.45 + 255*0.55, ...) through the compositor, which is not an
    // integer this probe should predict -- the IDLE colour is, and the difference
    // is what proves the dimming reached the screen.
    problems = problems + expectStr(bd, 26, 26, SERIF, "the live button's fill");
    problems = problems + expectDiff(bd, 26, 26, 26, 68, "a disabled button paints the same colour as a live one");

    // (c) DISABLED IS INERT: the click must not reach the handler, even though it
    //     was dispatched straight at the node (handleClick, not the pick walk).
    clickLocal(d, 10, 10);
    clickLocal(a, 10, 10);
    if (st.deadClicks != 0) problems = problems + "a disabled button ran its onClick " + st.deadClicks + " time(s); ";
    if (st.clicks != 1) problems = problems + "the live button ran its onClick " + st.clicks + " time(s) not 1; ";

    carry = problems;
    setTimeout(phaseHover, 100);
}

// ---- phase 1: HOVER --------------------------------------------------------
// Through the REAL pointer path: the library derives hover from one stage
// MOUSE_MOVE and the click's own hit test, so a probe that dispatched mouseOver at
// the backing would be testing a listener that is gone (and would pass while the
// whole app had no hover at all).
// btnA's centre is (90,36); btnD's is (90,78).
function phaseHover():void
{
    send(90, 36, "mouseMove");
    setTimeout(checkHover, 250);
}

function checkHover():void
{
    var problems:String = carry;
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    problems = problems + expectStr(bd, 26, 26, HOVERED, "the hovered button's fill (8% toward white)");
    // A disabled button does not react to the pointer at all.
    var before:uint = bd.getPixel(26, 68) & 0xFFFFFF;
    send(90, 78, "mouseMove");
    carry = problems;
    setTimeout(function ():void { checkHoverDisabled(before); }, 250);
}

function checkHoverDisabled(before:uint):void
{
    var problems:String = carry;
    if (app.findByKey("btnD").state.hover == 0)
        problems = problems + "the disabled button did not even record the hover (it must not paint it, but the flag is not the guard); ";
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    var after:uint = bd.getPixel(26, 68) & 0xFFFFFF;
    if (after != before) problems = problems + "a disabled button lifted its fill on hover (" + hex(before) + " -> " + hex(after) + "); ";
    // Leave the pointer — over the root's own padding, i.e. off every control.
    send(700, 520, "mouseMove");
    carry = problems;
    setTimeout(checkUnhovered, 250);
}

function checkUnhovered():void
{
    var problems:String = carry;
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    problems = problems + expectStr(bd, 26, 26, SERIF, "the fill did not return to idle after the pointer left");
    carry = problems;
    setTimeout(phasePress, 100);
}

// ---- phase 2: PRESS --------------------------------------------------------
function phasePress():void
{
    app.findByKey("btnA").backing.dispatchEvent(new MouseEvent(MouseEvent.MOUSE_DOWN, false, false));
    setTimeout(checkPress, 250);
}

function checkPress():void
{
    var problems:String = carry;
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    problems = problems + expectStr(bd, 26, 26, PRESSED, "the pressed button's fill (12% toward black)");
    app.findByKey("btnA").backing.dispatchEvent(new MouseEvent(MouseEvent.MOUSE_UP, false, false));
    carry = problems;
    setTimeout(checkReleased, 250);
}

function checkReleased():void
{
    var problems:String = carry;
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    problems = problems + expectStr(bd, 26, 26, SERIF, "the fill did not return to idle after MOUSE_UP");
    carry = problems;
    setTimeout(phaseFocus, 100);
}

// ---- phase 3: FOCUS + the TAB RING ----------------------------------------
function phaseFocus():void
{
    app.focusNode(app.findByKey("btnA"));
    setTimeout(checkFocus, 250);
}

function checkFocus():void
{
    var problems:String = carry;
    var f:UiNode = app.focusedNode();
    if (f == null || String(f.key) != "btnA") problems = problems + "focusNode did not take (focused: " + (f == null ? "null" : f.key) + "); ";
    if (app.findByKey("btnA").state.focused == 0) problems = problems + "the focused node's state.focused is 0; ";
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    // The ring is 2px INSIDE the box: (21,36) is the left bar, (26,26) is still the
    // fill (the ring must not eat the whole control).
    problems = problems + expectStr(bd, 21, 36, RING, "the focus ring's left bar");
    problems = problems + expectStr(bd, 26, 26, SERIF, "the focus ring painted over the fill");
    carry = problems;
    setTimeout(phaseTab, 100);
}

// ---- phase 4: TAB (forward skips the disabled control, Shift+Tab reverses) --
function phaseTab():void
{
    // btnA is focused; btnD is disabled, so the next stop is the text field.
    key(9, false);
    setTimeout(checkTab1, 250);
}

function checkTab1():void
{
    var problems:String = carry;
    var f:UiNode = app.focusedNode();
    var k:String = f == null ? "null" : String(f.key);
    if (k != "inp") problems = problems + "Tab from btnA landed on " + k + " not inp (a disabled control must be skipped); ";
    if (app.tabMoves != 1) problems = problems + "tabMoves is " + app.tabMoves + " not 1 (the ring is ours, not the runtime's); ";
    carry = problems;
    key(9, true);
    setTimeout(checkTab2, 250);
}

function checkTab2():void
{
    var problems:String = carry;
    var f:UiNode = app.focusedNode();
    var k:String = f == null ? "null" : String(f.key);
    if (k != "btnA") problems = problems + "Shift+Tab from inp landed on " + k + " not btnA; ";
    carry = problems;
    setTimeout(phaseType, 100);
}

// ---- phase 5: the TEXT FIELD write-back ------------------------------------
function phaseType():void
{
    // Focus the field the way a user's click would.
    app.focusNode(app.findByKey("inp"));
    var inp:UiNode = app.findByKey("inp");
    // A real edit: the runtime's text pipeline writes tf.text and dispatches
    // Event.CHANGE on the field. That is the ONLY signal the widget gets, so
    // dispatching it here is the exact contract being tested.
    inp.tf.text = "Ada";
    inp.tf.dispatchEvent(new Event(Event.CHANGE, false, false));
    setTimeout(checkTyped, 250);
}

function checkTyped():void
{
    var problems:String = carry;
    var inp:UiNode = app.findByKey("inp");
    if (st.name != "Ada") problems = problems + "the field did not write the model back (value: '" + st.name + "'); ";
    if (inp.value != "Ada") problems = problems + "the retained node's value is '" + inp.value + "' not 'Ada'; ";
    // THE BUG THIS FEATURE EXISTS FOR: a repaint must not erase the typing.
    if (inp.tf.text != "Ada") problems = problems + "a repaint erased the typing (field is '" + inp.tf.text + "'); ";
    carry = problems;
    key(13, false);      // Enter commits
    setTimeout(checkCommitted, 250);
}

function checkCommitted():void
{
    var problems:String = carry;
    if (st.committed != "Ada") problems = problems + "Enter did not commit (onCommit got '" + st.committed + "'); ";
    // Enter must not ALSO have activated the field as a button (`click`), and it
    // must not have re-run the button handler.
    if (st.clicks != 1) problems = problems + "Enter over the text field fired the button handler (" + st.clicks + "); ";
    carry = problems;
    setTimeout(phaseDisable, 100);
}

// ---- phase 6: a DISABLED FLIP at runtime -----------------------------------
function phaseDisable():void
{
    st.aDis = true;
    app.invalidate(Dirty.VALUE);
    setTimeout(checkDisabledFlip, 350);
}

function checkDisabledFlip():void
{
    var problems:String = carry;
    var a:UiNode = app.findByKey("btnA");
    if (a.state.disabled == 0) problems = problems + "the disabled flip did not reach the node; ";
    if (a.backing.alpha != 0.45) problems = problems + "the disabled flip did not reach the display object (alpha " + a.backing.alpha + "); ";
    if (app.focusedNode() == a) problems = problems + "a node that became disabled kept the keyboard focus; ";
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    // Not just "dimmed": the fill must no longer BE the live colour at all.
    problems = problems + expectNot(bd, 26, 26, SERIF, "the disabled flip left the live colour on screen");
    carry = problems;
    setTimeout(finish, 100);
}

function finish():void
{
    var problems:String = carry;
    writeText(OUT + ".done", problems == "" ? "PASS" : "FAIL " + problems);
}

// ---- helpers ---------------------------------------------------------------
function key(code:int, shift:Boolean):void
{
    var e:KeyboardEvent = new KeyboardEvent(KeyboardEvent.KEY_DOWN, true, true,
        0, code, 0, false, false, shift, false, false, false);
    stage.dispatchEvent(e);
}

function expectStr(bd:BitmapData, x:int, y:int, rgb:uint, what:String):String
{
    var got:uint = bd.getPixel(x, y) & 0xFFFFFF;
    if (got == rgb) return "";
    return what + " is " + hex(got) + " not " + hex(rgb) + "; ";
}

function expectNot(bd:BitmapData, x:int, y:int, rgb:uint, what:String):String
{
    var got:uint = bd.getPixel(x, y) & 0xFFFFFF;
    if (got != rgb) return "";
    return what + " (still " + hex(got) + "); ";
}

function expectDiff(bd:BitmapData, x1:int, y1:int, x2:int, y2:int, what:String):String
{
    var a:uint = bd.getPixel(x1, y1) & 0xFFFFFF;
    var b:uint = bd.getPixel(x2, y2) & 0xFFFFFF;
    if (a != b) return "";
    return what + " (" + hex(a) + " at " + x1 + "," + y1 + " == " + hex(b) + " at " + x2 + "," + y2 + "); ";
}

function hex(v:uint):String
{
    var s:String = (v & 0xFFFFFF).toString(16);
    while (s.length < 6) s = "0" + s;
    return "#" + s;
}

function clickLocal(n:UiNode, lx:Number, ly:Number):void
{
    n.backing.dispatchEvent(new MouseEvent(MouseEvent.CLICK, true, false, lx, ly));
}

// A real pointer move at stage coordinates: the stage hit-tests, then UiApp derives
// hover from the target (one listener, the click's own hit test).
function send(x:Number, y:Number, type:String):void
{
    try
    {
        stage.dispatchMouse(x, y, type);
    }
    catch (err:Error)
    {
        carry = carry + type + " at (" + x + "," + y + ") threw " + err.name + ": " + err.message + "; ";
    }
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
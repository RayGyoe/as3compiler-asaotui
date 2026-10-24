// probes/widgets/callback/Main.as -- the probe for the AUTHOR-CALLBACK contract,
// and for the slider's drag.
//
// Output prefix MUST equal the directory name (`callback`), because tools/probe.cjs
// derives the expected file names from it.
//
// WHY THIS PROBE EXISTS
// ---------------------
// Every control's `onChange` is declared to take the NEW value, and every docs page
// declares it that way (`function (v:Boolean)`, `function (v:Number)`). The widgets
// used to call `onChange()` with NO argument. On AVM2 that is not a silent no-op: a
// closure that declares a parameter, called with fewer arguments, throws
// "Error #1063: Argument count mismatch". The frame guard then swallows it, so the
// page still rendered, the model never changed, and the only trace was a console
// line -- which is exactly the report that produced this probe: the docs' slider
// threw #1063 on every click and "did not move".
//
// The old form probe could not see it: it only ever clicked BOUND controls (the
// `binding != null` branch), never the `onChange` branch. So the two branches are
// now covered by different probes and this one owns the unbound one.
//
// What it pins:
//   * each unbound control reports the NEW value to a ONE-ARGUMENT handler, exactly
//     once per gesture, and the value actually arrives (a #1063 leaves the counter
//     at zero -- the probe names that instead of timing out);
//   * the slider's PRESS sets the value, a DRAG follows the pointer 1:1 through the
//     stage (including beyond the node, i.e. the temporary stage listener), the
//     release detaches it, and the CLICK the window glue sends afterwards does NOT
//     report a second time;
//   * the value change reaches the SCREEN: the pixel checks below are taken after
//     the drag on a sliders whose label never changed, which is the case the old
//     `invalidate(Dirty.VALUE)`-only path failed (no M_PAINT was ever raised, so
//     nothing repainted -- the docs hid it because "Volume 41%" relayouts).
import asaot.ui.*;
import asaot.ui.style.*;
import flash.display.BitmapData;
import flash.display.Stage;
import flash.display.StageAlign;
import flash.display.StageScaleMode;
import flash.events.MouseEvent;
import flash.filesystem.File;
import flash.filesystem.FileMode;
import flash.filesystem.FileStream;
import flash.geom.Rectangle;
import flash.utils.ByteArray;
import flash.utils.setTimeout;

var W:int = 240;
var H:int = 162;
var OUT:String = 'callback';

// The probe's model. It is written by the callbacks and read by render(), exactly
// like an author's model -- an unbound control whose author does nothing would be
// reverted by payload()'s mirror on the next describe (that is the CONTROLLED
// contract, not the thing under test here).
class CallbackProbe extends View
{
    private static const ROOT:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", padding: 10, gap: 10, size: [240, 162],
        background: 0xF3F4F6, text: { fontSize: 12, color: 0x111827 }
    });
    private static const N24:StyleRefinement = StyleRefinement.from({ size: [200, 24] });
    private static const S40:StyleRefinement = StyleRefinement.from({ size: [200, 40] });

    public var ckOn:Boolean = false;
    public var tgOn:Boolean = false;
    public var rdOn:Boolean = false;
    public var slVal:Number = 0;

    // Observables. A #1063 never runs the body, so a zero here IS the defect.
    public var boolCalls:int = 0;
    public var lastBool:Boolean = false;
    public var numCalls:int = 0;
    public var lastNum:Number = -1;

    public function CallbackProbe():void
    {
        super();
    }

    override public function render():Node
    {
        var self:CallbackProbe = this;
        return column({ key: "root", style: ROOT, ariaName: "callback" }, [
            // NOTE the factory shapes: `checkbox(opts)` takes the label INSIDE the bag,
            // while toggle/radio/slider take (label, opts).
            checkbox({ key: "ck", label: "A", style: N24, checked: this.ckOn,
                onChange: function (v:Boolean):void { self.ckOn = v; self.boolCalls = self.boolCalls + 1; self.lastBool = v; } }),
            toggle("B", { key: "tg", style: N24, checked: this.tgOn,
                onChange: function (v:Boolean):void { self.tgOn = v; self.boolCalls = self.boolCalls + 1; self.lastBool = v; } }),
            radio("C", { key: "rd", style: N24, group: "g", selected: this.rdOn,
                onChange: function (v:Boolean):void { self.rdOn = v; self.boolCalls = self.boolCalls + 1; self.lastBool = v; } }),
            slider("D", { key: "sl", style: S40, value: this.slVal,
                onChange: function (v:Number):void { self.slVal = v; self.numCalls = self.numCalls + 1; self.lastNum = v; } })
        ]);
    }
}

var view:CallbackProbe = new CallbackProbe();
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

var problems:String = "";
// Gesture exceptions, collected by send() below. DECLARED HERE, with the other
// top-level state, and not next to send(): a file-scope initializer is emitted in
// SOURCE ORDER between the top-level statements, and `stage.showWindow(...)` below
// blocks for the life of the window -- anything initialised after it is dead code.
// (Measured: declared after showWindow, this stayed NULL and the probe failed with
// "a gesture threw: null" on a run where nothing threw.)
var threw:String = "";

// Stage coordinates of the four controls, from the layout derivation in
// expect.json: x = 10 + padding is inside the node, y = the node's rows.
//   ck 10..34, tg 44..68, rd 78..102, sl 112..152 (node x 10..210).
setTimeout(settle, 900);
stage.showWindow(W, H, "probe callback");

function settle():void
{
    var names:Array = ["ck", "tg", "rd", "sl"];
    var lines:String = "";
    var missing:int = 0;
    var i:int;
    for (i = 0; i < names.length; i++)
    {
        var n:UiNode = app.findByKey(names[i]);
        if (n == null) { missing = missing + 1; lines = lines + names[i] + " MISSING\n"; continue; }
        lines = lines + names[i] + " " + n.absX + "," + n.absY + "," + n.absW + "," + n.absH + "\n";
    }
    writeText(OUT + ".rects.txt", lines);

    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    writeBmp(OUT + ".bmp", bd);

    if (missing > 0)
    {
        writeText(OUT + ".done", "FAIL " + missing + " node(s) missing");
        return;
    }
    setTimeout(booleanClicks, 250);
}

function failWhat(what:String):String
{
    return what + " threw, or its handler did not run: ";
}

// A press anywhere in the track, through the stage's hit test (the real routing
// path). A MouseEvent dispatched straight at the backing would carry stageX = 0,
// so the widget -- which converts the POINTER position, not the target-relative
// one -- could not use it.
//
// NOTE the y: a control's pick region is its DRAWN region, not its layout box
// (as_pick_hit_local), and a slider paints nothing above its track. The track is
// the 8pt band at local y = h-12 .. h-4, i.e. stage y = node.y + 28 .. 36 -- so
// y = 144 is inside the 112..152 box AND on the track, while the box's centre
// (132) is empty space and would route the press to the column instead.
// Gestures run inside a try/catch. Not belt-and-braces: a #1063 thrown by a handler
// unwinds the whole DISPATCH, so an uncaught one skips the rest of the probe's
// setTimeout chain and the program never writes <name>.done at all -- the tool would
// report an opaque TIMEOUT instead of "the handler did not run". The counter
// assertions elsewhere still name the control; `threw` names the exception.
function send(x:Number, y:Number, type:String):void
{
    try
    {
        stage.dispatchMouse(x, y, type);
    }
    catch (err:Error)
    {
        threw = threw + type + " at (" + x + "," + y + "): " + err.message + "; ";
    }
}

function press(x:Number, y:Number):void
{
    send(x, y, "mouseDown");
}

function release(x:Number, y:Number):void
{
    send(x, y, "mouseUp");
}

// What the window glue sends after a release (src/emit.ts dispatch "click").
function glueClick(x:Number, y:Number):void
{
    send(x, y, "click");
}

// ---- phase 1: the three boolean controls -----------------------------------
function booleanClicks():void
{
    var ck:UiNode = app.findByKey("ck");
    press(18, 22);
    release(18, 22);
    glueClick(18, 22);
    if (view.boolCalls != 1 || view.lastBool != true || !view.ckOn)
    {
        problems = problems + "checkbox onChange " + failWhat("checkbox") + "calls=" + view.boolCalls
            + " arg=" + view.lastBool + " model=" + view.ckOn + "; ";
    }

    press(38, 56);
    release(38, 56);
    glueClick(38, 56);
    if (view.boolCalls != 2 || view.lastBool != true || !view.tgOn)
    {
        problems = problems + "toggle onChange " + failWhat("toggle") + "calls=" + view.boolCalls
            + " arg=" + view.lastBool + " model=" + view.tgOn + "; ";
    }

    press(18, 90);
    release(18, 90);
    glueClick(18, 90);
    if (view.boolCalls != 3 || view.lastBool != true || !view.rdOn)
    {
        problems = problems + "radio onChange " + failWhat("radio") + "calls=" + view.boolCalls
            + " arg=" + view.lastBool + " model=" + view.rdOn + "; ";
    }

    // A radio does not toggle off on a second click, so it must not report again.
    press(18, 90);
    release(18, 90);
    glueClick(18, 90);
    if (view.boolCalls != 3)
    {
        problems = problems + "a second click on the selected radio reported again (calls="
            + view.boolCalls + "); ";
    }
    setTimeout(booleanPixels, 250);
}

// Hand-derived pixel checks for the three ON states. The check mark of a checkbox
// is a 2pt white stroke through local (4,12)->(7,16)->(13,8); (8,10) is 2.8px off
// that path, so it is solid fill: the box is 16x16 at local (0,4), fill #2F80ED
// when checked. The switch's track is 36x20 at local y=2 -- green #34D399 when on
// -- and the knob MOVES to the right when on (centre x=26, radius 8), so the
// sample is local (8,12), LEFT of the knob, not the (28,12) the form probe uses
// for its OFF switch. The radio dot is a 4px blue disc at its centre (8,12).
function booleanPixels():void
{
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    problems = problems + expectStr(bd, 18, 16, 0x2F80ED, "the checked checkbox's fill");
    problems = problems + expectStr(bd, 18, 56, 0x34D399, "the toggled switch's track");
    problems = problems + expectStr(bd, 18, 90, 0x2563EB, "the selected radio's dot");
    setTimeout(sliderPress, 250);
}

// ---- phase 2: the slider's press ------------------------------------------
function sliderPress():void
{
    var sl:UiNode = app.findByKey("sl");
    if (sl == null)
    {
        problems = problems + "sl missing; ";
        finish();
        return;
    }
    if (sl.binding != null)
    {
        // This probe owns the UNBOUND branch (the bound one is probes/widgets/form).
        problems = problems + "the slider took a Binding: this probe measures the onChange branch; ";
    }
    // local x 50 of 200 = 0.25.
    press(60, 144);
    if (view.numCalls != 1 || !near(view.lastNum, 0.25) || !near(view.slVal, 0.25))
    {
        problems = problems + "slider onChange " + failWhat("slider") + "calls=" + view.numCalls
            + " arg=" + view.lastNum + " model=" + view.slVal + " (press at local 50 of 200 = 0.25); ";
    }
    release(60, 144);
    glueClick(60, 144);
    // The press already did the work: the glue's CLICK must not report a second time.
    if (view.numCalls != 1)
    {
        problems = problems + "the click after a press reported again (calls=" + view.numCalls + "); ";
    }
    setTimeout(dragPress, 250);
}

// ---- phase 3a: press, then ONE move, then look at the screen --------------
// The pixel check has to be taken on the frame AFTER a lone MOVE, with no press and
// no release in the same callback: `UiNode.setPressed` raises its own paint request,
// and a press in the same frame would mask a widget that never asked for one. Here
// nothing has changed except the value (the label is a constant "D"), so the ONLY
// reason the knob is allowed to move is SliderWidget.commit's markPaint.
function dragPress():void
{
    // Press where the value already is: no change, so no report.
    press(60, 144);
    if (view.numCalls != 1)
    {
        problems = problems + "pressing where the value already is reported a change (calls="
            + view.numCalls + "); ";
    }
    setTimeout(dragMove, 250);
}

function dragMove():void
{
    // local 150 of 200 = 0.75.
    send(160, 144, "mouseMove");
    if (view.numCalls != 2 || !near(view.lastNum, 0.75))
    {
        problems = problems + "the drag did not follow to 0.75 (calls=" + view.numCalls
            + " arg=" + view.lastNum + "); ";
    }
    setTimeout(dragMidPixels, 250);
}

// Value 0.75: fill = 200*0.75 = 150 wide, so the knob (white disc radius 7 with a
// 2pt blue stroke) is centred at local (150,32) and the track is bare right of it.
// Without the widget's own paint request this frame still shows value 0.25 -- the
// knob at local 50, i.e. a WHITE knob exactly where (60,144) is.
// NOTE the samples: the FILL (hard-coded #2563EB) and the KNOB (hard-coded white)
// do not read the node's interaction state, but the grey TRACK does
// (`PaintKit.stateColor`), and mid-drag the node is PRESSED -- (200,144) is the
// pressed tint #CACBCF, not #E5E7EB. So the bare-track sample is taken after the
// release (sliderPixels), and this frame checks the two stable colours.
function dragMidPixels():void
{
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    problems = problems + expectStr(bd, 60, 144, 0x2563EB, "the fill after a drag to 0.75 (the knob must follow the drag)");
    problems = problems + expectStr(bd, 160, 144, 0xFFFFFF, "the knob after a drag to 0.75");
    setTimeout(dragEnd, 250);
}

// ---- phase 3b: clamps, the release, and one gesture = one report ----------
function dragEnd():void
{
    // Beyond the node's right edge (the node ends at x=210): the stage listener must
    // still own the pointer, and the value must clamp at 1.
    send(250, 144, "mouseMove");
    if (view.numCalls != 3 || !near(view.lastNum, 1))
    {
        problems = problems + "a drag past the end did not clamp at 1 (calls=" + view.numCalls
            + " arg=" + view.lastNum + "); ";
    }
    // ... and all the way back to 0. A one-way mapping that only ever grows would
    // pass the two checks above.
    send(10, 144, "mouseMove");
    if (view.numCalls != 4 || !near(view.lastNum, 0))
    {
        problems = problems + "a leftward drag did not reach 0 (calls=" + view.numCalls
            + " arg=" + view.lastNum + "); ";
    }
    release(10, 144);
    // The release ENDS the drag: a later move must not be one (the flag, and the
    // detachment of the stage listener, are the same contract -- see
    // ScrollViewWidget.endDrag).
    send(110, 144, "mouseMove");
    if (view.numCalls != 4 || !near(view.slVal, 0))
    {
        problems = problems + "the stage listener survived the release (calls=" + view.numCalls
            + " model=" + view.slVal + "); ";
    }
    // A fresh press with no drag: local 100 of 200 = 0.5, then the glue's click.
    press(110, 144);
    release(110, 144);
    glueClick(110, 144);
    if (view.numCalls != 5 || !near(view.lastNum, 0.5) || !near(view.slVal, 0.5))
    {
        problems = problems + "a press with no drag did not set 0.5 (calls=" + view.numCalls
            + " arg=" + view.lastNum + " model=" + view.slVal + "); ";
    }
    setTimeout(sliderPixels, 250);
}

// The settled value after the release. Value 0.5: fill = 100 wide, knob centre at
// local (100,32) -> stage (110,144), bare track right of it.
function sliderPixels():void
{
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    problems = problems + expectStr(bd, 60, 144, 0x2563EB, "the slider's filled half (value 0.5)");
    problems = problems + expectStr(bd, 110, 144, 0xFFFFFF, "the slider's knob centre");
    problems = problems + expectStr(bd, 160, 144, 0xE5E7EB, "the slider's empty half");
    finish();
}

function finish():void
{
    if (threw != "") problems = problems + "a gesture threw: " + threw;
    writeText(OUT + ".done", problems == "" ? "PASS" : "FAIL " + problems);
}

function near(a:Number, b:Number):Boolean
{
    var d:Number = a - b;
    if (d < 0) d = -d;
    return d < 0.001;
}

function expectStr(bd:BitmapData, x:int, y:int, rgb:uint, what:String):String
{
    var got:uint = bd.getPixel(x, y) & 0xFFFFFF;
    if (got == rgb) return "";
    return what + " is " + hex(got) + " not " + hex(rgb) + " at (" + x + "," + y + "); ";
}

function hex(v:uint):String
{
    var s:String = (v & 0xFFFFFF).toString(16);
    while (s.length < 6) s = "0" + s;
    return "#" + s;
}

function writeText(path:String, t:String):void
{
    var f:File = new File(path);
    var fs:FileStream = new FileStream();
    fs.open(f, FileMode.WRITE);
    fs.writeUTFBytes(t);
    fs.close();
}

// 32-bit bottom-up BMP written by hand (copied verbatim from
// probes/widgets/form/Main.as): this runtime has BitmapData but no PNG encoder,
// and a raw frame buffer is BETTER evidence than an encoded image -- it is a 1:1
// copy of the compositor output, so the samplers compare exact integers.
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
    var y:int;
    var x:int;
    for (y = h - 1; y >= 0; y--)
    {
        for (x = 0; x < w; x++)
        {
            var i:int = (y * w + x) * 4;
            ba.writeByte(px[i + 3]);
            ba.writeByte(px[i + 2]);
            ba.writeByte(px[i + 1]);
            ba.writeByte(px[i]);
        }
    }
    var f:File = new File(path);
    var fs:FileStream = new FileStream();
    fs.open(f, FileMode.WRITE);
    fs.writeBytes(ba, 0, 0);
    fs.close();
}
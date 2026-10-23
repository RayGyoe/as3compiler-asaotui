// probes/widgets/form/Main.as -- the probe for the FORM widget group
// (radio / switch / slider / progress).
//
// Output prefix MUST equal the directory name (`form`), because tools/probe.cjs
// derives the expected file names from it.
//
// What it pins, and why each thing is here:
//   * the RECTS of a fixed column (padding 10 / gap 10, all explicit sizes) --
//     hand-computed positions, verified externally against expect.json;
//   * one exact PIXEL per visual state, 4px clear of every glyph:
//       radio on  = inner dot blue,  radio off = white interior over the grey page
//       switch on = green track,     switch off = grey track
//       slider    = blue fill / white knob / grey track, progress at 0 and 1;
//   * TWO things a bitmap cannot show: that the four kinds registered with
//     Widgets, and that clicking writes back through a Binding (a bound radio,
//     a bound switch, and a click-to-set bound slider).
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
var H:int = 280;
var OUT:String = 'form';

// The probe's observable model: the bound controls read from / write to it.
class FormModel extends Observable
{
    public var radioSel:Boolean = false;   // bound to r2
    public var switchOn:Boolean = false;   // bound to s2
    public var sliderVal:Number = 0.5;     // bound to sl
}

class FormProbe extends View
{
    private static const ROOT:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", padding: 10, gap: 10, size: [240, 280],
        background: 0xF3F4F6, text: { fontSize: 12, color: 0x111827 }
    });
    private static const NODE24:StyleRefinement = StyleRefinement.from({ size: [200, 24] });
    private static const SLIDER_S:StyleRefinement = StyleRefinement.from({ size: [200, 40] });
    private static const PROG_S:StyleRefinement = StyleRefinement.from({ size: [200, 32] });

    public var model:FormModel;

    public function FormProbe(m:FormModel):void
    {
        super();
        this.model = m;
    }

    override public function render():Node
    {
        return column({ key: "root", style: ROOT, ariaName: "form" }, [
            radio("Alpha", { key: "r1", style: NODE24, selected: true, group: "g" }),
            radio("Beta", { key: "r2", style: NODE24, selected: bindTo(this.model, "radioSel"), group: "g" }),
            toggle("Wifi", { key: "s1", style: NODE24, checked: true }),
            toggle("BT", { key: "s2", style: NODE24, checked: bindTo(this.model, "switchOn") }),
            slider("Vol", { key: "sl", style: SLIDER_S, value: bindTo(this.model, "sliderVal") }),
            progress("Zero", { key: "p0", style: PROG_S, value: 0 }),
            progress("Full", { key: "p1", style: PROG_S, value: 1 })
        ]);
    }
}

var model:FormModel = new FormModel();
var view:FormProbe = new FormProbe(model);
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

setTimeout(settle, 900);
stage.showWindow(W, H, "probe form");

function settle():void
{
    var names:Array = ["r1", "r2", "s1", "s2", "sl", "p0", "p1"];
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

    solveAtSettle = app.layoutSolves;
    frame0 = app.enterFrameTicks;
    if (missing > 0) { writeText(OUT + ".done", "FAIL " + missing + " node(s) missing"); return; }
    setTimeout(steady, 400);
}

var solveAtSettle:Number = 0;
var frame0:int = 0;

function steady():void
{
    var problems:String = "";

    // (a0) A Binding keeps its identity inside an option bag, and a bound FALSE
    // arrives as FALSE. This is the regression guard for compiler-gaps.md G9:
    // `Boolean(x)` where x is declared `Object` lowers to a pointer test, so a
    // bound `false` reads as true and r2 silently paints SELECTED. Asserting the
    // flag directly means a G9 regression names its own cause instead of only
    // showing up as a mysterious colour change.
    var tb:Binding = bindTo(model, "radioSel");
    var bag:Object = { selected: tb, checked: tb, value: tb };
    if (!(bag.selected is Binding)) problems = problems + "a Binding stored in an option bag lost its identity (the factory would take the wrong branch); ";
    var r2node:UiNode = app.findByKey("r2");
    if (r2node != null)
    {
        if (r2node.binding == null) problems = problems + "r2.binding is null: the factory did not take the `is Binding` branch; ";
        if (r2node.checked) problems = problems + "r2.checked is true but the model says false (G9: boxed false read as truthy); ";
    }

    // (a) kinds registered -- a bitmap cannot show a registry miss.
    if (!Widgets.has("radio")) problems = problems + "Widgets.has('radio') is false; ";
    if (!Widgets.has("switch")) problems = problems + "Widgets.has('switch') is false; ";
    if (!Widgets.has("slider")) problems = problems + "Widgets.has('slider') is false; ";
    if (!Widgets.has("progress")) problems = problems + "Widgets.has('progress') is false; ";

    // (b) clicking a bound radio writes back through its Binding.
    var r2:UiNode = app.findByKey("r2");
    if (r2 == null) problems = problems + "r2 missing; ";
    else
    {
        r2.handleClick();
        if (model.radioSel != true) problems = problems + "radio binding not written: " + model.radioSel + "; ";
    }

    // (c) clicking a bound switch writes back through its Binding.
    var s2:UiNode = app.findByKey("s2");
    if (s2 == null) problems = problems + "s2 missing; ";
    else
    {
        s2.handleClick();
        if (model.switchOn != true) problems = problems + "switch binding not written: " + model.switchOn + "; ";
    }

    // (d) clicking the slider at localX=150 of 200 sets the value to 0.75.
    var sl:UiNode = app.findByKey("sl");
    if (sl == null) problems = problems + "sl missing; ";
    else
    {
        sl.backing.dispatchEvent(new MouseEvent(MouseEvent.CLICK, true, false, 150, 20));
        if (model.sliderVal < 0.7 || model.sliderVal > 0.8) problems = problems + "slider click did not set value: " + model.sliderVal + "; ";
    }

    // (e) a settled tree never re-solves layout.
    var extraSolves:Number = app.layoutSolves - solveAtSettle;
    var extraFrames:int = app.enterFrameTicks - frame0;
    if (extraFrames < 2) problems = problems + "only " + extraFrames + " frame(s) elapsed; ";
    if (extraSolves > 0) problems = problems + "a settled tree re-solved layout " + extraSolves + " time(s); ";

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

// 32-bit bottom-up BMP written by hand (copied verbatim from
// probes/widgets/chip/Main.as): this runtime has BitmapData but no PNG encoder,
// and a raw frame buffer is BETTER evidence than an encoded image -- it is a
// 1:1 copy of the compositor output, so the samplers can compare exact integers.
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
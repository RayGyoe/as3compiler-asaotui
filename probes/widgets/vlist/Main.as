// probes/widgets/vlist/Main.as -- VIRTUALISATION: the mounted window, the clip, the
// wheel, and the keys.
//
// Output prefix MUST equal the directory name (`vlist`).
//
// WHAT IS BEING MEASURED. ListNode's own header states its boundary: every item
// becomes a UiNode, so a 10k list builds 10k nodes. This probe measures the removal
// of that boundary, and it has to be measured in BOTH directions:
//
//   * READY: with count = 1000 the tree must hold NINE row nodes, not a thousand.
//     "It feels fast" is not a measurement; the child count is.
//   * CORRECT: the nine rows must be the RIGHT nine, at the right pixels. A list
//     that mounts rows 0..8 forever would pass the first assertion and be useless,
//     so the probe scrolls (through the real wheel path), asserts the new window by
//     key, and then reads the FRAME BUFFER at the top of the viewport -- the row
//     colour there must be row 3's, which proves the pixels moved with the window
//     and not just the bookkeeping.
//
// HAND ARITHMETIC (window 320x260; root column, padding 20, background white;
// vlist at x=20, y=20, size 200x150; rowHeight 20; count 1000):
//
//   fit          = ceil(150/20) = 8      (rows that fit, incl. the partial one)
//   window       = 8 + 1 = 9 rows        (the +1 is the partial row a non-multiple
//                                         viewport shows, see virtualList.as)
//   rows at      = 20, 40, 60, 80, 100, 120, 140, 160, 180
//   viewport     = y 20..170, so row 8 (180..200) is mounted but FULLY clipped
//   row colour   = 0x101010 * (i + 1)    -> r0 #101010, r3 #404040, r7 #808080
//
//   pixel (30,25)  inside r0                    -> #101010
//   pixel (30,165) inside r7 (160..180)         -> #808080
//   pixel (30,175) below the viewport, inside r8 but clipped -> #ffffff
//   ... and after one wheel notch (3 rows, offset 60, rows r3..r11 at 20,40,...):
//   pixel (30,25)  inside r3                    -> #404040
//
// Protocol (tools/probe.cjs): dir name == output prefix; write <OUT>.rects.txt,
// <OUT>.bmp, <OUT>.done (PASS | FAIL <reason>).
import asaot.ui.*;
import asaot.ui.style.StyleRefinement;
import flash.display.BitmapData;
import flash.display.Stage;
import flash.display.StageAlign;
import flash.display.StageScaleMode;
import flash.events.KeyboardEvent;
import flash.filesystem.File;
import flash.filesystem.FileMode;
import flash.filesystem.FileStream;
import flash.geom.Rectangle;
import flash.utils.ByteArray;
import flash.utils.setTimeout;

var W:int = 320;
var H:int = 260;
var OUT:String = 'vlist';
var ROW_H:int = 20;
var COUNT:int = 1000;

class VListModel extends Observable
{
    public var off:Number = 0;
}

class VListProbe extends View
{
    public var model:VListModel;

    private static const ROOT:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", alignItems: "flex-start",
        padding: 20, gap: 10, size: [320, 260], background: 0xFFFFFF
    });

    public function VListProbe(m:VListModel):void
    {
        super();
        this.model = m;
    }

    override public function render():Node
    {
        return column({ key: "root", style: ROOT, ariaName: "vlist probe" }, [
            virtualList({
                key: "vl",
                size: [200, 150],
                rowHeight: ROW_H,
                count: COUNT,
                offsetY: model.off,
                renderRow: rowFor,
                onScroll: scrolled
            })
        ]);
    }
}

// One mounted row. The background encodes the row's ABSOLUTE index, which is what
// makes "the window really moved" readable from a single pixel.
function rowFor(i:int):Node
{
    return box({ key: "vl:r" + i, style: StyleRefinement.from({ background: 0x101010 * (i + 1) }) });
}

var onScrollSaw:Number = -1;

function scrolled(y:Number):void
{
    onScrollSaw = y;
    model.off = y;
    view.invalidate(Dirty.ALL);
}

var model:VListModel = new VListModel();
var view:VListProbe = new VListProbe(model);
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

var problems:String = "";
var log:String = "";
var SolvesAtStart:int = -1;

function say(s:String):void
{
    log = log + s + "\n";
    trace(s);
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

function keysOf(n:UiNode):String
{
    var out:String = "";
    for (var i:int = 0; i < n.children.length; i++)
    {
        var c:UiNode = n.children[i];
        out = out + (i == 0 ? "" : ",") + String(c.key);
        if (c.absH != ROW_H)
            fail("row " + c.key + " is " + c.absH + " tall, not " + ROW_H
                + " (a row must not be flexed into the viewport)");
    }
    return out;
}

setTimeout(ready, 900);
stage.showWindow(W, H, "probe vlist");

function ready():void
{
    var bd:BitmapData = frame();
    var vl:UiNode = app.findByKey("vl");
    if (vl == null) { fail("the vlist never mounted"); finish(); return; }
    var desc:VirtualListNode = VirtualListNode(vl.desc);

    if (vl.absX != 20 || vl.absY != 20 || vl.absW != 200 || vl.absH != 150)
        fail("vlist is " + vl.absX + "," + vl.absY + "," + vl.absW + "," + vl.absH + " not 20,20,200,150");

    // (a) THE POINT OF THE WIDGET: nine nodes for a thousand items.
    if (desc.firstIndex != 0 || desc.lastIndex != 8)
        fail("first/last are " + desc.firstIndex + "/" + desc.lastIndex + " not 0/8");
    if (desc.visibleCount != 8)
        fail("visibleCount is " + desc.visibleCount + " not 8 (ceil(150/20))");
    // EVERY INDEX READ BELOW IS GUARDED BY THIS. A mutation that mounts the wrong
    // number of rows must be reported as the named failure, not crash the probe on an
    // out-of-range Vector read (which writes no verdict at all, and a mutation
    // harness cannot tell that apart from a build that never ran).
    var windowOk:Boolean = vl.children.length == 9;
    if (!windowOk)
        fail("mounted " + vl.children.length + " rows for " + COUNT + " items, not 9 (the window is " + COUNT + "x smaller)");
    if (app.findByKey("vl:r0") == null || app.findByKey("vl:r8") == null)
        fail("the window is not r0..r8 (keys: " + keysOf(vl) + ")");
    if (app.findByKey("vl:r9") != null)
        fail("row r9 is mounted but is outside the window");

    // (b) the rows are stacked at rowHeight and are NOT shrunk.
    if (windowOk && (vl.children[0].absY != 20 || vl.children[7].absY != 160 || vl.children[8].absY != 180))
        fail("row tops are " + vl.children[0].absY + "/" + vl.children[7].absY + "/" + vl.children[8].absY + " not 20/160/180");

    // (c) pixels: the first row, the last visible row, and the CLIP.
    if (rgbAt(bd, 30, 25) != 0x101010)
        fail("the top of the viewport is " + hex(rgbAt(bd, 30, 25)) + " not row 0's #101010");
    if (rgbAt(bd, 30, 165) != 0x808080)
        fail("y=165 is " + hex(rgbAt(bd, 30, 165)) + " not row 7's #808080");
    // r8 spans 180..200 and the viewport ends at 170: without the clip this pixel
    // would be r8's #909090 painted BELOW the viewport.
    if (rgbAt(bd, 30, 175) != 0xFFFFFF)
        fail("y=175 is " + hex(rgbAt(bd, 30, 175)) + " -- row 8 painted outside the viewport (the clip is missing)");

    SolvesAtStart = app.layoutSolves;
    say("ready: window " + desc.firstIndex + ".." + desc.lastIndex + " mounted " + vl.children.length
        + " keys " + keysOf(vl) + " solves " + SolvesAtStart);

    // The REAL wheel path: Stage hit-tests the point, dispatches a bubbling
    // MOUSE_WHEEL, and this widget's listener answers. delta = -1 means "toward the
    // end" (the runtime's own convention, see the widget header).
    stage.dispatchWheel(100, 100, -1);
    setTimeout(afterWheel, 350);
}

function afterWheel():void
{
    var bd:BitmapData = frame();
    var vl:UiNode = app.findByKey("vl");
    if (vl == null) { fail("the vlist vanished after the wheel"); finish(); return; }
    var desc:VirtualListNode = VirtualListNode(vl.desc);

    if (onScrollSaw != 60)
        fail("onScroll reported " + onScrollSaw + " not 60 (3 rows x 20)");
    if (desc.offsetY != 60)
        fail("offsetY is " + desc.offsetY + " not 60");
    if (desc.firstIndex != 3 || desc.lastIndex != 11)
        fail("after the wheel first/last are " + desc.firstIndex + "/" + desc.lastIndex + " not 3/11");
    if (vl.children.length != 9)
        fail("the window is " + vl.children.length + " rows after scrolling, not 9");
    if (app.findByKey("vl:r0") != null)
        fail("row r0 is still mounted after scrolling past it (stale rows are never unmounted)");
    if (app.findByKey("vl:r3") == null || app.findByKey("vl:r11") == null)
        fail("the window after the wheel is not r3..r11 (keys: " + keysOf(vl) + ")");
    if (vl.children.length > 0 && vl.children[0].absY != 20)
        fail("the first mounted row is at y=" + vl.children[0].absY + " not 20 (rows must restart at the viewport top)");

    // The pixels followed the window: row 3 is now at the top.
    if (rgbAt(bd, 30, 25) != 0x404040)
        fail("the top of the viewport is " + hex(rgbAt(bd, 30, 25)) + " not row 3's #404040 (the keys moved but not the pixels)");
    if (rgbAt(bd, 30, 165) != 0xB0B0B0)
        fail("y=165 is " + hex(rgbAt(bd, 30, 165)) + " not row 10's #b0b0b0");
    if (rgbAt(bd, 30, 175) != 0xFFFFFF)
        fail("y=175 is " + hex(rgbAt(bd, 30, 175)) + " -- the clip was lost after scrolling");
    if (app.layoutSolves <= SolvesAtStart)
        fail("a different window did not re-solve layout (" + SolvesAtStart + " -> " + app.layoutSolves + ")");

    say("afterWheel: window " + desc.firstIndex + ".." + desc.lastIndex + " off " + desc.offsetY
        + " keys " + keysOf(vl) + " solves " + app.layoutSolves);

    app.focusNode(app.findByKey("vl"));
    setTimeout(afterFocus, 200);
}

// ---- keys: End jumps to the last window, Home comes back --------------------
function afterFocus():void
{
    var f:UiNode = app.focusedNode();
    if (f == null || String(f.key) != "vl") { fail("the vlist could not take focus"); finish(); return; }
    key(35, false);   // End
    setTimeout(afterEnd, 300);
}

function afterEnd():void
{
    var vl:UiNode = app.findByKey("vl");
    var desc:VirtualListNode = VirtualListNode(vl.desc);
    // fit = 8, so the last full window starts at 1000 - 8 = 992 and the reported
    // offset is 992*20 = 19840. The offset matters as much as the window: it is what
    // the AUTHOR stores, and it is the only thing that proves the widget clamped the
    // request instead of reporting a nonsense End jump (1<<28) back to the model.
    if (desc.firstIndex != 992)
        fail("End landed on row " + desc.firstIndex + " not 992 (count 1000 - 8 that fit)");
    if (desc.lastIndex != 999)
        fail("End's window ends at row " + desc.lastIndex + " not 999");
    if (vl.children.length != 8)
        fail("the last window mounts " + vl.children.length + " rows, not 8 (there is no 9th)");
    if (onScrollSaw != 19840)
        fail("End's onScroll reported " + onScrollSaw + " not 19840 (992 rows x 20): the request was not clamped before it reached the author");
    say("afterEnd: window " + desc.firstIndex + ".." + desc.lastIndex + " mounted " + vl.children.length + " onScroll " + onScrollSaw);
    key(36, false);   // Home
    setTimeout(afterHome, 300);
}

function afterHome():void
{
    var vl:UiNode = app.findByKey("vl");
    var desc:VirtualListNode = VirtualListNode(vl.desc);
    if (desc.firstIndex != 0)
        fail("Home landed on row " + desc.firstIndex + " not 0");
    if (onScrollSaw != 0)
        fail("Home's onScroll reported " + onScrollSaw + " not 0");
    say("afterHome: window " + desc.firstIndex + ".." + desc.lastIndex);

    // ---- an AUTHOR-SUPPLIED offset past the end -------------------------
    // The wheel and the keys clamp before they report; an author who writes
    // `offsetY: 99999` straight into the model does not. The FACTORY must clamp it,
    // or the window arithmetic produces an empty list with a white viewport.
    model.off = 99999;
    view.invalidate(Dirty.ALL);
    setTimeout(afterOverflow, 350);
}

function afterOverflow():void
{
    var vl:UiNode = app.findByKey("vl");
    var desc:VirtualListNode = VirtualListNode(vl.desc);
    if (desc.firstIndex != 992)
        fail("an offset of 99999 landed on row " + desc.firstIndex + " not 992 (the factory did not clamp it)");
    if (desc.offsetY != 19840)
        fail("the clamped offset is " + desc.offsetY + " not 19840");
    if (vl.children.length != 8)
        fail("the clamped window mounts " + vl.children.length + " rows, not 8");
    say("afterOverflow: window " + desc.firstIndex + ".." + desc.lastIndex + " off " + desc.offsetY);
    // Back to the top for the frame buffer, so <OUT>.bmp / <OUT>.rects.txt describe the
    // SAME state expect.json pins (the overflow window's colours are 0x101010*993 and
    // nowhere near a hand-computable value).
    model.off = 0;
    view.invalidate(Dirty.ALL);
    setTimeout(finish, 400);
}

function key(code:int, shift:Boolean):void
{
    var e:KeyboardEvent = new KeyboardEvent(KeyboardEvent.KEY_DOWN, true, true,
        0, code, 0, false, false, shift, false, false, false);
    stage.dispatchEvent(e);
}

function finish():void
{
    var bd:BitmapData = frame();
    var lines:String = "";
    var names:Array = ["root", "vl", "vl:r0", "vl:r3", "vl:r8", "vl:r11"];
    for (var i:int = 0; i < names.length; i++)
    {
        var n:UiNode = app.findByKey(names[i]);
        if (n == null) { lines = lines + names[i] + " MISSING\n"; continue; }
        lines = lines + names[i] + " " + n.absX + "," + n.absY + "," + n.absW + "," + n.absH + "\n";
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
    var f:File = new File(path);
    var fs:FileStream = new FileStream();
    fs.open(f, FileMode.WRITE);
    fs.writeBytes(ba, 0, 0);
    fs.close();
}
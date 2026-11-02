// probes/widgets/select-scroll/Main.as -- a dropdown OPENED INSIDE A SCROLLED VIEWPORT
// must hang under its trigger, not under where the trigger would be without the scroll.
//
// Output prefix MUST equal the directory name (`select-scroll`).
//
// THE DEFECT. A scroll viewport scrolls by `backing.scrollRect` (ScrollViewWidget's
// header): the slide lives in the CLIP, never in a child's rect. `absX/absY` are
// therefore LAYOUT coordinates -- they do not move when the pane scrolls. An open
// select is LIFTED onto the stage container and positioned at its "absolute" rect
// (UiNode.applyLift, probes/widgets/popup), and a lift by definition leaves the
// viewport that was sliding it: nothing shifts the node any more, so it appears at
// the UNSCROLLED position -- 40px of scroll is 40px of offset between the trigger and
// the dropdown that is supposed to be flush under it.
//
// WHAT IS PINNED HERE
//   * at offset 0 the lift is byte-for-byte today's behaviour (the control);
//   * at offset 40 the lifted backing's y is `absY - clipY`, i.e. it keeps the slide
//     it lost, and the PIXELS agree: the selected row lands on its scrolled row and
//     the pane's own content shows where the unshifted dropdown used to be;
//   * a TAP on a row after scrolling picks the row under the finger (the router
//     dispatches localX/localY, which have the same "layout, not screen" problem);
//   * closing returns the backing to its layout parent -- no sprite left on the stage.
//
// HAND ARITHMETIC (window 320x280; root column, padding 10, background 0x111111;
// viewport 280x140 at (10,10), background 0xF5F5F5, no bars; children in order:
// spacer 280x40 0xDDDDDD, select (width 200), spacer 280x200 0xCCCCCC)
//
//   contentH = 40 + 34 + 200 = 274, viewport 140  ->  maxOffsetY = 134
//   sel abs  = (10, 50, 200, 34)      50 = 10 + 40
//   dropdown = (10, 84, 200, 88)      84 = 50 + 34; MENU_PANEL is 1px border + 4px
//     padding, rows are 26 tall:      row0 89..115  row1(selected) 115..141
//                                     row2 141..167
//   at offsetY 40, the lift must place the node at y = 50 - 40 = 10:
//     trigger 10..44, dropdown 44..132, row0 49..75, row1 75..101, row2 101..127.
//     So (100,88) is the SELECTED row (#dbeafe), (100,120) is row2 (#ffffff) and
//     (100,140) is past the dropdown and shows the pane's spacer (#cccccc). Without
//     the shift those three points read row0 white / row1 #dbeafe / row2 white.
//
// Protocol (tools/probe.cjs): dir name == output prefix; write <OUT>.rects.txt,
// <OUT>.bmp, <OUT>.done (PASS | FAIL <reason>).
import asaot.ui.*;
import asaot.ui.style.StyleRefinement;
import flash.display.BitmapData;
import flash.display.DisplayObjectContainer;
import flash.display.Stage;
import flash.display.StageAlign;
import flash.display.StageScaleMode;
import flash.events.TouchEvent;
import flash.filesystem.File;
import flash.filesystem.FileMode;
import flash.filesystem.FileStream;
import flash.geom.Rectangle;
import flash.utils.ByteArray;
import flash.utils.setTimeout;

var W:int = 320;
var H:int = 280;
var OUT:String = "select-scroll";

var checks:int = 0;
var failures:String = "";
var log:String = "";

// The author's model. `offsetY` is DECLARED so it is a position request (ScrollViewNode
// header), which is how the probe scrolls: the same path a "back to top" button uses.
var svOffset:Number = 0;
var selOpen:Boolean = false;
var selValue:String = "Beta";
var picks:int = 0;

var OPTIONS:Array = ["Alpha", "Beta", "Gamma"];

class SelectScrollProbe extends View
{
    private static const ROOT:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", padding: 10, size: [320, 280], background: 0x111111
    });
    private static const SV:StyleRefinement = StyleRefinement.from({
        size: [280, 140], background: 0xF5F5F5
    });
    private static const SPACER_A:StyleRefinement = StyleRefinement.from({
        size: [280, 40], background: 0xDDDDDD
    });
    private static const SPACER_B:StyleRefinement = StyleRefinement.from({
        size: [280, 200], background: 0xCCCCCC
    });

    public function SelectScrollProbe():void { super(); }

    override public function render():Node
    {
        return column({ key: "root", style: ROOT }, [
            scrollView({ key: "sv", style: SV, offsetY: svOffset,
                         scrollbarX: "never", scrollbarY: "never" }, [
                box({ key: "spa", style: SPACER_A, ariaName: "" }),
                select({ key: "sel", width: 200, options: OPTIONS, value: selValue,
                         open: selOpen,
                         onSelect: function (i:int):void {
                             selValue = String(OPTIONS[i]);
                             picks = picks + 1;
                             app.invalidate(Dirty.VALUE);
                         },
                         onOpenChange: function (o:Boolean):void {
                             selOpen = o;
                             app.invalidate(Dirty.VALUE);
                         } }),
                box({ key: "spb", style: SPACER_B, ariaName: "" })
            ])
        ]);
    }
}

var view:SelectScrollProbe = new SelectScrollProbe();
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

setTimeout(settle, 900);
stage.showWindow(W, H, "probe select-scroll");

function settle():void
{
    writeText(OUT + ".rects.txt",
        "root " + rectOf(app.findByKey("root")) + "\n"
        + "sv " + rectOf(app.findByKey("sv")) + "\n"
        + "sel " + rectOf(app.findByKey("sel")) + "\n");
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    writeBmp(OUT + ".bmp", bd);
    setTimeout(phaseInit, 250);
}

// ---- phase 1: the arithmetic this probe is built on -----------------------
function phaseInit():void
{
    stageMark("init");
    var sv:ScrollViewNode = ScrollViewNode(app.findByKey("sv").desc);
    var sel:UiNode = app.findByKey("sel");
    expect(sv.contentH == 274, "content height is " + sv.contentH + ", want 274");
    expect(sv.maxOffsetY == 134, "max offset is " + sv.maxOffsetY + ", want 134");
    expect(sv.offsetY == 0, "the pane did not start at the top (" + sv.offsetY + ")");
    expect(!sel.lifted, "a CLOSED select is already lifted");
    expect(sel.backing.parent == sel.parent.backing,
        "a closed select left its layout parent before it was ever opened");
    setTimeout(phaseOpen, 200);
}

// ---- phase 2: open at offset 0 -- the control ----------------------------
function phaseOpen():void
{
    stageMark("open at offset 0");
    selOpen = true;
    app.invalidate(Dirty.VALUE);
    setTimeout(phaseOpenCheck, 250);
}

function phaseOpenCheck():void
{
    var sel:UiNode = app.findByKey("sel");
    var drop:UiNode = app.findByKey("sel:drop");
    expect(sel.lifted, "opening the select did not lift it");
    expect(sel.backing.parent == app.stageContainer,
        "the lifted select is not on the stage container");
    expect(drop != null && drop.backing != null && drop.backing.visible,
        "the dropdown is not visible while open");
    // At offset 0 the shift is zero, so the old and the new formula agree: this is the
    // CONTROL that keeps the fix from moving the unscrolled case.
    expect(sel.backing.y == 50, "the lifted select is at y " + sel.backing.y + ", want 50");
    var shot:BitmapData = frameShot();
    log = log + "open/row0 " + hex(rgbAt(shot, 100, 100))
        + " row1 " + hex(rgbAt(shot, 100, 128)) + "\n";
    // Rows at 89..115 / 115..141 / 141..167 (hand arithmetic above).
    expect(rgbAt(shot, 100, 100) == 0xFFFFFF,
        "row 0 at offset 0 is " + hex(rgbAt(shot, 100, 100)) + ", want #ffffff");
    expect(rgbAt(shot, 100, 128) == 0xDBEAFE,
        "the selected row at offset 0 is " + hex(rgbAt(shot, 100, 128)) + ", want #dbeafe");
    setTimeout(phaseScroll, 200);
}

// ---- phase 3: scroll the pane 40 while the dropdown is open --------------
function phaseScroll():void
{
    stageMark("scroll to 40 with the popup open");
    svOffset = 40;
    app.invalidate(Dirty.VALUE);
    setTimeout(phaseScrollCheck, 250);
}

function phaseScrollCheck():void
{
    var sv:UiNode = app.findByKey("sv");
    var sel:UiNode = app.findByKey("sel");
    var sc:ScrollViewNode = ScrollViewNode(sv.desc);
    expect(sc.offsetY == 40, "the pane is at offsetY " + sc.offsetY + ", want 40");
    expect(clipY("sv") == 40, "the clip is at y " + clipY("sv") + ", want 40");
    // THE ASSERTION OF THIS PROBE. absY is 50 (layout), the pane shows it at 10
    // (50 - 40); the lifted backing must carry that slide itself.
    expect(sel.backing.y == 10,
        "the lifted select is at y " + sel.backing.y + ", want 10 (absY 50 - scroll 40)");
    var shot:BitmapData = frameShot();
    log = log + "scrolled/row1 " + hex(rgbAt(shot, 100, 88))
        + " row2 " + hex(rgbAt(shot, 100, 120))
        + " below " + hex(rgbAt(shot, 100, 140)) + "\n";
    // Rows at 49..75 / 75..101 / 101..127 (hand arithmetic above).
    expect(rgbAt(shot, 100, 88) == 0xDBEAFE,
        "the selected row is not under the scrolled trigger ("
        + hex(rgbAt(shot, 100, 88)) + ", want #dbeafe)");
    expect(rgbAt(shot, 100, 120) == 0xFFFFFF,
        "row 2 is not at its scrolled place (" + hex(rgbAt(shot, 100, 120)) + ", want #ffffff)");
    // Past the dropdown's bottom (132): the pane's own spacer, NOT dropdown white. This
    // is the point that says the whole popup stayed 40px too low instead of the
    // popup being merely stretched.
    expect(rgbAt(shot, 100, 140) == 0xCCCCCC,
        "the pane's content under the popup is " + hex(rgbAt(shot, 100, 140)) + ", want #cccccc");
    setTimeout(phaseTap, 200);
}

// ---- phase 4: a tap on a row after scrolling picks THAT row --------------
function phaseTap():void
{
    stageMark("tap row 0 after scrolling");
    var before:int = picks;
    var hit:UiNode = app.pickAt(100, 60);
    log = log + "pick(100,60) " + (hit == null ? "null" : String(hit.key)) + "\n";
    // (100,60) is inside row0 (49..75) and inside the pane.
    touchAt(TouchEvent.TOUCH_BEGIN, 1, 100, 60);
    touchAt(TouchEvent.TOUCH_END, 1, 100, 60);
    log = log + "router down " + app.router.downCounts + " taps " + app.router.taps
        + " delayed " + app.router.delayedCounts + " presses " + app.router.pressCounts
        + " slopCancels " + app.router.slopCancels
        + " open " + selOpen + " picks " + picks + "\n";
    expect(picks == before + 1, "the tap did not select a row (picks " + picks + ")");
    expect(selValue == "Alpha",
        "the tap picked \"" + selValue + "\", want Alpha (the row under the finger)");
    setTimeout(phaseReopen, 250);
}

// ---- phase 5: re-open AFTER the scroll -- the common user flow ----------
function phaseReopen():void
{
    stageMark("re-open at offset 40");
    selOpen = true;
    app.invalidate(Dirty.VALUE);
    setTimeout(phaseReopenCheck, 250);
}

function phaseReopenCheck():void
{
    var sel:UiNode = app.findByKey("sel");
    // Opening while the pane is ALREADY scrolled is the case a user hits, and the one
    // the old code got wrong without any scroll happening in the same frame: the lift
    // read absY and never looked at the clip.
    expect(sel.backing.y == 10,
        "the re-opened select is at y " + sel.backing.y + ", want 10");
    var shot:BitmapData = frameShot();
    log = log + "reopen/row0 " + hex(rgbAt(shot, 100, 60))
        + " row1 " + hex(rgbAt(shot, 100, 88)) + "\n";
    // The pick above selected Alpha, so ROW 0 now carries the band.
    expect(rgbAt(shot, 100, 60) == 0xDBEAFE,
        "the selected row (Alpha) is not under the trigger ("
        + hex(rgbAt(shot, 100, 60)) + ", want #dbeafe)");
    expect(rgbAt(shot, 100, 88) == 0xFFFFFF,
        "row 1 after the pick is " + hex(rgbAt(shot, 100, 88)) + ", want #ffffff");
    setTimeout(phaseCloseTap, 200);
}

// ---- phase 6: a tap on the TRIGGER closes, and the backing goes home ----
function phaseCloseTap():void
{
    stageMark("tap the trigger to close");
    touchAt(TouchEvent.TOUCH_BEGIN, 1, 100, 20);
    touchAt(TouchEvent.TOUCH_END, 1, 100, 20);
    expect(!selOpen, "a tap on the trigger did not close the dropdown");
    setTimeout(phaseClose, 250);
}

// ---- phase 7: closing puts the backing back -----------------------------
function phaseClose():void
{
    stageMark("close after the pick");
    var sel:UiNode = app.findByKey("sel");
    var sv:UiNode = app.findByKey("sv");
    expect(!selOpen, "the pick did not close the dropdown");
    expect(!sel.lifted, "the closed select is still lifted");
    expect(sel.backing.parent == sv.backing,
        "the closed select did not return to its layout parent");
    expect(app.liftedCount() == 0, "the lifted list kept a closed node ("
        + app.liftedCount() + ")");
    setTimeout(finish, 200);
}

function finish():void
{
    writeText(OUT + ".dbg.txt", log + "checks " + checks + "\n");
    writeText(OUT + ".done", failures == "" ? "PASS" : "FAIL " + failures);
}

// ---- helpers --------------------------------------------------------------

function touchAt(type:String, id:int, x:Number, y:Number):void
{
    try
    {
        stage.dispatchEvent(new TouchEvent(type, true, false, id, true, x, y, 1, 1, 0.5));
    }
    catch (err:Error)
    {
        failures = failures + type + " at (" + x + "," + y + ") threw " + err.name + ": " + err.message + "; ";
    }
}

function expect(ok:Boolean, msg:String):void
{
    checks = checks + 1;
    if (!ok) failures = failures + msg + "; ";
}

function rectOf(n:UiNode):String
{
    if (n == null) return "MISSING";
    return n.absX + "," + n.absY + "," + n.absW + "," + n.absH;
}

// Where the viewport's content is actually shown from.
function clipY(key:String):Number
{
    var n:UiNode = app.findByKey(key);
    if (n == null || n.backing == null || n.backing.scrollRect == null) return -999;
    return n.backing.scrollRect.y;
}

function frameShot():BitmapData
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

function stageMark(label:String):void
{
    writeText(OUT + ".step", label + "\n");
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
    var f:File = File.applicationDirectory.resolvePath(path);
    var fs:FileStream = new FileStream();
    fs.open(f, FileMode.WRITE);
    fs.writeBytes(ba);
    fs.close();
}
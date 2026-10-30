// probes/widgets/popup/Main.as -- an OPEN popup must paint ABOVE the widget below it.
//
// Output prefix MUST equal the directory name (`popup`).
//
// THE DEFECT. This engine deliberately has no z-index (overlay.as says so: the list
// order IS the stacking order), and a select/combobox/datePicker dropdown is a CHILD
// of its owner node -- so it can only ever paint above the owner's own content. Any
// sibling the page renders AFTER the owner tore the open list in half: the gallery's
// Advanced page showed "Low" cut off exactly at the top edge of the card below it.
//
// THE FIX (UiNode.lifted). While `open` the owner node's backing is re-parented onto
// the stage container and positioned at its ABSOLUTE rect, so it is the last thing the
// main tree paints. Everything else -- layout through the real parent, keys, focus,
// the click path, the description tree -- is untouched. This probe pins all of it:
//
//   * rasterization: a pixel INSIDE the dropdown's rows and INSIDE the card below it
//     must be the row's colour, not the card's;
//   * geometry: the dropdown keeps its own rect while its owner moves;
//   * ordering: lifted BELOW the overlay tree (a dialog still covers a dropdown);
//   * the closed state is byte-for-byte the old one (the pixel goes back to the card);
//   * unmounting a LIFTED node leaves no sprite behind (destroySubtree was the one
//     removal path that assumed `parent.backing` was the display parent).
//
// HAND ARITHMETIC (window 380x520; root column, padding 20, gap 12, alignItems
// flex-start, white; children in order: select, lower card, combobox, datePicker)
//
//   sel   (20,20,240,34)    SELECT_TRIGGER: fixed height 34, no border
//   lower (20,66,240,180)   66 = 20 + 34 + 12, filled 0x1E3A8A
//   cb    (20,258,240,34)   258 = 66 + 180 + 12
//   dp    (20,304,240,34)   304 = 258 + 34 + 12
//
//   select dropdown: left 0 and top = the owner's height (34) -> (20,54); MENU_PANEL is
//     1px border + [4,4] padding, so its rows start at 54+1+4 = 59 and are 26 tall:
//       Low   59..85     Normal 85..111 (SELECTED -> ITEM_SELECTED 0xDBEAFE)
//       High 111..137    Ultra 137..163
//     x = 20+1+4 = 25 .. 20+240-5 = 255. The card below covers 66..246, so rows 1..3
//     (85..163) are the overlap: (250,95) must be #dbeafe and (250,150) #ffffff.
//
//   combobox dropdown: top = 258+34 = 292, rows at 297..323..349..375..401 (4 cities);
//     row 0 has no selection, so panel white. dp's trigger (304..338, #F3F4F6) is
//     UNDER it: (230,312) is #ffffff while open and #f3f4f6 while closed.
//
// Protocol (tools/probe.cjs): dir name == output prefix; write <OUT>.rects.txt,
// <OUT>.bmp, <OUT>.done (PASS | FAIL <reason>).
import asaot.ui.*;
import asaot.ui.style.StyleRefinement;
import flash.display.BitmapData;
import flash.display.DisplayObject;
import flash.display.DisplayObjectContainer;
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

var W:int = 380;
var H:int = 520;
var OUT:String = 'popup';

var OPTIONS:Array = ["Low", "Normal", "High", "Ultra"];
var CITIES:Array = ["Amsterdam", "Berlin", "Lisbon", "Madrid"];

class PopupModel
{
    public var selOpen:Boolean = false;
    // Deliberately NOT the row this probe clicks: a click that did nothing would
    // otherwise satisfy the "the row moved" assertion (see choice's M8 lesson).
    public var selValue:String = "Normal";
    public var picks:int = 0;
    public var showSel:Boolean = true;
    public var cbOpen:Boolean = false;
    public var dpOpen:Boolean = false;
}

class PopupProbe extends View
{
    public var model:PopupModel;

    private static const ROOT:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", alignItems: "flex-start",
        padding: 20, gap: 12, size: [380, 520], background: 0xFFFFFF
    });
    private static const CARD:StyleRefinement = StyleRefinement.from({
        size: [240, 180], background: 0x1E3A8A
    });
    // The popup's owner deliberately does NOT sit at a zero-offset position: a lift that
    // keeps writing the PARENT-RELATIVE x is only observable when the parent has moved
    // (which is why the gallery hit it and a root-level probe would not).
    private static const TOP:StyleRefinement = StyleRefinement.from({
        size: [240, 34], padding: 0
    });

    public function PopupProbe(m:PopupModel):void
    {
        super();
        this.model = m;
    }

    override public function render():Node
    {
        var kids:Array = [];
        var inner:Array = [];
        if (model.showSel)
        {
            inner.push(select({
                key: "sel", open: model.selOpen, value: model.selValue,
                options: OPTIONS, width: 240,
                onSelect: selPicked, onOpenChange: selOpened
            }));
        }
        kids.push(box({ key: "top", style: TOP }, inner));
        kids.push(box({ key: "lower", style: CARD, ariaName: "lower card" }));
        kids.push(combobox({
            key: "cb", width: 240, options: CITIES, open: model.cbOpen,
            value: "", placeholder: "City",
            onOpenChange: cbOpened, onSelect: cbPicked
        }));
        kids.push(datePicker({
            key: "dp", width: 240, value: "2026-10-24", open: model.dpOpen,
            year: 2026, month: 10, onOpenChange: dpOpened
        }));
        return column({ key: "root", style: ROOT, ariaName: "popup probe" }, kids);
    }

    // The overlay tree exists (closed toast) so the probe can assert the LIFTED
    // surface sits BELOW it: a dialog must still cover a dropdown.
    override public function renderOverlay():Node
    {
        return overlay([ toast({ key: "t", open: false, duration: 0, message: "Saved" }) ]);
    }
}

function selPicked(i:int):void
{
    model.picks = i + 1;
    if (i >= 0 && i < OPTIONS.length) model.selValue = String(OPTIONS[i]);
    view.invalidate(Dirty.ALL);
}

function selOpened(open:Boolean):void
{
    model.selOpen = open;
    view.invalidate(Dirty.ALL);
}

function cbOpened(open:Boolean):void
{
    model.cbOpen = open;
    view.invalidate(Dirty.ALL);
}

function cbPicked(i:int):void
{
    model.cbOpen = false;
    view.invalidate(Dirty.ALL);
}

function dpOpened(open:Boolean):void
{
    model.dpOpen = open;
    view.invalidate(Dirty.ALL);
}

var model:PopupModel = new PopupModel();
var view:PopupProbe = new PopupProbe(model);
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

function at(bd:BitmapData, x:int, y:int, want:uint, what:String):void
{
    var got:uint = rgbAt(bd, x, y);
    if (got != want)
        fail("(" + x + "," + y + ") " + what + " is " + hex(got) + " not " + hex(want));
}

function clickAt(n:UiNode, lx:Number, ly:Number):void
{
    n.backing.dispatchEvent(new MouseEvent(MouseEvent.CLICK, true, false, lx, ly));
}

function clickAbs(key:String, ax:Number, ay:Number):void
{
    var n:UiNode = app.findByKey(key);
    if (n == null) { fail("no node '" + key + "' to click"); return; }
    clickAt(n, ax - n.absX, ay - n.absY);
}

function rect(n:UiNode):String
{
    return n.absX + "," + n.absY + "," + n.absW + "," + n.absH;
}

function wantRect(n:UiNode, x:Number, y:Number, w:Number, h:Number, what:String):void
{
    if (n == null) { fail(what + " is missing"); return; }
    if (n.absX != x || n.absY != y || n.absW != w || n.absH != h)
        fail(what + " is " + rect(n) + " not " + x + "," + y + "," + w + "," + h);
}

function overlayIndex():int
{
    var ov:DisplayObject = app.overlayDisplay();
    if (ov == null) return -1;
    return app.stageContainer.getChildIndex(ov);
}

// The lifted-state contract, asserted as a whole so a partial fix cannot pass.
function checkLifted(key:String, lifted:Boolean):void
{
    var n:UiNode = app.findByKey(key);
    if (n == null) { fail(key + " is missing"); return; }
    if (n.lifted != lifted)
        fail(key + ".lifted is " + n.lifted + " not " + lifted);
    var host:DisplayObjectContainer = app.stageContainer;
    if (lifted)
    {
        // Early return: every check below needs the node to BE on the stage container,
        // and getChildIndex THROWS for a non-child (which would abort the phase chain
        // instead of failing the probe -- a hang is not a red test).
        if (n.backing.parent != host)
        {
            fail(key + " is not on the stage container while open");
            return;
        }
        if (n.backing.x != n.absX || n.backing.y != n.absY)
            fail(key + " backing is at " + n.backing.x + "," + n.backing.y
                + " not its absolute " + n.absX + "," + n.absY);
        var i:int = host.getChildIndex(n.backing);
        var rootIdx:int = host.getChildIndex(app.findByKey("root").backing);
        if (i <= rootIdx)
            fail(key + " paints at index " + i + ", not above the main tree (index " + rootIdx + ")");
        var oi:int = overlayIndex();
        if (oi >= 0 && i >= oi)
            fail(key + " paints at index " + i + ", not below the overlay tree (index " + oi + ")");
    }
    else
    {
        var p:UiNode = n.parent;
        if (p == null || p.backing == null)
            fail(key + " has no owner backing to go back into");
        else if (n.backing.parent != p.backing)
            fail(key + " did not go back into its owner's backing");
    }
}

setTimeout(ready, 900);
stage.showWindow(W, H, "probe popup");

// ==================== phase 0: the closed page ==============================
function ready():void
{
    var bd:BitmapData = frame();
    var root:UiNode = app.findByKey("root");
    var sel:UiNode = app.findByKey("sel");
    var lower:UiNode = app.findByKey("lower");
    var cb:UiNode = app.findByKey("cb");
    var dp:UiNode = app.findByKey("dp");
    if (root == null || sel == null || lower == null || cb == null || dp == null)
    {
        fail("the page did not mount (root/sel/lower/cb/dp)");
        finish();
        return;
    }
    wantRect(root, 0, 0, 380, 520, "root");
    wantRect(app.findByKey("top"), 20, 20, 240, 34, "top (the popup's owner box)");
    wantRect(sel, 20, 20, 240, 34, "sel");
    wantRect(lower, 20, 66, 240, 180, "lower");
    wantRect(cb, 20, 258, 240, 34, "cb");
    wantRect(dp, 20, 304, 240, 34, "dp");

    // The dropdown's own rect, even while closed (it is `visible: false`, and a
    // hidden absolute child still solves): 4 rows x 26 + 1px border x2 + 4px pad x2.
    wantRect(app.findByKey("sel:drop"), 20, 54, 240, 114, "sel:drop");
    wantRect(app.findByKey("sel:i1"), 25, 85, 230, 26, "sel:i1 (Normal, selected)");
    wantRect(app.findByKey("sel:i3"), 25, 137, 230, 26, "sel:i3 (Ultra)");

    // Closed: the card below shows through everywhere the list will cover.
    at(bd, 250, 95, 0x1E3A8A, "row 1's slot with the list closed");
    at(bd, 250, 120, 0x1E3A8A, "row 2's slot with the list closed");
    at(bd, 250, 150, 0x1E3A8A, "row 3's slot with the list closed");
    at(bd, 230, 312, 0xF3F4F6, "the date picker's trigger");
    checkLifted("sel", false);
    checkLifted("cb", false);
    checkLifted("dp", false);
    say("closed: sel " + rect(sel) + " drop " + rect(app.findByKey("sel:drop"))
        + " children " + app.stageContainer.numChildren);

    clickAt(sel, 120, 17);
    setTimeout(afterSelOpen, 360);
}

// ==================== phase 1: the select is open ==========================
function afterSelOpen():void
{
    var bd:BitmapData = frame();
    var sel:UiNode = app.findByKey("sel");
    if (sel == null) { fail("the select vanished when it opened"); finish(); return; }
    if (!model.selOpen) fail("opening the select did not report onOpenChange(true)");
    checkLifted("sel", true);
    // The owner MOVED, not the list: its own rect and the dropdown's are the same.
    wantRect(sel, 20, 20, 240, 34, "sel while open");
    wantRect(app.findByKey("sel:drop"), 20, 54, 240, 114, "sel:drop while open");
    checkLifted("lower", false);

    // THE DEFECT: these two points are inside the card below AND inside the list.
    at(bd, 250, 95, 0xDBEAFE, "the selected row (Normal) over the card");
    at(bd, 250, 120, 0xFFFFFF, "row High over the card");
    at(bd, 250, 150, 0xFFFFFF, "row Ultra over the card");
    // getChildIndex THROWS #2025 for a non-child, and this line must be able to REPORT
    // a popup that never left its owner (that is mutation M1's whole point).
    var hostIdx:int = -1;
    if (sel.backing.parent == app.stageContainer) hostIdx = app.stageContainer.getChildIndex(sel.backing);
    say("selOpen: lifted sel parent==stage " + (sel.backing.parent == app.stageContainer)
        + " idx " + hostIdx
        + " overlay idx " + overlayIndex()
        + " px(250,95) " + hex(rgbAt(bd, 250, 95))
        + " px(250,120) " + hex(rgbAt(bd, 250, 120)));

    // Click "High" (row 2): the click path must survive the re-parenting.
    clickAbs("sel:drop", 150, 124);
    setTimeout(afterSelPick, 360);
}

// ==================== phase 2: the list closed again ======================
function afterSelPick():void
{
    var bd:BitmapData = frame();
    if (model.picks != 3) fail("clicking row 2 reported pick " + model.picks + " not 3");
    if (model.selValue != "High")
        fail("after picking row 2 the value is '" + model.selValue + "' not 'High'");
    if (model.selOpen) fail("picking a row did not close the list");
    checkLifted("sel", false);
    // Closing is a COMPLETE undo: the card is the only thing at those points again.
    at(bd, 250, 95, 0x1E3A8A, "row 1's slot after closing");
    at(bd, 250, 120, 0x1E3A8A, "row 2's slot after closing");
    at(bd, 250, 150, 0x1E3A8A, "row 3's slot after closing");
    say("selPicked: value " + model.selValue + " px(250,120) " + hex(rgbAt(bd, 250, 120)));

    var cb:UiNode = app.findByKey("cb");
    clickAt(cb, 200, 17);
    setTimeout(afterCbOpen, 360);
}

// ==================== phase 3: the combobox ===============================
function afterCbOpen():void
{
    var bd:BitmapData = frame();
    if (!model.cbOpen) fail("opening the combobox did not report onOpenChange(true)");
    checkLifted("cb", true);
    checkLifted("sel", false);
    // The combobox's own dropdown hangs over the datePicker's trigger.
    at(bd, 230, 312, 0xFFFFFF, "the city list over the date picker's trigger");
    say("cbOpen: px(230,312) " + hex(rgbAt(bd, 230, 312)) + " dp lifted " + app.findByKey("dp").lifted);

    // A combobox does NOT close on a trigger click while open (that click is a
    // caret placement for its field -- see ComboBoxWidget.onClickAt), so the list is
    // dismissed the way a user dismisses it: by picking a row (Berlin, row 1).
    clickAbs("cb:drop", 150, 336);
    setTimeout(afterCbClose, 360);
}

function afterCbClose():void
{
    var bd:BitmapData = frame();
    if (model.cbOpen) fail("picking a city did not close the list");
    checkLifted("cb", false);
    at(bd, 230, 312, 0xF3F4F6, "the date picker's trigger after the city list closed");
    say("cbClosed: px(230,312) " + hex(rgbAt(bd, 230, 312)));

    var dp:UiNode = app.findByKey("dp");
    clickAt(dp, 120, 17);
    setTimeout(afterDpOpen, 360);
}

// ==================== phase 4: the date picker ============================
function afterDpOpen():void
{
    if (!model.dpOpen) fail("opening the date picker did not report onOpenChange(true)");
    checkLifted("dp", true);
    var dp:UiNode = app.findByKey("dp");
    // Its panel is the last child and hangs below the 34pt trigger.
    var panel:UiNode = dp.children.length > 0 ? dp.children[dp.children.length - 1] : null;
    if (panel == null) fail("the date picker has no panel node");
    else if (panel.absY != 338)
        fail("the panel's top is " + panel.absY + " not 338 (304 + 34)");
    say("dpOpen: lifted " + dp.lifted + " panel " + (panel == null ? "?" : rect(panel)));

    var dp2:UiNode = app.findByKey("dp");
    clickAt(dp2, 120, 17);
    setTimeout(afterDpClose, 360);
}

function afterDpClose():void
{
    checkLifted("dp", false);

    // ============ phase 5: unmounting a LIFTED node =======================
    var sel:UiNode = app.findByKey("sel");
    if (sel == null) { fail("the select is gone before the unmount phase"); finish(); return; }
    clickAt(sel, 120, 17);
    setTimeout(afterReopenForUnmount, 360);
}

function afterReopenForUnmount():void
{
    var sel:UiNode = app.findByKey("sel");
    if (sel == null || !sel.lifted) { fail("the select did not lift again for the unmount phase"); finish(); return; }
    var before:int = app.stageContainer.numChildren;
    model.showSel = false;
    view.invalidate(Dirty.ALL);
    setTimeout(function ():void { afterUnmount(before); }, 400);
}

function afterUnmount(before:int):void
{
    var bd:BitmapData = frame();
    if (app.findByKey("sel") != null) fail("sel was not removed from the retained tree");
    var after:int = app.stageContainer.numChildren;
    // root + overlay root. A leaked lifted sprite makes it one more.
    if (after != before - 1)
        fail("unmounting a lifted node left " + (after - (before - 1)) + " extra display object(s)"
            + " (stage children " + before + " -> " + after + ")");
    // The owner box is empty now, so its slot is the root's white -- a leaked select
    // sprite would still be there painting its grey trigger 0xF3F4F6.
    at(bd, 100, 30, 0xFFFFFF, "where the select used to be");
    say("unmounted: stage children " + before + " -> " + after
        + " px(100,30) " + hex(rgbAt(bd, 100, 30)));
    finish();
}

function finish():void
{
    var bd:BitmapData = frame();
    var lines:String = "";
    var names:Array = ["root", "top", "lower", "cb", "dp"];
    for (var i:int = 0; i < names.length; i++)
    {
        var n:UiNode = app.findByKey(names[i]);
        if (n == null) { lines = lines + names[i] + " MISSING\n"; continue; }
        lines = lines + names[i] + " " + rect(n) + "\n";
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
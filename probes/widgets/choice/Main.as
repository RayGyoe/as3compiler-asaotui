// probes/widgets/choice/Main.as -- the three CHOICE widgets: tree, combobox, datePicker.
//
// Output prefix MUST equal the directory name (`choice`).
//
// WHAT IS BEING MEASURED. All three are "report, never apply" controls: the widget
// answers a key/click with a CALLBACK and the AUTHOR re-renders. So each one is probed
// in both directions:
//
//   * the descriptor really produces the geometry (row ys, the indentation of a nested
//     row, the panel hanging under the trigger, a day cell's exact cell);
//   * a click/key goes back out as the right callback with the right ARGUMENT, and the
//     NEXT render (driven by the model, exactly as an app would) shows the result.
//
// HAND ARITHMETIC (window 420x560; root column, padding 20, gap 12; background white)
//
//   tr   (20,20,240,130)    5 rows of 26: src(open), a, b, lib(closed), readme
//                            rows at y = 20, 46, 72, 98, 124
//                            label x = 20 + TREE_PAD(22) + depth*TREE_INDENT(18)
//                                    = 42 for depth 0, 60 for depth 1
//   cb   (20,162,220,34)    162 = 20 + 130 + 12
//   dp   (20,208,200,34)    208 = 162 + 34 + 12
//
//   combo dropdown: top = 162+34 = 196, its own 4pt padding -> row i at
//                   200 + 26*i (MENU_ITEM height 26)
//   dp panel:       top = 208+34 = 242, width 7*28 + 8 = 232
//                   head row 246..272, week w at 272 + 26*w, day cell x = 24 + 28*col
//                   2026-10-01 is a THURSDAY (weekday 4), so day 1 is at col 4:
//                   day 15 is week 2, col 4 -> x 136..164, y 324..350
//
// Protocol (tools/probe.cjs): dir name == output prefix; write <OUT>.rects.txt,
// <OUT>.bmp, <OUT>.done (PASS | FAIL <reason>).
import asaot.ui.*;
import asaot.ui.style.StyleRefinement;
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

var W:int = 420;
var H:int = 560;
var OUT:String = 'choice';

var ITEMS:Array = [
    { key: "src", label: "src", children: [
        { key: "a", label: "a.as" },
        { key: "b", label: "b.as" }
    ] },
    { key: "lib", label: "lib", children: [
        { key: "c", label: "c.as" }
    ] },
    { key: "readme", label: "README" }
];

var ALL_CITIES:Array = ["Berlin", "Berne", "Lisbon", "Porto"];

class ChoiceModel extends Observable
{
    public var expanded:Array = ["src"];
    public var sel:String = "a";
    public var toggles:int = 0;
    public var cbOpen:Boolean = false;
    public var q:String = "";
    public var picked:int = -1;
    public var dpOpen:Boolean = false;
    public var value:String = "2026-10-02";
    public var year:int = 2026;
    public var month:int = 10;
    public var monthSeen:String = "";
}

class ChoiceProbe extends View
{
    public var model:ChoiceModel;

    private static const ROOT:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", alignItems: "flex-start",
        padding: 20, gap: 12, size: [420, 560], background: 0xFFFFFF
    });

    public function ChoiceProbe(m:ChoiceModel):void
    {
        super();
        this.model = m;
    }

    override public function render():Node
    {
        return column({ key: "root", style: ROOT, ariaName: "choice probe" }, [
            tree(ITEMS, {
                key: "tr",
                size: [240, null],
                expanded: model.expanded,
                selectedKey: model.sel,
                rowHeight: 26,
                background: 0xF9FAFB,
                onToggle: toggled,
                onSelect: pickedKey
            }),
            combobox({
                key: "cb",
                width: 220,
                options: filtered(),
                open: model.cbOpen,
                value: model.q,
                placeholder: "City",
                onSelect: chose,
                onQuery: typed,
                onOpenChange: openChanged
            }),
            datePicker({
                key: "dp",
                width: 200,
                value: model.value,
                open: model.dpOpen,
                year: model.year,
                month: model.month,
                onSelect: dateChosen,
                onMonthChange: monthChanged,
                onOpenChange: dpOpenChanged
            })
        ]);
    }
}

// The author-side filter -- the whole point of `combobox` passing `onQuery` back: the
// matching rule belongs to the app, not to the library.
function filtered():Array
{
    if (model.q == null || model.q == "") return ALL_CITIES;
    var out:Array = [];
    var needle:String = model.q.toLowerCase();
    for (var i:int = 0; i < ALL_CITIES.length; i++)
    {
        var s:String = String(ALL_CITIES[i]);
        if (s.toLowerCase().indexOf(needle) >= 0) out.push(s);
    }
    return out;
}

function toggled(key:String):void
{
    model.toggles = model.toggles + 1;
    var out:Array = [];
    for (var i:int = 0; i < model.expanded.length; i++)
    {
        if (String(model.expanded[i]) != key) out.push(model.expanded[i]);
    }
    if (out.length == model.expanded.length) out.push(key);
    model.expanded = out;
    view.invalidate(Dirty.ALL);
}

function pickedKey(key:String):void
{
    model.sel = key;
    view.invalidate(Dirty.ALL);
}

function chose(i:int):void
{
    model.picked = i;
    model.cbOpen = false;
    view.invalidate(Dirty.ALL);
}

function typed(t:String):void
{
    model.q = t;
    view.invalidate(Dirty.ALL);
}

function openChanged(open:Boolean):void
{
    model.cbOpen = open;
    view.invalidate(Dirty.ALL);
}

function dateChosen(iso:String):void
{
    model.value = iso;
    view.invalidate(Dirty.ALL);
}

function monthChanged(y:int, m:int):void
{
    model.year = y;
    model.month = m;
    model.monthSeen = DateMath.iso(y, m, 1).substring(0, 7);
    view.invalidate(Dirty.ALL);
}

function dpOpenChanged(open:Boolean):void
{
    model.dpOpen = open;
    view.invalidate(Dirty.ALL);
}

var model:ChoiceModel = new ChoiceModel();
var view:ChoiceProbe = new ChoiceProbe(model);
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

function clickAt(n:UiNode, lx:Number, ly:Number):void
{
    n.backing.dispatchEvent(new MouseEvent(MouseEvent.CLICK, true, false, lx, ly));
}

function clickAbs(key:String, ax:Number, ay:Number):void
{
    var n:UiNode = app.findByKey(key);
    clickAt(n, ax - n.absX, ay - n.absY);
}

function key(code:int, shift:Boolean):void
{
    var e:KeyboardEvent = new KeyboardEvent(KeyboardEvent.KEY_DOWN, true, true,
        0, code, 0, false, false, shift, false, false, false);
    stage.dispatchEvent(e);
}

function rows(n:UiNode):String
{
    var out:String = "";
    for (var i:int = 0; i < n.children.length; i++)
    {
        out = out + (i == 0 ? "" : ",") + String(n.children[i].key);
    }
    return out;
}

setTimeout(ready, 900);
stage.showWindow(W, H, "probe choice");

// ======================= phase 1: the three descriptors ======================
function ready():void
{
    var bd:BitmapData = frame();
    var tr:UiNode = app.findByKey("tr");
    if (tr == null) { fail("the tree never mounted"); finish(); return; }

    if (tr.absX != 20 || tr.absY != 20 || tr.absW != 240 || tr.absH != 130)
        fail("tree is " + tr.absX + "," + tr.absY + "," + tr.absW + "," + tr.absH + " not 20,20,240,130");

    // ---- the tree: five visible rows, in document order -------------------
    var want:String = "tr:tsrc,tr:ta,tr:tb,tr:tlib,tr:treadme";
    if (rows(tr) != want) fail("tree rows are " + rows(tr) + " not " + want);
    var tops:String = "";
    for (var i:int = 0; i < tr.children.length; i++)
    {
        tops = tops + (i == 0 ? "" : "/") + tr.children[i].absY;
    }
    if (tops != "20/46/72/98/124")
        fail("row tops are " + tops + " not 20/46/72/98/124 (rowHeight 26)");

    // ---- INDENTATION: depth 0 at 42, depth 1 at 60 ------------------------
    var l0:UiNode = app.findByKey("tr:tsrc:l");
    var l1:UiNode = app.findByKey("tr:ta:l");
    if (l0 == null || l1 == null) { fail("a row lost its label"); finish(); return; }
    if (l0.absX != 42) fail("a depth-0 label starts at x=" + l0.absX + " not 42");
    if (l1.absX != 60) fail("a depth-1 label starts at x=" + l1.absX + " not 60 (TREE_PAD 22 + TREE_INDENT 18)");

    // ---- the twisties: src is OPEN (down triangle), lib is CLOSED (right) --
    if (rgbAt(bd, 29, 31) != 0x6B7280)
        fail("the open branch's twisty at (29,31) is " + hex(rgbAt(bd, 29, 31)) + " not #6B7280");
    if (rgbAt(bd, 29, 111) != 0x6B7280)
        fail("the closed branch's twisty at (29,111) is " + hex(rgbAt(bd, 29, 111)) + " not #6B7280");
    // A LEAF has no twisty: the same spot on the `readme` row is the row's background.
    if (rgbAt(bd, 29, 137) != 0xF9FAFB)
        fail("the leaf row at (29,137) is " + hex(rgbAt(bd, 29, 137)) + " not the row background #f9fafb (a leaf must not draw a twisty)");

    // ---- the selected row is a DECLARATIVE background --------------------
    if (rgbAt(bd, 200, 59) != 0xDBEAFE)
        fail("the selected row's background at (200,59) is " + hex(rgbAt(bd, 200, 59)) + " not #dbeafe");

    var cb:UiNode = app.findByKey("cb");
    if (cb == null || cb.absX != 20 || cb.absY != 162 || cb.absW != 220 || cb.absH != 34)
        fail("combobox is " + (cb == null ? "missing" : cb.absX + "," + cb.absY + "," + cb.absW + "," + cb.absH) + " not 20,162,220,34");
    var dp:UiNode = app.findByKey("dp");
    if (dp == null || dp.absX != 20 || dp.absY != 208 || dp.absW != 200 || dp.absH != 34)
        fail("datePicker is " + (dp == null ? "missing" : dp.absX + "," + dp.absY + "," + dp.absW + "," + dp.absH) + " not 20,208,200,34");
    if (app.findByKey("cb:drop") != null && app.findByKey("cb:drop").backing.visible)
        fail("the combobox dropdown is visible while `open` is false");
    if (app.findByKey("dp:panel") != null && app.findByKey("dp:panel").backing.visible)
        fail("the date panel is visible while `open` is false");

    say("ready: tree rows " + rows(tr) + " tops " + tops + " labels " + l0.absX + "/" + l1.absX);

    // (1) collapse `src` by clicking its twisty: row-local (10, 13).
    clickAt(tr, 10, 13);
    setTimeout(afterCollapse, 320);
}

function afterCollapse():void
{
    var tr:UiNode = app.findByKey("tr");
    var want:String = "tr:tsrc,tr:tlib,tr:treadme";
    if (model.toggles != 1) fail("toggling src reported " + model.toggles + " times, not 1");
    if (rows(tr) != want) fail("after collapsing src the rows are " + rows(tr) + " not " + want);
    say("afterCollapse: toggles " + model.toggles + " rows " + rows(tr));

    // (2) expand `lib`: it is now the second row, so its twisty is at (10, 26+13).
    clickAt(tr, 10, 39);
    setTimeout(afterExpand, 320);
}

function afterExpand():void
{
    var tr:UiNode = app.findByKey("tr");
    var want:String = "tr:tsrc,tr:tlib,tr:tc,tr:treadme";
    if (rows(tr) != want) fail("after expanding lib the rows are " + rows(tr) + " not " + want);
    // The expanded child is INDENTED one step (42 -> 60) and sits on the next line.
    var lc:UiNode = app.findByKey("tr:tc:l");
    if (lc == null) { fail("the expanded child has no label"); finish(); return; }
    if (lc.absX != 60 || lc.absY != 79)
        fail("the child row's label is at " + lc.absX + "," + lc.absY + " not 60,79 (the label is vertically centred in the 26pt row)");
    say("afterExpand: rows " + rows(tr) + " child label " + lc.absX + "," + lc.absY);

    // (3) select the child by clicking its LABEL area (not the padding).
    clickAbs("tr", 80, 72 + 13);
    setTimeout(afterSelect, 320);
}

function afterSelect():void
{
    if (model.sel != "c") fail("clicking the child reported key '" + model.sel + "' not 'c'");
    say("afterSelect: selected " + model.sel);

    // Back to the state expect.json pins (src open, "a" selected).
    model.expanded = ["src"];
    model.sel = "a";
    view.invalidate(Dirty.ALL);
    setTimeout(openCombo, 320);
}

// ============================ the combobox ==================================
function openCombo():void
{
    var cb:UiNode = app.findByKey("cb");
    // A click anywhere on the trigger (here: the right padding, clear of the field's
    // text) must OPEN it -- there is no "toggle off", see ComboBoxWidget.
    clickAt(cb, cb.absW - 4, 17);
    setTimeout(afterComboOpen, 320);
}

function afterComboOpen():void
{
    if (!model.cbOpen) { fail("clicking the trigger did not report open=true"); finish(); return; }
    var drop:UiNode = app.findByKey("cb:drop");
    if (drop == null || !drop.backing.visible) { fail("the dropdown is not visible after open"); finish(); return; }
    if (drop.absX != 20 || drop.absY != 196 || drop.absW != 220)
        fail("the dropdown is at " + drop.absX + "," + drop.absY + " w " + drop.absW + " not 20,196 w 220");
    var want:String = "cb:i0,cb:i1,cb:i2,cb:i3";
    if (rows(drop) != want) fail("the dropdown rows are " + rows(drop) + " not " + want);
    // MENU_ITEM is 26 high inside the panel's 1pt border + 4pt padding: row 0 is at
    // 196+5 = 201, so row 1 is at 227.
    if (drop.children.length > 1 && drop.children[1].absY != 227)
        fail("dropdown row 1 is at y=" + drop.children[1].absY + " not 227");
    say("afterComboOpen: drop " + drop.absX + "," + drop.absY + " rows " + rows(drop));

    // Click row 1 ("Berne"), dispatched ON THE DROPDOWN (the router measures the point
    // in the dropdown's own space, see OverlayList.localYIn).
    clickAbs("cb:drop", 100, 227 + 13);
    setTimeout(afterComboPick, 320);
}

function afterComboPick():void
{
    if (model.picked != 1) fail("clicking row 1 reported index " + model.picked + " not 1");
    if (model.cbOpen) fail("the combobox did not close after a pick");
    say("afterComboPick: picked " + model.picked + " open " + model.cbOpen);

    // TYPE-TO-FILTER: the field is the focus target, and CHANGE is the only signal the
    // widget gets. "ber" matches Berlin and Berne.
    var inp:UiNode = app.findByKey("cb:q");
    app.focusNode(inp);
    inp.tf.text = "ber";
    inp.tf.dispatchEvent(new Event(Event.CHANGE, false, false));
    setTimeout(afterType, 320);
}

function afterType():void
{
    if (model.q != "ber") fail("typing reported query '" + model.q + "' not 'ber'");
    var cb:UiNode = app.findByKey("cb");
    // Re-open so the filtered rows are mounted (the pick above closed it).
    clickAt(cb, cb.absW - 4, 17);
    setTimeout(afterFiltered, 320);
}

function afterFiltered():void
{
    var drop:UiNode = app.findByKey("cb:drop");
    var want:String = "cb:i0,cb:i1";
    if (rows(drop) != want)
        fail("after typing 'ber' the dropdown rows are " + rows(drop) + " not " + want + " (the factory must render the FILTERED options the author passes)");
    say("afterFiltered: rows " + rows(drop));

    // Reset for the final frame, then open the date picker.
    model.q = "";
    model.cbOpen = false;
    view.invalidate(Dirty.ALL);
    setTimeout(openDate, 320);
}

// =========================== the date picker ===============================
function openDate():void
{
    var dp:UiNode = app.findByKey("dp");
    clickAt(dp, 100, 17);
    setTimeout(afterDateOpen, 320);
}

function afterDateOpen():void
{
    if (!model.dpOpen) { fail("clicking the date trigger did not report open=true"); finish(); return; }
    var panel:UiNode = app.findByKey("dp:panel");
    if (panel == null || !panel.backing.visible) { fail("the date panel is not visible after open"); finish(); return; }
    if (panel.absX != 20 || panel.absY != 242 || panel.absW != 206)
        fail("the date panel is at " + panel.absX + "," + panel.absY + " w " + panel.absW + " not 20,242 w 206 (7 x 28 cells + 8 padding + 2 border)");
    var title:UiNode = app.findByKey("dp:title");
    if (title == null) { fail("the month title is missing"); finish(); return; }
    if (title.tf.text != "2026-10")
        fail("the month title is '" + title.tf.text + "' not '2026-10'");
    // 2026-10-01 is a Thursday (weekday 4) -> day 1 is week 0, column 4. The grid
    // starts at 20 (panel) + 1 (border) + 4 (padding) = 25, so column 4 is x 137..165,
    // and the head row (26) starts at 242+5 = 247, so week 0 is y 273..299.
    var d1:UiNode = app.findByKey("dp:d01");
    if (d1 == null) { fail("day 1 has no cell"); finish(); return; }
    if (d1.absX != 137 || d1.absY != 273 || d1.absW != 28 || d1.absH != 26)
        fail("the day-1 cell is " + d1.absX + "," + d1.absY + "," + d1.absW + "," + d1.absH + " not 137,273,28,26 (Thursday column)");
    var d31:UiNode = app.findByKey("dp:d31");
    if (d31 == null) fail("October has no day 31");
    else if (d31.absY != 377 || d31.absX != 193)
        fail("day 31 is at " + d31.absX + "," + d31.absY + " not 193,377 (week 4, column 6)");
    say("afterDateOpen: panel " + panel.absX + "," + panel.absY + " w " + panel.absW
        + " title " + title.tf.text + " d1 " + d1.absX + "," + d1.absY);

    // Click day 15: week 2, column 4 -> x 137..165, y 325..351.
    clickAbs("dp", 150, 338);
    setTimeout(afterDatePick, 320);
}

function afterDatePick():void
{
    // The initial value is deliberately the 2nd: if it were already the 15th, a day
    // click that did NOTHING would still satisfy this check (mutation M8 found that).
    if (model.value != "2026-10-15")
        fail("clicking the 15th reported '" + model.value + "' not '2026-10-15'");
    say("afterDatePick: value " + model.value);

    // Page back one month with the "<" cell (head row, first 28pt cell at y 247).
    clickAbs("dp", 38, 260);
    setTimeout(afterPrev, 320);
}

function afterPrev():void
{
    if (model.year != 2026 || model.month != 9)
        fail("the previous-month arrow reported " + model.year + "-" + model.month + " not 2026-9");
    var title:UiNode = app.findByKey("dp:title");
    if (title == null || title.tf.text != "2026-09")
        fail("after paging the title is '" + (title == null ? "missing" : title.tf.text) + "' not '2026-09'");
    // 2026-09-01 is a Tuesday (weekday 2) -> day 1 moves to column 2: x = 25 + 56 = 81.
    var d1:UiNode = app.findByKey("dp:d01");
    if (d1 == null) fail("September has no day 1");
    else if (d1.absX != 81)
        fail("September's day 1 is at x=" + d1.absX + " not 81 (Tuesday column)");
    say("afterPrev: title " + (title == null ? "?" : title.tf.text) + " d1 x " + (d1 == null ? -1 : d1.absX));

    // Back to the state expect.json pins.
    model.year = 2026;
    model.month = 10;
    model.dpOpen = false;
    view.invalidate(Dirty.ALL);
    setTimeout(finish, 400);
}

function finish():void
{
    var bd:BitmapData = frame();
    var lines:String = "";
    var names:Array = ["root", "tr", "tr:tsrc", "tr:ta", "tr:tb", "tr:tlib", "tr:treadme",
                       "cb", "dp"];
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
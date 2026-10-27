// probes/widgets/inputs/Main.as -- THE 2026-10-26 BATCH, measured end to end:
// numberInput, rangeSlider, multiSelect, and `virtual: true` on list + tree.
//
// Output prefix MUST equal the directory name (`inputs`).
//
// WHY EACH ASSERTION IS WHERE IT IS. The five additions share one failure mode --
// "it renders, so it works" -- and each of them can be wrong in a way a bitmap of
// the resting state cannot see:
//
//   numberInput  the STEPPER is a hit region on the right 32pt of the box. A bitmap
//                looks identical whether the press landed on `+` or on the text, so
//                the probe dispatches a real mouse press and reads the model. The
//                keyboard half (40/33/36) and the REVERT (garbage typed into the
//                field, then blur) are separate paths into the same `commit`.
//   rangeSlider  two thumbs, one track. A single-thumb implementation and a correct
//                one differ only after the SECOND thumb is dragged -- and the clamp
//                (low stops at high) is only visible when a drag crosses over, which
//                is exactly what the second phase does.
//   multiSelect  the contract is "the author owns `values`": the click must call
//                `onToggle(i)` and must NOT mutate the node. It also must stay OPEN
//                after a toggle (a multi-select that closes is a select).
//   list virtual the child COUNT is the measurement (6 mounted for 200 rows), and
//                the absolute index is the second one: after a wheel the first
//                mounted row is r3, so a click there must report 3, not 0.
//   tree virtual the same two, plus the flatten: 41 rows for one open branch, and a
//                click after scrolling must report `a2` (absolute row 3), not `a`.
//
// HAND ARITHMETIC (window 560x640; root column, padding 16, gap 10, alignItems
// flex-start, background white; children in order qty, rng, vl, tr, ms):
//
//   qty  (16,  16, 220, 32)   explicit size
//   rng  (16,  58, 220, 44)   58  = 16 + 32 + 10
//   vl   (16, 112, 240, 100)  112 = 58 + 44 + 10 ; rowHeight 20, count 200
//   tr   (16, 222, 240, 100)  222 = 112 + 100 + 10 ; rowHeight 20, 41 rows
//   ms   (16, 332, 220, 34)   332 = 222 + 100 + 10 ; SELECT_TRIGGER is 34 tall
//   drop (16, 366, 220, 88)   366 = 332 + 34 ; 3 * 26 rows + [4,4] padding + 1px border
//
//   WINDOW ARITHMETIC (both are 100 tall, rowHeight 20):
//     fit        = ceil(100/20) = 5 rows     (ignoring the partial row)
//     mounted    = 5 + 1 = 6 rows            (the partial row is real)
//     r_i at y   = top + 20*i ; r0..r5
//     r5 (y +100..+120) is MOUNTED but fully clipped -> proves the scrollRect
//
//   PIXELS (row background = 0x101010 * (i + 1)):
//     (30,120) inside vl row 0          -> #101010
//     (30,200) inside vl row 4          -> #505050
//     (30,216) below the viewport (212) -> #ffffff  (no clip => row 5's #606060)
//
//   STEPPER   press at (206, 24): localX 190 >= 220-32, localY 8 < 32/2 -> "+2";
//             the old 20pt column started at localX 200, so this also pins the enlargement
//   RANGE     track y = 44-12 = 32, thumb centre 36 -> stage y = 58+36 = 94
//             lo thumb x = 16 + 220*0.35 = 93 ; drag to 126 -> (126-16)/220 = 0.5
//             hi thumb x = 16 + 220*0.75 = 181; drag to 20  -> clamps to lo
//   DROPDOWN  first row starts at 366+1+4 = 371 ; row 2 centre = 371 + 2*26 + 13 = 436
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
import flash.events.MouseEvent;
import flash.filesystem.File;
import flash.filesystem.FileMode;
import flash.filesystem.FileStream;
import flash.geom.Rectangle;
import flash.utils.ByteArray;
import flash.utils.setTimeout;

var W:int = 560;
var H:int = 640;
var OUT:String = "inputs";
var ROW_H:int = 20;
var LIST_COUNT:int = 200;
var TREE_LEAVES:int = 40;

class InputsProbe extends View
{
    private static const ROOT:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", alignItems: "flex-start",
        padding: 16, gap: 10, size: [560, 640], background: 0xFFFFFF
    });

    public function InputsProbe():void { super(); }

    override public function render():Node
    {
        return column({ key: "root", style: ROOT, ariaName: "inputs probe" }, [
            numberInput("Qty", {
                key: "qty", style: StyleRefinement.from({ size: [220, 32] }),
                value: 5, min: 0, max: 10, step: 2,
                onChange: qtyChanged, onCommit: qtyCommitted
            }),
            rangeSlider("Price", {
                key: "rng", style: StyleRefinement.from({ size: [220, 44] }),
                value: 0.25, value2: 0.75, step: 0.1,
                onRange: rangeChanged
            }),
            list(listItems(), listRow, {
                key: "vl", style: StyleRefinement.from({ size: [240, 100] }),
                virtual: true, itemHeight: ROW_H, offsetY: listOffset,
                // THE AUTHOR OWNS THE SELECTION (the kit never writes selectedIndex
                // back): the widget reports the index and the factory re-reads it, so a
                // probe that forgot this line would look like "selection does not move".
                selectedIndex: listSel,
                onScroll: listScrolled, onSelect: listSelected
            }),
            tree(treeItems(), {
                key: "tr", style: StyleRefinement.from({ size: [240, 100] }),
                rowHeight: ROW_H, expanded: ["a"], offsetY: treeOffset, selectedKey: treeSel,
                virtual: true, onScroll: treeScrolled, onSelect: treeSelected
            }),
            multiSelect({
                key: "ms", width: 220, open: true,
                options: ["Alpha", "Beta", "Gamma"], values: ["Beta"],
                onToggle: msToggled, onOpenChange: msOpened
            })
        ]);
    }
}

// A row's colour encodes its ABSOLUTE index, which is what makes "the window really
// moved" readable from one pixel (0x101010 * 1 .. 0x101010 * 200 stays < white).
function listRow(item:Object, i:int):Node
{
    return box({ key: "vl:r" + i,
                 style: StyleRefinement.from({ background: 0x101010 * (i + 1) }) });
}

function listItems():Array
{
    var out:Array = [];
    for (var i:int = 0; i < LIST_COUNT; i++) out.push("row " + i);
    return out;
}

// One open branch with 40 leaves: the flatten must yield 41 rows (the branch then its
// children), and index 3 must be `a2` -- not the branch and not the leaf at 2.
function treeItems():Array
{
    var kids:Array = [];
    for (var i:int = 0; i < TREE_LEAVES; i++)
        kids.push({ key: "a" + i, label: "a" + i });
    return [{ key: "a", label: "A", children: kids }];
}

var listOffset:Number = 0;
var treeOffset:Number = 0;
var qty:Number = -1;
var qtyCommittedTo:Number = -1;
var expectQty:Number = 9;           // what the field held when the blur started
var rangeLo:Number = -1;
var rangeHi:Number = -1;
var rangeCalls:int = 0;
var listSel:int = 0;
var listScrollSaw:Number = -1;
var treeSel:String = "";
var treeScrollSaw:Number = -1;
var msToggledTo:int = -1;
var msOpenCalls:int = 0;

function qtyChanged(v:Number):void { qty = v; }
function qtyCommitted(v:Number):void { qtyCommittedTo = v; }
function rangeChanged(lo:Number, hi:Number):void { rangeLo = lo; rangeHi = hi; rangeCalls = rangeCalls + 1; }
function listSelected(i:int):void { listSel = i; view.invalidate(Dirty.ALL); }
function listScrolled(y:Number):void { listScrollSaw = y; listOffset = y; view.invalidate(Dirty.ALL); }
function treeSelected(k:String):void { treeSel = k; view.invalidate(Dirty.ALL); }
function treeScrolled(y:Number):void { treeScrollSaw = y; treeOffset = y; view.invalidate(Dirty.ALL); }
function msToggled(i:int):void { msToggledTo = i; }
function msOpened(o:Boolean):void { msOpenCalls = msOpenCalls + 1; }

var view:InputsProbe = new InputsProbe();
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

var problems:String = "";
var log:String = "";

setTimeout(ready, 900);
stage.showWindow(W, H, "probe inputs");

function say(s:String):void { log = log + s + "\n"; trace(s); }
function bad(s:String):void { problems = problems + s + "; "; }
function check(cond:Boolean, s:String):void { if (!cond) bad(s); }

function frame():BitmapData
{
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    return bd;
}

function rgbAt(bd:BitmapData, x:int, y:int):uint { return bd.getPixel(x, y) & 0xFFFFFF; }
function hex(c:uint):String
{
    var s:String = c.toString(16);
    while (s.length < 6) s = "0" + s;
    return "#" + s;
}

function key(code:int):void
{
    var e:KeyboardEvent = new KeyboardEvent(KeyboardEvent.KEY_DOWN, true, true,
        0, code, 0, false, false, false, false, false, false);
    stage.dispatchEvent(e);
}

function focus(k:String):void
{
    var n:UiNode = app.findByKey(k);
    if (n == null) { bad("no node " + k); return; }
    app.focusNode(n);
}

// A PRESS (what focus, steppers and slider thumbs want) is not a CLICK: the
// runtime dispatches exactly the type it is given, and only the real window
// synthesises "click" from a down/up pair on the same object (see
// Stage.dispatchMouse in the emitted C). Every widget that listens
// MouseEvent.CLICK must therefore be driven with "click" here.
function press(x:Number, y:Number):void
{
    stage.dispatchMouse(x, y, "mouseDown");
    stage.dispatchMouse(x, y, "mouseUp");
}
function click(x:Number, y:Number):void
{
    stage.dispatchMouse(x, y, "click");
}

function typeText(t:String):void
{
    for (var i:int = 0; i < t.length; i++) stage.dispatchText(t.charAt(i));
}

function keysOf(n:UiNode):String
{
    var out:String = "";
    for (var i:int = 0; i < n.children.length; i++)
    {
        var c:UiNode = n.children[i];
        out = out + (i == 0 ? "" : ",") + String(c.key);
    }
    return out;
}

// ==================== phase 0: what the resting frame proves =================
function ready():void
{
    // Registration is not visible in a bitmap.
    check(Widgets.has("numberInput"), "Widgets.has('numberInput') is false");
    check(Widgets.has("rangeSlider"), "Widgets.has('rangeSlider') is false");
    check(Widgets.has("multiSelect"), "Widgets.has('multiSelect') is false");

    var q:UiNode = app.findByKey("qty");
    var r:UiNode = app.findByKey("rng");
    var vl:UiNode = app.findByKey("vl");
    var tr:UiNode = app.findByKey("tr");
    var ms:UiNode = app.findByKey("ms");
    if (q == null || r == null || vl == null || tr == null || ms == null)
    {
        bad("a widget never mounted");
        finish();
        return;
    }

    // THE WINDOW, in both directions: six mounted rows for two hundred, and the six
    // are the FIRST six. A list that mounted everything would also be six tall.
    check(vl.children.length == 6, "the virtual list mounts " + vl.children.length + " rows, not 6");
    check(keysOf(vl) == "vl:r0,vl:r1,vl:r2,vl:r3,vl:r4,vl:r5",
        "the list window is " + keysOf(vl));
    check(tr.children.length == 6, "the virtual tree mounts " + tr.children.length + " rows, not 6");
    check(app.findByKey("tr:ta0") != null && app.findByKey("tr:ta4") != null,
        "the tree window is not a..a4: " + keysOf(tr));

    var ldesc:ListNode = ListNode(vl.desc);
    check(ldesc.count == LIST_COUNT, "the list's total count is " + ldesc.count);
    check(ldesc.firstIndex == 0 && ldesc.lastIndex == 5,
        "the list window is " + ldesc.firstIndex + ".." + ldesc.lastIndex + " not 0..5");
    var tdesc:TreeNode = TreeNode(tr.desc);
    check(tdesc.rowCount == TREE_LEAVES + 1,
        "the tree flattened to " + tdesc.rowCount + " rows, not " + (TREE_LEAVES + 1));

    // The clip: row 5 is mounted and its background differs from every other row, so
    // a missing scrollRect shows up as #606060 under the viewport's bottom edge.
    var bd:BitmapData = frame();
    if (rgbAt(bd, 30, 120) != 0x101010)
        bad("(30,120) is " + hex(rgbAt(bd, 30, 120)) + " not row 0's #101010");
    if (rgbAt(bd, 30, 200) != 0x505050)
        bad("(30,200) is " + hex(rgbAt(bd, 30, 200)) + " not row 4's #505050");
    if (rgbAt(bd, 30, 216) != 0xFFFFFF)
        bad("(30,216) is " + hex(rgbAt(bd, 30, 216))
            + " -- row 5 painted below the viewport (the clip is missing)");

    say("ready: list " + keysOf(vl) + "; tree " + keysOf(tr));

    // THE STEPPER: x=206 is only inside the ENLARGED strip (the old 20pt
    // column started at x=216). This press therefore pins the hit area, not
    // merely the paint: with the old column it lands in the text field.
    focus("qty");
    press(206, 24);
    setTimeout(afterStepper, 250);
}

// ==================== phase 1: numberInput ===================================
// The LIVE value is UiNode.value (what the widget wrote into the field) and the
// onChange argument -- NOT NumberInputNode.value, which is the AUTHOR's input and
// is never rewritten by an uncontrolled widget.
function afterStepper():void
{
    var q:UiNode = app.findByKey("qty");
    check(qty == 7, "the + stepper reported " + qty + " not 7 (5+2)");
    check(q.tf != null && q.tf.text == "7", "the field shows '" + (q.tf == null ? "?" : q.tf.text) + "' not '7'");

    // Keyboard: down, then a page step that must CLAMP at max, then Home.
    key(40);
    check(qty == 5, "Down reported " + qty + " not 5");
    key(33);   // PageUp: 10 steps of 2 -> 25, clamped to max 10
    check(qty == 10, "PageUp reported " + qty + " not 10 (clamped)");
    key(36);   // Home -> min
    check(qty == 0, "Home reported " + qty + " not 0");

    say("number: stepper " + qty + " (after Home the model is 0)");

    // TYPING REACHES THE MODEL. The caret lands wherever the click puts it, so the
    // expected value is derived from the text the field ACTUALLY holds after typing --
    // what this pins is that the commit PARSES the field, CLAMPS it and reports it,
    // not that AIR puts the caret at any particular offset.
    press(200, 32);          // localX 184 < 188, so this is the field and not a stepper
    typeText("9");
    var typed:String = q.tf.text;
    var want:Number = Number(typed);
    if (isNaN(want)) want = 0;
    want = want > 10 ? 10 : (want < 0 ? 0 : want);
    expectQty = want;
    say("number: field holds '" + typed + "' -> " + want + " on blur");
    press(400, 80);          // empty root area: nothing below the field to disturb
    setTimeout(afterCommit, 300);
}

// ==================== phase 1b: commit / revert ==============================
function afterCommit():void
{
    var q:UiNode = app.findByKey("qty");
    check(qty == expectQty, "blurring left the model at " + qty + " not " + expectQty);
    check(qtyCommittedTo == expectQty, "onCommit reported " + qtyCommittedTo + " not " + expectQty);
    check(q.tf != null && q.tf.text == String(int(expectQty)),
        "the field shows '" + (q.tf == null ? "?" : q.tf.text) + "' not '" + int(expectQty) + "'");

    // GARBAGE REVERTS: "9" + "abc" is not a number, so the model keeps 9. A widget
    // that substituted 0 (or NaN) would silently overwrite the author's state.
    press(200, 32);
    typeText("abc");
    press(400, 80);
    setTimeout(afterRevert, 300);
}

function afterRevert():void
{
    var q:UiNode = app.findByKey("qty");
    check(qty == expectQty, "garbage input moved the model to " + qty + " (it must stay " + expectQty + ")");
    check(q.tf != null && q.tf.text == String(int(expectQty)),
        "the field shows '" + (q.tf == null ? "?" : q.tf.text) + "' not '" + int(expectQty) + "' (revert)");
    check(qtyCommittedTo == expectQty,
        "an unparseable field still called onCommit with " + qtyCommittedTo);
    say("number: typed " + int(expectQty) + " committed, garbage reverted to " + int(expectQty));

    // ==================== phase 2: rangeSlider ================================
    // A range is TWO values and the widget is uncontrolled: the contract is the
    // onRange argument pair, so that is what is asserted (RangeSliderNode.value is
    // the author's opening state and never moves).
    focus("rng");
    key(39);   // Right: low += 0.1
    check(Math.abs(rangeLo - 0.35) < 0.000001, "Right moved the low thumb to " + rangeLo + " not 0.35");
    check(Math.abs(rangeHi - 0.75) < 0.000001, "Right moved the HIGH thumb to " + rangeHi + " (it must not)");

    // Drag the low thumb from its painted position to exactly x=126 -> 0.5.
    stage.dispatchMouse(93, 94, "mouseDown");
    stage.dispatchMouse(126, 94, "mouseMove");
    stage.dispatchMouse(126, 94, "mouseUp");
    check(Math.abs(rangeLo - 0.5) < 0.005, "the low drag landed on " + rangeLo + " not 0.5");
    check(Math.abs(rangeHi - 0.75) < 0.005, "the low drag moved the HIGH thumb to " + rangeHi);

    // Cross the thumbs over: the high thumb stops AT the low one (never passes it).
    stage.dispatchMouse(181, 94, "mouseDown");
    stage.dispatchMouse(20, 94, "mouseMove");
    stage.dispatchMouse(20, 94, "mouseUp");
    check(rangeHi >= rangeLo, "the range inverted: " + rangeLo + " .. " + rangeHi);
    check(Math.abs(rangeHi - rangeLo) < 0.005,
        "the high thumb stopped at " + rangeHi + " not at the low one (" + rangeLo + ")");
    check(rangeCalls >= 3, "onRange fired " + rangeCalls + " times (three real changes)");
    say("range: " + rangeLo + " .. " + rangeHi + " after " + rangeCalls + " calls");

    // ==================== phase 3: multiSelect ===============================
    // Row 2 of the OPEN dropdown: (46, 436) from the header arithmetic.
    click(46, 436);
    check(msToggledTo == 2, "the third option reported index " + msToggledTo + " not 2");
    var m:UiNode = app.findByKey("ms");
    var md:MultiSelectNode = MultiSelectNode(m.desc);
    check(md.values.length == 1 && String(md.values[0]) == "Beta",
        "the widget mutated its values array (it must not -- the author owns it): " + md.values.length);
    check(msOpenCalls == 0, "onOpenChange fired " + msOpenCalls + " time(s) on a toggle (it must stay open)");
    check(m.lifted, "the dropdown is no longer lifted after a toggle");

    // Space toggles the ACTIVE row and keeps the panel open, like Enter.
    focus("ms");
    key(40);
    key(32);
    check(msOpenCalls == 0, "Space asked to close the multi-select");
    check(app.findByKey("ms").lifted, "Space dropped the dropdown");
    say("multi: toggle " + msToggledTo + ", values kept, still open");

    // ==================== phase 4: the virtual list ==========================
    // One wheel notch = 3 rows. Offset 60 means the window starts at row 3.
    stage.dispatchWheel(30, 120, -1);
    setTimeout(afterListWheel, 350);
}

function afterListWheel():void
{
    var vl:UiNode = app.findByKey("vl");
    var d:ListNode = ListNode(vl.desc);
    check(listScrollSaw == 60, "onScroll reported " + listScrollSaw + " not 60");
    check(d.offsetY == 60, "offsetY is " + d.offsetY + " not 60");
    check(d.firstIndex == 3 && d.lastIndex == 8,
        "after the wheel the window is " + d.firstIndex + ".." + d.lastIndex + " not 3..8");
    check(keysOf(vl) == "vl:r3,vl:r4,vl:r5,vl:r6,vl:r7,vl:r8",
        "the window after the wheel is " + keysOf(vl));
    check(app.findByKey("vl:r0") == null, "row r0 is still mounted after scrolling past it");

    // The pixels moved with the window, not just the bookkeeping.
    var bd:BitmapData = frame();
    if (rgbAt(bd, 30, 120) != 0x404040)
        bad("(30,120) is " + hex(rgbAt(bd, 30, 120)) + " not row 3's #404040");

    // A click on the FIRST MOUNTED row must report the ABSOLUTE index 3.
    click(30, 120);
    check(listSel == 3, "the click selected " + listSel + " not the absolute row 3");

    // End: the selection leaves the window, so the window follows it. The MOVE is
    // async: `select` only tells the AUTHOR, and the new index reaches the
    // description on the next describe -- so the assertions live in afterListEnd.
    // NO explicit focus(): the click above is what focuses the list (a row click is
    // a focus claim), so this line pins that claim instead of hiding it behind a call.
    key(35);
    setTimeout(afterListEnd, 350);
}

function afterListEnd():void
{
    var d2:ListNode = ListNode(app.findByKey("vl").desc);
    check(listSel == LIST_COUNT - 1, "End reported " + listSel + " not " + (LIST_COUNT - 1));
    check(d2.selectedIndex == LIST_COUNT - 1,
        "End selected " + d2.selectedIndex + " not " + (LIST_COUNT - 1));
    check(d2.firstIndex == LIST_COUNT - 5,
        "End left the window at " + d2.firstIndex + " not " + (LIST_COUNT - 5) + " (no reveal)");
    say("list: wheel 3..8, click 3, end " + d2.firstIndex + ".." + d2.lastIndex);

    // ==================== phase 5: the virtual tree ==========================
    click(30, 252);   // row 1 of the tree, absolute (offset 0) -> a0
    check(treeSel == "a0", "the tree click selected '" + treeSel + "' not 'a0'");
    stage.dispatchWheel(30, 232, -1);
    setTimeout(afterTreeWheel, 350);
}

function afterTreeWheel():void
{
    var tr:UiNode = app.findByKey("tr");
    var d:TreeNode = TreeNode(tr.desc);
    check(treeScrollSaw == 60, "the tree reported offset " + treeScrollSaw + " not 60");
    check(d.firstRow == 3, "the tree window starts at row " + d.firstRow + " not 3");
    check(keysOf(tr) == "tr:ta2,tr:ta3,tr:ta4,tr:ta5,tr:ta6,tr:ta7",
        "the tree window after the wheel is " + keysOf(tr));

    // Absolute row 3 is `a2`. A window-relative index would report `a`.
    treeSel = "";
    click(30, 232);
    check(treeSel == "a2", "the click after scrolling selected '" + treeSel + "' not 'a2'");

    // End walks to the last row and reveals it (async for the same reason).
    key(35);   // focused by the click above, not by a focus() call
    say("tree: wheel to " + d.firstRow + ", click a2");
    setTimeout(afterTreeEnd, 350);
}

function afterTreeEnd():void
{
    // A TREE IS NOT A LIST: End moves the ACTIVE band (the highlight) and Enter
    // activates it, while a list's End selects outright. Asserting a selection here
    // would have pinned the list's semantics onto the tree.
    var d2:TreeNode = TreeNode(app.findByKey("tr").desc);
    check(treeSel == "a2", "End must not select on its own (selected '" + treeSel + "')");
    check(d2.firstRow == TREE_LEAVES - 4,
        "End left the tree window at " + d2.firstRow + " not " + (TREE_LEAVES - 4));
    check(d2.rows.length == TREE_LEAVES + 1, "the tree lost rows while scrolling");
    say("tree: end window " + d2.firstRow + ".." + (d2.firstRow + d2.visibleRows));
    key(13);   // Enter activates the active row
    setTimeout(afterTreeSelect, 300);
}

function afterTreeSelect():void
{
    check(treeSel == "a" + (TREE_LEAVES - 1),
        "Enter selected '" + treeSel + "' not 'a" + (TREE_LEAVES - 1) + "'");
    phaseThrows();
}

// ==================== phase 6: the refusals ==================================
// The guards run at DESCRIBE time, so this is the same call an author's render()
// would make -- caught here so the probe can name what each one must say.
function threw(what:String, fn:Function):void
{
    var hit:Boolean = false;
    var msg:String = "";
    try { fn(); }
    catch (e:Error) { hit = true; msg = e.message; }
    if (!hit) bad(what + " did NOT throw");
    else if (msg == "") bad(what + " threw an error with no message");
    else say("refused: " + msg);
}

function phaseThrows():void
{
    threw("a virtual list with no height", function ():void {
        list([], listRow, { virtual: true, itemHeight: ROW_H });
    });
    threw("a virtual list with a separator", function ():void {
        // StyleRefinement.from, NOT a bare object: a raw literal coerces to
        // #1034 inside the factory and the guard under test never runs.
        list([], listRow, { virtual: true, itemHeight: ROW_H, separator: true,
                            style: StyleRefinement.from({ size: [200, 100] }) });
    });
    threw("a virtual list with no itemHeight", function ():void {
        list([], listRow, { virtual: true, style: StyleRefinement.from({ size: [200, 100] }) });
    });
    threw("a virtual tree with no height", function ():void {
        tree([], { virtual: true, rowHeight: ROW_H });
    });

    // Back to the top so the frame buffer and <OUT>.rects.txt describe the state
    // expect.json pins (the End tours left both lists scrolled to the bottom).
    var l:ListNode = ListNode(app.findByKey("vl").desc);
    l.offsetY = 0;
    listOffset = 0;
    var t:TreeNode = TreeNode(app.findByKey("tr").desc);
    t.offsetY = 0;
    treeOffset = 0;
    view.invalidate(Dirty.ALL);
    setTimeout(finish, 400);
}

function finish():void
{
    var bd:BitmapData = frame();
    var names:Array = ["root", "qty", "rng", "vl", "vl:r0", "vl:r4", "vl:r5",
                       "tr", "tr:ta0", "ms", "ms:drop"];
    var lines:String = "";
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
    ba.writeByte(0); ba.writeByte(0); ba.writeByte(0); ba.writeByte(0);   // x ppm
    ba.writeByte(0); ba.writeByte(0); ba.writeByte(0); ba.writeByte(0);   // y ppm
    ba.writeByte(0); ba.writeByte(0); ba.writeByte(0); ba.writeByte(0);   // clrUsed
    ba.writeByte(0); ba.writeByte(0); ba.writeByte(0); ba.writeByte(0);   // clrImportant
    // BMP rows live BOTTOM-UP and are BGRA, while `getPixels` hands us top-down
    // RGBA -- reverse the rows and swap the channels, or the frame comes out upside
    // down and blue (both happened while this probe was being written).
    for (var y:int = h - 1; y >= 0; y--)
    {
        for (var x:int = 0; x < w; x++)
        {
            var o:int = (y * w + x) * 4;
            ba.writeByte(px[o + 3]);
            ba.writeByte(px[o + 2]);
            ba.writeByte(px[o + 1]);
            ba.writeByte(px[o]);
        }
    }
    var f:File = new File(path);
    var fs:FileStream = new FileStream();
    fs.open(f, FileMode.WRITE);
    fs.writeBytes(ba);
    fs.close();
}
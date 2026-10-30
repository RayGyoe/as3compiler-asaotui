// probes/widgets/overlay/Main.as -- the probe for the OVERLAY group
// (overlay host + dialog + drawer + popover + menu + toast + select).
//
// Output prefix MUST equal the directory name (`overlay`).
//
// NO TEXT INSIDE THE MEASURED BOXES. Every box the probe pins is either a fixed
// size or a fixed-height row, so every expected number below is arithmetic: the
// dialog is 18 + 80 + 12 + 28 + 18 = 156 tall, the menu is 4 + 3*26 + 4 = 86, the
// select's dropdown starts exactly at the trigger's 34px height. Font metrics are
// never involved, which is what makes the hand-computed expect.json honest.
//
// THE SCENE IS STAGED, because a 760x560 window cannot show six overlapping
// surfaces at once without the top one hiding the one being measured:
//
//   A  dialog + popover + open select + 2 toasts   <- rects.txt + bmp written here
//   B  dialog and popover closed; a select-row CLICK through the real event path
//   C  drawer open (edge sheet), then closed
//   D  menu open: selection band, then a row CLICK moving it
//
// The pixels are asserted where they are EXACT: the scrim's composite over white
// (0x66 alpha -> 153), the panel's white padding, the drawer sheet, the toast fill
// and the menu's selection band. Nothing is compared against a screenshot.
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

var W:int = 760;
var H:int = 560;
var OUT:String = 'overlay';

// The model the view renders from -- exactly what an author would keep.
var st:Object = {
    dlg: true, drw: false, pop: true, mnu: false,
    sel: true, selVal: "Beta",
    t1: true, t2: true,
    menuSel: 1,
    selectedRow: -1,
    subMenu: -1,       // which menu item's submenu is open
    subRow: -1,        // the last row activated INSIDE a submenu
    entered: -1        // a keyboard Enter on the menu reports the active row here
};

class OverlayProbe extends View
{
    private static const ROOT:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", alignItems: "flex-start",
        padding: 20, gap: 10, size: [760, 560],
        background: 0xFFFFFF, text: { fontSize: 12, color: 0x111827 }
    });
    private static const ANCHOR:StyleRefinement = StyleRefinement.from({
        size: [120, 32], background: 0xE0E7FF
    });
    private static const DLG_BODY:StyleRefinement = StyleRefinement.from({ size: [264, 80] });
    private static const OK_BTN:StyleRefinement = StyleRefinement.from({
        size: [100, 28], background: 0x2563EB
    });
    private static const POP_BODY:StyleRefinement = StyleRefinement.from({ size: [136, 40] });
    private static const DRW_BODY:StyleRefinement = StyleRefinement.from({ size: [200, 30] });

    public function OverlayProbe():void { super(); }

    override public function render():Node
    {
        return column({ key: "root", style: ROOT, ariaName: "overlay probe" }, [
            box({ key: "anchorBtn", style: ANCHOR, ariaName: "anchor" }),
            select({
                key: "sel", open: st.sel, value: st.selVal, placeholder: "Pick one",
                width: 200, options: ["Alpha", "Beta", "Gamma"],
                onSelect: function (i:int):void
                {
                    st.selVal = ["Alpha", "Beta", "Gamma"][i];
                    st.selectedRow = i;
                    app.invalidate(Dirty.VALUE);
                },
                onOpenChange: function (o:Boolean):void
                {
                    st.sel = o;
                    app.invalidate(Dirty.VALUE);
                }
            })
        ]);
    }

    override public function renderOverlay():Node
    {
        var d:Node = dialog({
            key: "dlg", open: st.dlg, width: 300,
            onClose: function ():void { st.dlg = false; app.invalidate(Dirty.VALUE); },
            footer: [ box({ key: "dlg:ok", style: OK_BTN, ariaName: "ok" }) ]
        }, [ box({ key: "dlg:body", style: DLG_BODY, ariaName: "body" }) ]);
        var w:Node = drawer({
            key: "drw", open: st.drw, side: "bottom", size: 100,
            onClose: function ():void { st.drw = false; app.invalidate(Dirty.VALUE); }
        }, [ box({ key: "drw:body", style: DRW_BODY, ariaName: "sheet body" }) ]);
        var p:Node = popover({
            key: "pop", open: st.pop, anchorKey: "anchorBtn",
            placement: "right", offset: 6, width: 160,
            onClose: function ():void { st.pop = false; app.invalidate(Dirty.VALUE); }
        }, [ box({ key: "pop:body", style: POP_BODY, ariaName: "popover body" }) ]);
        var m:Node = menu({
            key: "mnu", open: st.mnu, anchorKey: "anchorBtn",
            placement: "bottom", offset: 6, width: 160,
            items: ["Cut", { label: "Copy", submenu: ["Copy one", "Copy two"],
                             onSelect: function (i:int):void { st.subRow = i; } }, "Paste"],
            selectedIndex: st.menuSel, submenuIndex: st.subMenu,
            onSelect: function (i:int):void { st.menuSel = i; app.invalidate(Dirty.VALUE); },
            onClose: function ():void { st.mnu = false; app.invalidate(Dirty.VALUE); }
        });
        var ts:Node = toastHost({ key: "toasts" }, [
            toast({ key: "t1", open: st.t1, message: "Saved",
                    onClose: function ():void { st.t1 = false; app.invalidate(Dirty.VALUE); } }),
            toast({ key: "t2", open: st.t2, message: "Uploaded", tone: "success",
                    onClose: function ():void { st.t2 = false; app.invalidate(Dirty.VALUE); } })
        ]);
        return overlay([d, w, p, m, ts]);
    }
}

var view:OverlayProbe = new OverlayProbe();
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

setTimeout(settle, 900);
stage.showWindow(W, H, "probe overlay");

var solveAtSettle:Number = 0;
var frame0:int = 0;
var carry:String = "";

function settle():void
{
    var names:Array = ["root", "anchorBtn", "sel", "sel:label", "sel:drop",
                       "sel:i0", "sel:i1", "sel:i2",
                       "dlg", "dlg:scrim", "dlg:panel", "dlg:body", "dlg:footer", "dlg:ok",
                       "drw", "drw:scrim", "drw:panel", "drw:body",
                       "pop", "pop:body",
                       "mnu", "mnu:i0", "mnu:i1", "mnu:i2",
                       "toasts", "t1", "t2"];
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

    solveAtSettle = app.layoutSolves;
    frame0 = app.enterFrameTicks;
    if (missing > 0) { writeText(OUT + ".done", "FAIL " + missing + " node(s) missing"); return; }

    var problems:String = "";

    // (a) all six kinds are registered -- an unregistered one throws at structure
    //     time, but `Widgets.has` also pins that the registry was populated by the
    //     factory rather than by a fallback.
    var kinds:Array = ["dialog", "drawer", "popover", "menu", "toast", "select"];
    for (var k:int = 0; k < kinds.length; k++)
    {
        if (!Widgets.has(kinds[k])) problems = problems + "Widgets.has('" + kinds[k] + "') is false; ";
    }

    // (b) a settled overlay tree stops solving (the second retained tree must not
    //     reflow once nothing changes).

    // (c) the dialog is centred on BOTH axes: the layer centres it, so this is the
    //     whole point of LAYER_CENTER. 18 + 80 + 12 + 28 + 18 = 156 tall.
    var dp:UiNode = app.findByKey("dlg:panel");
    if (dp.absH != 158) problems = problems + "dialog panel height is " + dp.absH + " not 158 (1+18+80+12+28+18+1); ";
    if (2 * dp.absY + dp.absH != H) problems = problems + "dialog is not vertically centred: " + dp.absY + "+" + dp.absH + "; ";
    if (dp.absX != 230 || dp.absW != 300) problems = problems + "dialog panel is " + dp.absX + "," + dp.absW + " not 230,300; ";

    var bd2:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd2.draw(stage);
    problems = problems + expectStr(bd2, 240, 210, 0xFFFFFF, "the dialog panel's own padding is not white (the scrim must not tint INSIDE the panel)");
    problems = problems + expectStr(bd2, 700, 300, 0x999999, "the scrim over white is not #999999 (0x66 alpha == 0.4 -> 255*0.6)");
    problems = problems + expectStr(bd2, 740, 10, 0x999999, "the scrim does not reach the top-right corner");

    // (d) the popover hangs off the anchor's RIGHT edge: 20 + 120 + 6 = 146, top 20.
    var pp:UiNode = app.findByKey("pop");
    if (pp.absX != 146 || pp.absY != 20) problems = problems + "popover at " + pp.absX + "," + pp.absY + " not 146,20; ";
    if (pp.absW != 160) problems = problems + "popover width is " + pp.absW + " not 160; ";
    if (pp.absH != 66) problems = problems + "popover height is " + pp.absH + " not 66 (1+12+40+12+1); ";
    problems = problems + expectStr(bd2, 150, 24, 0xFFFFFF, "the popover panel's padding is not white");

    // (e) the toasts stack in the bottom-right corner: right edge 760-16 = 744, so
    //     x = 744 - 220 = 524; the last one's bottom is 560 - 16 = 544.
    var t1:UiNode = app.findByKey("t1");
    var t2:UiNode = app.findByKey("t2");
    if (t1.absX != 524 || t2.absX != 524) problems = problems + "toasts are not flush right (" + t1.absX + "," + t2.absX + " not 524); ";
    if (t1.absW != 220 || t2.absW != 220) problems = problems + "toast widths are " + t1.absW + "," + t2.absW + " not 220; ";
    if (t2.absY + t2.absH != 544) problems = problems + "the last toast's bottom is " + (t2.absY + t2.absH) + " not 544; ";
    if (t1.absY + t1.absH + 8 != t2.absY) problems = problems + "the toast gap is not 8 (" + (t1.absY + t1.absH) + " -> " + t2.absY + "); ";
    problems = problems + expectStr(bd2, int(t2.absX) + 20, int(t2.absY) + 4, 0x065F46, "the success toast fill");
    problems = problems + expectStr(bd2, int(t1.absX) + 20, int(t1.absY) + 4, 0x111827, "the default toast fill");

    // (f) the select's dropdown sits flush under the 34px trigger and is as wide as
    //     it; it is visible because `open` travels as the child's `visible`.
    var drop:UiNode = app.findByKey("sel:drop");
    if (!drop.backing.visible) problems = problems + "the open dropdown is not visible; ";

    // A flex row centres the text NODE. Its field must cancel the renderer's
    // 2px paragraph gutter or the glyphs sit low inside both trigger and rows.
    var triggerLabel:UiNode = app.findByKey("sel:label");
    var rowLabel:UiNode = app.findByKey("sel:i0:t");
    if (triggerLabel == null || triggerLabel.tf == null || triggerLabel.tf.y != -PaintKit.TEXT_GUTTER)
        problems = problems + "the select trigger label ignores the paragraph gutter; ";
    if (rowLabel == null || rowLabel.tf == null || rowLabel.tf.y != -PaintKit.TEXT_GUTTER)
        problems = problems + "the select row label ignores the paragraph gutter; ";

    carry = problems;
    setTimeout(stageB, 300);
}

// ---- B: close the modal+popover, then CLICK a select row -------------------
function stageB():void
{
    // A settled overlay tree must stop reflowing. Measured HERE, not in settle(),
    // where both snapshots are taken in the same tick and the answer is always 0.
    var extraSolves:Number = app.layoutSolves - solveAtSettle;
    var extraFrames:int = app.enterFrameTicks - frame0;
    if (extraFrames < 2) carry = carry + "only " + extraFrames + " frame(s) elapsed in 300ms; ";
    if (extraSolves > 0) carry = carry + "a settled tree re-solved layout " + extraSolves + " time(s); ";
    st.dlg = false;
    st.pop = false;
    app.invalidate(Dirty.VALUE);
    setTimeout(clickSelectRow, 300);
}

function clickSelectRow():void
{
    var problems:String = carry;
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    // The dialog is closed => the select is no longer under the scrim.
    problems = problems + expectStr(bd, 240, 210, 0xFFFFFF, "the closed dialog still dims the page (its scrim must stop painting)");
    // Row 1 is selected (`value: "Beta"`), so its band is ITEM_SELECTED.
    problems = problems + expectStr(bd, 30, 140, 0xDBEAFE, "the select's selected row band");
    problems = problems + expectStr(bd, 30, 113, 0xFFFFFF, "the select's unselected row is not the panel white");

    // A REAL click: hit test -> bubble -> SelectWidget row routing -> onSelect.
    // Row 2's centre is (24 + 96, 152 + 13).
    clickLocal(app.findByKey("sel:i2"), 10, 13);
    carry = problems;
    setTimeout(selectMoved, 300);
}

function selectMoved():void
{
    var problems:String = carry;
    if (st.selectedRow != 2) problems = problems + "the select reported row " + st.selectedRow + " not 2; ";
    if (st.selVal != "Gamma") problems = problems + "the select did not report: value is " + st.selVal + "; ";
    // Choosing a row CLOSES the dropdown, so the badge under it is gone.
    if (st.sel) problems = problems + "the select stayed open after a row was chosen; ";

    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    problems = problems + expectStr(bd, 30, 166, 0xFFFFFF, "the dropdown did not close after the row click");
    problems = problems + expectStr(bd, 30, 140, 0xFFFFFF, "the closed dropdown its band left behind");

    // Re-open it: the band must now sit on ROW 2 and row 1 must be plain again.
    st.sel = true;
    app.invalidate(Dirty.VALUE);
    carry = problems;
    setTimeout(selectReopened, 400);
}

function selectReopened():void
{
    var problems:String = carry;
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    problems = problems + expectStr(bd, 30, 166, 0xDBEAFE, "the band did not move to row 2 after the click");
    problems = problems + expectStr(bd, 30, 140, 0xFFFFFF, "row 1's band survived the selection move");
    carry = problems;
    setTimeout(stageC, 100);
}

// ---- C: the drawer ---------------------------------------------------------
function stageC():void
{
    st.sel = false;
    st.drw = true;
    app.invalidate(Dirty.VALUE);
    setTimeout(checkDrawer, 400);
}

function checkDrawer():void
{
    var problems:String = carry;
    var p:UiNode = app.findByKey("drw:panel");
    // side "bottom": the sheet is pinned to the bottom edge, full width (align
    // stretch on the cross axis), and exactly `size` tall.
    if (p.absX != 0 || p.absW != W) problems = problems + "the bottom sheet is not full width: " + p.absX + "," + p.absW + "; ";
    if (p.absH != 100) problems = problems + "the sheet is " + p.absH + " tall not 100; ";
    if (p.absY + p.absH != H) problems = problems + "the sheet is not pinned to the bottom edge: " + (p.absY + p.absH) + "; ";

    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    problems = problems + expectStr(bd, 30, 470, 0xFFFFFF, "the sheet's own surface");
    problems = problems + expectStr(bd, 730, 550, 0xFFFFFF, "the sheet is not stretched to the right edge");
    problems = problems + expectStr(bd, 700, 100, 0x999999, "the drawer's scrim over white");
    carry = problems;
    setTimeout(stageD, 100);
}

// ---- D: the menu -----------------------------------------------------------
function stageD():void
{
    st.drw = false;
    st.mnu = true;
    app.invalidate(Dirty.VALUE);
    setTimeout(checkMenu, 400);
}

function checkMenu():void
{
    var problems:String = carry;
    var m:UiNode = app.findByKey("mnu");
    // 20 (anchor x), 20+32+6 = 58, 160 wide, 4 + 3*26 + 4 = 86 tall.
    if (m.absX != 20 || m.absY != 58) problems = problems + "menu at " + m.absX + "," + m.absY + " not 20,58; ";
    if (m.absW != 160) problems = problems + "menu width is " + m.absW + " not 160; ";
    if (m.absH != 88) problems = problems + "menu height is " + m.absH + " not 88 (1+4+3*26+4+1); ";

    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    // selectedIndex is 1 -> row 1's band (row 1 spans y 88..113).
    problems = problems + expectStr(bd, 30, 102, 0xDBEAFE, "the menu's selected row band");
    problems = problems + expectStr(bd, 30, 75, 0xFFFFFF, "menu row 0 must not be banded");
    problems = problems + expectStr(bd, 30, 60, 0xFFFFFF, "the menu panel's top padding");

    // A row click moves the band: dispatched on ROW 2's backing in row-local space.
    clickLocal(app.findByKey("mnu:i2"), 10, 13);
    carry = problems;
    setTimeout(menuMoved, 300);
}

function menuMoved():void
{
    var problems:String = carry;
    if (st.menuSel != 2) problems = problems + "the menu reported row " + st.menuSel + " not 2; ";
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    problems = problems + expectStr(bd, 30, 128, 0xDBEAFE, "the band did not move down after the row click");
    problems = problems + expectStr(bd, 30, 102, 0xFFFFFF, "the old band survived the move");
    carry = problems;
    // A submenu is armed by the author, exactly like every other `open`.
    st.subMenu = 1;
    app.invalidate(Dirty.VALUE);
    setTimeout(checkSubmenu, 400);
}

// ---- E: the SUBMENU (a nested menu anchored to its own row) -----------------
function checkSubmenu():void
{
    var problems:String = carry;
    var sub:UiNode = app.findByKey("mnu:sub1");
    if (sub == null) { writeText(OUT + ".done", problems + "the submenu node does not exist (menu.as did not build it)"); return; }
    if (!sub.backing.visible) problems = problems + "the submenu was not opened by submenuIndex; ";
    // Row 1 of the menu is 25,89,150,26 => its right edge is 175, +4 = 179, and the
    // nested panel's top is the row's own top (89).
    if (sub.absX != 179) problems = problems + "the submenu is at x=" + sub.absX + " not 179 (row right 175 + 4); ";
    if (sub.absY != 89) problems = problems + "the submenu is at y=" + sub.absY + " not 89 (its row's top); ";
    if (sub.absW != 160) problems = problems + "the submenu is " + sub.absW + " wide not 160 (it inherits the menu width); ";

    // A click INSIDE the submenu must not be read as a click on the parent row that
    // happens to sit at the same height (row 1 spans y 89..115, and the submenu's
    // first row is 94..120 -- they overlap).
    clickLocal(app.findByKey("mnu:sub1:i0"), 10, 13);
    carry = problems;
    setTimeout(subClicked, 250);
}

function subClicked():void
{
    var problems:String = carry;
    if (st.subRow != 0) problems = problems + "the submenu reported row " + st.subRow + " not 0; ";
    if (st.menuSel != 2) problems = problems + "a click inside the submenu also activated parent row " + st.menuSel + "; ";
    carry = problems;
    setTimeout(stageMotion, 100);
}

// ---- F: the ENTRANCE animation --------------------------------------------
// Driven white-box: `start` + one `apply` in the same tick is t == 0, so the
// mid-flight value does not depend on frame pacing (a frame-count-based sample
// would be a coin flip). The LANDING is what matters, and it is exact: alpha back
// to 1, the backing back on its solved offset, and the motion disarmed.
function stageMotion():void
{
    var t:UiNode = app.findByKey("t1");
    OverlayMotion.start(t);
    OverlayMotion.apply(t, t, t, 0, 8);
    carry = carry
        + (t.backing.alpha < 1 ? "" : "the entrance never faded (alpha is already 1); ")
        + (t.backing.y != t.absY ? "" : "the entrance never moved the surface; ");
    setTimeout(checkMotionLanded, 400);
}

function checkMotionLanded():void
{
    var problems:String = carry;
    var t:UiNode = app.findByKey("t1");
    if (OverlayMotion.isRunning(t)) problems = problems + "the entrance never finished (it is still armed); ";
    if (t.backing.alpha != 1) problems = problems + "the toast settled at alpha " + t.backing.alpha + " not 1; ";
    // The toast host is at 0,0, so a landed backing sits exactly on its own absY.
    if (t.backing.y != t.absY) problems = problems + "the toast settled at y=" + t.backing.y + " not " + t.absY + " (the entrance parked it); ";
    // ...and it must stop repainting once landed.
    var paints:int = app.paintPasses;
    carry = problems + "|" + paints;
    setTimeout(stopPaintCheck, 250);
}

function stopPaintCheck():void
{
    var parts:Array = carry.split("|");
    var problems:String = String(parts[0]);
    if (parts.length > 1 && app.paintPasses != int(Number(parts[1])))
        problems = problems + "a landed entrance kept repainting (" + parts[1] + " -> " + app.paintPasses + "); ";
    writeText(OUT + ".done", problems == "" ? "PASS" : "FAIL " + problems);
}

function expectStr(bd:BitmapData, x:int, y:int, rgb:uint, what:String):String
{
    var got:uint = bd.getPixel(x, y) & 0xFFFFFF;
    if (got == rgb) return "";
    return what + " is " + hex(got) + " not " + hex(rgb) + "; ";
}

function hex(v:uint):String
{
    var s:String = (v & 0xFFFFFF).toString(16);
    while (s.length < 6) s = "0" + s;
    return "#" + s;
}

// A click on a node's own backing, in that backing's LOCAL coordinates -- the
// protocol every other widget probe uses. It also exercises the TARGET-RELATIVE
// localY contract that OverlayList.localYIn fixes: a real click picks the ROW, so
// the row's own backing receives the coordinates.
function clickLocal(n:UiNode, lx:Number, ly:Number):void
{
    n.backing.dispatchEvent(new MouseEvent(MouseEvent.CLICK, true, false, lx, ly));
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
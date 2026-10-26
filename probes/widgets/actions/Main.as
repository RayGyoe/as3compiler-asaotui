// probes/widgets/actions/Main.as -- the 2026-10-27 batch, measured end to end:
// RIGHT CLICK + POINT-ANCHORED MENU, DOUBLE CLICK, splitPane, and the KEYMAP
// (ActionRegistry + Control.action + tabIndex ordering).
//
// Output prefix MUST equal the directory name (`actions`).
//
// WHY EACH ASSERTION IS WHERE IT IS. All four of these can look right in a bitmap
// and be wrong:
//
//   right click   The handler is the only evidence that the runtime's
//                 `rightMouseDown` reached a kit node at all. The menu's RECT then
//                 proves the point anchor placed the panel at the pointer (a
//                 clamped or anchored panel would land elsewhere), and one pixel on
//                 the panel proves the overlay really is ABOVE the layout.
//   menu band     The click sets the menu's ACTIVE row, not its SELECTION, so the
//                 band is ITEM_HOVER (0xF3F4F6) and not ITEM_SELECTED -- reading
//                 the band colour is what tells the two apart.
//   double click  Two separate things: the flag the RUNTIME reads
//                 (`backing.doubleClickEnabled`) is on for a node with a handler
//                 and OFF for one without, and the handler runs when the event
//                 arrives. Asserting only the second would pass with the flag on
//                 globally, which would change what a fast second click means for
//                 every control in the library.
//   splitPane     Both drags assert a NUMBER, not "it moved": the second one is
//                 clamped at the minimum (40) and the third lands on exactly 2/3.
//                 A widget that ignored minSize, or that reported the pointer
//                 position instead of a share, gives a different number.
//   keymap        Every branch is a different code path: a bound key inside the
//                 context, the same key OUTSIDE it, a payload, `Control.action` on
//                 Enter (which must NOT also run onClick), Tab rebound (which must
//                 NOT move the ring), and tabIndex ordering.
//
//   tabIndex      Document order is [btn, btn2, btn3] and the indices are 1 and 0,
//                 so the ring is [btn3, btn2, btn]. An implementation that ignored
//                 tabIndex would still be a ROTATION of that, and a rotation has the
//                 same successors from every start point -- so the only place the two
//                 differ is a start whose successor changes: Tab from `btn` (ordered
//                 -> btn3, document order -> btn2). The next two Tabs pin the rest.
//
// HAND ARITHMETIC (window 560x640; root column, padding 16, gap 10, alignItems
// flex-start, background white; children rrow, dbl, sp, wiz):
//
//   rrow (16,  16, 240, 28)   explicit size
//   dbl  (16,  54, 240, 28)   54 = 16 + 28 + 10
//   sp   (16,  92, 300, 80)   92 = 54 + 28 + 10
//   wiz  (16, 182, 300, 96)   182 = 92 + 80 + 10
//
//   SPLIT (row, dividerSize 6, minSize 40, ratio 0.5):
//     avail = 300 - 6 = 294
//     A     = round(294 * 0.5) = 147      div x = 16 + 147 = 163     B x = 169
//     drag 1  press (166) -> 20: share 4/294 = 0.0136 -> CLAMP 40/294 = 0.13605
//             A = round(294 * 0.13605) = 40 ; div 56..62 ; B 62..316 (254 wide)
//     drag 2  press (59)  -> 212: share 196/294 = 0.666667
//             A = round(294 * 0.666667) = 196 ; div 212..218 ; B 218..316 (98)
//
//   MENU at the pointer (60, 30), width 160, 3 items:
//     panel  160 wide, height = 1 + 4 + 3*26 + 4 + 1 = 88   -> (60, 30, 160, 88)
//     rows   inset by border 1 + padding 4 = 5              -> (65, 35 + 26i, 150, 26)
//     no flip: 30 + 88 = 118 < 640 and 60 + 160 = 220 < 560
//
//   PIXELS (all read AFTER the two drags, so the split geometry is the second one):
//     (70,  40) inside menu row 0  -> #F3F4F6 (ITEM_HOVER: active, not selected)
//     (200,100) inside menu row 2  -> #FFFFFF (row 2 carries no band)
//     (30, 150) inside pane A      -> #EEF2FF
//     (215,150) inside the grip    -> #E5E7EB
//     (300,150) inside pane B      -> #FFF1F2
//     (30,  70) inside `dbl`       -> #DDF6DD (left of the menu, so not covered)
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

var W:int = 560;
var H:int = 640;
var OUT:String = "actions";

class ActionsProbe extends View
{
    private static const ROOT:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", alignItems: "flex-start",
        padding: 16, gap: 10, size: [560, 640], background: 0xFFFFFF
    });
    private static const RROW:StyleRefinement = StyleRefinement.from({
        size: [240, 28], background: 0xDDE6FF
    });
    private static const DBL:StyleRefinement = StyleRefinement.from({
        size: [240, 28], background: 0xDDF6DD
    });
    private static const SPLIT:StyleRefinement = StyleRefinement.from({ size: [300, 80] });
    // A SECOND splitter, authored with a ratio BELOW minSize/avail. Nothing else in
    // the probe can reach `measure`'s clamp: the drag clamps its own report first, so
    // a splitter only collapses if measure ignores minSize on the author's ratio.
    // avail is 294 again (same 300 width, same 6pt grip).
    private static const SPLIT2:StyleRefinement = StyleRefinement.from({ size: [300, 40] });
    private static const PANE_C:StyleRefinement = StyleRefinement.from({
        size: [null, 40], background: 0xEEF2FF
    });
    private static const PANE_D:StyleRefinement = StyleRefinement.from({
        size: [null, 40], background: 0xFFF1F2
    });
    // The panes carry NO main-axis size on purpose: the widget's flex basis is the
    // only thing that may decide the share (see SplitPaneWidget.measure).
    private static const PANE_A:StyleRefinement = StyleRefinement.from({
        size: [null, 80], background: 0xEEF2FF
    });
    private static const PANE_B:StyleRefinement = StyleRefinement.from({
        size: [null, 80], background: 0xFFF1F2
    });
    private static const WIZ:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", alignItems: "flex-start",
        padding: 8, gap: 6, size: [300, 128], background: 0xFFFFFF
    });
    private static const INNER:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", alignItems: "flex-start",
        padding: 4, size: [160, 34], background: 0xFAFAFA
    });
    private static const BTN:StyleRefinement = StyleRefinement.from({ size: [120, 32] });
    private static const BTN2:StyleRefinement = StyleRefinement.from({ size: [120, 26] });
    public function ActionsProbe():void { super(); }

    override public function render():Node
    {
        return column({ key: "root", style: ROOT, ariaName: "actions probe" }, [
            box({ key: "rrow", style: RROW, ariaName: "right click target",
                  onRightClick: rightClicked }),
            box({ key: "dbl", style: DBL, ariaName: "double click target",
                  onDoubleClick: doubleClicked }),
            splitPane(
                box({ key: "sp:a", style: PANE_A }),
                box({ key: "sp:b", style: PANE_B }),
                { key: "sp", style: SPLIT, direction: "row",
                  ratio: spRatio, minSize: 40, dividerSize: 6, onResize: splitResized }
            ),
            // THE KEY CONTEXT LIVES ON TWO CONTAINERS, not on the buttons: that is
            // the point of the design -- an author tags a region once and every
            // control inside it inherits the context.
            column({ key: "wiz", style: WIZ, keyContext: "probe", ariaName: "keymap host" }, [
                button({ key: "btn", label: "Run", action: "probe.act",
                         onClick: buttonClicked, style: BTN }),
                box({ key: "inner", keyContext: "modal", style: INNER }, [
                    button({ key: "btn2", label: "Inner", tabIndex: tab2, style: BTN2 })
                ]),
                button({ key: "btn3", label: "Last", tabIndex: tab3, style: BTN })
            ]),
            splitPane(
                box({ key: "sp2:a", style: PANE_C }),
                box({ key: "sp2:b", style: PANE_D }),
                { key: "sp2", style: SPLIT2, direction: "row",
                  ratio: 0.02, minSize: 40, dividerSize: 6 }
            )
        ]);
    }

    // A POINT-ANCHORED MENU. `atX`/`atY` are stage coordinates -- exactly what
    // onRightClick hands the author -- so the handler is one assignment.
    override public function renderOverlay():Node
    {
        return overlay([
            menu({ key: "cm", open: cmOpen, atX: cmX, atY: cmY, width: 160,
                   items: ["Copy", "Paste", "Delete"],
                   onSelect: menuPicked,
                   onClose: function ():void { cmOpen = false; view.invalidate(Dirty.ALL); } })
        ]);
    }
}

var cmOpen:Boolean = false;
var cmX:Number = 0;
var cmY:Number = 0;
var cmSel:int = -1;
var cmArgX:Number = -1;
var cmArgY:Number = -1;
var dblHits:int = 0;
var spRatio:Number = 0.5;
// Explicit tab indices, AUTHOR-owned like every other model field. btn2 takes 1 and
// btn3 takes 0, so the ring is [btn3, btn2, btn] -- which is NOT a rotation of the
// document order [btn, btn2, btn3] and therefore actually distinguishable.
var tab2:int = 1;
var tab3:int = 0;
var splitReports:int = 0;
var actFired:int = 0;
var btnClicks:int = 0;
var escFired:int = 0;
var tabFired:int = 0;
var opened:String = "";

function rightClicked(x:Number, y:Number):void
{
    cmArgX = x;
    cmArgY = y;
    cmX = x;
    cmY = y;
    cmOpen = true;
    view.invalidate(Dirty.ALL);
}
function doubleClicked():void { dblHits = dblHits + 1; }
function menuPicked(i:int):void { cmSel = i; view.invalidate(Dirty.ALL); }
function splitResized(r:Number):void { spRatio = r; splitReports = splitReports + 1; view.invalidate(Dirty.ALL); }
function buttonClicked():void { btnClicks = btnClicks + 1; }

var view:ActionsProbe = new ActionsProbe();
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

var problems:String = "";
var log:String = "";

setTimeout(ready, 900);
stage.showWindow(W, H, "probe actions");

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

function key(code:int):void { keyMod(code, false); }

// ctrlKey is argument 7 of the KeyboardEvent constructor (charCode, keyCode,
// keyLocation come before it) -- the same order AIR uses.
function keyMod(code:int, ctrl:Boolean):void
{
    var e:KeyboardEvent = new KeyboardEvent(KeyboardEvent.KEY_DOWN, true, true,
        0, code, 0, ctrl, false, false, false, false, false);
    stage.dispatchEvent(e);
}

function focus(k:String):void
{
    var n:UiNode = app.findByKey(k);
    if (n == null) { bad("no node " + k); return; }
    app.focusNode(n);
}

function keyOfFocused():String
{
    var n:UiNode = app.focusedNode();
    return n == null ? "?" : String(n.key);
}

function rect(n:UiNode):String
{
    return n.absX + "," + n.absY + "," + n.absW + "," + n.absH;
}

// Numeric comparison, not a string one: the four numbers are what the expectation
// pins, and a stray ".0" must not turn a correct layout into a failure.
function rectIs(n:UiNode, x:Number, y:Number, w:Number, h:Number):Boolean
{
    return n.absX == x && n.absY == y && n.absW == w && n.absH == h;
}

// ==================== phase 0: the resting frame ============================
function ready():void
{
    check(Widgets.has("splitPane"), "Widgets.has('splitPane') is false");

    var sp:UiNode = app.findByKey("sp");
    if (sp == null) { bad("the split pane never mounted"); finish(); return; }
    check(sp.children.length == 3, "the split pane has " + sp.children.length + " children, not 3");

    // ratio 0.5, avail 294 -> 147 / 6 / 147. Hand arithmetic, not a copy of the
    // program's own output: 300 - 6 = 294 and round(294 * 0.5) = 147.
    var a:UiNode = app.findByKey("sp:a");
    var dv:UiNode = app.findByKey("sp:div");
    var b:UiNode = app.findByKey("sp:b");
    if (a == null || dv == null || b == null) { bad("a split child never mounted"); finish(); return; }
    check(rectIs(a, 16, 92, 147, 80), "pane A is " + rect(a) + " not 16,92,147,80");
    check(rectIs(dv, 163, 92, 6, 80), "the grip is " + rect(dv) + " not 163,92,6,80");
    check(rectIs(b, 169, 92, 147, 80), "pane B is " + rect(b) + " not 169,92,147,80");

    // A ratio BELOW the minimum is legal input (0..1) and must be clamped, not obeyed:
    // round(294 * 0.02) = 6, which is under minSize 40 -> the first pane is 40 and the
    // second gets the rest. The splitter sits after `wiz` (182 + 128 + 10 = 320).
    var a2:UiNode = app.findByKey("sp2:a");
    var d2:UiNode = app.findByKey("sp2:div");
    var b2:UiNode = app.findByKey("sp2:b");
    if (a2 == null || d2 == null || b2 == null) { bad("the ratio-0.02 splitter never mounted"); finish(); return; }
    check(rectIs(a2, 16, 320, 40, 40),
        "after the clamp pane A is " + rect(a2) + " not 16,320,40,40");
    check(rectIs(d2, 56, 320, 6, 40), "its grip is " + rect(d2) + " not 56,320,6,40");
    check(rectIs(b2, 62, 320, 254, 40), "its pane B is " + rect(b2) + " not 62,320,254,40");
    say("clamp: " + rect(a2) + " / " + rect(d2) + " / " + rect(b2));

    // Nothing has been right-clicked yet, so the menu must not exist as a visible
    // surface even though its node is in the overlay tree.
    var cm:UiNode = app.findByKey("cm");
    check(cm != null && !cm.visible, "the context menu is visible before any right click");

    // The flag the RUNTIME reads must be off when there is no handler -- otherwise
    // every fast second click in the app becomes a doubleClick.
    var rrow:UiNode = app.findByKey("rrow");
    check(rrow.backing != null && rrow.backing.doubleClickEnabled == false,
        "a node without onDoubleClick has doubleClickEnabled on");
    var dbl:UiNode = app.findByKey("dbl");
    check(dbl.backing != null && dbl.backing.doubleClickEnabled == true,
        "a node with onDoubleClick has doubleClickEnabled off (the runtime will never send it)");

    say("ready: split " + rect(a) + " / " + rect(dv) + " / " + rect(b));

    // A RIGHT press at (60,30), which is inside `rrow` (16..256, 16..44).
    stage.dispatchMouse(60, 30, "rightMouseDown");
    setTimeout(afterMenuOpen, 300);
}

// ==================== phase 1: right click -> point-anchored menu ===========
function afterMenuOpen():void
{
    check(cmArgX == 60 && cmArgY == 30,
        "onRightClick got (" + cmArgX + "," + cmArgY + ") not the stage point (60,30)");
    check(cmOpen, "the menu did not open");

    var cm:UiNode = app.findByKey("cm");
    if (cm == null) { bad("no menu node"); finish(); return; }
    check(cm.visible, "the menu is still invisible after opening");
    // (60,30) + 160x88, no flip: 30 + 88 = 118 < 640 and 60 + 160 = 220 < 560.
    check(rectIs(cm, 60, 30, 160, 88), "the menu is at " + rect(cm) + " not 60,30,160,88");
    check(cm.children.length == 3, "the menu has " + cm.children.length + " rows, not 3");
    var r0:UiNode = app.findByKey("cm:i0");
    if (r0 == null) { bad("no menu row 0"); finish(); return; }
    check(rectIs(r0, 65, 35, 150, 26), "row 0 is " + rect(r0) + " not 65,35,150,26");

    say("menu: " + rect(cm) + " (row 0 " + rect(r0) + ")");

    // Row 0 centre: y = 35 + 13 = 48. It is BELOW `rrow` (which ends at 44), so the
    // click cannot also be a click on the right-click target.
    stage.dispatchMouse(80, 48, "click");
    setTimeout(afterMenuPick, 300);
}

function afterMenuPick():void
{
    check(cmSel == 0, "the menu reported row " + cmSel + " not 0");

    var bd:BitmapData = frame();
    // ITEM_HOVER, not ITEM_SELECTED: a click sets the ACTIVE row, and the author's
    // `selectedIndex` is still -1. (0xF3F4F6 vs 0xDBEAFE -- reading this pixel is
    // what separates the two bands.)
    if (rgbAt(bd, 70, 40) != 0xF3F4F6)
        bad("menu row 0 is " + hex(rgbAt(bd, 70, 40)) + " not the #F3F4F6 active band");
    // The panel surface on row 2, which carries no band at all.
    if (rgbAt(bd, 200, 100) != 0xFFFFFF)
        bad("the menu surface at (200,100) is " + hex(rgbAt(bd, 200, 100)) + " not #FFFFFF");
    say("menu: picked " + cmSel + ", band + surface pixels exact");

    // ==================== phase 2: double click ==============================
    // (30,70), NOT (60,70): the menu opened at x=60, so its left border sits exactly
    // over that column and the overlay would win the hit test.
    stage.dispatchMouse(30, 70, "doubleClick");
    check(dblHits == 1, "the double click handler ran " + dblHits + " time(s), not 1");

    // ==================== phase 3: the splitter ==============================
    // Press on the grip's centre (163..169 -> 166) and drag far LEFT: the share
    // clamps at minSize 40, it does not follow the pointer to 0.
    stage.dispatchMouse(166, 120, "mouseDown");
    stage.dispatchMouse(20, 120, "mouseMove");
    stage.dispatchMouse(20, 120, "mouseUp");
    setTimeout(afterDrag1, 350);
}

function afterDrag1():void
{
    // 40/294 = 0.136054...
    check(Math.abs(spRatio - 40 / 294) < 0.001,
        "the clamped share is " + spRatio + " not 40/294 = 0.13605");
    var a:UiNode = app.findByKey("sp:a");
    var dv:UiNode = app.findByKey("sp:div");
    var b:UiNode = app.findByKey("sp:b");
    check(rectIs(a, 16, 92, 40, 80), "after the clamp pane A is " + rect(a) + " not 16,92,40,80");
    check(rectIs(dv, 56, 92, 6, 80), "after the clamp the grip is " + rect(dv) + " not 56,92,6,80");
    check(rectIs(b, 62, 92, 254, 80), "after the clamp pane B is " + rect(b) + " not 62,92,254,80");
    say("split: clamped to " + rect(a) + " / " + rect(dv) + " / " + rect(b));

    // Drag the grip (now at 56..62) to x=212 -> share 196/294 = 2/3 exactly.
    stage.dispatchMouse(59, 120, "mouseDown");
    stage.dispatchMouse(212, 120, "mouseMove");
    stage.dispatchMouse(212, 120, "mouseUp");
    setTimeout(afterDrag2, 350);
}

function afterDrag2():void
{
    check(Math.abs(spRatio - 196 / 294) < 0.001,
        "the second drag reported " + spRatio + " not 196/294 = 0.6667");
    check(splitReports >= 3, "onResize fired " + splitReports + " times for three real changes");
    var a:UiNode = app.findByKey("sp:a");
    var dv:UiNode = app.findByKey("sp:div");
    var b:UiNode = app.findByKey("sp:b");
    // round(294 * 0.666667) = 196 -> div 212..218 -> B 218..316 (98 wide).
    check(rectIs(a, 16, 92, 196, 80), "after the second drag pane A is " + rect(a) + " not 16,92,196,80");
    check(rectIs(dv, 212, 92, 6, 80), "after the second drag the grip is " + rect(dv) + " not 212,92,6,80");
    check(rectIs(b, 218, 92, 98, 80), "after the second drag pane B is " + rect(b) + " not 218,92,98,80");

    var bd:BitmapData = frame();
    if (rgbAt(bd, 30, 150) != 0xEEF2FF)
        bad("pane A at (30,150) is " + hex(rgbAt(bd, 30, 150)) + " not #EEF2FF");
    if (rgbAt(bd, 215, 150) != 0xE5E7EB)
        bad("the grip at (215,150) is " + hex(rgbAt(bd, 215, 150)) + " not #E5E7EB");
    if (rgbAt(bd, 300, 150) != 0xFFF1F2)
        bad("pane B at (300,150) is " + hex(rgbAt(bd, 300, 150)) + " not #FFF1F2");
    if (rgbAt(bd, 30, 70) != 0xDDF6DD)
        bad("the double-click box at (30,70) is " + hex(rgbAt(bd, 30, 70)) + " not #DDF6DD");
    say("split: " + rect(a) + " / " + rect(dv) + " / " + rect(b) + "; pixels exact");

    keyPhase();
}

// ==================== phase 4: the keymap ==================================
function keyPhase():void
{
    ActionRegistry.reset();
    ActionRegistry.register("probe.act", function (p:Object):void { actFired = actFired + 1; });
    ActionRegistry.register("probe.esc", function (p:Object):void { escFired = escFired + 1; });
    ActionRegistry.register("probe.open", function (p:Object):void {
        opened = p == null ? "(no payload)" : String(p.name);
    });
    ActionRegistry.register("probe.tab", function (p:Object):void { tabFired = tabFired + 1; });

    ActionRegistry.setKeymap([
        // The SAME key, two contexts: only the inner one may fire it.
        { context: "probe > modal", bindings: { "escape": "probe.esc" } },
        { context: "probe", bindings: { "ctrl-k": ["probe.open", { name: "palette" }] } }
    ]);
    check(ActionRegistry.keymapEntryCount() == 2,
        "the keymap holds " + ActionRegistry.keymapEntryCount() + " entries, not 2");
    check(ActionRegistry.bindingCount() == 2,
        "the keymap holds " + ActionRegistry.bindingCount() + " bindings, not 2");
    check(ActionRegistry.actionCount() == 4,
        "the registry holds " + ActionRegistry.actionCount() + " actions, not 4");

    // Control.action: Enter on a focused control runs the ACTION and not onClick.
    focus("btn");
    key(13);
    check(actFired == 1, "Enter on a control with an action did not dispatch it");
    check(btnClicks == 0, "Enter also ran onClick (" + btnClicks + " time(s))");

    // Inside the nested context: `probe > modal` matches (modal is innermost).
    focus("btn2");
    key(27);
    check(escFired == 1, "Escape inside `probe > modal` did not fire the action");

    // Outside it: only "probe" is active, so the same key must do nothing.
    focus("btn");
    key(27);
    check(escFired == 1, "Escape fired outside its context (" + escFired + " times)");

    // The payload reaches the handler.
    keyMod(75, true);
    check(opened == "palette", "the ctrl-k payload arrived as '" + opened + "' not 'palette'");

    // A keymap binding beats Tab, and beats the runtime's own ring move too.
    ActionRegistry.setKeymap([
        { context: "probe", bindings: { "tab": "probe.tab",
                                        "ctrl-k": ["probe.open", { name: "palette" }] } }
    ]);
    var before:int = app.tabMoves;
    focus("btn");
    key(9);
    check(tabFired == 1, "a keymap binding on Tab did not fire");
    check(app.tabMoves == before,
        "Tab moved the ring as well (" + app.tabMoves + " vs " + before + ")");
    check(keyOfFocused() == "btn", "focus left btn on a rebound Tab (now " + keyOfFocused() + ")");
    say("keys: action 1, esc 1, payload '" + opened + "', tab rebound");

    // Drop the whole keymap again: phase 5 measures the RING, and the binding above
    // deliberately shadows Tab -- leaving it in place would make every assertion
    // below measure nothing but the binding.
    ActionRegistry.clearKeymap();
    check(ActionRegistry.keymapEntryCount() == 0, "clearKeymap left "
        + ActionRegistry.keymapEntryCount() + " entries behind");

    // ==================== phase 5: tabIndex ordering =========================
    // The document order is [btn, btn2, btn3] and the explicit indices make the
    // ring [btn3, btn2, btn]. A ring that ignored tabIndex would be a ROTATION of
    // that, so the discriminating move is Tab from `btn`: ordered -> btn3,
    // document order -> btn2.
    var before2:int = app.tabMoves;
    // The mirroring is asserted FIRST: if the retained node never picked up
    // Control.tabIndex, the ring below measures the wrong thing for a reason that
    // has nothing to do with the ordering.
    var t1:UiNode = app.findByKey("btn");
    var t2:UiNode = app.findByKey("btn2");
    var t3:UiNode = app.findByKey("btn3");
    check(t1.tabIndex == -1 && t2.tabIndex == 1 && t3.tabIndex == 0,
        "mirrored tabIndex is " + t1.tabIndex + "/" + t2.tabIndex + "/" + t3.tabIndex
        + " not -1/1/0");
    check(t1.tabEnabled && t2.tabEnabled && t3.tabEnabled,
        "tabEnabled is " + t1.tabEnabled + "/" + t2.tabEnabled + "/" + t3.tabEnabled);

    focus("btn");
    key(9);
    var first:String = keyOfFocused();
    say("tab 1 -> " + first);
    key(9);
    var second:String = keyOfFocused();
    say("tab 2 -> " + second);
    key(9);
    var third:String = keyOfFocused();
    say("tab 3 -> " + third);
    check(first == "btn3", "Tab went to '" + first + "' not btn3 (tabIndex 0 is first)");
    check(second == "btn2", "the second Tab went to '" + second + "' not btn2 (tabIndex 1)");
    check(third == "btn", "the third Tab went to '" + third + "' not back to btn (no index)");
    check(app.tabMoves == before2 + 3, "three Tabs moved the ring " + (app.tabMoves - before2) + " times");
    say("tabIndex: ring " + first + " -> " + second + " -> " + third);

    // ==================== phase 6: the refusals ==============================
    refused();
    setTimeout(finish, 400);
}

// The guards run where the author would hit them: at setKeymap / factory time.
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

function refused():void
{
    threw("a keymap that is not an array", function ():void {
        var notArray:Object = "nope";
        ActionRegistry.setKeymap(notArray as Array);
    });
    threw("a keymap entry with an empty context", function ():void {
        ActionRegistry.setKeymap([{ context: "", bindings: { "a": "probe.act" } }]);
    });
    threw("an unknown modifier", function ():void {
        ActionRegistry.setKeymap([{ context: "probe", bindings: { "ctrll-s": "probe.act" } }]);
    });
    threw("an unknown key name", function ():void {
        ActionRegistry.setKeymap([{ context: "probe", bindings: { "f13": "probe.act" } }]);
    });
    threw("a dangling context operator", function ():void {
        ActionRegistry.setKeymap([{ context: "probe &&", bindings: { "a": "probe.act" } }]);
    });
    threw("a context with an unbalanced parenthesis", function ():void {
        ActionRegistry.setKeymap([{ context: "(probe", bindings: { "a": "probe.act" } }]);
    });
    threw("dispatching an action nobody registered", function ():void {
        ActionRegistry.dispatch("probe.missing");
    });
    threw("a menu with only one of atX/atY", function ():void {
        menu({ items: ["a"], atX: 10 });
    });
    threw("a splitPane with a null pane", function ():void {
        splitPane(box({ key: "x" }), null, null);
    });
    threw("a splitPane direction of 'horizontal'", function ():void {
        splitPane(box({ key: "x" }), box({ key: "y" }), { direction: "horizontal" });
    });
    threw("a splitPane ratio above 1", function ():void {
        splitPane(box({ key: "x" }), box({ key: "y" }), { ratio: 1.5 });
    });
    threw("a splitPane with a zero divider", function ():void {
        splitPane(box({ key: "x" }), box({ key: "y" }), { dividerSize: 0 });
    });

    // Pure predicate checks: the ancestor direction is the one mistake this
    // grammar invites, so it is pinned in both directions here.
    var an:ContextExpr = ContextExpr.parse("probe > modal");
    check(an.matches(["modal", "probe"]) == true, "'probe > modal' did not match inner-first [modal, probe]");
    check(an.matches(["probe", "modal"]) == false, "'probe > modal' matched the REVERSED list");
    var neg:ContextExpr = ContextExpr.parse("!modal");
    check(neg.matches(["probe"]) == true, "'!modal' did not match [probe]");
    check(neg.matches(["modal", "probe"]) == false, "'!modal' matched [modal, probe]");
    var kv:ContextExpr = ContextExpr.parse("os == macos");
    check(kv.matches(["os=macos"]) == true, "'os == macos' did not match the pair context");
    check(kv.matches(["os=linux"]) == false, "'os == macos' matched os=linux");
    var orx:ContextExpr = ContextExpr.parse("a || b");
    check(orx.matches(["b"]) == true, "'a || b' did not match [b]");
    var andx:ContextExpr = ContextExpr.parse("a && b");
    check(andx.matches(["a"]) == false, "'a && b' matched [a] alone");

    // The modifier rule: an unbound modifier must NOT be held. The press below holds
    // NO modifier other than ctrl, so SHIFT is the only term that can reject it -- an
    // earlier vector also held meta, which made the check pass even with the shift
    // comparison deleted (caught by the mutation run, M10).
    var ks:KeyStroke = KeyStroke.parse("ctrl-shift-s");
    check(ks.code == 83 && ks.ctrl && ks.shift && !ks.alt && !ks.meta,
        "ctrl-shift-s parsed to code " + ks.code);
    check(ks.matches(83, true, false, false, false) == false,
        "ctrl-shift-s matched a press without shift");
    check(ks.matches(83, true, false, true, false) == true,
        "ctrl-shift-s did not match its own press");
}

function finish():void
{
    var bd:BitmapData = frame();
    var names:Array = ["root", "rrow", "dbl", "sp", "sp:a", "sp:div", "sp:b", "wiz",
                       "sp2", "sp2:a", "sp2:div", "sp2:b",
                       "cm", "cm:i0", "cm:i1", "cm:i2"];
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
    // down and blue (both happened while the inputs probe was being written).
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
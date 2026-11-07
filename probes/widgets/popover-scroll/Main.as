// probes/widgets/popover-scroll/Main.as -- a POPOVER or MENU anchored to a control
// inside a scrolled viewport must hang under the control the reader SEES.
//
// Output prefix MUST equal the directory name (`popover-scroll`).
//
// THE DEFECT. A scroll viewport slides its content by `backing.scrollRect`
// (ScrollViewWidget's header), so `absX/absY` stay at their LAYOUT values: the pane
// scrolls, the numbers do not. The floating layer is solved against the WINDOW, so a
// panel placed at `anchor.absY` sits at the anchor's UNSCROLLED height -- 40px of
// scroll is 40px between the trigger and the panel that is supposed to be flush under
// it. `UiNode.visualX/visualY` are the published "layout minus every ancestor's
// slide"; select was taught to use them (probes/widgets/select-scroll), popover and
// menu were not, and they are the two surfaces the docs app anchors inside its
// scrolling reading pane.
//
// WHAT IS PINNED HERE
//   * offset 0: the panel lands under the trigger (the control -- the fix must not
//     move the unscrolled case);
//   * offset 40: the SAME panel lands 40px higher, i.e. under the trigger the reader
//     is looking at, and the pixels say so in both directions (white where the panel
//     now is, the pane's own grey where it used to be);
//   * a `menu` inherits it: it reaches the same code through PopoverWidget.measure
//     (MenuWidget only overrides the POINT-anchored context-menu case);
//   * a SUBMENU -- the one floating surface whose parent is another floating surface
//     -- lands on its own row. That is a SECOND mechanism: the panel is solved after
//     the main tree, so an anchor that is itself a panel row is final by then. Measured
//     once on the frame it is created, a nested panel reads the row's PREVIOUS rect and
//     keeps it forever, because a scroll dirties no layout bit anywhere.
//
// HAND ARITHMETIC (window 320x300; root column, padding 10, background 0x111111;
// viewport 280x150 at (10,10), background 0xF5F5F5, no bars; children in order:
// spacer 280x40 0xDDDDDD, trigger 200x34 0x2563EB, spacer 280x200 0xCCCCCC)
//
//   contentH = 40 + 34 + 200 = 274, viewport 150  ->  maxOffsetY = 124
//   trigger abs = (10, 50, 200, 34)            50 = 10 + 40
//   POPOVER_PANEL: 1px border + 12px padding -> the panel's own box starts at
//     y = 50 + 34 + 8 = 92 (at offset 0) and x = 10 (clampX leaves it alone:
//     10 + 200 = 210 < 320 - 4).
//   the wheel turns the pane to offsetY 40 (2 notches of wheelStep 20, through
//     stage.dispatchWheel -- the real path, which raises no layout dirty bit),
//     so the trigger is DRAWN at y = 10 and the panel must start at
//     y = 10 + 34 + 8 = 52.
//   MENU_PANEL: 1px border + 4px padding, rows 26 tall; anchored the same way, so
//     its box starts at 52 too, and its first row is 57..83.
//   SUBMENU of a 120-wide menu at (10,52): rows at 15..125, row 1 is 83..109, and
//     the submenu opens to its RIGHT -- x = 125 + 4 = 129, y = 83. 129 + 120 = 249
//     fits the 320 window, so the overflow flip is not involved.
//
// Protocol (tools/probe.cjs): dir name == output prefix; write <OUT>.rects.txt,
// <OUT>.bmp, <OUT>.done (PASS | FAIL <reason>).
import asaot.ui.*;
import asaot.ui.style.StyleRefinement;
import flash.display.BitmapData;
import flash.display.Stage;
import flash.display.StageAlign;
import flash.display.StageScaleMode;
import flash.filesystem.File;
import flash.filesystem.FileMode;
import flash.filesystem.FileStream;
import flash.geom.Rectangle;
import flash.utils.ByteArray;
import flash.utils.setTimeout;

var W:int = 320;
var H:int = 300;
var OUT:String = "popover-scroll";

var checks:int = 0;
var failures:String = "";
var log:String = "";

// Author-owned model. `offsetY` is DECLARED, so writing it is a position REQUEST
// (ScrollViewNode header) -- the same path a "back to top" button uses.
var svOffset:Number = 0;
var popOpen:Boolean = false;
var mnuOpen:Boolean = false;
var subOpen:Boolean = false;
var subIndex:int = -1;

class PopoverScrollProbe extends View
{
    private static const ROOT:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", padding: 10, size: [320, 300], background: 0x111111
    });
    private static const SV:StyleRefinement = StyleRefinement.from({
        size: [280, 150], background: 0xF5F5F5
    });
    private static const SPACER_A:StyleRefinement = StyleRefinement.from({
        size: [280, 40], background: 0xDDDDDD
    });
    private static const TRIGGER:StyleRefinement = StyleRefinement.from({
        size: [200, 34], background: 0x2563EB
    });
    private static const SPACER_B:StyleRefinement = StyleRefinement.from({
        size: [280, 200], background: 0xCCCCCC
    });
    private static const BODY:StyleRefinement = StyleRefinement.from({
        text: { fontSize: 12, color: 0x374151 }
    });

    public function PopoverScrollProbe():void { super(); }

    override public function render():Node
    {
        return column({ key: "root", style: ROOT }, [
            // wheelStep 20 (a FACTORY option, not a style key): two notches are the
            // 40px of scroll every hand-computed expectation below is built on.
            scrollView({ key: "sv", style: SV, offsetY: svOffset, wheelStep: 20,
                         scrollbarX: "never", scrollbarY: "never" }, [
                box({ key: "spa", style: SPACER_A, ariaName: "" }),
                box({ key: "trg", style: TRIGGER, ariaName: "trigger" }),
                box({ key: "spb", style: SPACER_B, ariaName: "" })
            ])
        ]);
    }

    override public function renderOverlay():Node
    {
        var nodes:Array = [];
        if (popOpen)
        {
            nodes.push(popover({ key: "pop", open: true, anchorKey: "trg",
                                 placement: "bottom", offset: 8, width: 200,
                                 onClose: function ():void { popOpen = false;
                                     app.invalidate(Dirty.VALUE); } }, [
                text("Anchored under the trigger.", { key: "popBody", style: BODY, ariaName: "" })
            ]));
        }
        if (mnuOpen)
        {
            nodes.push(menu({ key: "mnu", open: true, anchorKey: "trg",
                              placement: "bottom", offset: 8, width: 170,
                              items: ["Rename", "Duplicate", "Delete"],
                              onSelect: function (i:int):void { },
                              onClose: function ():void { mnuOpen = false;
                                  app.invalidate(Dirty.VALUE); } }));
        }
        if (subOpen)
        {
            // 120 wide on purpose: the submenu inherits the width and opens to the
            // RIGHT, so the row's right edge (125) + 4 + 120 has to stay inside the
            // 320px window -- otherwise the overflow flip moves it and the arithmetic
            // below would be about the flip instead of about the parent origin.
            nodes.push(menu({ key: "mnu2", open: true, anchorKey: "trg",
                              placement: "bottom", offset: 8, width: 120,
                              items: ["Rename", { label: "Duplicate",
                                  submenu: ["As text", "As image"] }, "Delete"],
                              submenuIndex: subIndex,
                              onSelect: function (i:int):void { },
                              onClose: function ():void { subOpen = false;
                                  app.invalidate(Dirty.VALUE); } }));
        }
        if (nodes.length == 0) return null;
        return overlay(nodes);
    }
}

var view:PopoverScrollProbe = new PopoverScrollProbe();
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

setTimeout(settle, 900);
stage.showWindow(W, H, "probe popover-scroll");

function settle():void
{
    writeText(OUT + ".rects.txt",
        "root " + rectOf(app.findByKey("root")) + "\n"
        + "sv " + rectOf(app.findByKey("sv")) + "\n"
        + "trg " + rectOf(app.findByKey("trg")) + "\n");
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
    expect(sv.contentH == 274, "content height is " + sv.contentH + ", want 274");
    expect(sv.maxOffsetY == 124, "max offset is " + sv.maxOffsetY + ", want 124");
    expect(sv.offsetY == 0, "the pane did not start at the top (" + sv.offsetY + ")");
    expect(rectOf(app.findByKey("trg")) == "10,50,200,34",
        "the trigger is at " + rectOf(app.findByKey("trg")) + ", want 10,50,200,34");
    setTimeout(phaseOpenAt0, 200);
}

// ---- phase 2: open at offset 0 -- the control ----------------------------
function phaseOpenAt0():void
{
    stageMark("open at offset 0");
    popOpen = true;
    app.invalidate(Dirty.VALUE);
    setTimeout(phaseOpenAt0Check, 250);
}

function phaseOpenAt0Check():void
{
    var trg:UiNode = app.findByKey("trg");
    var pop:UiNode = app.findByKey("pop");
    expect(pop != null && pop.backing != null && pop.backing.visible,
        "the popover is not visible while open");
    // 50 + 34 + 8: no scroll, so the old formula and the new one agree.
    expect(pop.absY == 92,
        "the panel is at y " + pop.absY + " at offset 0, want 92 (trigger bottom 84 + 8)");
    expect(pop.absX == 10, "the panel is at x " + pop.absX + ", want 10");
    var shot:BitmapData = frameShot();
    log = log + "offset0/panel " + hex(rgbAt(shot, 60, 100))
        + " above " + hex(rgbAt(shot, 60, 88)) + "\n";
    expect(rgbAt(shot, 60, 100) == 0xFFFFFF,
        "the panel's top padding at (60,100) is " + hex(rgbAt(shot, 60, 100)) + ", want #ffffff");
    expect(rgbAt(shot, 60, 88) == 0xCCCCCC,
        "the pane above the panel at (60,88) is " + hex(rgbAt(shot, 60, 88)) + ", want #cccccc");
    setTimeout(phaseScroll, 200);
}

// ---- phase 3: scroll the pane 40 with the panel open --------------------
function phaseScroll():void
{
    stageMark("wheel the pane 40 with the panel open");
    // THE REAL PATH: Stage hit-tests the point and dispatches a bubbling
    // MOUSE_WHEEL; the viewport scrolls and calls markPaint. NO describe, NO layout
    // dirty bit anywhere -- which is exactly why an anchored panel needs the
    // viewport's slide epoch to be re-solved (UiApp.reflow).
    // delta -1 is "toward the end" (the runtime's own convention), 2 notches of
    // wheelStep 20 = the 40 these expectations are built on.
    // The point has to be over the PANE and NOT over the panel that is floating above
    // it: the stage hit-tests to the topmost painted region, and the panel (92..126)
    // would swallow the notch. 145 is pane, below the panel, over the grey spacer.
    stage.dispatchWheel(100, 145, -1);
    stage.dispatchWheel(100, 145, -1);
    setTimeout(phaseScrollCheck, 250);
}

function phaseScrollCheck():void
{
    var sv:UiNode = app.findByKey("sv");
    var trg:UiNode = app.findByKey("trg");
    var pop:UiNode = app.findByKey("pop");
    var sc:ScrollViewNode = ScrollViewNode(sv.desc);
    // The widget wrote the new offset into the description; the author model follows
    // it here so the describe in phase 4 does not scroll the pane back to the top.
    svOffset = sc.offsetY;
    expect(sc.offsetY == 40, "the pane is at offsetY " + sc.offsetY + ", want 40");
    expect(clipY("sv") == 40, "the clip is at y " + clipY("sv") + ", want 40");
    // Where the reader SEES the trigger: absY 50 - scroll 40 = 10.
    expect(trg.visualY() == 10, "the trigger is drawn at y " + trg.visualY() + ", want 10");
    // THE ASSERTION OF THIS PROBE.
    expect(pop.absY == 52,
        "the panel is at y " + pop.absY + " after scrolling 40, want 52 (10 + 34 + 8)");
    var shot:BitmapData = frameShot();
    log = log + "offset40/panel " + hex(rgbAt(shot, 60, 60))
        + " stale " + hex(rgbAt(shot, 60, 100)) + "\n";
    // The panel now starts at 52, so its top padding covers 52..64.
    expect(rgbAt(shot, 60, 60) == 0xFFFFFF,
        "the panel is not under the scrolled trigger: (60,60) is "
        + hex(rgbAt(shot, 60, 60)) + ", want #ffffff");
    // ... and 100 is past the panel's bottom (~94), where the stale panel used to be.
    expect(rgbAt(shot, 60, 100) == 0xCCCCCC,
        "the panel is still hanging at its unscrolled height: (60,100) is "
        + hex(rgbAt(shot, 60, 100)) + ", want #cccccc");
    setTimeout(phaseMenu, 200);
}

// ---- phase 4: the MENU takes the same path ------------------------------
function phaseMenu():void
{
    stageMark("a menu anchored to the same trigger, still at offset 40");
    popOpen = false;
    mnuOpen = true;
    app.invalidate(Dirty.VALUE);
    setTimeout(phaseMenuCheck, 250);
}

function phaseMenuCheck():void
{
    var mnu:UiNode = app.findByKey("mnu");
    expect(mnu != null, "the menu node is missing");
    // A menu reaches PopoverWidget.measure (MenuWidget only overrides the
    // point-anchored context menu), so it has to land at the same y.
    expect(mnu.absY == 52,
        "the menu is at y " + mnu.absY + " after scrolling 40, want 52");
    var shot:BitmapData = frameShot();
    log = log + "menu/row0 " + hex(rgbAt(shot, 60, 60))
        + " stale " + hex(rgbAt(shot, 60, 100)) + "\n";
    // MENU_PANEL: 1px border + 4px padding -> the first row is 57..83.
    expect(rgbAt(shot, 60, 60) == 0xFFFFFF,
        "the menu's first row is not at (60,60): " + hex(rgbAt(shot, 60, 60))
        + ", want #ffffff");
    // The menu is 88 tall (3 rows of 26 + 2*4 padding + 2*1 border): 52..140. Point 145
    // is below it now, and was INSIDE it while the panel hung at the unscrolled 92.
    expect(rgbAt(shot, 60, 145) == 0xCCCCCC,
        "the menu is still where the unscrolled trigger was: (60,145) is "
        + hex(rgbAt(shot, 60, 145)) + ", want #cccccc");
    setTimeout(phaseSubmenu, 200);
}

// ---- phase 5: a SUBMENU under a row of a menu that is itself in the pane ----
//
// A submenu is the one floating surface whose PARENT is not the overlay root at
// the origin: it is a child of the menu node. `PopoverWidget.measure` therefore
// converts the anchor's window coordinates into the parent's padding box, and the
// parent has to be read the same way the anchor is (visual, not layout) or the panel
// is off by exactly the parent's own slide.
//
// HAND ARITHMETIC at offsetY 40 (menu at y 52, x 10, width 120):
//   row box starts at 52 + 1 (border) + 4 (padding) = 57, rows are 26 tall
//   row 1 (the one that owns the submenu) is 83..109
//   submenu = "right" of that row: x = 15 + 110 + 4 = 129, y = 83
//   no flip: 15 + 110 + 4 + 120 = 249 <= 320
function phaseSubmenu():void
{
    stageMark("a submenu of a menu anchored in the scrolled pane");
    mnuOpen = false;
    subOpen = true;
    subIndex = 1;
    app.invalidate(Dirty.VALUE);
    setTimeout(phaseSubmenuCheck, 250);
}

function phaseSubmenuCheck():void
{
    var mnu:UiNode = app.findByKey("mnu2");
    var sub:UiNode = app.findByKey("mnu2:sub1");
    expect(mnu != null && mnu.absY == 52,
        "the submenu's parent menu is at y " + (mnu == null ? "MISSING" : mnu.absY)
        + ", want 52");
    expect(sub != null && sub.backing != null && sub.backing.visible,
        "the submenu is not visible while submenuIndex names it");
    if (sub != null)
    {
        expect(sub.absY == 83,
            "the submenu is at y " + sub.absY + ", want 83 (menu 52 + border 1 + padding"
            + " 4 + row 26); a parent read in LAYOUT coordinates lands it a slide away");
        expect(sub.absX == 129,
            "the submenu is at x " + sub.absX + ", want 129 (row left 15 + width 110"
            + " + offset 4)");
    }
    setTimeout(finish, 200);
}

function finish():void
{
    writeText(OUT + ".dbg.txt", log + "checks " + checks + "\n");
    writeText(OUT + ".done", failures == "" ? "PASS" : "FAIL " + failures);
}

// ---- helpers --------------------------------------------------------------

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
// probes/widgets/data/Main.as -- the probe for the DATA widget group
// (table / accordion / breadcrumb / pagination).
//
// Output prefix MUST equal the directory name (`data`), because tools/probe.cjs
// derives the expected file names from it.
//
// HAND-COMPUTED LAYOUT (nothing below is copied from the program's own output;
// the same numbers are written independently into expect.json):
//
//   window 350x350, root = column {padding:10, gap:10}, four explicit sizes:
//     tbl 320x104 @ (10,10)    rowHeight 26 => four rows of 26: header 10..36,
//                              body rows 36..62, 62..88, 88..114. Two columns of
//                              equal flex share => 160 each, so column 1 starts at
//                              x=170 and the vertical grid hairline is x=170.
//     acc 320x140 @ (10,124)
//     bc  320x20  @ (10,274)
//     pg  320x28  @ (10,304)
//
//   Sampled pixels (4px clear of every glyph):
//     (12,15)  header fill            #F3F4F6
//     (12,36)  hairline under header  #E5E7EB  (bottom edge of the header row)
//     (12,47)  row 0, unstriped       #FFFFFF  (the page behind the table is white)
//     (12,73)  row 1, SELECTED        #DBEAFE  (selection paints over the stripe)
//     (12,99)  row 2, unstriped       #FFFFFF
//     (170,99) vertical hairline      #E5E7EB  (at the column boundary)
//
// WHAT A BITMAP CANNOT SHOW, so it is asserted in-program:
//   * all four kinds registered with Widgets;
//   * a settled tree does not re-solve even though render() rebuilds every
//     descriptor (a per-pass style object must not look like a change);
//   * a table row click writes the binding AND the selection fill MOVES;
//   * an accordion header click opens that panel (p1 appears, p0 disappears) and
//     clicking the open header again reports -1 (single-open toggle);
//   * a crumb click navigates, a click on the CURRENT crumb does not;
//   * the page stepper: next advances the bound page, the number 6 jumps there,
//     the slot list CHANGES with the page (pg3 gone, ellipses at both ends), and
//     prev at page 1 reports nothing.
//
// Note on coordinates: every click is dispatched on the widget's own backing with
// LOCAL coordinates (the established probe idiom), computed from the live rects --
// a text-driven width is never guessed, and a hand-computed number is never used
// where the engine is the thing under test.
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

var W:int = 350;
var H:int = 350;
var OUT:String = 'data';

// The observable model: every bound widget reads from and writes to it.
class DataModel extends Observable
{
    public var row:int = 1;     // table selection (body row, 0-based)
    public var open:int = 0;    // accordion open section
    public var page:int = 3;    // pagination page (1-based)
}

class DataProbe extends View
{
    private static const ROOT:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", padding: 10, gap: 10, size: [350, 350],
        background: 0xFFFFFF, text: { fontSize: 12, color: 0x111827 }
    });
    private static const TBL_S:StyleRefinement = StyleRefinement.from({ size: [320, 104] });
    private static const ACC_S:StyleRefinement = StyleRefinement.from({ size: [320, 140], gap: 2 });
    private static const BC_S:StyleRefinement = StyleRefinement.from({ size: [320, 20] });
    private static const PG_S:StyleRefinement = StyleRefinement.from({ size: [320, 28] });
    private static const PANEL_S:StyleRefinement = StyleRefinement.from({
        size: [320, 40], background: 0xEAEAEA
    });

    public function DataProbe():void { super(); }

    // PURE DESCRIPTION, rebuilt on every dirty frame: the factories are what turn
    // `page` / `activeIndex` / `selectedIndex` into children, so a cached descriptor
    // would freeze the slot list at whatever it was on the first pass.
    override public function render():Node
    {
        return column({ key: "root", style: ROOT, ariaName: "data" }, [
            table(
                [{ key: "name", title: "Name" }, { key: "qty", title: "Qty" }],
                [{ name: "Widget", qty: 3 }, { name: "Gadget", qty: 12 },
                 { name: "Doohickey", qty: 7 }],
                { key: "tbl", style: TBL_S, rowHeight: 26, stripes: true, grid: true,
                  selectedIndex: bindTo(model, "row"),
                  onSelect: function (i:int):void { noteRow(i); } }),
            accordion(
                [{ title: "General", content: box({ key: "p0", style: PANEL_S }) },
                 { title: "Advanced", content: box({ key: "p1", style: PANEL_S }) }],
                { key: "acc", style: ACC_S, activeIndex: bindTo(model, "open"),
                  onToggle: function (i:int):void { noteOpen(i); } }),
            breadcrumb(["Library", "Data", "Raw"],
                { key: "bc", style: BC_S,
                  onNavigate: function (i:int):void { noteCrumb(i); } }),
            pagination(3, 20,
                { key: "pg", style: PG_S, windowSize: 7, page: bindTo(model, "page"),
                  onSelect: function (p:int):void { notePage(p); } })
        ]);
    }
}

var model:DataModel = new DataModel();

var rowCalls:int = 0;
var lastRow:int = -1;
var openCalls:int = 0;
var lastOpen:int = -2;
var crumbCalls:int = 0;
var lastCrumb:int = -1;
var pageCalls:int = 0;
var lastPage:int = -1;
var problems:String = "";
var solves0:int = 0;

var view:DataProbe = new DataProbe();
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

setTimeout(settle, 900);
stage.showWindow(W, H, "probe data");

// ---- callback sinks (module functions, like the media probe's noteScroll) ----
function noteRow(i:int):void
{
    lastRow = i;
    rowCalls = rowCalls + 1;
}

function noteOpen(i:int):void
{
    lastOpen = i;
    openCalls = openCalls + 1;
}

function noteCrumb(i:int):void
{
    lastCrumb = i;
    crumbCalls = crumbCalls + 1;
}

function notePage(p:int):void
{
    lastPage = p;
    pageCalls = pageCalls + 1;
}

// ---- assertion helpers ------------------------------------------------------
function note(msg:String):void
{
    problems = problems + msg + "; ";
}

function frame():BitmapData
{
    var b:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    b.draw(stage);
    return b;
}

function hexOf(v:uint):String
{
    var s:String = v.toString(16);
    while (s.length < 6) s = "0" + s;
    return s;
}

function want(b:BitmapData, x:Number, y:Number, rgb:uint, what:String):void
{
    var got:uint = b.getPixel32(int(x), int(y)) & 0xFFFFFF;
    if (got != rgb)
    {
        note(what + " at (" + int(x) + "," + int(y) + ") want #" + hexOf(rgb)
             + " got #" + hexOf(got));
    }
}

function node(k:String):UiNode
{
    return app.findByKey(k);
}

// A click on a widget's own backing, in that backing's LOCAL coordinates.
function clickLocal(n:UiNode, lx:Number, ly:Number):void
{
    n.backing.dispatchEvent(new MouseEvent(MouseEvent.CLICK, true, false, lx, ly));
}

// ---- stage 0: settle, publish the hand-computable rects, check structure ----
function settle():void
{
    var names:Array = ["root", "tbl", "hdr", "r0", "r1", "r2",
                       "h:0", "h:1", "r0c0", "r0c1", "r1c0", "r1c1", "r2c0", "r2c1",
                       "acc", "bc", "pg"];
    var lines:String = "";
    var missing:int = 0;
    for (var i:int = 0; i < names.length; i++)
    {
        var n:UiNode = app.findByKey(names[i]);
        if (n == null)
        {
            missing = missing + 1;
            lines = lines + names[i] + " MISSING\n";
            continue;
        }
        lines = lines + names[i] + " " + n.absX + "," + n.absY + "," + n.absW + "," + n.absH + "\n";
    }
    writeText(OUT + ".rects.txt", lines);
    writeBmp(OUT + ".bmp", frame());

    // (a) all four kinds registered -- a bitmap cannot show a registry miss.
    if (!Widgets.has("table")) note("Widgets.has('table') is false");
    if (!Widgets.has("accordion")) note("Widgets.has('accordion') is false");
    if (!Widgets.has("breadcrumb")) note("Widgets.has('breadcrumb') is false");
    if (!Widgets.has("pagination")) note("Widgets.has('pagination') is false");

    // (b) the accordion holds exactly the OPEN panel: section 0 is open (model.open).
    if (node("p0") == null) note("p0 (the open panel) is missing");
    if (node("p1") != null) note("p1 (a closed panel) is mounted");

    // (c) the trail is horizontal: three links, strictly increasing x, each later
    //     crumb strictly right of the previous one's right edge.
    var c0:UiNode = node("c0");
    var c1:UiNode = node("c1");
    var c2:UiNode = node("c2");
    if (c0 == null || c1 == null || c2 == null) note("a crumb is missing");
    else
    {
        if (!(c0.absX < c1.absX && c1.absX < c2.absX)) note("crumbs are not left-to-right");
        if (!(c0.absX + c0.absW <= c1.absX)) note("c0 overlaps c1");
        if (!(c1.absX + c1.absW <= c2.absX)) note("c1 overlaps c2");
        if (c2.absY != c0.absY) note("crumbs are not on one baseline (a column, not a row?)");
        if (node("s0") == null || node("s1") == null) note("a separator is missing");
        // The separator's BOX is its glyph plus its own padding. The engine's
        // boxSizing is border-box, so a text node that publishes its bare glyph
        // width (as this widget path once did) gets a box SMALLER than its content:
        // the "/" then overflows its box and glues itself to the next crumb. The
        // drawn field's textWidth is the very metric the measure pass published, so
        // this compares like with like; the +/-1 slack absorbs layout rounding.
        // sepRef pads 4+4 -- see breadcrumb.as.
        var sep:UiNode = node("s0");
        if (sep == null) note("s0 is missing");
        else if (sep.tf == null) note("the separator has no label field (nothing was measured)");
        else if (!(Math.abs(sep.absW - (sep.tf.textWidth + 8)) <= 1))
        {
            note("separator box " + sep.absW + " is not its text " + sep.tf.textWidth
                + " + padding 8 (an auto text node must include its insets)");
        }
    }

    // (d) the stepper rendered page 3 of 20 with a 7-slot window: the hand-derived
    //     slot list is [1,2,3,4,5,6,<ellipsis>,20] -- pg1..pg6, gap, pg20.
    var p:int = 1;
    for (p = 1; p <= 6; p++)
    {
        if (node("pg" + p) == null) note("pg" + p + " is missing (page 3 should show 1..6)");
    }
    if (node("pg7") != null) note("pg7 is mounted but page 3 should not show it");
    if (node("pg20") == null) note("pg20 (the last page) is missing");
    if (node("prev") == null || node("next") == null) note("a prev/next chip is missing");

    // (e) chips in a horizontal row, all inside the container.
    var pv:UiNode = node("prev");
    var nx:UiNode = node("next");
    if (pv != null && nx != null)
    {
        if (!(pv.absX < nx.absX)) note("the stepper is not laid out left-to-right (a column?)");
        if (nx.absX + nx.absW > pgOf().absX + pgOf().absW)
            note("the chips overflow the stepper's own width");
    }

    // (f) a settled tree does not re-solve even though render() rebuilt every
    //     descriptor (the per-pass style objects must compare equal).
    solves0 = app.layoutSolves;
    frame0 = app.enterFrameTicks;
    setTimeout(settle2, 400);
}

function pgOf():UiNode
{
    return app.findByKey("pg");
}

var frame0:int = 0;

function settle2():void
{
    if (app.layoutSolves != solves0)
        note("an idle tree re-solved: layoutSolves " + solves0 + " -> " + app.layoutSolves);
    if (app.enterFrameTicks <= frame0) note("no frames ticked while idle");
    setTimeout(restCheck, 10);
}

// ---- stage 1: the colours at rest, then click table row 2 -------------------
function restCheck():void
{
    var b:BitmapData = frame();
    var tbl:UiNode = node("tbl");
    var r0:UiNode = node("r0");
    var r1:UiNode = node("r1");
    var r2:UiNode = node("r2");

    // Colours sampled from LIVE rects (the hand-computed copies of the same
    // numbers are in expect.json; these catch a drift of the widget's own paint).
    if (tbl != null && r1 != null && r2 != null)
    {
        want(b, tbl.absX + 2, tbl.absY + 5, 0xF3F4F6, "header fill");
        want(b, tbl.absX + 2, r0.absY + 11, 0xFFFFFF, "row 0 background");
        want(b, tbl.absX + 2, r1.absY + 11, 0xDBEAFE, "row 1 selection");
        want(b, tbl.absX + 2, r2.absY + 11, 0xFFFFFF, "row 2 background");
        // Row 1 is odd: with the selection moved away its stripe must show. (Checked
        // after the click below, where row 1 is no longer selected.)
    }

    // The accordion's open header is filled with OPEN_BG, a closed one with the
    // header background; the panel behind is the author's own colour.
    var acc:UiNode = node("acc");
    var h0:UiNode = node("acc:h0");
    var h1:UiNode = node("acc:h1");
    var p0:UiNode = node("p0");
    if (acc != null && h0 != null && h1 != null)
    {
        want(b, acc.absX + 3, h0.absY + int(h0.absH / 2), 0xDBEAFE, "open header fill");
        want(b, acc.absX + 3, h1.absY + int(h1.absH / 2), 0xF3F4F6, "closed header fill");
        if (!(h0.absY < h1.absY)) note("the accordion headers are not stacked top-down");
    }
    if (p0 != null && h0 != null)
    {
        want(b, p0.absX + 3, p0.absY + 20, 0xEAEAEA, "open panel fill");
        if (!(p0.absY >= h0.absY + h0.absH)) note("the open panel overlaps its header");
    }

    // Click body row 2 (local y = its own offset inside the table).
    if (tbl != null && r2 != null)
    {
        clickLocal(tbl, 30, (r2.absY - tbl.absY) + 13);
    }
    setTimeout(afterRow, 300);
}

// ---- stage 2: the row click wrote back and the selection moved -------------
function afterRow():void
{
    if (rowCalls != 1) note("onSelect fired " + rowCalls + " times, want 1");
    if (lastRow != 2) note("onSelect reported " + lastRow + ", want 2");
    if (model.row != 2) note("model.row is " + model.row + ", want 2 (the binding write)");

    var b:BitmapData = frame();
    var tbl:UiNode = node("tbl");
    var r1:UiNode = node("r1");
    var r2:UiNode = node("r2");
    if (tbl != null && r1 != null && r2 != null)
    {
        want(b, tbl.absX + 2, r2.absY + 11, 0xDBEAFE, "row 2 after the click (now selected)");
        want(b, tbl.absX + 2, r1.absY + 11, 0xF9FAFB, "row 1 after the click (stripe back)");
        want(b, tbl.absX + 2, tbl.absY + 5, 0xF3F4F6, "header untouched by the selection");
    }

    // Click the second header: section 1 opens.
    var acc:UiNode = node("acc");
    var h1:UiNode = node("acc:h1");
    if (acc != null && h1 != null) clickLocal(acc, 30, (h1.absY - acc.absY) + int(h1.absH / 2));
    setTimeout(afterOpen, 300);
}

// ---- stage 3: section 1 is open, section 0's panel is gone ----------------
function afterOpen():void
{
    if (openCalls != 1) note("onToggle fired " + openCalls + " times, want 1");
    if (lastOpen != 1) note("onToggle reported " + lastOpen + ", want 1");
    if (model.open != 1) note("model.open is " + model.open + ", want 1");
    if (node("p1") == null) note("the newly opened panel p1 did not mount");
    if (node("p0") != null) note("the collapsed panel p0 is still mounted (it must not hold space)");

    var b:BitmapData = frame();
    var acc:UiNode = node("acc");
    var h0:UiNode = node("acc:h0");
    var h1:UiNode = node("acc:h1");
    var p1:UiNode = node("p1");
    if (acc != null && h0 != null && h1 != null)
    {
        want(b, acc.absX + 3, h1.absY + int(h1.absH / 2), 0xDBEAFE, "section 1 header now open");
        want(b, acc.absX + 3, h0.absY + int(h0.absH / 2), 0xF3F4F6, "section 0 header now closed");
        if (p1 != null && !(p1.absY >= h1.absY + h1.absH)) note("p1 overlaps its header");
    }
    // Close it again: a second click on the OPEN header toggles to -1.
    if (acc != null && h1 != null) clickLocal(acc, 30, (h1.absY - acc.absY) + int(h1.absH / 2));
    setTimeout(afterClose, 300);
}

function afterClose():void
{
    if (openCalls != 2) note("onToggle fired " + openCalls + " times, want 2");
    if (lastOpen != -1) note("a click on the open header reported " + lastOpen + ", want -1");
    if (model.open != -1) note("model.open is " + model.open + ", want -1 (all collapsed)");
    if (node("p0") != null || node("p1") != null) note("a panel is mounted with every section collapsed");

    // Re-open section 0 so the trailing state is the documented one.
    var acc:UiNode = node("acc");
    var h0:UiNode = node("acc:h0");
    if (acc != null && h0 != null) clickLocal(acc, 30, (h0.absY - acc.absY) + int(h0.absH / 2));
    setTimeout(afterReopen, 300);
}

function afterReopen():void
{
    if (node("p0") == null) note("p0 did not come back after re-opening section 0");

    // Click crumb 1 ("Data"): navigates to index 1.
    var bc:UiNode = node("bc");
    var c1:UiNode = node("c1");
    if (bc != null && c1 != null) clickLocal(bc, (c1.absX - bc.absX) + 2, 10);
    setTimeout(afterCrumb, 300);
}

// ---- stage 4: crumb navigation, and the CURRENT crumb is a dead end --------
function afterCrumb():void
{
    if (crumbCalls != 1) note("onNavigate fired " + crumbCalls + " times, want 1");
    if (lastCrumb != 1) note("onNavigate reported " + lastCrumb + ", want 1");

    // The current crumb is the LAST one (currentIndex left at -1): clicking it must
    // be consumed silently -- no callback, no binding write.
    var bc:UiNode = node("bc");
    var c2:UiNode = node("c2");
    if (bc != null && c2 != null) clickLocal(bc, (c2.absX - bc.absX) + 2, 10);
    setTimeout(afterCur, 300);
}

function afterCur():void
{
    if (crumbCalls != 1) note("a click on the CURRENT crumb navigated (" + crumbCalls + " calls)");

    // A click on a separator must navigate nowhere either.
    var bc:UiNode = node("bc");
    var s0:UiNode = node("s0");
    if (bc != null && s0 != null) clickLocal(bc, (s0.absX - bc.absX) + 1, 10);
    setTimeout(afterSep, 300);
}

function afterSep():void
{
    if (crumbCalls != 1) note("a click on a separator navigated (" + crumbCalls + " calls)");

    // Stepper: next takes page 3 -> 4.
    var pg:UiNode = node("pg");
    var nx:UiNode = node("next");
    if (pg != null && nx != null) clickLocal(pg, (nx.absX - pg.absX) + 2, 14);
    setTimeout(afterNext, 300);
}

// ---- stage 5: next, then jump to 6 (the slot list must change) -------------
function afterNext():void
{
    if (pageCalls != 1) note("onSelect fired " + pageCalls + " times, want 1");
    if (lastPage != 4) note("next from page 3 reported " + lastPage + ", want 4");
    if (model.page != 4) note("model.page is " + model.page + ", want 4");

    var pg:UiNode = node("pg");
    var p6:UiNode = node("pg6");
    if (pg != null && p6 != null) clickLocal(pg, (p6.absX - pg.absX) + 2, 14);
    setTimeout(afterJump, 300);
}

function afterJump():void
{
    if (pageCalls != 2) note("onSelect fired " + pageCalls + " times, want 2");
    if (lastPage != 6) note("clicking the number 6 reported " + lastPage + ", want 6");
    if (model.page != 6) note("model.page is " + model.page + ", want 6");

    // pageList(6, 20, 7) = [1, -1, 4,5,6,7,8, -1, 20]: page 3 is gone, the window
    // slid to 4..8, and BOTH ends now have an ellipsis.
    if (node("pg3") != null) note("pg3 is still mounted at page 6");
    if (node("pg5") == null) note("pg5 is missing at page 6");
    if (node("pg8") == null) note("pg8 is missing at page 6");
    if (node("pg9") != null) note("pg9 is mounted but the window should end at 8");
    if (node("gap1") == null) note("the leading ellipsis (gap1) is missing at page 6");
    if (node("gap7") == null) note("the trailing ellipsis (gap7) is missing at page 6");

    var b:BitmapData = frame();
    var pg:UiNode = node("pg");
    var p6:UiNode = node("pg6");
    var p5:UiNode = node("pg5");
    if (pg != null && p6 != null && p5 != null)
    {
        want(b, pg.absX + int((p6.absX - pg.absX)) + 3, pg.absY + 14, 0xDBEAFE, "the current page chip");
        want(b, pg.absX + int((p5.absX - pg.absX)) + 3, pg.absY + 14, 0xE5E7EB, "an inactive page chip");
    }

    // prev from 6 -> 5.
    var nx:UiNode = node("next");
    var pv:UiNode = node("prev");
    if (pg != null && pv != null) clickLocal(pg, (pv.absX - pg.absX) + 2, 14);
    setTimeout(afterPrev, 300);
}

function afterPrev():void
{
    if (pageCalls != 3) note("onSelect fired " + pageCalls + " times, want 3");
    if (lastPage != 5) note("prev from page 6 reported " + lastPage + ", want 5");

    // Now drive the model to page 1 and prove the low end clamps silently.
    model.page = 1;
    app.invalidate(Dirty.VALUE);
    setTimeout(afterToFirst, 300);
}

function afterToFirst():void
{
    var pg:UiNode = node("pg");
    var pv:UiNode = node("prev");
    if (node("pg1") == null) note("pg1 is missing at page 1");
    if (pg != null && pv != null) clickLocal(pg, (pv.absX - pg.absX) + 2, 14);
    setTimeout(afterClamp, 300);
}

function afterClamp():void
{
    if (pageCalls != 3) note("prev at page 1 reported a page (" + pageCalls + " calls, want 3)");
    if (model.page != 1) note("prev at page 1 moved the model to " + model.page);

    writeText(OUT + ".done", problems == "" ? "PASS" : ("FAIL " + problems));
}

// ---- file writers (copied from probes/widgets/media/Main.as) ----------------
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

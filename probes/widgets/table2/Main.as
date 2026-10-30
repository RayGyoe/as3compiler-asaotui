// probes/widgets/table2/Main.as -- the three table opt-ins: sorting, column
// resize and row virtualisation.
//
// Output prefix MUST equal the directory name (`table2`).
//
// WHY A SECOND TABLE PROBE. `probes/widgets/data` already pins the table's static
// half (geometry, stripes, grid, a click selecting a row). This one exists for the
// half that can only be seen by INTERACTING, and each of the three has a way of
// looking correct while doing nothing:
//
//   * SORT: the arrow can be painted from the model while the rows never move (the
//     factory could sort nothing and every pixel assertion in `data` would still
//     pass). So the assertions here are the CELL TEXTS after each click, and the
//     data is chosen so numeric and alphabetical order DIFFER (qty 1 / 2 / 10:
//     "10" < "2" as text), which is also the answer to "why is my column sorted
//     wrongly".
//   * RESIZE: a preview line that draws and a commit that is never called look the
//     same on screen for one frame; and the click the window glue sends after the
//     release must NOT also sort the column it resized. Both are pinned.
//   * VIRTUAL: mounting 11 of 200 rows is invisible if you only look at the picture
//     (the other 189 are outside the clip anyway) -- the children COUNT is the
//     assertion, plus the absolute row index a click reports.
//
// Coordinates are hand-computed (window 320x340, root padding 10, gap 8):
//   tbl  (10,10,280,80)    header (10,10,280,20), rows at y=30/50/70, h=20
//                          column 0 is 100 wide -> boundary hairline at x=110
//   vt   (10,98,280,220)   header (10,98,280,20), body 10 rows of 20 = y 118..318
//                          fit = ceil(200/20) = 10 body rows, +1 partial mounted
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

var W:int = 320;
var H:int = 340;
var OUT:String = "table2";
// The sort arrows, as ESCAPES: this dialect indexes strings by BYTE, so a literal
// "\u25B2" in the source is fine but a `charAt` on it would not be. `indexOf` on the
// whole escape is the only safe test (STATUS.md 3.15).
var UP:String = "\u25B2";
var DOWN:String = "\u25BC";

var checks:int = 0;
var failures:String = "";

// The model. Every opt-in writes here and the PROBE re-renders, which is exactly
// what the contract asks of an author (the widget never reorders or resizes itself).
var st:Object = {
    sortCol: -1, sortDesc: false,
    w0: 100,                    // column 0's width, in the author's model
    off: 0,                     // the virtual table's row-granular offset
    sortCalls: 0, sortColArg: -99, sortDescArg: false,
    resizeCalls: 0, rzCol: -99, rzW: -99,
    rowSel: -99
};

// 200 rows, one column, so the mounted window is countable at a glance.
function bigRows():Array
{
    var out:Array = new Array();
    for (var i:int = 0; i < 200; i++) out.push({ i: i });
    return out;
}

class Table2Probe extends View
{
    private static const ROOT:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", padding: 10, gap: 8, size: [320, 340],
        background: 0xFFFFFF, text: { fontSize: 12, color: 0x111827 }
    });

    public function Table2Probe():void { super(); }

    override public function render():Node
    {
        // Column widths are REBUILT per pass from the model, because that is what the
        // widget's onColumnResize asks the author to do.
        var colsA:Array = [
            { key: "n", title: "Name", width: st.w0 },
            { key: "q", title: "Qty" }
        ];
        var rowsA:Array = [
            { n: "b", q: 2 },
            { n: "a", q: 10 },
            { n: "c", q: 1 }
        ];
        return column({ key: "root", style: ROOT, ariaName: "table options probe" }, [
            table(colsA, rowsA, {
                key: "tbl", size: [280, 80],
                rowHeight: 20, stripes: true,
                sortColumn: st.sortCol, sortDescending: st.sortDesc,
                onSort: function (col:int, desc:Boolean):void { noteSort(col, desc); },
                resizable: true,
                onColumnResize: function (col:int, w:Number):void { noteResize(col, w); }
            }),
            table([{ key: "i", title: "#" }], bigRows(), {
                key: "vt", size: [280, 220],
                rowHeight: 20,
                virtual: true, offsetY: st.off,
                onScroll: function (y:Number):void { noteScroll(y); },
                onSelect: function (i:int):void { st.rowSel = i; }
            })
        ]);
    }
}

// The author's half of each contract: write the model, ask for a new pass.
function noteSort(col:int, desc:Boolean):void
{
    st.sortCalls = st.sortCalls + 1;
    st.sortColArg = col;
    st.sortDescArg = desc;
    st.sortCol = col;
    st.sortDesc = desc;
    // Invalidate ONLY: this runs inside the click dispatch, and a reflow here would
    // rebuild the very node the event is still bubbling through.
    app.invalidate(Dirty.STRUCTURE);
}

function noteResize(col:int, w:Number):void
{
    st.resizeCalls = st.resizeCalls + 1;
    st.rzCol = col;
    st.rzW = w;
    st.w0 = w;              // column 0 is the one being dragged
    app.invalidate(Dirty.STRUCTURE);
}

function noteScroll(y:Number):void
{
    st.off = y;
    app.invalidate(Dirty.STRUCTURE);
}

var view:Table2Probe = new Table2Probe();
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

// DECLARED BEFORE showWindow: a file-scope initializer is emitted in SOURCE ORDER
// between the top-level statements, and showWindow blocks for the life of the window.
setTimeout(settle, 900);
stage.showWindow(W, H, "probe table2");

// ---- phase 0: the resting state -------------------------------------------
function settle():void
{
    stageMark("settle");
    var tbl:UiNode = node("tbl");
    var vt:UiNode = node("vt");
    if (tbl == null || vt == null)
    {
        writeText(OUT + ".done", "FAIL a table is missing");
        return;
    }
    var lines:String = "";
    // Only the two CONTAINERS and the root are looked up by key: both tables use the
    // factory's row keys (r0, r1, ...), and keys only have to be unique among
    // SIBLINGS, so an app-level lookup for "r0" would answer with whichever table it
    // found first. Cells are read through their container instead (see cell()).
    var names:Array = ["root", "tbl", "vt"];
    for (var i:int = 0; i < names.length; i++)
    {
        var n:UiNode = node(String(names[i]));
        if (n != null) lines = lines + names[i] + " " + rectOf(n) + "\n";
    }
    stageMark("settle: rects");
    writeText(OUT + ".rects.txt", lines);
    stageMark("settle: bmp");
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    writeBmp(OUT + ".bmp", bd);
    stageMark("settle: checks");

    // 1 header + 3 body rows.
    expect(tbl.children.length == 4, "the plain table mounted " + tbl.children.length + " rows, want 4");
    // 1 header + fit(10) + 1 partial = 12; 189 of the 200 rows must NOT exist.
    expect(vt.children.length == 12, "the virtual table mounted " + vt.children.length + " rows, want 12 (1 header + 10 + 1 partial)");
    expect(keyOf(vt, 1) == "r0", "the virtual table starts at row " + keyOf(vt, 1) + ", want r0");
    expect(cell("tbl", 1, 0) == "b", "row 0 name is " + cell("tbl", 1, 0) + ", want b (the model's own order)");
    expect(cell("tbl", 1, 1) == "2", "row 0 qty is " + cell("tbl", 1, 1) + ", want 2");
    setTimeout(phaseResize, 250);
}

// ---- phase 1: drag the boundary between column 0 and column 1 --------------
//
// EVERY PHASE IS "ACT, THEN WAIT, THEN ASSERT". The widget reports and the AUTHOR
// re-renders, so the new order and the new column width only exist after the next
// frame's reflow -- asserting in the same tick would read the old tree and then blame
// the widget for it (this probe's first run failed eight assertions that way).
function phaseResize():void
{
    stageMark("resize drag");
    // The boundary hairline is at stage x=110 (10 + 100). Press IN the header (y=20)
    // within RESIZE_GRAB of it, drag 40px right, release.
    send(110, 20, "mouseDown");
    send(130, 20, "mouseMove");    // two moves, so "commits once per gesture" is testable
    send(150, 20, "mouseMove");
    send(150, 20, "mouseUp");
    setTimeout(afterResize, 250);
}

function afterResize():void
{
    // The three callback facts hold in the release handler itself, but they are read
    // here anyway: one wait for both halves keeps the chain readable.
    expect(st.resizeCalls == 1, "onColumnResize fired " + st.resizeCalls + " times, want 1");
    expect(st.rzCol == 0, "onColumnResize reported column " + st.rzCol + ", want 0");
    expect(st.rzW == 140, "onColumnResize reported width " + st.rzW + ", want 140 (100 + the 40px drag)");
    var r0:UiNode = node("tbl").children[1];
    var c1:UiNode = r0 == null ? null : r0.children[1];
    expect(c1 != null && c1.absX == 150, "column 1 now starts at " + (c1 == null ? "MISSING" : String(c1.absX)) + ", want 150");
    expect(r0 != null && r0.absW == 280, "the row lost its width to the resize: " + (r0 == null ? "MISSING" : String(r0.absW)));

    // The window glue sends a CLICK after every release. On a resize that click lands
    // on the divider we just committed, and it must NOT also sort the column.
    send(150, 20, "click");
    setTimeout(afterResizeClick, 250);
}

function afterResizeClick():void
{
    expect(st.sortCalls == 0, "the click after a resize sorted the column (" + st.sortCalls + " onSort call(s))");
    stageMark("sort ascending");
    send(200, 20, "click");            // inside header column 1 (x 150..290)
    setTimeout(afterAsc, 250);
}

// ---- phase 2: click the Qty header -> ascending ----------------------------
function afterAsc():void
{
    expect(st.sortCalls == 1, "onSort fired " + st.sortCalls + " times, want 1");
    expect(st.sortColArg == 1, "onSort reported column " + st.sortColArg + ", want 1");
    expect(st.sortDescArg == false, "the first click on a column asked for descending");
    // qty ascending is 1, 2, 10 -- NUMERIC order. As text it would be 1, 10, 2, so the
    // first and last names below are what tells the two apart.
    expect(cell("tbl", 1, 0) == "c", "ascending: row 0 is " + cell("tbl", 1, 0) + ", want c (qty 1)");
    expect(cell("tbl", 2, 0) == "b", "ascending: row 1 is " + cell("tbl", 2, 0) + ", want b (qty 2)");
    expect(cell("tbl", 3, 0) == "a", "ascending: row 2 is " + cell("tbl", 3, 0) + ", want a (qty 10) -- text order would put 10 first");
    expect(head("tbl", 1).indexOf(UP) >= 0, "the sorted header has no ascending arrow: " + head("tbl", 1));
    stageMark("sort descending");
    send(200, 20, "click");
    setTimeout(afterDesc, 250);
}

// ---- phase 3: click it again -> descending --------------------------------
function afterDesc():void
{
    expect(st.sortCalls == 2, "onSort fired " + st.sortCalls + " times, want 2");
    expect(st.sortDescArg == true, "the second click on the same column asked for ascending");
    expect(cell("tbl", 1, 0) == "a", "descending: row 0 is " + cell("tbl", 1, 0) + ", want a (qty 10)");
    expect(cell("tbl", 3, 0) == "c", "descending: row 2 is " + cell("tbl", 3, 0) + ", want c (qty 1)");
    expect(head("tbl", 1).indexOf(DOWN) >= 0, "the descending header has no down arrow: " + head("tbl", 1));
    stageMark("sort cleared");
    send(200, 20, "click");
    setTimeout(afterClear, 250);
}

// ---- phase 4: third click -> unsorted (the model's own order) --------------
function afterClear():void
{
    expect(st.sortCalls == 3, "onSort fired " + st.sortCalls + " times, want 3");
    expect(st.sortColArg == -1, "the third click reported column " + st.sortColArg + ", want -1 (unsorted)");
    expect(cell("tbl", 1, 0) == "b", "cleared: row 0 is " + cell("tbl", 1, 0) + ", want b (the model's order)");
    expect(head("tbl", 1).indexOf(UP) < 0 && head("tbl", 1).indexOf(DOWN) < 0,
        "an arrow survived the clear: " + head("tbl", 1));
    stageMark("virtual scroll");
    // One notch = WHEEL_STEP (3) rows = 60px. Positive delta scrolls toward the START,
    // so a NEGATIVE delta is "down".
    sendWheel(200, 200, -120);
    setTimeout(afterScroll, 250);
}

// ---- phase 5: the virtual table scrolls by a row window --------------------
function afterScroll():void
{
    expect(st.off == 60, "onScroll reported " + st.off + ", want 60 (3 rows of 20)");
    var vt:UiNode = node("vt");
    expect(keyOf(vt, 1) == "r3", "after the scroll the first mounted row is " + keyOf(vt, 1) + ", want r3");
    expect(vt.children.length == 12, "after the scroll the window is " + vt.children.length + " rows, want 12");
    expect(cell("vt", 1, 0) == "3", "the first visible row shows " + cell("vt", 1, 0) + ", want 3 (model row 3)");
    stageMark("absolute row index");
    // Body row 0 of the window is model row 3, and it sits at stage y=118..138.
    send(60, 128, "click");
    setTimeout(afterAbsolute, 250);
}

// ---- phase 6: a click in a scrolled table reports the ABSOLUTE row --------
function afterAbsolute():void
{
    expect(st.rowSel == 3, "a click on the first visible row reported " + st.rowSel + ", want 3 (absolute, not window-relative)");
    stageMark("offset clamp");
    // 99999 is past the last page: max first row = 200 - 10 = 190, i.e. y = 3800.
    st.off = 99999;
    app.invalidate(Dirty.STRUCTURE);
    app.reflow();
    setTimeout(afterClamp, 250);
}

// ---- phase 7: the factory clamps an offset past the end -------------------
function afterClamp():void
{
    var vt:UiNode = node("vt");
    expect(keyOf(vt, 1) == "r190", "a clamped window starts at " + keyOf(vt, 1) + ", want r190");
    expect(keyOf(vt, vt.children.length - 1) == "r199", "a clamped window ends at " + keyOf(vt, vt.children.length - 1) + ", want r199");
    // 1 header + rows 190..199: the +1 partial row must NOT be mounted past the end.
    expect(vt.children.length == 11, "the clamped window mounted " + vt.children.length + " rows, want 11 (1 header + 10)");
    setTimeout(finish, 250);
}

function finish():void
{
    writeText(OUT + ".done", failures == "" ? "PASS" : "FAIL " + failures);
}

// ---- helpers --------------------------------------------------------------

function node(k:String):UiNode { return app.findByKey(k); }

// The reconciler's key of child `i`, so a "which row is mounted" assertion needs no
// access to anything the widget keeps private.
function keyOf(n:UiNode, i:int):String
{
    if (n == null || i < 0 || i >= n.children.length) return "MISSING";
    var k:String = n.children[i].key;
    return k == null ? "NULL" : k;
}

// A cell read THROUGH its container: child 0 is the header row, so a body row's
// number is the child index. `findByKey` cannot be used for cells here -- both tables
// use the factory's row keys (r0, r1, ...) and keys only have to be unique among
// siblings, so an app-level lookup would answer with whichever table came first.
function cell(tblKey:String, child:int, col:int):String
{
    var t:UiNode = node(tblKey);
    if (t == null || child < 0 || child >= t.children.length) return "NO-ROW";
    var r:UiNode = t.children[child];
    if (col < 0 || col >= r.children.length) return "NO-CELL";
    var c:UiNode = r.children[col];
    if (c.tf == null) return "NO-TEXT";
    var s:String = c.tf.text;
    return s == null ? "NULL" : s;
}

function head(tblKey:String, col:int):String
{
    return cell(tblKey, 0, col);
}

// One REAL pointer event at stage coordinates: the runtime hit-tests, then the event
// bubbles through the table's backing, which is where the widget listens.
function send(x:Number, y:Number, type:String):void
{
    try
    {
        stage.dispatchMouse(x, y, type);
    }
    catch (err:Error)
    {
        failures = failures + type + " at (" + x + "," + y + ") threw " + err.name + ": " + err.message + "; ";
    }
}

function sendWheel(x:Number, y:Number, delta:Number):void
{
    try
    {
        stage.dispatchWheel(x, y, delta);
    }
    catch (err:Error)
    {
        failures = failures + "wheel at (" + x + "," + y + ") threw " + err.name + ": " + err.message + "; ";
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

// The stage survives in `<name>.step`, never in `.done`: tools/probe.cjs only prints
// the breadcrumb when the verdict never arrived.
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

// 32-bit bottom-up BMP written by hand (this runtime has BitmapData but no PNG encoder).
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
    fs.writeBytes(ba, 0, 0);
    fs.close();
}
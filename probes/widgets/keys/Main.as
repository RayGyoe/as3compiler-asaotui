// probes/widgets/keys/Main.as -- the probe for KEYBOARD navigation in the three
// kinds that were pointer-only until 2026-10-26: `list`, `table` and `tabs`.
//
// Output prefix MUST equal the directory name (`keys`), because tools/probe.cjs
// derives the expected file names from it.
//
// WHAT IS BEING MEASURED, and why each half is here:
//   * the MODEL side -- which index the author's Binding ends up holding after a
//     key, plus the `onSelect`/`onChange` callback. A bitmap cannot show either.
//   * the PIXEL side -- the selection fill of each kind, sampled at a point clear
//     of every glyph. This is what proves the keyboard moved the PICTURE and not
//     just a number: the final frame is the keyboard-achieved state, so expect.json
//     pins the state the KEYS produced.
//   * the BOUNDARIES that make a listbox a listbox and a tab strip a tab strip:
//     arrows are CLAMPED in list/table (a sequence has ends) and WRAP in tabs (a
//     strip is a ring). Both directions are asserted, because either one alone
//     passes with the other behaviour.
//   * the VIRTUAL table's reveal: an unmounted row cannot be highlighted, so a key
//     that leaves the window must also scroll it. This is the only interaction
//     between the keyboard and the window, and it is invisible in the model.
//   * TWO KEYS IN ONE FRAME. The keys read the CURRENT index from the Binding, not
//     from what payload last applied, precisely so a held arrow steps twice. The
//     burst assertions below are what keep that read honest.
//
// HAND ARITHMETIC (window 440x480; root column, padding 20, gap 10, alignItems
// flex-start, background white):
//
//   ls  list    x=20  y=20   w=200 h=150   itemHeight 30, 5 items -> rows at
//                                           20, 50, 80, 110, 140 (each 30 tall)
//   tb  tabs    x=20  y=180  w=240 h=32    gap 8, 3 labels -> pitch (240-16)/3 = 74.67
//                                           segment i starts at 74.67*i + 8*i
//                                           segment 2 spans 165.33..240 (abs 185.33..260)
//   t1  table   x=20  y=222  w=260 h=120   2 cols (120 / flex 140), header on, rowHeight 20
//                                           -> header 0..19, rows r0..r4 at
//                                              20, 40, 60, 80, 100 (exactly 120)
//   t2  table   x=20  y=352  w=260 h=100   virtual, 20 rows, body = 100-20 = 80
//                                           -> fit = ceil(80/20) = 4
//
//   After the key script (see the steps below) the frame shows:
//     list   row 4 selected  -> #DBEAFE at (205, 155)      [row 4 = y 140..169]
//     list   row 0 NOT        -> #F9FAFB at (205, 25)       [the list's own bg]
//     tabs   segment 2        -> #2563EB at (220, 183)      [above the label]
//     t1     row 4 selected  -> #DBEAFE at (270, 332)      [row 4 = y 322..341]
//     t2     row 5 selected, window starting at row 2
//                             -> #DBEAFE at (270, 442)      [row 5 = 20+3*20 = 80 rel]
//
//   t2's reveal math, with fit = 4: selecting row 5 while row 0 is the window's
//   first mounted row leaves the row outside it, so first = 5 - 4 + 1 = 2 and the
//   offset becomes 2 * 20 = 40.
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

var W:int = 440;
var H:int = 480;
var OUT:String = 'keys';

var KEY_LEFT:int = 37;
var KEY_UP:int = 38;
var KEY_RIGHT:int = 39;
var KEY_DOWN:int = 40;
var KEY_PGUP:int = 33;
var KEY_PGDN:int = 34;
var KEY_HOME:int = 36;
var KEY_END:int = 35;

class KeysModel extends Observable
{
    public var ls:Number = 0;
    public var tb:Number = 0;
    public var t1:Number = -1;
    public var t2:Number = -1;
    public var off2:Number = 0;
}

class KeysProbe extends View
{
    private static const ROOT:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", alignItems: "flex-start",
        padding: 20, gap: 10, size: [440, 480], background: 0xFFFFFF,
        text: { fontSize: 12, color: 0x111827 }
    });
    private static const LIST_S:StyleRefinement = StyleRefinement.from({
        size: [200, 150], background: 0xF9FAFB
    });
    private static const ROW_S:StyleRefinement = StyleRefinement.from({ width: 200 });
    private static const TABS_S:StyleRefinement = StyleRefinement.from({ size: [240, 32] });
    private static const T1_S:StyleRefinement = StyleRefinement.from({ size: [260, 120] });
    private static const T2_S:StyleRefinement = StyleRefinement.from({ size: [260, 100] });

    public var model:KeysModel;
    public var lsPicked:int = -1;
    public var t1Picked:int = -1;
    public var t2Picked:int = -1;

    public function KeysProbe(m:KeysModel):void
    {
        super();
        this.model = m;
    }

    override public function render():Node
    {
        var cols:Array = [
            { key: "a", title: "A", width: 120 },
            { key: "b", title: "B" }
        ];
        var rows:Array = [];
        for (var i:int = 0; i < 5; i++) rows.push({ a: "A" + i, b: "B" + i });
        var many:Array = [];
        for (var j:int = 0; j < 20; j++) many.push({ a: "A" + j, b: "B" + j });

        return column({ key: "root", style: ROOT, ariaName: "keys" }, [
            list(["One", "Two", "Three", "Four", "Five"], this.buildRow, {
                key: "ls", style: LIST_S, itemHeight: 30,
                selectedIndex: bindTo(this.model, "ls"),
                onSelect: this.lsSelected
            }),
            tabs(["T1", "T2", "T3"], {
                key: "tb", style: TABS_S, gap: 8,
                selectedIndex: bindTo(this.model, "tb"),
                onChange: this.tbChanged
            }),
            table(cols, rows, {
                key: "t1", style: T1_S, rowHeight: 20, header: true,
                selectedIndex: bindTo(this.model, "t1"),
                onSelect: this.t1Selected
            }),
            table(cols, many, {
                key: "t2", style: T2_S, rowHeight: 20, header: true,
                virtual: true, offsetY: this.model.off2,
                selectedIndex: bindTo(this.model, "t2"),
                onSelect: this.t2Selected,
                onScroll: this.t2Scrolled
            })
        ]);
    }

    public function buildRow(item:Object, index:int):Node
    {
        return row({ key: "lr" + index, style: ROW_S, ariaName: "row" }, [
            text(String(item), {})
        ]);
    }

    public function lsSelected(i:int):void { this.lsPicked = i; }
    public function tbChanged(i:int):void { }
    public function t1Selected(i:int):void { this.t1Picked = i; }
    public function t2Selected(i:int):void { this.t2Picked = i; }
    public function t2Scrolled(y:Number):void { this.model.off2 = y; }
}

var model:KeysModel = new KeysModel();
var view:KeysProbe = new KeysProbe(model);
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

var problems:String = "";

setTimeout(ready, 900);
stage.showWindow(W, H, "probe keys");

function fail(s:String):void
{
    problems = problems + s + "; ";
}

function check(cond:Boolean, s:String):void
{
    if (!cond) fail(s);
}

// The keys go to the FOCUSED node: UiApp hands an unconsumed KEY_DOWN to
// `WidgetKeys(f.widget).onKey(...)` for `_focus` only, so every step below focuses
// the widget it is about to drive -- exactly what Tab would do in a real app.
function key(code:int):void
{
    var e:KeyboardEvent = new KeyboardEvent(KeyboardEvent.KEY_DOWN, true, true,
        0, code, 0, false, false, false, false, false, false);
    stage.dispatchEvent(e);
}

function focus(k:String):void
{
    var n:UiNode = app.findByKey(k);
    if (n == null) { fail("no node " + k); return; }
    app.focusNode(n);
}

function ready():void
{
    // Registration is not visible in a bitmap.
    if (!Widgets.has("list")) fail("Widgets.has('list') is false");
    if (!Widgets.has("table")) fail("Widgets.has('table') is false");
    if (!Widgets.has("tabs")) fail("Widgets.has('tabs') is false");

    var ls:UiNode = app.findByKey("ls");
    var tb:UiNode = app.findByKey("tb");
    var t1:UiNode = app.findByKey("t1");
    var t2:UiNode = app.findByKey("t2");
    if (ls == null || tb == null || t1 == null || t2 == null)
    {
        fail("a widget never mounted");
        finish();
        return;
    }
    // The three kinds were pointer-only: they were not in the tab ring at all, so
    // their keys were unreachable even if a widget had answered them.
    check(ls.tabEnabled, "list is not a tab stop");
    check(tb.tabEnabled, "tabs is not a tab stop");
    check(t1.tabEnabled, "table is not a tab stop");

    // The window the virtual table computed, before any key touches it.
    var d2:TableNode = TableNode(t2.desc);
    check(d2.visibleRows == 4, "t2 fit is " + d2.visibleRows + " not 4 (ceil(80/20))");
    check(d2.rowCount == 20, "t2 rowCount is " + d2.rowCount + " not 20");
    var d1:TableNode = TableNode(t1.desc);
    check(d1.visibleRows == 5, "t1 fit is " + d1.visibleRows + " not 5");

    focus("ls");
    key(KEY_END);
    setTimeout(afterListEnd, 220);
}

function afterListEnd():void
{
    // End jumps to the last row, and the write goes back through the Binding.
    check(model.ls == 4, "list End -> " + model.ls + " not 4");
    check(view.lsPicked == 4, "list onSelect got " + view.lsPicked + " not 4");

    // A listbox CLAMPS: Down at the last row must stay put, not wrap to 0.
    key(KEY_DOWN);
    setTimeout(afterListClamp, 220);
}

function afterListClamp():void
{
    check(model.ls == 4, "list Down at the end -> " + model.ls + " not 4 (must clamp)");

    key(KEY_HOME);
    setTimeout(afterListHome, 220);
}

function afterListHome():void
{
    check(model.ls == 0, "list Home -> " + model.ls + " not 0");

    // TWO KEYS IN ONE FRAME: Down then End, with no frame between them. Both must
    // count (0 -> 1 -> 4). A widget that reads the last APPLIED index instead of the
    // Binding would land on 1 and then on 4 from 0 -- i.e. End alone, which is why
    // the interesting half is the pair landing on 4 after a Down that came first.
    key(KEY_DOWN);
    key(KEY_END);
    setTimeout(afterListBurst, 220);
}

function afterListBurst():void
{
    check(model.ls == 4, "list burst Down+End -> " + model.ls + " not 4");

    focus("tb");
    key(KEY_LEFT);
    setTimeout(afterTabsWrapBack, 220);
}

function afterTabsWrapBack():void
{
    // A strip is a RING: Left from the first segment goes to the last.
    check(model.tb == 2, "tabs Left from 0 -> " + model.tb + " not 2 (must wrap)");

    key(KEY_HOME);
    setTimeout(afterTabsHome, 220);
}

function afterTabsHome():void
{
    check(model.tb == 0, "tabs Home -> " + model.tb + " not 0");

    // Leave the frame in the state expect.json pins: segment 2 selected.
    key(KEY_LEFT);
    setTimeout(afterTabsFinal, 220);
}

function afterTabsFinal():void
{
    check(model.tb == 2, "tabs Left from 0 -> " + model.tb + " not 2 (final state)");

    focus("t1");
    key(KEY_END);
    setTimeout(afterTableEnd, 220);
}

function afterTableEnd():void
{
    check(model.t1 == 4, "table End -> " + model.t1 + " not 4");

    // Home then PageDown (one window = fit = 5 rows) in ONE frame: 0 -> 5, clamped
    // to the last row. The clamp is the point -- a table has ends too.
    key(KEY_HOME);
    key(KEY_PGDN);
    setTimeout(afterTablePage, 220);
}

function afterTablePage():void
{
    check(model.t1 == 4, "table Home+PageDown -> " + model.t1 + " not 4 (0+5 clamped)");

    key(KEY_HOME);
    setTimeout(afterTableHome, 220);
}

function afterTableHome():void
{
    check(model.t1 == 0, "table Home -> " + model.t1 + " not 0");

    key(KEY_END);
    setTimeout(afterTableFinal, 220);
}

function afterTableFinal():void
{
    check(model.t1 == 4, "table End -> " + model.t1 + " not 4 (final state)");
    check(view.t1Picked == 4, "table onSelect got " + view.t1Picked + " not 4");

    // Six Downs in one frame, from "nothing selected": -1 -> 0 -> 1 -> 2 -> 3 -> 4 -> 5.
    focus("t2");
    key(KEY_DOWN); key(KEY_DOWN); key(KEY_DOWN);
    key(KEY_DOWN); key(KEY_DOWN); key(KEY_DOWN);
    setTimeout(afterVirtual, 260);
}

function afterVirtual():void
{
    var t2:UiNode = app.findByKey("t2");
    check(model.t2 == 5, "virtual table Down x6 -> " + model.t2 + " not 5");
    check(view.t2Picked == 5, "virtual table onSelect got " + view.t2Picked + " not 5");
    if (t2 == null) { fail("t2 vanished"); finish(); return; }

    var d:TableNode = TableNode(t2.desc);
    // The reveal: row 5 cannot be seen from a window that starts at row 0, so the
    // table asks its author for the offset that puts it one row from the bottom.
    check(d.firstRow == 2, "virtual table firstRow is " + d.firstRow + " not 2 (5-4+1)");
    check(model.off2 == 40, "virtual table scroll offset is " + model.off2 + " not 40 (2*20)");
    var mounted:int = t2.children.length;
    // 4 visible + the partial row the factory mounts past the window, + the header.
    check(mounted == 6, "virtual table mounted " + mounted + " children, not 6 (hdr + 2..7)");
    check(app.findByKey("A5") == null, "sanity: cell text is not a key");

    setTimeout(finish, 260);
}

function finish():void
{
    var names:Array = ["root", "ls", "tb", "t1", "t2", "lr0", "lr4"];
    var lines:String = "";
    for (var i:int = 0; i < names.length; i++)
    {
        var n:UiNode = app.findByKey(names[i]);
        if (n == null) { lines = lines + names[i] + " MISSING\n"; continue; }
        lines = lines + names[i] + " " + n.absX + "," + n.absY + "," + n.absW + "," + n.absH + "\n";
    }
    writeText(OUT + ".rects.txt", lines);

    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
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

// 32-bit bottom-up BMP written by hand (copied verbatim from
// probes/widgets/nav/Main.as): this runtime has BitmapData but no PNG encoder.
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
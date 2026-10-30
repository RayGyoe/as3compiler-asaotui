// probes/widgets/nav/Main.as -- the probe for the NAV widget group (tabs + list).
//
// Output prefix MUST equal the directory name (`nav`), because tools/probe.cjs
// derives the expected file names from it.
//
// What it pins, and why each thing is here:
//   * the RECTS of a fixed column (padding 20 / gap 16, all explicit sizes):
//     the tabs node and the list node, plus the list's rows and separator
//     hairlines -- hand-computed positions, verified externally against
//     expect.json;
//   * exact PIXEL colours, one per visual state, sampled a few px inside the
//     solid region and clear of every glyph:
//       tab selected = blue segment, tab unselected = grey segment,
//       list row = the list's own background, selected row = its highlight,
//       separator = the hairline;
//   * things a bitmap CANNOT show: that both kinds registered with Widgets, that
//     clicking a tab writes the index back through its Binding AND calls
//     onChange with the right index, that clicking a list row does the same for
//     onSelect, and that the list is a REAL container -- every row rect lies
//     inside the list's rect (they are engine-placed child nodes, not hand-drawn
//     boxes).
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

var W:int = 360;
var H:int = 300;
var OUT:String = 'nav';

class NavModel extends Observable
{
    public var tabIndex:Number = 1;    // bound to the tabs' selectedIndex
    public var listIndex:Number = 1;   // bound to the list's selectedIndex
}

class NavProbe extends View
{
    private static const ROOT:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", padding: 20, gap: 16, size: [360, 300],
        background: 0xFFFFFF, text: { fontSize: 12, color: 0x111827 }
    });
    private static const TABS_S:StyleRefinement = StyleRefinement.from({ size: [320, 36] });
    private static const LIST_S:StyleRefinement = StyleRefinement.from({
        size: [320, 160], background: 0xF9FAFB
    });
    // The builder rows carry an explicit width; their HEIGHT comes from the
    // list's `itemHeight` opt, which also exercises the style patch.
    private static const ROW_S:StyleRefinement = StyleRefinement.from({ width: 320 });
    private static const ROWTEXT_S:StyleRefinement = StyleRefinement.from({ text: { fontSize: 12, color: 0x111827 } });

    public var model:NavModel;
    public var pickedTab:int = -1;
    public var pickedList:int = -1;

    public function NavProbe(m:NavModel):void
    {
        super();
        this.model = m;
    }

    override public function render():Node
    {
        return column({ key: "root", style: ROOT, ariaName: "nav" }, [
            tabs(["One", "Two", "Three", "Four"], {
                key: "tabs", style: TABS_S, gap: 8,
                selectedIndex: bindTo(this.model, "tabIndex"),
                onChange: this.tabChanged
            }),
            list(["Alpha", "Beta", "Gamma"], this.buildRow, {
                key: "list", style: LIST_S,
                separator: true, itemHeight: 40,
                selectedIndex: bindTo(this.model, "listIndex"),
                onSelect: this.listSelected
            })
        ]);
    }

    public function buildRow(item:Object, index:int):Node
    {
        return row({ key: "row" + index, style: ROW_S, ariaName: "row" }, [
            text(String(item), { style: ROWTEXT_S })
        ]);
    }

    public function tabChanged(i:int):void { this.pickedTab = i; }
    public function listSelected(i:int):void { this.pickedList = i; }
}

var model:NavModel = new NavModel();
var view:NavProbe = new NavProbe(model);
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

setTimeout(settle, 900);
stage.showWindow(W, H, "probe nav");

function settle():void
{
    var names:Array = ["root", "tabs", "list", "row0", "sep:0", "row1", "sep:1", "row2"];
    var lines:String = "";
    var missing:int = 0;
    var i:int;
    for (i = 0; i < names.length; i++)
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
    setTimeout(steady, 400);
}

var solveAtSettle:Number = 0;
var frame0:int = 0;

function steady():void
{
    var problems:String = "";

    // (a) both kinds registered -- a bitmap cannot show a registry miss.
    if (!Widgets.has("tabs")) problems = problems + "Widgets.has('tabs') is false; ";
    if (!Widgets.has("list")) problems = problems + "Widgets.has('list') is false; ";

    // (b) clicking tab 2 writes the index back through its Binding AND calls
    //     onChange with the right index. Segment pitch = (320 - 8*3)/4 = 74, so
    //     segment 2 starts at local x = 2*(74+8) = 164; click its centre (201).
    var tn:UiNode = app.findByKey("tabs");
    if (tn == null) problems = problems + "tabs missing; ";
    else
    {
        tn.backing.dispatchEvent(new MouseEvent(MouseEvent.CLICK, true, false, 201, 18));
        if (model.tabIndex != 2) problems = problems + "tab binding not written: " + model.tabIndex + "; ";
        if (view.pickedTab != 2) problems = problems + "tab onChange index: " + view.pickedTab + "; ";
    }

    // (c) clicking list row 2 writes back through the Binding and calls onSelect.
    //     Rows: 40 tall at y=0, 41..80 (row1), 82..121 (row2) in list-local
    //     coords (row0 0..39, sep 40, row1 41..80, sep 81, row2 82..121); click
    //     row 2's centre at local y = 82 + 20 = 102.
    var ln:UiNode = app.findByKey("list");
    if (ln == null) problems = problems + "list missing; ";
    else
    {
        ln.backing.dispatchEvent(new MouseEvent(MouseEvent.CLICK, true, false, 100, 102));
        if (model.listIndex != 2) problems = problems + "list binding not written: " + model.listIndex + "; ";
        if (view.pickedList != 2) problems = problems + "list onSelect index: " + view.pickedList + "; ";
    }

    // (d) the list is a REAL container: exactly 3 non-divider rows, each inside
    //     the list's rect.
    if (ln != null)
    {
        var rows:int = 0;
        for (var k:int = 0; k < ln.children.length; k++)
        {
            if (ln.children[k].kind != "divider") rows = rows + 1;
        }
        if (rows != 3) problems = problems + "list row count is " + rows + " not 3; ";
        var rk:Array = ["row0", "row1", "row2"];
        for (var r:int = 0; r < 3; r++)
        {
            var row:UiNode = app.findByKey(rk[r]);
            if (row == null) { problems = problems + rk[r] + " missing; "; continue; }
            if (row.absX < ln.absX || row.absY < ln.absY
                || row.absX + row.absW > ln.absX + ln.absW
                || row.absY + row.absH > ln.absY + ln.absH)
            {
                problems = problems + rk[r] + " is not inside the list rect; ";
            }
        }
    }

    // (e) a settled tree never re-solves layout.
    var extraSolves:Number = app.layoutSolves - solveAtSettle;
    var extraFrames:int = app.enterFrameTicks - frame0;
    if (extraFrames < 2) problems = problems + "only " + extraFrames + " frame(s) elapsed; ";
    if (extraSolves > 0) problems = problems + "a settled tree re-solved layout " + extraSolves + " time(s); ";

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
// probes/widgets/chip/Main.as): this runtime has BitmapData but no PNG encoder,
// and a raw frame buffer is BETTER evidence than an encoded image -- it is a
// 1:1 copy of the compositor output, so the samplers can compare exact integers.
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
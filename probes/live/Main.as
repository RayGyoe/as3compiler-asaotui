// probes/live/Main.as -- WHERE A LIVE TICK GOES, measured, not asserted.
//
// This reproduces the SHAPE of the gallery's live board (DocsLive.as): N rows,
// each row = a memo'd identity column (2 text nodes) + one sparkline + a price
// column (2 text nodes). Every TICK_MS the market steps -- every price changes,
// every series shifts in place and bumps `version` -- and the view raises
// Dirty.VALUE, exactly what the gallery's frameTick does. The cost of one such
// tick is reported per-phase by UiApp.profile.
//
// N is read from case.txt at startup (default 22), so tools/scan-rows.cjs can
// build ONCE and sweep 22/100/200/500/1000 without recompiling. The rows are a
// plain column with no scrollView: measure and paint-command recording run over
// the FULL set of rows, which is the upper bound a subtree-level skip would
// reclaim (the gallery virtualizes, so its real per-tick cost is lower).
//
// It is a TIMING probe: it writes live.samples.txt and live.done = PASS, and
// asserts no pixels and no milliseconds.
import asaot.ui.*;
import asaot.ui.style.*;
import flash.display.Stage;
import flash.display.StageAlign;
import flash.display.StageScaleMode;
import flash.events.Event;
import flash.filesystem.File;
import flash.filesystem.FileMode;
import flash.filesystem.FileStream;
import flash.utils.getTimer;

var W:int = 800;
var H:int = 600;
var ROWS:int = readRows();
var SERIES:int = 24;
var TICK_MS:int = 100;
var OUT:String = 'live';
// Enough ticks to average the per-tick phases (each tick runs one reflow), and
// enough frames to fill the ASC_FRAME_STATS 512-frame window (FRAME_GOAL > 512).
// With vsync off and frameRate=120 the FRAME p50 reflects real work, not the
// 60 Hz vsync lock, so this is the runtime-side cost probe.
var FRAME_GOAL:int = 600;

var log:String = "";

function readRows():int
{
    var f:File = File.applicationDirectory.resolvePath('case.txt');
    if (!f.exists) return 22;
    var fs:FileStream = new FileStream();
    fs.open(f, FileMode.READ);
    var s:String = fs.readUTFBytes(fs.bytesAvailable);
    fs.close();
    s = s.replace("\r", "").replace("\n", "").replace(" ", "");
    var n:int = int(s);
    return n > 0 ? n : 22;
}

class LiveView extends View
{
    private static const UP:uint = 0x15803D;
    private static const DOWN:uint = 0xB91C1C;
    private static const INK:uint = 0x0F172A;
    private static const MUTED:uint = 0x64748B;

    private static const ROW:StyleRefinement = StyleRefinement.from({
        flexDirection: "row", alignItems: "center", gap: 12,
        size: [Length.pct(1), Length.px(52)], padding: [14, 0],
        borderWidths: [0, 0, 1, 0], borderColor: 0xF1F5F9 });
    private static const C_TITLE:StyleRefinement = StyleRefinement.from({
        size: [Length.pct(1), Length.px(13)],
        text: { fontSize: 13, fontWeight: "bold", color: INK } });
    private static const C_NAME:StyleRefinement = StyleRefinement.from({
        size: [Length.pct(1), Length.px(13)],
        text: { fontSize: 11, color: MUTED } });
    private static const C_LAST:StyleRefinement = StyleRefinement.from({
        size: [Length.px(160), Length.px(17)],
        text: { fontSize: 13, fontWeight: "bold", color: INK, textAlign: "right" } });
    private static const C_CHG:StyleRefinement = StyleRefinement.from({
        size: [Length.px(160), Length.px(14)],
        text: { fontSize: 11, fontWeight: "bold", textAlign: "right" } });
    private static const SPARK:StyleRefinement = StyleRefinement.from({
        size: [Length.px(104), Length.px(34)] });
    private static const ROOT:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", size: [Length.pct(1), Length.px(500)], background: 0xFFFFFF });

    public var rows:Array;
    public var n:int;

    public function LiveView():void
    {
        super();
        this.n = ROWS;
        this.rows = [];
        for (var i:int = 0; i < this.n; i++)
        {
            var s:Object = {};
            s.code = "S" + (i + 1);
            s.name = "Name " + (i + 1);
            s.prev = 50 + (i % 20);
            s.last = 50 + (i % 20);
            s.rev = 0;
            s.chg = 0;
            s.series = [];
            for (var k:int = 0; k < SERIES; k++) s.series.push(50 + (i % 20));
            this.rows.push(s);
        }
    }

    public function step():void
    {
        var n:int = this.rows.length;
        for (var i:int = 0; i < n; i++)
        {
            var s:Object = this.rows[i];
            var last:Number = Number(s.last) * (1 + (Math.random() - 0.5) * 0.01);
            s.last = last;
            s.chg = (last - Number(s.prev)) / Number(s.prev) * 100;
            s.rev = int(s.rev) + 1;
            var series:Array = s.series as Array;
            series.push(last);
            if (series.length > SERIES) series.shift();
        }
    }

    public override function render():Node
    {
        var kids:Array = [];
        for (var i:int = 0; i < this.rows.length; i++)
        {
            kids.push(stockRow(this.rows[i]));
        }
        return column({ key: "liveBoard", style: ROOT }, kids);
    }

    private function stockRow(s:Object):Node
    {
        var chg:Number = Number(s.chg);
        var tone:uint = chg > 0.005 ? UP : (chg < -0.005 ? DOWN : MUTED);
        return row({ key: "liveRow:" + String(s.code), style: ROW }, [
            this.memo("identity:" + String(s.code), String(s.name),
                function ():Node { return stockIdentity(s); }),
            sparkline({ key: "liveSp:" + String(s.code),
                        values: s.series as Array, version: int(s.rev),
                        color: tone, fill: true, baseline: Number(s.prev),
                        strokeWidth: 1.5, style: SPARK }),
            column({ style: StyleRefinement.from({
                flexDirection: "column", gap: 2, alignItems: "flex-end",
                size: [Length.px(160), Length.px(32)] }) }, [
                text(price(Number(s.last)), { style: C_LAST, ariaName: "" }),
                text(signed(chg) + "%", { style: C_CHG.withPatch(
                    StyleRefinement.from({ text: { color: tone } })), ariaName: "" })
            ])
        ]);
    }

    private function stockIdentity(s:Object):Node
    {
        return column({ style: StyleRefinement.from({
            flexDirection: "column", gap: 2, flexGrow: 1, flexBasis: 0,
            size: [null, Length.px(32)] }) }, [
            text(String(s.code), { style: C_TITLE, ariaName: "" }),
            text(String(s.name), { style: C_NAME, ariaName: "" })
        ]);
    }

    private function price(v:Number):String { return Number(v).toFixed(2); }
    private function signed(v:Number):String { return (v < 0 ? "" : "+") + Number(v).toFixed(2); }
}

function writeText(path:String, t:String):void
{
    var f:File = File.applicationDirectory.resolvePath(path);
    var fs:FileStream = new FileStream();
    fs.open(f, FileMode.WRITE);
    fs.writeUTFBytes(t);
    fs.close();
}

var view:LiveView = new LiveView();
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
stage.vsyncEnabled = false;
stage.frameRate = 120;
var app:UiApp = new UiApp(view);
UiApp.profile = true;
app.mount(stage);
app.attachRoot();

var tickCount:int = 0;
var lastStep:Number = 0;
var frames:int = 0;

function tick(e:Event):void
{
    frames++;
    if (lastStep == 0) lastStep = getTimer();
    if (getTimer() - lastStep >= TICK_MS)
    {
        lastStep = getTimer();
        view.step();
        app.invalidate(Dirty.VALUE);
        tickCount++;
    }
    if (frames >= FRAME_GOAL) finish();
}

function finish():void
{
    var d:int = tickCount > 0 ? tickCount : 1;
    log = log
        + "frames=" + frames
        + " ticks=" + tickCount
        + " rows=" + ROWS
        + " describe=" + app.describeCalls
        + " solves=" + app.layoutSolves
        + " paints=" + app.paintPasses
        + " nodes=" + countNodes(app.getRoot()) + "\n"
        + "per-tick ms:\n"
        + "  render    " + (app.profRenderMs / d).toFixed(2) + "\n"
        + "  reconcile " + (app.profReconcileMs / d).toFixed(2) + "\n"
        + "  measure   " + (app.profMeasureMs / d).toFixed(2) + "\n"
        + "  solve     " + (app.profSolveMs / d).toFixed(2) + "\n"
        + "  arrange   " + (app.profArrangeMs / d).toFixed(2) + "\n"
        + "  paint     " + (app.profPaintMs / d).toFixed(2) + "\n";
    writeText(OUT + ".samples.txt", log);
    writeText(OUT + ".done", "PASS");
}

function countNodes(n:UiNode):int
{
    var c:int = 1;
    for (var i:int = 0; i < n.children.length; i++) c += countNodes(n.children[i]);
    return c;
}

stage.addEventListener(Event.ENTER_FRAME, tick);
stage.showWindow(W, H, "probe live");

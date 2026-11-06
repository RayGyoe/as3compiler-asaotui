// probes/widgets/static-layer/Main.as -- 验证封装 API `box({ staticLayer: true })`
// 正确映射到 retained 节点的 `backing.cacheAsBitmap`，且渲染与动态更新不受破坏。
//
// 与 repaint-boundary 的差别：那里直接写 `n.backing.cacheAsBitmap = true`（底层机制），
// 这里走作者视角的 opt-in（`box({ staticLayer: true })`）。断言因此多一层：
//   * stable（设了 staticLayer）的 backing.cacheAsBitmap 必须 == true
//   * root（没设）的 backing.cacheAsBitmap 必须 == false（opt-in 不是默认）
//   * 改 s1 颜色后像素正确更新（cache 不冻结内容）
//
// 时间线（配合 ASC_BAKE_TRACE=1 观察，trace 打 stderr，AS3 侧看不见）：
//   t≈0ms    首帧
//   t≈900ms  changeColor 改 s1 颜色 + invalidate(Dirty.VALUE)
//   t≈1200ms settle 读 cacheAsBitmap + 采样像素 + 写 .done
import asaot.ui.*;
import asaot.ui.style.*;

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
var H:int = 200;
var OUT:String = 'static-layer';

// s1 的两种颜色（只有 R 通道降一档：0xEE -> 0xCC），其余通道不动。
var S1_REST:uint = 0xEE1111;
var S1_HOT:uint = 0xCC1111;
var C2:uint = 0x11EE11;
var C3:uint = 0x1111EE;

class SlaModel extends Observable
{
    public var s1Color:uint = 0xEE1111;
}

class SlaProbe extends View
{
    public var model:SlaModel;

    private static const ROOT:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", alignItems: "flex-start",
        padding: 20, gap: 10, size: [320, 200], background: 0xFFFFFF
    });
    private static const STABLE:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", size: [280, 120],
        padding: 10, gap: 8, background: 0xF3F4F6
    });
    private static const BAND2:StyleRefinement = StyleRefinement.from({
        size: [260, 20], background: 0x11EE11
    });
    private static const BAND3:StyleRefinement = StyleRefinement.from({
        size: [260, 20], background: 0x1111EE
    });

    public function SlaProbe(m:SlaModel):void
    {
        super();
        this.model = m;
    }

    override public function render():Node
    {
        // 每次 render 都新建 s1 的 refinement（指针变化 => reconcile 标记 s1 重绘），
        // 但 size 不变 => 不触发 reflow，只触发局部 paint。
        var b1:StyleRefinement = StyleRefinement.from({
            size: [260, 20], background: this.model.s1Color
        });
        // `staticLayer: true` 是作者视角的 opt-in：这一层变化少，值得 rasterize 缓存。
        return column({ key: "root", style: ROOT, ariaName: "sla root" }, [
            box({ key: "stable", style: STABLE, staticLayer: true, ariaName: "stable subtree" }, [
                box({ key: "s1", style: b1, ariaName: "band 1" }),
                box({ key: "s2", style: BAND2, ariaName: "band 2" }),
                box({ key: "s3", style: BAND3, ariaName: "band 3" })
            ])
        ]);
    }
}

var model:SlaModel = new SlaModel();
var view:SlaProbe = new SlaProbe(model);
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

setTimeout(changeColor, 900);
stage.showWindow(W, H, "probe static-layer");

function changeColor():void
{
    model.s1Color = S1_HOT;
    view.invalidate(Dirty.VALUE);
    writeText(OUT + ".step", "s1 color changed");
    setTimeout(settle, 300);
}

function settle():void
{
    step("settle enter");
    try { settleBody(); }
    catch (err:Error) { writeText(OUT + ".done", "FAIL settle threw #" + err.errorID + ": " + err.message); }
}

function settleBody():void
{
    // ---- 封装 API 的正确性：staticLayer 必须映射到 backing.cacheAsBitmap ----
    // stable 设了 staticLayer => cacheAsBitmap true；root 没设 => 默认 false。
    // 这是本探针相对 repaint-boundary 的核心增量：证明 opt-in 真的落到了 display object。
    var stableNode:UiNode = app.findByKey("stable");
    var rootNode:UiNode = app.findByKey("root");
    var s1Node:UiNode = app.findByKey("s1");
    var s2Node:UiNode = app.findByKey("s2");
    var s3Node:UiNode = app.findByKey("s3");
    var flagFail:String = "";
    if (stableNode == null) flagFail = flagFail + "stable missing; ";
    else if (stableNode.backing == null) flagFail = flagFail + "stable backing null; ";
    else if (stableNode.backing.cacheAsBitmap != true) flagFail = flagFail + "stable cacheAsBitmap not true; ";
    if (rootNode == null) flagFail = flagFail + "root missing; ";
    else if (rootNode.backing == null) flagFail = flagFail + "root backing null; ";
    else if (rootNode.backing.cacheAsBitmap != false) flagFail = flagFail + "root cacheAsBitmap not false; ";
    // staticLayer 是「本节点」的声明，不得向下传播：子节点没声明就必须保持 false。
    if (s1Node != null && s1Node.backing != null && s1Node.backing.cacheAsBitmap != false) flagFail = flagFail + "s1 cacheAsBitmap not false; ";
    if (s2Node != null && s2Node.backing != null && s2Node.backing.cacheAsBitmap != false) flagFail = flagFail + "s2 cacheAsBitmap not false; ";
    if (s3Node != null && s3Node.backing != null && s3Node.backing.cacheAsBitmap != false) flagFail = flagFail + "s3 cacheAsBitmap not false; ";

    var names:Array = ["root", "stable", "s1", "s2", "s3"];
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

    var problems:String = flagFail;
    if (missing > 0) problems = problems + missing + " node(s) missing; ";
    // s1 已改成 HOT，采样它验证颜色真的变了；s2/s3 不动，验证只变 s1。
    problems = problems + expectStr(bd, 160, 40, S1_HOT, "s1 did not take its new colour");
    problems = problems + expectStr(bd, 160, 68, C2, "s2 changed although it should not");
    problems = problems + expectStr(bd, 160, 96, C3, "s3 changed although it should not");
    // bake 不得把子树漏到框外。
    problems = problems + expectStr(bd, 160, 10, 0xFFFFFF, "something leaked above the stable box");

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

function step(s:String):void
{
    writeText(OUT + ".step", s);
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

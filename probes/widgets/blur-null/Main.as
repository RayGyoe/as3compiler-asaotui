// probes/widgets/blur-null -- focusNode(null) after a TextField held focus must not
// throw (compiler-gaps.md G47, 2026-11-15).
//
// Output prefix MUST equal the directory name (`blur-null`).
//
// G47 was logged as "focusNode(null) throws Error #1009 once a text field has held
// the focus"; the hymn demo worked around it by blurring to ANOTHER node. The root
// cause was a COMPILER bug, not a library one: sequenceValueExpr hoisted the impure
// left operand of a short-circuited `&&`/`||` to an eager `_sc` prelude temp even
// when the expression was not guaranteed to run, so `n != null && (n.inert() || ...)`
// evaluated n.inert() on a null n (as_req_obj -> #1009). Fixed in as3compiler by
// gating that hoist on `guaranteed`. This probe pins the library contract that the
// fix restores: focusNode(null) is a safe no-op both with nothing focused and after
// a TextField held the focus, and blurring to another node still clears stage.focus.
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

var W:int = 240;
var H:int = 120;
var OUT:String = "blur-null";

var problems:String = "";
var log:String = "";

class BNProbe extends View
{
    override public function render():Node
    {
        return column({ key: "root", style: StyleRefinement.from({
            size: [240, 120], padding: 10, gap: 8, background: 0xFFFFFF }) }, [
            textField({ key: "inp", value: "hello", placeholder: "type here",
                        style: StyleRefinement.from({ size: [200, 32] }) }),
            box({ key: "other", style: StyleRefinement.from({ size: [200, 32], background: 0xE2E8F0 }) }, [])
        ]);
    }
    public function BNProbe():void { super(); }
}

var view:BNProbe = new BNProbe();
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

setTimeout(run, 500);
stage.showWindow(W, H, "probe blur-null");

function say(s:String):void { log = log + s + String.fromCharCode(10); trace(s); }
function bad(s:String):void { problems = problems + s + "; "; }
function check(cond:Boolean, s:String):void { if (!cond) bad(s); }

function run():void
{
    app.reflow();
    var inp:UiNode = app.findByKey("inp");
    if (inp == null) { bad("no inp node"); finish(); return; }

    // ---- 1. focusNode(null) with NOTHING focused must be a safe no-op ----
    var t0:String = "";
    try { app.focusNode(null); }
    catch (e0:Error) { t0 = e0.message; }
    check(t0 == "", "focusNode(null) with nothing focused threw: " + t0);

    // ---- 2. focus the text field, then blur to NULL (the G47 path) -------
    app.focusNode(inp);
    check(stage.focus != null, "focusNode(field) did not give the stage focus");
    var t1:String = "";
    try { app.focusNode(null); }
    catch (e1:Error) { t1 = e1.message; }
    check(t1 == "", "focusNode(null) threw after a field held focus: " + t1);
    check(stage.focus == null, "focusNode(null) did not clear stage.focus");
    say("blur-to-null: threw='" + t1 + "' stage.focus!=null=" + (stage.focus != null));

    // ---- 3. blur to ANOTHER node still works (the old workaround path) ---
    app.focusNode(inp);
    var other:UiNode = app.findByKey("other");
    var t2:String = "";
    try { app.focusNode(other); }
    catch (e2:Error) { t2 = e2.message; }
    check(t2 == "", "focusNode(other) threw: " + t2);
    check(stage.focus == null, "a non-editable target must clear stage.focus");

    finish();
}

function finish():void
{
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    var keys:Array = ["root"];
    var lines:String = "";
    for (var i:int = 0; i < keys.length; i++)
    {
        var n:UiNode = app.findByKey(String(keys[i]));
        if (n == null) { lines = lines + keys[i] + " MISSING" + String.fromCharCode(10); continue; }
        lines = lines + keys[i] + " " + n.absX + "," + n.absY + "," + n.absW + "," + n.absH + String.fromCharCode(10);
    }
    writeText(OUT + ".rects.txt", lines);
    writeText(OUT + ".samples.txt", log);
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
            var o:int = (y * w + x) * 4;
            ba.writeByte(px[o + 3]);
            ba.writeByte(px[o + 2]);
            ba.writeByte(px[o + 1]);
            ba.writeByte(px[o]);
        }
    }
    var f:File = File.applicationDirectory.resolvePath(path);
    var fs:FileStream = new FileStream();
    fs.open(f, FileMode.WRITE);
    fs.writeBytes(ba);
    fs.close();
}
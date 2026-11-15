// probes/widgets/focus-trap -- opt-in modal focus management (2026-11-15).
//
// Output prefix MUST equal the directory name (`focus-trap`).
//
// WHAT THIS PROVES:
//   1. DEFAULT DOES NOT STEAL. A dialog with focusTrap:false (the ship default)
//      opening leaves the live focus exactly where it was, and closing leaves it too.
//   2. AUTO-FOCUS. A dialog with focusTrap:true moves focus to its FIRST tab stop on
//      open (d1), which is also what engages UiApp's existing Tab trap.
//   3. TRAP. While the trapping dialog is open, Tab / Shift+Tab cycle ONLY its stops
//      (d1 -> d2 -> d1 ...), never the page behind (bg).
//   4. RESTORE. Closing the trapping dialog returns focus to the node that was live
//      when it opened (bg).
//
// Protocol (tools/probe.cjs): dir name == output prefix; write <OUT>.rects.txt,
// <OUT>.bmp, <OUT>.done (PASS | FAIL <reason>).
import asaot.ui.*;
import asaot.ui.anim.Motion;
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

var W:int = 480;
var H:int = 300;
var OUT:String = "focus-trap";
var TAB:int = 9;

var openTrap:Boolean = false;
var openPlain:Boolean = false;
var problems:String = "";
var log:String = "";

class FocusProbe extends View
{
    override public function render():Node
    {
        return column({ key: "root", style: StyleRefinement.from({
            size: [480, 300], padding: 12, gap: 10, background: 0xFFFFFFFF }) }, [
            button({ key: "bg", label: "Background", style: StyleRefinement.from({ size: [160, 40] }) }),
            textField({ key: "bgField", style: StyleRefinement.from({ size: [200, 40] }) })
        ]);
    }
    // Dialogs live in the OVERLAY tree (View.renderOverlay) -- that is what puts them
    // under overlayRoot, which is the condition UiApp's Tab trap tests. A dialog left
    // in render() stays in the main tree and would NOT trap.
    override public function renderOverlay():Node
    {
        return box({ key: "ovl", style: StyleRefinement.from({ size: [480, 300] }) }, [
            dialog({ key: "plain", open: openPlain, title: "Plain", focusTrap: false }, [
                button({ key: "p1", label: "P1" })
            ]),
            dialog({ key: "dlg", open: openTrap, title: "Trap", focusTrap: true }, [
                button({ key: "d1", label: "D1" }),
                button({ key: "d2", label: "D2" })
            ])
        ]);
    }
    public function FocusProbe():void { super(); }
}

var view:FocusProbe = new FocusProbe();
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

setTimeout(ready, 700);
stage.showWindow(W, H, "probe focus-trap");

function say(s:String):void { log = log + s + String.fromCharCode(10); trace(s); }
function bad(s:String):void { problems = problems + s + "; "; }
function check(cond:Boolean, s:String):void { if (!cond) bad(s); }
function node(k:String):UiNode { var n:UiNode = app.findByKey(k); if (n == null) bad("no node " + k); return n; }
function focusedKey():String
{
    var f:UiNode = app.focusedNode();
    return f == null ? "(none)" : String(f.key);
}
function key(code:int, shift:Boolean):void
{
    var e:KeyboardEvent = new KeyboardEvent(KeyboardEvent.KEY_DOWN, true, true,
        0, code, 0, false, false, shift, false, false, false);
    stage.dispatchEvent(e);
}
function settle():void { app.invalidate(Dirty.ALL); app.reflow(); }

function ready():void
{
    // Instant open/close (no exit hold) so the final bitmap is the clean main tree.
    Motion.reducedMotion = true;
    settle();
    app.focusNode(node("bg"));
    check(focusedKey() == "bg", "could not focus bg to start");

    // ---- 1. default dialog does not steal focus -------------------------
    openPlain = true; settle();
    check(focusedKey() == "bg", "a focusTrap:false dialog stole focus on open (now " + focusedKey() + ")");
    openPlain = false; settle();
    check(focusedKey() == "bg", "a focusTrap:false dialog disturbed focus on close (now " + focusedKey() + ")");
    say("default: focus stayed bg through plain open/close");

    // ---- 2. trapping dialog auto-focuses its first stop -----------------
    openTrap = true; settle();
    check(focusedKey() == "d1", "focusTrap:true did not auto-focus the first stop (now " + focusedKey() + ")");
    say("open: focus=" + focusedKey());

    // ---- 3. Tab / Shift+Tab stay inside the dialog ----------------------
    key(TAB, false);
    check(focusedKey() == "d2", "Tab left the dialog or did not advance (now " + focusedKey() + ")");
    key(TAB, false);
    check(focusedKey() == "d1", "Tab did not wrap within the dialog (now " + focusedKey() + ")");
    key(TAB, true);
    check(focusedKey() == "d2", "Shift+Tab did not wrap backwards within the dialog (now " + focusedKey() + ")");
    say("trap: Tab cycle d1->d2->d1, Shift+Tab->d2");

    // ---- 4. closing restores the pre-open focus -------------------------
    openTrap = false; settle();
    check(focusedKey() == "bg", "closing did not restore the pre-open focus (now " + focusedKey() + ")");
    say("close: focus restored to " + focusedKey());
    finish();
}

function finish():void
{
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    var keys:Array = ["root", "bg", "bgField"];
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
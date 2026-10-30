// probes/widgets/accordion/Main.as -- accordion's TWO MODES, told apart.
//
// Output prefix MUST equal the directory name (`accordion`).
//
// WHY THIS PROBE EXISTS
// ---------------------
// probes/widgets/data already pins the single-open accordion (data 2026-10-23). What
// it cannot show is the batch that added `mode: "multi"`, because single and multi
// are the SAME child list with a different predicate over the open set -- a widget
// that ignored `mode` would still open panels, still fill a header, and still fire
// onToggle. So this probe is built to distinguish the two:
//
//   1. THREE sections, TWO open at once ([0,2]). A single-open implementation can
//      only ever mount one panel, so "pa AND pc mounted, pb absent" is already a
//      statement no single-mode code can satisfy. The middle header must be CLOSED
//      (#F3F4F6) while its two neighbours are OPEN (#DBEAFE) -- a fill test at three
//      x positions, which a "paint the last index" or "paint index 0" bug fails.
//   2. A CLICK TOGGLES ONE MEMBER OF THE SET and reports the CLICKED index: clicking
//      the middle header must leave the other two alone and make `opens` [0,1,2] --
//      in single mode the same click would have produced [1] (or []) instead.
//   3. THE STATE IS THE AUTHOR'S ARRAY, AND IT IS CANONICAL WHEN WE WRITE IT: the
//      author hands us [2,0] (unsorted) and both stay open -- equality is by
//      membership, not by order -- while a click that changes the set writes back an
//      ASCENDING array, so [2,0] and [0,2] do not read as two different states.
//   4. THE TWO SPELLINGS ARE EXCLUSIVE AND REFUSED: `mode:"multi"` with
//      `activeIndex`, `mode:"single"` with `openIndices`, and an unknown `mode` all
//      THROW at describe time (AGENTS.md 2.5: no silently ignored option). Asserted
//      by catching the error -- a probe that only checked the happy path would not
//      notice if the guard disappeared and the option was quietly dropped.
//   5. SINGLE MODE STILL BEHAVES, on the same frame: its own accordion with
//      `activeIndex` opens one at a time and closes on a second click, so the new
//      mode cannot have been implemented by rewriting the old one.
//
// HAND-COMPUTED LAYOUT (window 300x420, root column, padding 10, gap 10, white):
//
//   m  [280,150] @ (10,10)      three headers + two panels (header height is the
//                               engine's, so it is read from the live rects)
//   s  [280, 90] @ (10,170)
//
// Header fills are sampled 3px in from the accordion's left edge, at each header's
// vertical midpoint (clear of the title glyph, which starts at pad 12).
//
// Protocol (tools/probe.cjs): dir name == output prefix; writes <OUT>.rects.txt,
// <OUT>.bmp, <OUT>.done (PASS | FAIL <reason>) and <OUT>.samples.txt.
import asaot.ui.*;
import asaot.ui.style.StyleRefinement;
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

var W:int = 300;
var H:int = 420;
var OUT:String = 'accordion';

class AccModel extends Observable
{
    public var opens:Array = [0, 2];   // multi: the open set, deliberately unsorted
    public var open:Number = 0;        // single: one index
}

var st:Object = { toggles: 0, last: -2, sets: "" };

class AccProbe extends View
{
    private static const ROOT:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", padding: 10, gap: 10, size: [300, 420],
        background: 0xFFFFFF, text: { fontSize: 12, color: 0x111827 }
    });
    private static const M_S:StyleRefinement = StyleRefinement.from({ size: [280, 150], gap: 2 });
    private static const S_S:StyleRefinement = StyleRefinement.from({ size: [280, 90], gap: 2 });
    private static const PANEL:StyleRefinement = StyleRefinement.from({
        size: [280, 20], background: 0xEAEAEA
    });

    public function AccProbe():void { super(); }

    override public function render():Node
    {
        return column({ key: "root", style: ROOT, ariaName: "accordion probe" }, [
            accordion(
                [{ title: "Alpha", content: box({ key: "pa", style: PANEL }) },
                 { title: "Beta", content: box({ key: "pb", style: PANEL }) },
                 { title: "Gamma", content: box({ key: "pc", style: PANEL }) }],
                { key: "m", style: M_S, mode: "multi",
                  openIndices: bindTo(model, "opens"),
                  onToggle: function (i:int):void { noteToggle(i); } }),
            accordion(
                [{ title: "One", content: box({ key: "px", style: PANEL }) },
                 { title: "Two", content: box({ key: "py", style: PANEL }) }],
                { key: "s", style: S_S, activeIndex: bindTo(model, "open"),
                  onToggle: function (i:int):void { noteToggle(i); } })
        ]);
    }
}

var model:AccModel = new AccModel();

var problems:String = "";
var log:String = "";

var view:AccProbe = new AccProbe();
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

setTimeout(begin, 900);
stage.showWindow(W, H, "probe accordion");

function noteToggle(i:int):void
{
    st.toggles = int(st.toggles) + 1;
    st.last = i;
    st.sets = st.sets + "[" + String(model.opens) + "]#" + i + " ";
    say("toggle " + i + " -> opens=" + String(model.opens));
}

function say(s:String):void
{
    log = log + s + "\n";
    writeText(OUT + ".samples.txt", log);
}

function bad(s:String):void
{
    problems = problems + s + "; ";
}

function node(k:String):UiNode
{
    return app.findByKey(k);
}

function frame():BitmapData
{
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    return bd;
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
        bad(what + " at (" + int(x) + "," + int(y) + ") want #" + hexOf(rgb) + " got #" + hexOf(got));
}

// A click on a widget's own backing, in that backing's LOCAL coordinates.
function clickLocal(n:UiNode, lx:Number, ly:Number):void
{
    n.backing.dispatchEvent(new MouseEvent(MouseEvent.CLICK, true, false, lx, ly));
}

// Click the middle of header `i` of accordion `accKey`, computing y from the LIVE
// rects: the header's height is a font metric + padding, not a number to guess.
function clickHeader(accKey:String, i:int):void
{
    var acc:UiNode = node(accKey);
    var h:UiNode = node(accKey + ":h" + i);
    if (acc == null || h == null) { bad("cannot click h" + i + accKey + ": node missing"); return; }
    clickLocal(acc, 30, (h.absY - acc.absY) + int(h.absH / 2));
}

function churn():void
{
    app.invalidate(Dirty.STRUCTURE);
    app.reflow();
}

// ==================== phase 1: two open at once ============================
function begin():void
{
    var m:UiNode = node("m");
    if (m == null) { bad("the accordion page did not mount"); finish(); return; }

    var lines:String = "";
    var names:Array = ["root", "m", "m:h0", "m:h1", "m:h2", "pa", "pb", "pc", "s", "s:h0", "s:h1", "px", "py"];
    for (var i:int = 0; i < names.length; i++)
    {
        var n:UiNode = node(names[i]);
        lines = lines + names[i] + " "
            + (n == null ? "MISSING" : n.absX + "," + n.absY + "," + n.absW + "," + n.absH) + "\n";
    }
    writeText(OUT + ".rects.txt", lines);
    writeBmp(OUT + ".bmp", frame());
    say("toggles=" + int(st.toggles) + " opens=" + String(model.opens) + " open=" + model.open);

    // ---- 1: the MULTI set decides which panels exist -------------------
    if (node("pa") == null) bad("pa (section 0 of the open set) is missing");
    if (node("pb") != null) bad("pb (section 1, CLOSED) is mounted");
    if (node("pc") == null) bad("pc (section 2 of the open set) is missing");
    // Single mode beside it: only its own index is open.
    if (node("px") == null) bad("px (single mode, activeIndex 0) is missing");
    if (node("py") != null) bad("py (single mode, closed) is mounted");

    // ---- 2: three header fills, two open -------------------------------
    var b:BitmapData = frame();
    var m2:UiNode = node("m");
    if (m2 != null)
    {
        for (var k:int = 0; k < 3; k++)
        {
            var h:UiNode = node("m:h" + k);
            if (h == null) continue;
            var y:int = h.absY + int(h.absH / 2);
            want(b, m2.absX + 3, y, k == 1 ? 0xF3F4F6 : 0xDBEAFE, "header " + k + " fill");
        }
    }
    if (node("pa") == null || node("pc") == null) { finish(); return; }

    // ---- 3: a click adds ONE member -----------------------------------
    say("-- click B (section 1)");
    clickHeader("m", 1);
    churn();
    if (model.opens.length != 3) bad("after opening section 1 the set is " + String(model.opens) + ", not three members");
    if (node("pb") == null) bad("section 1 was opened but its panel is not mounted");
    if (node("pa") == null || node("pc") == null) bad("opening section 1 CLOSED another section");
    if (int(st.last) != 1) bad("onToggle reported " + int(st.last) + " for a click on section 1");

    // ---- 4: a click removes ONE member --------------------------------
    say("-- click A (section 0, now open)");
    clickHeader("m", 0);
    churn();
    if (node("pa") != null) bad("section 0 was toggled off but its panel is still mounted");
    if (node("pb") == null || node("pc") == null) bad("closing section 0 closed another section: " + String(model.opens));
    if (int(st.last) != 0) bad("onToggle reported " + int(st.last) + " for a click on section 0");

    // ---- 5: [2,0] is the same state as [0,2] --------------------------
    // The author rebuilds the array (a fresh object per render) in a different
    // order; membership is what counts, so nothing may close.
    say("-- author writes [2,0]");
    var unsorted:Array = [2, 0];
    model.opens = unsorted;
    churn();
    if (node("pa") == null || node("pc") == null) bad("[2,0] did not open both sections: " + String(model.opens));
    if (node("pb") != null) bad("[2,0] opened section 1, which is not listed");
    if (model.opens.length != 2) bad("the widget rewrote the author's array: " + String(model.opens));
    if (model.opens[0] != 2) bad("the widget reordered the author's array: " + String(model.opens));

    // ---- 6: what we WRITE back is canonical ---------------------------
    // Section 2 is open, so this click closes it: [2,0] -> [0] (ascending).
    say("-- click C (section 2, open)");
    clickHeader("m", 2);
    churn();
    if (model.opens.length != 1 || model.opens[0] != 0)
        bad("closing section 2 from [2,0] left " + String(model.opens) + ", not [0]");
    if (node("pc") != null) bad("section 2 is closed in the array but its panel is mounted");
    if (node("pa") == null) bad("section 0 is open in the array but its panel is not mounted");

    // ---- 7: single mode is unchanged ----------------------------------
    say("-- single: click X (section 0, open) then Y");
    clickHeader("s", 0);
    churn();
    if (node("px") != null) bad("single mode did not close its open section");
    clickHeader("s", 1);
    churn();
    if (node("py") == null) bad("single mode did not open section 1");
    if (node("px") != null) bad("single mode opened two sections at once");

    writeBmp(OUT + ".bmp", frame());
    phaseThrows();
    finish();
}

// ==================== phase 2: the refused combinations ====================
// The guards run at DESCRIBE time, so they are driven here through the factories
// and caught -- the same call an author's render() would make.
function threw(mode:String, opts:Object, what:String):void
{
    var hit:Boolean = false;
    var msg:String = "";
    try
    {
        accordion([{ title: "A", content: box({}) }], opts);
    }
    catch (e:Error)
    {
        hit = true;
        msg = e.message;
    }
    if (!hit) bad(what + " did NOT throw");
    else say("refused: " + msg);

    // And it must be the GUARD that fired, not a null-deref on the way there: the
    // message names the option that was refused.
    if (hit && msg == "") bad(what + " threw an error with no message");
}

function phaseThrows():void
{
    threw("multi", { mode: "multi", activeIndex: 0 },
        "mode multi + activeIndex");
    threw("single", { mode: "single", openIndices: [0] },
        "mode single + openIndices");
    threw("single", { openIndices: [0] },
        "default mode + openIndices");
    threw("bogus", { mode: "bogus" },
        "an unknown mode");
}

function finish():void
{
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
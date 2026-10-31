// probes/widgets/appbar/Main.as -- the page header: three slots, and a large title
// that the AUTHOR collapses from their own scroll position.
//
// Output prefix MUST equal the directory name (`appbar`).
//
// WHAT IS BEING MEASURED. A bar is easy to fudge: draw a rectangle, put a string
// in it, call it a header. So this probe measures the three things that are
// actually decisions:
//
//   * THE SLOTS ARE LAYOUT, not magic -- leading at the left padding edge, trailing
//     flush against the right one, and the title centred in what is LEFT BETWEEN
//     them (150 in a 320px bar: a 40px leading, a 60px trailing, 8px gaps and 12px
//     padding on both sides), vertically centred in the row;
//   * `collapse` IS ONE NUMBER -- the bar's height is `barHeight + largeExtra -
//     collapse` at every step (0, 20, 40, fully closed and an overshoot), the extra
//     row is GONE when the bar is closed, and a NON-large bar ignores `collapse`
//     entirely;
//   * THE COLLAPSING AREA IS CLIPPED -- at collapse 40 the extra row is 8px tall
//     while the title is ~31px, so the title's own background would hang over the
//     page below; the pixel just under the bar must be the page's, not the title's;
//   * A SLOT MAY BE A LIST -- `trailing: [a, b]` is what the gallery's own example
//     passes, and an implementation that only took a Node dropped it silently (the
//     slot's box was empty and nothing said so);
//   * THE NOTCH IS PADDING, NOT HEIGHT -- with a 47pt safe-area inset the bar is
//     103 tall, the slots start at 47+16, and the pixel in the inset band is the
//     BAR's own background (so the notch is covered, not left white).
//
// Hand arithmetic (window 320x260, root column, no padding, white):
//
//   bar           (0,0,320,56) compact;  (0,0,320,104) when large and open
//   lead          (12,16,40,24)          -- 12px padding, (56-24)/2 = 16
//   trail         (248,16,60,24)         -- 320-12-60
//   title centre  x = 150, y = 28        -- mid box 60..240
//   extra row     (0,56,320,48 -> 8)     -- largeExtra 48 minus collapse
//   page          (0,56,320,204)         -- the rest, #EEEEEE
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
var H:int = 260;
var OUT:String = "appbar";
var TITLE_BG:uint = 0x00FF00;
// A bar colour that is NOT the root's white: the safe-area phase has to prove the
// inset band is the bar's, and "white on white" proves nothing.
var BAR_BG:uint = 0x123456;

class FakeEnv extends EnvBase
{
    public function FakeEnv(t:Number, r:Number, b:Number, l:Number):void
    {
        super();
        this.setSafeArea(t, r, b, l);
    }
}

class AppModel extends Observable
{
    public var large:Boolean = false;
    public var collapse:Number = 0;
    public var strMode:Boolean = false;   // render the title as a plain String
    public var multi:Boolean = false;     // render `trailing` as a LIST of two nodes
}

var model:AppModel = new AppModel();
var view:BarProbe = null;
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;

class BarProbe extends View
{
    public var model:AppModel;

    private static const ROOT:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", size: [320, 260], background: 0xFFFFFF
    });
    private static const LEAD:StyleRefinement = StyleRefinement.from({
        size: [40, 24], background: 0xAA0000
    });
    private static const TRAIL:StyleRefinement = StyleRefinement.from({
        size: [60, 24], background: 0x0000AA
    });
    // The two actions of phase 9. 24 + 8 (gap) + 28 = 60, so the LIST lands in
    // exactly the box the single slot had -- the assertion is about the children,
    // not about a different geometry.
    private static const ACT1:StyleRefinement = StyleRefinement.from({
        size: [24, 24], background: 0x00AA00
    });
    private static const ACT2:StyleRefinement = StyleRefinement.from({
        size: [28, 24], background: 0xAA00AA
    });
    // The title is a solid GREEN box, not a run of text: every pixel assertion in
    // this probe samples inside the title's box, and glyph coverage would make the
    // sampled colour depend on the host's font (anti-aliased green at one point,
    // page colour two pixels away). The text path is covered by phase 8, which
    // renders the title as a String.
    private static const TTL:StyleRefinement = StyleRefinement.from({
        size: [70, 32], background: 0x00FF00
    });

    public function BarProbe(m:AppModel):void
    {
        super();
        this.model = m;
    }

    override public function render():Node
    {
        // if/else, not a ternary: the two branches are a String and a Node, and a
        // conditional that unifies them to String would hand the factory the string
        // "[object TextNode]" (and the keyed node would never be mounted).
        var title:Object = null;
        if (model.strMode) title = "Inbox";
        else title = box({ key: "ttl", style: TTL });
        // A LIST, passed as an Array -- exactly the shape the gallery's appBar page
        // documents (and used to lose).
        var right:Object = null;
        if (model.multi)
        {
            right = [ box({ key: "act1", style: ACT1 }), box({ key: "act2", style: ACT2 }) ];
        }
        else
        {
            right = box({ key: "trail", style: TRAIL });
        }
        return column({ key: "root", style: ROOT }, [
            appBar({ key: "bar", large: model.large, collapse: model.collapse,
                     title: title,
                     leading: box({ key: "lead", style: LEAD }),
                     trailing: right,
                     // The opt is what makes the notch exist for this bar; without
                     // it the insets are never folded anywhere (E2: one place, no
                     // scattering).
                     safeArea: "top",
                     style: StyleRefinement.from({ background: BAR_BG }) })
        ]);
    }
}

view = new BarProbe(model);
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

var problems:String = "";
var log:String = "";

function say(s:String):void
{
    log = log + s + "\n";
}

function fail(s:String):void
{
    problems = problems + s + "; ";
}

function check(cond:Boolean, s:String):void
{
    if (!cond) fail(s);
}

function frame():BitmapData
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

// A Vector of children throws on an out-of-range index, and the point of these
// assertions is to REPORT a missing row, not to die on it.
function childAt(n:UiNode, i:int):UiNode
{
    if (n == null) return null;
    if (i < 0 || i >= n.children.length) return null;
    return n.children[i];
}

function node(k:String):UiNode
{
    return app.findByKey(k);
}

function rectOf(n:UiNode):String
{
    return n.absX + "," + n.absY + "," + n.absW + "," + n.absH;
}

function want(what:String, n:UiNode, x:Number, y:Number, w:Number, h:Number):void
{
    if (n == null) { fail(what + " is missing"); return; }
    if (n.absX != x || n.absY != y || n.absW != w || n.absH != h)
        fail(what + " is " + rectOf(n) + " not " + x + "," + y + "," + w + "," + h);
}

function barH():Number
{
    var b:UiNode = node("bar");
    return b == null ? -1 : b.absH;
}

setTimeout(ready, 900);
stage.showWindow(W, H, "probe appbar");

// ---- phase 1: the compact bar and its three slots -----------------------
function ready():void
{
    var nav:UiNode = node("bar");
    if (nav == null) { fail("the appBar never mounted"); finish(); return; }

    want("bar", node("bar"), 0, 0, 320, 56);
    want("lead", node("lead"), 12, 16, 40, 24);
    want("trail", node("trail"), 248, 16, 60, 24);

    var t:UiNode = node("ttl");
    if (t == null) { fail("the title node is missing"); finish(); return; }
    say("title rect " + rectOf(t));
    var cx:Number = t.absX + t.absW / 2;
    var cy:Number = t.absY + t.absH / 2;
    check(Math.abs(cx - 150) <= 0.5, "the title centre is at x=" + cx
        + ", want 150 (centred between the slots, NOT the bar's 160)");
    check(Math.abs(cy - 28) <= 0.5, "the title centre is at y=" + cy
        + ", want 28 (centred in a 56px row)");

    // The title paints green; the two samples are inside it, so the bar's own
    // drawing is being measured, not the layout's intention.
    var bd:BitmapData = frame();
    var inTitle:uint = rgbAt(bd, int(t.absX + 2), int(t.absY + t.absH / 2));
    check(inTitle == TITLE_BG, "the pixel inside the title is " + hex(inTitle)
        + ", want the title's own #00FF00");

    model.large = true;
    view.invalidate(Dirty.ALL);
    setTimeout(phaseOpen, 250);
}

// ---- phase 2: large, nothing collapsed ---------------------------------
function phaseOpen():void
{
    want("bar", node("bar"), 0, 0, 320, 104);
    var b:UiNode = node("bar");
    check(b != null && b.children.length == 2,
        "an open large bar has " + (b == null ? "?" : String(b.children.length))
        + " rows, want 2 (the compact row and the large title area)");
    var extra:UiNode = childAt(b, 1);
    want("the large title area", extra, 0, 56, 320, 48);
    var big:UiNode = node("ttl");
    want("the title top-left", big, 12, 56, big == null ? 0 : big.absW, big == null ? 0 : big.absH);
    var bd:BitmapData = frame();
    var g:uint = rgbAt(bd, 15, 60);
    check(g == TITLE_BG, "the pixel inside the large title is " + hex(g)
        + ", want #00FF00 (the title sits BELOW the compact row)");
    model.collapse = 20;
    view.invalidate(Dirty.ALL);
    setTimeout(phaseHalf, 250);
}

// ---- phase 3: half collapsed -------------------------------------------
function phaseHalf():void
{
    check(barH() == 84, "a half-collapsed bar is " + barH() + " tall, want 84 (56+48-20)");
    var b:UiNode = node("bar");
    want("the large title area", childAt(b, 1), 0, 56, 320, 28);
    // The title itself does NOT move: the area shrinks from the bottom.
    want("the title top", node("ttl"), 12, 56, node("ttl").absW, node("ttl").absH);
    model.collapse = 40;
    view.invalidate(Dirty.ALL);
    setTimeout(phaseClipped, 250);
}

// ---- phase 4: the title is taller than its row -> it must be CUT --------
function phaseClipped():void
{
    check(barH() == 64, "a bar 8px from closed is " + barH() + " tall, want 64 (56+8)");
    var bd:BitmapData = frame();
    // 56..64 is the visible slice of the title; 70 is under the bar and inside the
    // title's 32px box, so it is only the ROOT's white if the bar clips. (The bar is
    // the root's only child on purpose: a sibling below it would paint OVER the
    // spill and the assertion would pass with no clip at all -- measured, that is
    // exactly how the first version of this probe stayed green without one.)
    var above:uint = rgbAt(bd, 15, 60);
    var below:uint = rgbAt(bd, 15, 70);
    check(above == TITLE_BG, "the visible slice of the title is " + hex(above)
        + ", want #00FF00");
    check(below == 0xFFFFFF, "the pixel under the bar is " + hex(below)
        + ", want the root's #FFFFFF (an unclipped title hangs over the content)");
    model.collapse = 48;
    view.invalidate(Dirty.ALL);
    setTimeout(phaseClosed, 250);
}

// ---- phase 5: fully closed -> the compact title comes back --------------
function phaseClosed():void
{
    want("bar", node("bar"), 0, 0, 320, 56);
    check(node("bar").children.length == 1,
        "a closed bar still has " + node("bar").children.length
        + " rows, want 1 (the large area is not mounted at all)");
    // A LARGE bar keeps its title LEFT-aligned when it collapses (the mid box starts
    // at 12+40+8 = 60 and the title is 70 wide, so its centre is 95). Only the
    // compact bar centres it.
    var tn:UiNode = node("ttl");
    if (tn == null)
    {
        fail("the collapsed large bar mounted no title");
    }
    else
    {
        var cx:Number = tn.absX + tn.absW / 2;
        check(Math.abs(cx - 95) <= 0.5, "the collapsed large bar's title centre is at x=" + cx
            + ", want 95 (left-aligned at the mid box's start, NOT the compact 150)");
        var cy:Number = tn.absY + tn.absH / 2;
        check(Math.abs(cy - 28) <= 0.5, "the compact title centre is at y=" + cy + ", want 28");
    }
    // An overshoot from a nudged list must clamp, not produce a negative row.
    model.collapse = 200;
    view.invalidate(Dirty.ALL);
    setTimeout(phaseOvershoot, 250);
}

// ---- phase 6: overshoot clamps -----------------------------------------
function phaseOvershoot():void
{
    want("bar", node("bar"), 0, 0, 320, 56);
    check(node("bar").children.length == 1, "an overshooting collapse mounted a second row");
    // ... and `collapse` means nothing without `large`.
    model.large = false;
    model.collapse = 30;
    view.invalidate(Dirty.ALL);
    setTimeout(phaseNotLarge, 250);
}

// ---- phase 7: a compact bar ignores collapse ---------------------------
function phaseNotLarge():void
{
    want("bar", node("bar"), 0, 0, 320, 56);
    model.collapse = 0;
    model.strMode = true;
    view.invalidate(Dirty.ALL);
    setTimeout(phaseString, 250);
}

// ---- phase 8: a String title is wrapped into a text node ---------------
function phaseString():void
{
    want("bar", node("bar"), 0, 0, 320, 56);
    check(node("ttl") == null, "a String title still produced a keyed text node");
    var bar:UiNode = node("bar");
    var row:UiNode = childAt(bar, 0);
    var mid:UiNode = childAt(row, 1);          // row = [lead, mid, trail]
    var tn:UiNode = childAt(mid, 0);
    if (tn == null) { fail("a String title mounted no text node"); finish(); return; }
    var d:TextNode = TextNode(tn.desc);
    check(d.content == "Inbox", "the wrapped title reads \"" + d.content + "\", want \"Inbox\"");
    check(tn.absY >= 0 && tn.absH > 0, "the wrapped title has no box");
    model.strMode = false;
    model.multi = true;
    view.invalidate(Dirty.ALL);
    setTimeout(phaseList, 250);
}

// ---- phase 9: a slot given as a LIST -----------------------------------
function phaseList():void
{
    want("bar", node("bar"), 0, 0, 320, 56);
    var bar:UiNode = node("bar");
    var r:UiNode = childAt(bar, 0);
    check(r != null && r.children.length == 3,
        "the bar row has " + (r == null ? "?" : String(r.children.length))
        + " slots with a list trailing, want 3 (lead, mid, the list)");
    var slot:UiNode = childAt(r, 2);
    want("the trailing list", slot, 248, 16, 60, 24);
    check(slot != null && slot.children.length == 2,
        "the trailing list mounted " + (slot == null ? "?" : String(slot.children.length))
        + " nodes, want 2 -- `trailing: [a, b]` used to be dropped entirely");
    want("the first action", node("act1"), 248, 16, 24, 24);
    want("the second action", node("act2"), 280, 16, 28, 24);
    var bd:BitmapData = frame();
    check(rgbAt(bd, 250, 20) == 0x00AA00, "the first action's pixel is "
        + hex(rgbAt(bd, 250, 20)) + ", want #00AA00");
    check(rgbAt(bd, 300, 20) == 0xAA00AA, "the second action's pixel is "
        + hex(rgbAt(bd, 300, 20)) + ", want #AA00AA");
    model.multi = false;
    view.invalidate(Dirty.ALL);
    setTimeout(phaseNotch, 250);
}

// ---- phase 10: the notch is padding, and the bar paints it --------------
function phaseNotch():void
{
    want("bar", node("bar"), 0, 0, 320, 56);
    app.bindEnv(new FakeEnv(47, 0, 0, 0));
    setTimeout(phaseNotchShown, 250);
}

function phaseNotchShown():void
{
    want("bar", node("bar"), 0, 0, 320, 103);
    want("lead", node("lead"), 12, 63, 40, 24);
    want("trail", node("trail"), 248, 63, 60, 24);
    var bd:BitmapData = frame();
    var band:uint = rgbAt(bd, 10, 10);
    check(band == BAR_BG, "the pixel in the notch band is " + hex(band)
        + ", want the bar's own " + hex(BAR_BG) + " (the inset must be PADDING, not a gap)");
    // ... and back to a desk-shaped env: the fold is reversible, not a one-way edit.
    app.bindEnv(new DesktopEnv(1));
    setTimeout(phaseNoNotch, 250);
}

function phaseNoNotch():void
{
    want("bar", node("bar"), 0, 0, 320, 56);
    want("lead", node("lead"), 12, 16, 40, 24);
    finish();
}

function finish():void
{
    if (problems == "" ) check(barH() == 56, "the final frame is not the compact bar");
    var bd:BitmapData = frame();
    var names:Array = ["root", "bar", "lead", "trail"];
    var lines:String = "";
    for (var i:int = 0; i < names.length; i++)
    {
        var n:UiNode = app.findByKey(names[i]);
        if (n == null) { lines = lines + names[i] + " MISSING\n"; continue; }
        lines = lines + names[i] + " " + rectOf(n) + "\n";
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

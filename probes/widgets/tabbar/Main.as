// probes/widgets/tabbar/Main.as -- the bottom navigation bar: equal cells, one
// selected, and a tap that reports WHICH cell without the factory guessing.
//
// Output prefix MUST equal the directory name (`tabbar`).
//
// WHAT IS BEING MEASURED:
//
//   * THE CELLS ARE EQUAL AND THEY FILL THE BAR -- 320/3 each, three of them, and
//     the last one's right edge is the window's (this is what `flexGrow: 1` means
//     and what a variable-length label strip would break);
//   * THE SELECTED STATE IS THE TINT -- read from `resolved.text.color` on each
//     label, compared against the THEME tokens the factory used, so a bar that
//     forgot the patch (or applied it to the wrong cell) is visible;
//   * A TAP REPORTS ITS OWN INDEX -- this is the AS3 loop-closure trap the factory
//     has to avoid: a handler written inline in `for (var i ...)` would report the
//     LAST index for every cell, and this probe's three taps are exactly that test;
//   * A RE-TAP OF THE CURRENT TAB IS STILL REPORTED (so "scroll this section to the
//     top" stays expressible);
//   * `barHeight` and `selectedIndex: -1` behave;
//   * THE TAB COUNT IS DATA -- `items` may shrink (a tab can disappear), and the
//     reconciler must drop the stale cell rather than leave it painted in the bar;
//   * A NODE ICON IS THE AUTHOR'S -- an `icon:` that is a Node is mounted as built,
//     so the bar's own tint cannot silently recolour it;
//   * THE HOME INDICATOR IS PADDING -- with a 34pt safe-area inset the bar is 90
//     tall and the cells still 56, so the band under them is the BAR's background.
//
// Hand arithmetic (window 320x260, root column, white, one spacer then the bar):
//
//   bar         (0,204,320,56)      -- object and slots at the BOTTOM
//   cells       106.67 wide each, at x = 0, 106.67, 213.33
//   t0 centre   (53,232)  t1 (160,232)  t2 (266,232)
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
var OUT:String = "tabbar";
var BAR_H:Number = 56;
var BAR_BG:uint = 0x222222;

class TabModel extends Observable
{
    public var sel:int = 1;
    public var barH:Number = 56;
    public var two:Boolean = false;       // items shrinks to two tabs
    public var nodeIcon:Boolean = false;  // t0's icon is a Node instead of path data
    public var longLabel:Boolean = false; // t0's label is far wider than its cell
}

class FakeEnv extends EnvBase
{
    public function FakeEnv(t:Number, r:Number, b:Number, l:Number):void
    {
        super();
        this.setSafeArea(t, r, b, l);
    }
}

var model:TabModel = new TabModel();
var view:BarView = null;
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;

var picks:Array = [];   // every index onSelect was handed, in order

function onPick(i:int):void
{
    picks.push(i);
    model.sel = i;
    view.invalidate(Dirty.ALL);
}

function items():Array
{
    if (model.two)
    {
        return [
            { key: "t0", label: model.longLabel ? "Conversations, notifications and account settings" : "One",
              icon: iconFor() },
            { key: "t1", label: "Two" }
        ];
    }
    return [
        { key: "t0", label: "One",   icon: iconFor() },
        { key: "t1", label: "Two",   icon: "M4 12 A8 8 0 1 0 12 4 Z" },
        { key: "t2", label: "Three", icon: "M4 20 L12 4 L20 20 Z" }
    ];
}

// A Node icon is mounted as the author built it: a solid box with an author
// colour the bar must not touch (it tints the STRING form, where it owns the glyph).
function iconFor():Object
{
    if (model.nodeIcon)
    {
        return box({ key: "myicon", style: StyleRefinement.from({
            size: [20, 20], background: 0x00AA00 }) });
    }
    return "M4 4 H20 V20 H4 Z";
}

class BarView extends View
{
    public var model:TabModel;

    private static const ROOT:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", size: [320, 260], background: 0xFFFFFF
    });
    private static const SPACER:StyleRefinement = StyleRefinement.from({ flexGrow: 1 });
    private static const BAR:StyleRefinement = StyleRefinement.from({ background: 0x222222 });

    public function BarView(m:TabModel):void { super(); this.model = m; }

    override public function render():Node
    {
        return column({ key: "root", style: ROOT }, [
            box({ key: "spacer", style: SPACER }),
            tabBar({ key: "bar", style: BAR, barHeight: model.barH,
                     selectedIndex: model.sel, items: items(), onSelect: onPick,
                     safeArea: "bottom" })
        ]);
    }
}

view = new BarView(model);
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

function node(k:String):UiNode
{
    return app.findByKey(k);
}

function childAt(n:UiNode, i:int):UiNode
{
    if (n == null) return null;
    if (i < 0 || i >= n.children.length) return null;
    return n.children[i];
}

function rectOf(n:UiNode):String
{
    return n.absX + "," + n.absY + "," + n.absW + "," + n.absH;
}

// A Vector of children throws on an out-of-range index, and the point of these
// assertions is to REPORT a missing cell, not to die on it.
function want(what:String, n:UiNode, x:Number, y:Number, w:Number, h:Number):void
{
    if (n == null) { fail(what + " is missing"); return; }
    if (n.absX != x || n.absY != y || n.absW != w || n.absH != h)
        fail(what + " is " + rectOf(n) + " not " + x + "," + y + "," + w + "," + h);
}

// The icon is the cell's FIRST child; its colour lives on the IconNode (an icon
// does not read the inherited text colour -- it is a filled glyph, not text), which
// is why the bar tints it where it BUILDS it, from the path string.
function iconColor(cellKey:String):Number
{
    var cell:UiNode = node(cellKey);
    if (cell == null) return -1;
    var ic:UiNode = childAt(cell, 0);
    if (ic == null) return -2;
    var d:IconNode = ic.desc as IconNode;
    if (d == null) return -3;
    return d.color;
}

// The label is the cell's LAST child (the icon, when present, comes first).
function labelColor(cellKey:String):Number
{
    var cell:UiNode = node(cellKey);
    if (cell == null) return -1;
    var lab:UiNode = childAt(cell, cell.children.length - 1);
    if (lab == null) return -2;
    if (lab.resolved.text == null) return -3;
    return lab.resolved.text.color;
}

setTimeout(ready, 900);
stage.showWindow(W, H, "probe tabbar");

function ready():void
{
    var bar:UiNode = node("bar");
    if (bar == null) { fail("the tabBar never mounted"); finish(); return; }

    if (bar.absX != 0 || bar.absY != 204 || bar.absW != 320 || bar.absH != BAR_H)
        fail("bar is " + rectOf(bar) + " not 0,204,320,56");

    // (a) THREE EQUAL CELLS THAT FILL THE BAR. Tolerance, because 320/3 is not an
    // integer and the engine may distribute the remainder.
    var want:Number = 320 / 3;
    var x:Number = 0;
    for (var i:int = 0; i < 3; i++)
    {
        var cell:UiNode = node("t" + i);
        if (cell == null) { fail("cell t" + i + " is missing"); continue; }
        if (Math.abs(cell.absX - x) > 1 || Math.abs(cell.absW - want) > 1)
            fail("cell t" + i + " is " + rectOf(cell) + ", want x=" + x + " w=" + want);
        if (cell.absY != 204 || cell.absH != BAR_H)
            fail("cell t" + i + " is " + rectOf(cell) + ", want y=204 h=56 (stretched)");
        x = x + want;
    }
    var last:UiNode = node("t2");
    if (last != null && Math.abs(last.absX + last.absW - 320) > 1)
        fail("the last cell ends at " + (last.absX + last.absW) + ", want 320");

    // (b) THE TINT IS THE SELECTED STATE. model.sel is 1.
    var t2:ThemeTokens = Theme.tokens();
    check(labelColor("t1") == t2.accent, "the selected label is " + hex(labelColor("t1"))
        + ", want the accent " + hex(t2.accent));
    check(labelColor("t0") == t2.textMuted, "an unselected label is " + hex(labelColor("t0"))
        + ", want the muted " + hex(t2.textMuted));
    check(labelColor("t2") == t2.textMuted, "an unselected label is " + hex(labelColor("t2"))
        + ", want the muted " + hex(t2.textMuted));

    // (b2) THE ICON IS TINTED TOO, and it is tinted on the IconNode (see iconColor).
    var cell1:UiNode = node("t1");
    check(cell1 != null && cell1.children.length == 2,
        "a cell with an icon has " + (cell1 == null ? "?" : String(cell1.children.length))
        + " children, want 2 (icon + label)");
    check(iconColor("t1") == t2.accent, "the selected icon is " + hex(iconColor("t1"))
        + ", want the accent " + hex(t2.accent));
    check(iconColor("t0") == t2.textMuted, "an unselected icon is " + hex(iconColor("t0"))
        + ", want the muted " + hex(t2.textMuted));

    var bd:BitmapData = frame();
    check(rgbAt(bd, 10, 210) == BAR_BG, "the pixel inside the bar is "
        + hex(rgbAt(bd, 10, 210)) + ", want the bar's own #222222");

    stage.dispatchMouse(53, 232, "click");
    setTimeout(afterTap0, 200);
}

// (c) EACH CELL REPORTS ITS OWN INDEX.
function afterTap0():void
{
    check(picks.length == 1 && int(picks[0]) == 0,
        "tapping cell 0 reported " + picks.length + " picks, last "
        + (picks.length == 0 ? "-" : String(picks[picks.length - 1])) + ", want [0]");
    stage.dispatchMouse(266, 232, "click");
    setTimeout(afterTap2, 200);
}

function afterTap2():void
{
    check(picks.length == 2 && int(picks[1]) == 2,
        "tapping cell 2 reported the index "
        + (picks.length < 2 ? "-" : String(picks[1])) + ", want 2");
    // (d) A RE-TAP OF THE CURRENT TAB (2, after the last pick) IS STILL REPORTED.
    stage.dispatchMouse(266, 232, "click");
    setTimeout(afterRetap, 200);
}

function afterRetap():void
{
    check(picks.length == 3 && int(picks[2]) == 2,
        "re-tapping the current tab did not report (" + picks.length + " picks)");
    // ... and the tint followed the model: 2 is now the accent, 1 is muted again.
    var t2:ThemeTokens = Theme.tokens();
    check(labelColor("t2") == t2.accent, "after the tap the selected label is "
        + hex(labelColor("t2")) + ", want the accent");
    check(labelColor("t1") == t2.textMuted, "after the tap the previous label is "
        + hex(labelColor("t1")) + ", want muted");
    // (e) NOTHING SELECTED.
    model.sel = -1;
    view.invalidate(Dirty.ALL);
    setTimeout(afterNone, 200);
}

function afterNone():void
{
    var t2:ThemeTokens = Theme.tokens();
    check(labelColor("t0") == t2.textMuted && labelColor("t1") == t2.textMuted
        && labelColor("t2") == t2.textMuted,
        "with selectedIndex -1 a label is still accented");
    // (f) A TALLER BAR: the strip grows and the bar keeps sitting on the bottom.
    model.sel = 1;
    model.barH = 72;
    view.invalidate(Dirty.ALL);
    setTimeout(afterTall, 200);
}

function afterTall():void
{
    var bar:UiNode = node("bar");
    if (bar.absH != 72 || bar.absY != 188)
        fail("a 72px bar is " + rectOf(bar) + ", want y=188 h=72");
    model.barH = 56;
    model.two = true;
    view.invalidate(Dirty.ALL);
    setTimeout(phaseShrink, 250);
}

// (g) `items` SHRINKS: the third cell must be gone, not merely invisible, and the
// surviving two must re-share the bar (160 each).
function phaseShrink():void
{
    want("bar", node("bar"), 0, 204, 320, 56);
    check(node("t2") == null, "the removed tab's cell is still mounted");
    want("cell t0", node("t0"), 0, 204, 160, 56);
    want("cell t1", node("t1"), 160, 204, 160, 56);
    model.nodeIcon = true;
    view.invalidate(Dirty.ALL);
    setTimeout(phaseNodeIcon, 250);
}

// (h) A NODE ICON IS THE AUTHOR'S: 20x20, centred in the cell, and its colour is
// not the tab tint.
function phaseNodeIcon():void
{
    var ic:UiNode = node("myicon");
    if (ic == null) { fail("the Node icon was not mounted (a String-only icon path drops it)"); finish(); return; }
    // HORIZONTALLY pinned (a 20px glyph centred in a 160px cell), vertically NOT:
    // the icon is the top half of a centred icon+label group, so its y is the font's
    // business. The colour sample uses the node's OWN rect for the same reason.
    check(ic.absX == 70 && ic.absW == 20 && ic.absH == 20,
        "the Node icon is " + rectOf(ic) + ", want x=70 w=20 h=20 (centred in the cell)");
    var lab:UiNode = childAt(node("t0"), 1);
    check(lab != null && lab.absY >= ic.absY + ic.absH,
        "the label does not sit under the Node icon");
    var bd:BitmapData = frame();
    var mx:int = int(ic.absX + ic.absW / 2);
    var my:int = int(ic.absY + ic.absH / 2);
    check(rgbAt(bd, mx, my) == 0x00AA00, "the Node icon's pixel is "
        + hex(rgbAt(bd, mx, my)) + ", want the author's #00AA00");
    var t2:ThemeTokens = Theme.tokens();
    check(labelColor("t0") == t2.textMuted, "de-selecting t0 did not mute its label");
    model.longLabel = true;
    view.invalidate(Dirty.ALL);
    setTimeout(phaseLongLabel, 250);
}

// (j) A LABEL TOO WIDE FOR ITS CELL IS TRUNCATED, NOT ALLOWED TO SPILL -- the cell
// is a flex share (~160px) and it does NOT clip, so a label laid out at its
// intrinsic width paints over the neighbouring tab. The label is therefore pinned
// to the cell's width and truncated by ellipsis; both halves are asserted (a box
// of the right width with an untrimmed run would still spill).
function phaseLongLabel():void
{
    var cell:UiNode = node("t0");
    var lab:UiNode = null;
    if (cell != null) lab = childAt(cell, cell.children.length - 1);
    if (lab == null) { fail("the long-label cell has no label child"); finish(); return; }
    check(lab.absX == 0 && lab.absW == 160,
        "the label box is " + rectOf(lab)
        + ", want x=0 w=160 (the cell's width, so ellipsis has something to truncate to)");
    // The run is wider than the box (the phase would be vacuous otherwise), and the
    // painted text is the TRUNCATED one: a plain clip would leave `tf.text` equal to
    // the source, so this separates "ellipsis" from "the field happens to clip".
    if (lab.tf == null) fail("the label has no TextField");
    else
    {
        var src:String = "Conversations, notifications and account settings";
        check(lab.textContent == src, "the label content is \"" + lab.textContent
            + "\", want the long one (the phase is not exercising truncation)");
        check(lab.tf.text != src, "the long label was not truncated at all");
        check(lab.tf.text.length < src.length, "the painted label is "
            + lab.tf.text.length + " chars, want fewer than the source's " + src.length);
        check(lab.tf.textWidth <= lab.absW + 1,
            "the painted run is " + lab.tf.textWidth + "px in a " + lab.absW + "px box");
    }
    var mid:int = int(lab.absY + lab.absH / 2);
    var bd:BitmapData = frame();
    // x=170 is inside t1's cell but outside t0's label box; the neighbour's own
    // label is centred at 240 and cannot reach it.
    check(rgbAt(bd, 170, mid) == BAR_BG, "the pixel just past the cell boundary is "
        + hex(rgbAt(bd, 170, mid)) + ", want the bar's " + hex(BAR_BG)
        + " (the over-long label painted into the next tab)");
    model.longLabel = false;
    app.bindEnv(new FakeEnv(0, 0, 34, 0));
    setTimeout(phaseHomeIndicator, 250);
}

// (i) THE HOME INDICATOR IS PADDING: 56 + 34 = 90 tall, cells still 56 at the top of
// the bar, and the band UNDER them is the bar's own background (not the root's).
function phaseHomeIndicator():void
{
    want("bar", node("bar"), 0, 170, 320, 90);
    want("cell t0", node("t0"), 0, 170, 160, 56);
    var bd:BitmapData = frame();
    check(rgbAt(bd, 10, 250) == BAR_BG, "the pixel in the home-indicator band is "
        + hex(rgbAt(bd, 10, 250)) + ", want the bar's own " + hex(BAR_BG)
        + " (the inset must be PADDING, not a gap under the bar)");
    check(rgbAt(bd, 10, 150) == 0xFFFFFF, "the pixel above the bar is "
        + hex(rgbAt(bd, 10, 150)) + ", want the root's #FFFFFF");
    app.bindEnv(new DesktopEnv(1));
    model.nodeIcon = false;
    model.two = false;
    model.sel = 1;
    view.invalidate(Dirty.ALL);
    setTimeout(phaseBackToDesk, 250);
}

function phaseBackToDesk():void
{
    want("bar", node("bar"), 0, 204, 320, 56);
    check(node("t2") != null, "the third tab did not come back");
    if (node("t2") != null)
    {
        var last:UiNode = node("t2");
        check(Math.abs(last.absX + last.absW - 320) <= 1,
            "the three cells do not fill the bar again: the last one ends at "
            + (last.absX + last.absW));
    }
    finish();
}

function finish():void
{
    var bd:BitmapData = frame();
    var names:Array = ["root", "bar"];
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

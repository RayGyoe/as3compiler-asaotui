// probes/widgets/theme -- the 2026-10-27 theme batch: ONE tree, painted twice.
//
// Output prefix MUST equal the directory name (`theme`).
//
// WHAT THIS PROVES, AND WHY EACH PART IS WHERE IT IS.
//
// The theme layer has four ways to reach a pixel, and each one fails differently:
//
//   paint-time read   `Theme.tokens().x` inside a widget's paint. If the epoch were
//                     never bumped, or `UiApp` never repainted, these stay light --
//                     so the probe asserts the SAME points before and after.
//   factory-baked     A `StyleRefinement` built by a factory (the table's header fill,
//                     the page background). These can only follow if the theme switch
//                     also RE-DESCRIBES the tree; a repaint alone leaves them stale.
//                     The table header pixel and the page pixel are the only two
//                     points in this probe that can see that difference.
//   baseline          `Theme.controlDefault(kind)`, rebuilt by `setTheme`. A text
//                     input's outline and every text colour come from here. The
//                     button's resolved text colour is asserted through the NODE
//                     (light 0x202020 -> dark 0xE5E7EB) because that is what a paint
//                     reads, and the input's border through its resolved style --
//                     NOT through a pixel: a 1px control border is stroked across the
//                     boundary, so it lands as two half-covered columns (measured:
//                     #2D3644 over #111827, i.e. two 50% blends) and can never be an
//                     exact-pixel expectation.
//   overlay chrome    `OverlayChrome` bakes colours into static StyleRefinements, so
//                     it needs an explicit `rebuild()`. Asserted on the static field
//                     (0xF3F4F6 -> 0x1F2937), which is what a menu row paints.
//
// THE TWO THINGS THAT MUST NOT CHANGE, and are checked as such:
//   * the AUTHOR's own colours (the red box) -- a theme swap is not a licence to
//     override what the author wrote;
//   * the GEOMETRY. A palette swap that re-solved the layout would move rects, so all
//     thirteen rects are captured before the switch and compared after.
//
// HAND ARITHMETIC (window 560x360; root column, padding 16, gap 10, alignItems
// flex-start, root size 560x360):
//
//   btn  (16, 16,120,32)    sw   (16, 58,140,20)   bd  (16, 88, 48,20)
//   ch   (16,118, 60,24)    dv   (16,152,200, 1)   pg  (16,163,120,12)
//   keep (16,185, 60,20)    tbl  (16,215,260,52)   ti  (16,277,160,32)
//
//   y: 16 | +32+10 = 58 | +20+10 = 88 | +20+10 = 118 | +24+10 = 152 | +1+10 = 163
//      | +12+10 = 185 | +20+10 = 215 | +52+10 = 277
//
//   root  (0,0,560,360)  surface (0,0,560,360)  page (0,0,560,360)
//   THE TREE: root > [surface (absolute, inset 0), page > the nine widgets]. The
//   two wrappers exist so that every flow position is unchanged while the surface
//   stays out of the flow -- see render() for why it is built separately.
//
//   table: rowHeight 26, header on, grid on, two equal columns
//     hdr  (16,215,260,26)     h:0 (16,215,130,26)
//     r0   (16,241,260,26)     r0c0(16,241,130,26)
//
// PIXELS (each one sits in the widest gap of its widget, clear of glyphs, of the
// rounded corners and of the switch's knob -- an OFF switch parks its knob at local
// x 2..18, which is exactly where the first draft sampled and got white):
//
//                        light      dark        what it is
//   (400,340) page     #FFFFFF    #111827     root background (factory refresh)
//   (126, 32) btn      #F1F3F5    #1F2937     controlSurface, paint-time
//   ( 48, 68) switch   #D1D5DB    #4B5563     trackOff, paint-time (right of the knob)
//   ( 60, 98) badge    #DBEAFE    #1E3A8A     accentSoft, paint-time
//   ( 72,130) chip     #E5E7EB    #374151     surfaceSoft, paint-time
//   (100,152) divider  #E5E7EB    #374151     border, paint-time
//   ( 26,167) progress #2563EB    #60A5FA     accent (the filled half)
//   (126,167) progress #E5E7EB    #374151     track (the empty half)
//   ( 60,195) keep     #FF2D55    #FF2D55     the author's colour: unchanged
//   (116,228) table    #F3F4F6    #1F2937     surfaceMuted (factory-baked row style)
//   ( 60,241) table    #E5E7EB    #374151     border (the hairline under the header)
//   (116,254) table    #FFFFFF    #111827     the body row is transparent
//
// Protocol (tools/probe.cjs): dir name == output prefix; write <OUT>.rects.txt,
// <OUT>.bmp, <OUT>.done (PASS | FAIL <reason>).
import asaot.ui.*;
import asaot.ui.style.Style;
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

var W:int = 560;
var H:int = 360;
var OUT:String = "theme";

// ---- the expectations as DATA --------------------------------------------
// EVERY module-level initialiser must live ABOVE `stage.showWindow(...)`: the AOT's
// showWindow enters the window's run loop, so a `var x = [...]` written after it is
// never executed and the array is null at run time (found the hard way here -- the
// first four failures were a null POINTS_X, not a wrong colour).
//
// The table is used TWICE: the light pass verifies it in code (so a widget that
// ignores the switch fails AT the switch), and the dark pass writes the same BMP the
// harness compares against expect.json.
var POINTS_X:Array = [400, 126, 48, 60, 72, 100, 26, 126, 60, 116, 60, 116];
var POINTS_Y:Array = [340, 32, 68, 98, 130, 152, 167, 167, 195, 228, 241, 254];
var LIGHT:Array = [0xFFFFFF, 0xF1F3F5, 0xD1D5DB, 0xDBEAFE, 0xE5E7EB, 0xE5E7EB,
                   0x2563EB, 0xE5E7EB, 0xFF2D55, 0xF3F4F6, 0xE5E7EB, 0xFFFFFF];
var DARK:Array = [0x111827, 0x1F2937, 0x4B5563, 0x1E3A8A, 0x374151, 0x374151,
                  0x60A5FA, 0x374151, 0xFF2D55, 0x1F2937, 0x374151, 0x111827];
var NAMES:Array = ["page", "button", "switch", "badge", "chip", "divider", "progress fill",
                   "progress track", "author colour", "table header", "table grid",
                   "table body"];
var RECT_KEYS:Array = ["root", "surface", "page", "btn", "sw", "bd", "ch", "dv", "pg", "keep", "tbl",
                       "hdr", "h:0", "r0", "ti"];

class ThemeProbe extends View
{
    // The root carries NO colour: a const that pointed at the palette would be
    // captured once and could never follow a swap.
    private static const ROOT:StyleRefinement = StyleRefinement.from({ size: [560, 360] });
    // The page carries the flow, never the colour: a const cannot follow a swap.
    private static const PAGE:StyleRefinement = StyleRefinement.from({
        size: [560, 360], padding: 16, gap: 10, alignItems: "flex-start"
    });
    public static const BTN:StyleRefinement = StyleRefinement.from({ size: [120, 32] });
    private static const SW:StyleRefinement = StyleRefinement.from({ size: [140, 20] });
    private static const BD:StyleRefinement = StyleRefinement.from({ size: [48, 20] });
    private static const CH:StyleRefinement = StyleRefinement.from({ size: [60, 24] });
    private static const DV:StyleRefinement = StyleRefinement.from({ size: [200, 1] });
    private static const PG:StyleRefinement = StyleRefinement.from({ size: [120, 12] });
    // The AUTHOR's colour, deliberately not in any palette.
    private static const KEEP:StyleRefinement = StyleRefinement.from({
        size: [60, 20], background: 0xFF2D55
    });
    private static const TB:StyleRefinement = StyleRefinement.from({ size: [260, 52] });
    private static const TI:StyleRefinement = StyleRefinement.from({ size: [160, 32] });

    public function ThemeProbe():void { super(); }

    override public function render():Node
    {
        // ★ EVERY STYLE POINTER IN THIS TREE IS STABLE. The root and the page are
        //   consts, so the describe pass hands the reconciler the very same
        //   refinements it saw last time: no node re-resolves because its pointer
        //   moved, and the inherited-subset cascade never fires. The tree can then
        //   ONLY follow a theme swap through UiApp.markThemeDirty -- which is the
        //   belt this probe exists to test. (Measured: with a per-render page style
        //   the cascade alone saves it and removing markThemeDirty stays invisible.
        //   The mutation suite pins this: M2 is caught only because of this shape.)
        //
        // THE ONE MOVING POINTER is the surface below, and it is the documented way
        // to make a factory-baked refinement follow a swap: rebuild it from the
        // palette on every render. It is ABSOLUTE with inset 0 so it sits under the
        // page without taking part in the column flow -- the page and every widget
        // keep the rects in the header of this file. That split is what separates
        // "the palette was copied" from "the tree was re-described"; M7 removes the
        // describe and this surface is what goes red.
        var surfaceStyle:StyleRefinement = StyleRefinement.from({
            position: "absolute", inset: 0, background: Theme.tokens().surface
        });
        return column({ key: "root", style: ROOT, ariaName: "theme probe" }, [
            box({ key: "surface", style: surfaceStyle }),
            column({ key: "page", style: PAGE }, [
                button({ key: "btn", label: "Run", style: BTN }),
                toggle("Off", { key: "sw", style: SW }),
                badge("3", { key: "bd", tone: "info", style: BD }),
                chip("Tag", { key: "ch", style: CH }),
                divider({ key: "dv", style: DV }),
                progress("", { key: "pg", value: 0.5, style: PG }),
                // The author-coloured box is also the CLICK TARGET of phase 3: a `box`
                // is a button, and its own background is what makes it hittable.
                box({ key: "keep", style: KEEP, onClick: clickToDark }),
                table([{ key: "name", title: "Name" }, { key: "qty", title: "Qty" }],
                      [{ name: "A", qty: 1 }],
                      { key: "tbl", style: TB, rowHeight: 26, grid: true,
                        header: true, stripes: false }),
                textField({ key: "ti", style: TI })
            ])
        ]);
    }
}

var view:ThemeProbe = new ThemeProbe();
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

var problems:String = "";
var log:String = "";
var rectsBefore:String = "";
var btnBefore:UiNode = null;
var epochBeforeLight:int = 0;

setTimeout(lightPhase, 900);
stage.showWindow(W, H, "probe theme");

function say(s:String):void { log = log + s + String.fromCharCode(10); trace(s); }
function bad(s:String):void { problems = problems + s + "; "; }
function check(cond:Boolean, s:String):void { if (!cond) bad(s); }

function frame():BitmapData
{
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    return bd;
}

function rgbAt(bd:BitmapData, x:int, y:int):uint { return bd.getPixel(x, y) & 0xFFFFFF; }

function hex(c:uint):String
{
    var s:String = c.toString(16);
    while (s.length < 6) s = "0" + s;
    return "#" + s;
}

function checkPoints(want:Array, when:String):void
{
    var bd:BitmapData = frame();
    for (var i:int = 0; i < POINTS_X.length; i++)
    {
        var got:uint = rgbAt(bd, int(POINTS_X[i]), int(POINTS_Y[i]));
        if (got != uint(want[i]))
            bad(when + ": " + NAMES[i] + " at (" + POINTS_X[i] + "," + POINTS_Y[i] + ") is "
                + hex(got) + " not " + hex(uint(want[i])));
    }
    say(when + ": " + POINTS_X.length + " points checked");
}

function rectsNow():String
{
    var s:String = "";
    for (var i:int = 0; i < RECT_KEYS.length; i++)
    {
        var n:UiNode = app.findByKey(RECT_KEYS[i]);
        if (n == null) { bad("no node " + RECT_KEYS[i]); continue; }
        s = s + RECT_KEYS[i] + "=" + n.absX + "," + n.absY + "," + n.absW + "," + n.absH + " ";
    }
    return s;
}

// ==================== phase 1: the light frame ==============================
function lightPhase():void
{
    // The palette the release has always shipped. Asserted as a whole, not just the
    // few slots the pixels below happen to read.
    check(Theme.isTheme(ThemeTokens.light()), "the starting palette is not ThemeTokens.light()");
    check(Theme.tokens().surface == 0xFFFFFF, "surface is " + hex(Theme.tokens().surface));
    check(Theme.themeEpoch() == 0, "the epoch starts at " + Theme.themeEpoch() + " not 0");
    check(Theme.tokens() == Theme.tokens(), "Theme.tokens() is not a stable instance");

    var rows:Array = [["root", 0, 0, 560, 360], ["btn", 16, 16, 120, 32],
                      ["sw", 16, 58, 140, 20], ["bd", 16, 88, 48, 20],
                      ["ch", 16, 118, 60, 24], ["dv", 16, 152, 200, 1],
                      ["pg", 16, 163, 120, 12], ["keep", 16, 185, 60, 20],
                      ["tbl", 16, 215, 260, 52], ["hdr", 16, 215, 260, 26],
                      ["h:0", 16, 215, 130, 26], ["r0", 16, 241, 260, 26]];
    for (var i:int = 0; i < rows.length; i++)
    {
        var r:Array = rows[i];
        var n:UiNode = app.findByKey(String(r[0]));
        if (n == null) { bad("no node " + r[0]); finish(); return; }
        check(n.absX == Number(r[1]) && n.absY == Number(r[2])
              && n.absW == Number(r[3]) && n.absH == Number(r[4]),
            r[0] + " is " + n.absX + "," + n.absY + "," + n.absW + "," + n.absH
            + " not " + r[1] + "," + r[2] + "," + r[3] + "," + r[4]);
    }
    var ti:UiNode = app.findByKey("ti");
    if (ti == null) { bad("the text input never mounted"); finish(); return; }
    check(ti.absX == 16 && ti.absY == 277 && ti.absW == 160 && ti.absH == 32,
        "the text input is " + ti.absX + "," + ti.absY + "," + ti.absW + "," + ti.absH
        + " not 16,277,160,32");

    checkPoints(LIGHT, "light");

    // The BASELINE path: a kind's colours come from `controlDefault`, which
    // `setTheme` rebuilds. Read through a node's resolved style, not the palette,
    // because that is what a paint actually sees.
    var btn:UiNode = app.findByKey("btn");
    check(btn != null && btn.resolved.text.color == 0x202020,
        "the button's text colour is not the light textControl (0x202020)");
    check(ti.resolved.borderColor == 0xCCCCCC,
        "the input's border is " + hex(uint(ti.resolved.borderColor))
        + " not the light borderInput (#CCCCCC)");
    check(OverlayChrome.ITEM_HOVER == 0xF3F4F6,
        "the overlay's hover band is " + hex(OverlayChrome.ITEM_HOVER) + " not #F3F4F6");

    check(btn.lastStyle == ThemeProbe.BTN, "light: the button style pointer is not the const");
    btnBefore = btn;
    rectsBefore = rectsNow();

    // An author override must survive the swap -- that is the difference between an
    // override LAYER and a write into the default table.
    var custom:Style = new Style();
    custom.text.fontSize = 14;
    custom.text.color = 0x123456;
    Theme.setControlDefault("text", custom);
    check(Theme.controlOverrideCount() == 1,
        "the override count is " + Theme.controlOverrideCount() + " not 1");

    Theme.setTheme(ThemeTokens.dark());
    setTimeout(darkPhase, 350);
}

// ==================== phase 2: the dark frame ===============================
function darkPhase():void
{
    check(Theme.isTheme(ThemeTokens.dark()), "the live palette is not ThemeTokens.dark()");
    check(Theme.themeEpoch() == 1, "the epoch is " + Theme.themeEpoch() + " not 1");

    checkPoints(DARK, "dark");

    var after:String = rectsNow();
    check(after == rectsBefore, "the theme switch moved the layout: " + after);

    var btn:UiNode = app.findByKey("btn");
    // Reuse, not rebuild: a recreated node would re-resolve for free and the
    // markThemeDirty question below would be untestable.
    check(btn == btnBefore, "the button node was RECREATED by the describe pass");
    check(btn != null && btn.lastStyle == ThemeProbe.BTN, "dark: the button style pointer MOVED");
    check(btn != null && btn.resolved.text.color == 0xE5E7EB,
        "after the switch the button text colour is " + hex(uint(btn.resolved.text.color))
        + " not the dark textControl (0xE5E7EB)");
    var ti:UiNode = app.findByKey("ti");
    check(ti != null && ti.resolved.borderColor == 0x4B5563,
        "after the switch the input's border is " + hex(uint(ti.resolved.borderColor))
        + " not the dark borderInput (#4B5563)");
    check(OverlayChrome.ITEM_HOVER == 0x1F2937,
        "the overlay's hover band did not follow (" + hex(OverlayChrome.ITEM_HOVER) + ")");

    // The override is still the author's colour AND is still counted as one.
    check(Theme.controlDefault("text").text.color == 0x123456,
        "the author's override is not in force after the swap");
    check(Theme.controlOverrideCount() == 1,
        "the override count changed across the swap (" + Theme.controlOverrideCount() + ")");
    Theme.clearControlDefault("text");
    check(Theme.controlOverrideCount() == 0, "clearControlDefault left the count at "
        + Theme.controlOverrideCount());
    check(Theme.controlDefault("text").text.color == 0xE5E7EB,
        "after the override is gone the baseline is " + hex(uint(Theme.controlDefault("text").text.color))
        + " not the dark text slot (0xE5E7EB)");

    promises();
    setTimeout(clickPhase, 350);
}

// ==================== phase 3: the swap a user actually triggers ============
// Every real app -- and the docs page -- changes the theme from an onClick, i.e.
// INSIDE the event dispatch, not from a timer. Same pipeline, different moment, and
// the moment is worth proving: `setTheme` rebuilds static StyleRefinement pointers
// while the app is in the middle of dispatching. If that were unsafe, this would show
// it as a wrong colour or a crash.
function clickToDark():void { Theme.setTheme(ThemeTokens.dark()); }

function clickPhase():void
{
    epochBeforeLight = Theme.themeEpoch();
    Theme.setTheme(ThemeTokens.light());
    setTimeout(dispatchClick, 350);
}

function dispatchClick():void
{
    // Exactly one bump per swap, no matter which entry point delivered it.
    check(Theme.themeEpoch() == epochBeforeLight + 1,
        "the second swap moved the epoch from " + epochBeforeLight + " to " + Theme.themeEpoch());
    checkPoints(LIGHT, "light #2");
    stage.dispatchMouse(46, 195, "click");
    setTimeout(afterClick, 350);
}

function afterClick():void
{
    check(Theme.isTheme(ThemeTokens.dark()), "the click did not reach Theme.setTheme");
    check(Theme.themeEpoch() == epochBeforeLight + 2,
        "the click-driven swap moved the epoch from " + epochBeforeLight + " to "
        + Theme.themeEpoch() + " not +2");
    checkPoints(DARK, "dark, driven by a click");
    finish();
}

// ==================== phase 3: the contracts ===============================
function threw(what:String, fn:Function):void
{
    var hit:Boolean = false;
    var msg:String = "";
    try { fn(); }
    catch (e:Error) { hit = true; msg = e.message; }
    if (!hit) bad(what + " did NOT throw");
    else if (msg == "") bad(what + " threw an error with no message");
    else say("refused: " + msg);
}

function promises():void
{
    check(!ThemeTokens.same(ThemeTokens.light(), ThemeTokens.dark()),
        "light() and dark() compare equal");
    var c:ThemeTokens = Theme.tokens().clone();
    check(ThemeTokens.same(c, Theme.tokens()), "a clone of the live palette is not equal to it");
    // Mutating a CLONE must not reach the live palette: `setTheme` copies in, so the
    // caller keeps its instance and nobody can change half the tree by accident.
    c.accent = 0x00FF00;
    check(Theme.tokens().accent == 0x60A5FA,
        "mutating a clone changed the live palette (" + hex(Theme.tokens().accent) + ")");
    // The converse, which is the documented rule: mutating the ARGUMENT after
    // setTheme must be invisible, because it was copied.
    var arg:ThemeTokens = ThemeTokens.dark();
    Theme.setTheme(arg);
    arg.surface = 0x000000;
    // Two swaps have happened by now (light -> dark, then this copy of dark), so the
    // epoch is 2. Asserted here because it is the one place the count is a constant.
    check(Theme.themeEpoch() == 2, "the epoch is " + Theme.themeEpoch() + " not 2 after two setTheme calls");
    check(Theme.tokens().surface == 0x111827,
        "setTheme aliased the caller's instance (surface " + hex(Theme.tokens().surface) + ")");

    threw("Theme.setTheme(null)", function ():void { Theme.setTheme(null); });
}

function finish():void
{
    var bd:BitmapData = frame();
    var lines:String = "";
    for (var i:int = 0; i < RECT_KEYS.length; i++)
    {
        var n:UiNode = app.findByKey(RECT_KEYS[i]);
        if (n == null) { lines = lines + RECT_KEYS[i] + " MISSING" + String.fromCharCode(10); continue; }
        lines = lines + RECT_KEYS[i] + " " + n.absX + "," + n.absY + "," + n.absW + ","
            + n.absH + String.fromCharCode(10);
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
    ba.writeByte(0); ba.writeByte(0); ba.writeByte(0); ba.writeByte(0);   // x ppm
    ba.writeByte(0); ba.writeByte(0); ba.writeByte(0); ba.writeByte(0);   // y ppm
    ba.writeByte(0); ba.writeByte(0); ba.writeByte(0); ba.writeByte(0);   // clrUsed
    ba.writeByte(0); ba.writeByte(0); ba.writeByte(0); ba.writeByte(0);   // clrImportant
    // BMP rows are BOTTOM-UP and BGRA; `getPixels` is top-down RGBA.
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
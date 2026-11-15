// probes/widgets/theme-scope -- a subtree that carries its OWN palette, on screen at
// the same time as the global one.
//
// Output prefix MUST equal the directory name (`theme-scope`).
//
// WHAT THIS PROVES. `Theme.setTheme` repaints the whole process; before scopes, "a
// darker sidebar over a lighter page" was impossible and the only per-subtree colour
// mechanism was a hand-written StyleRefinement on every node. A scope has to reach
// FIVE places or the subtree ends up half-recoloured, and this probe checks each one
// on the left (global palette) and the right (a custom SEPIA palette):
//
//   1. the kind BASELINE       `Theme.controlDefault` rebuilt from the scope palette.
//                              A button's fill, border and label ink are three
//                              different slots -- asserted through `resolved`, which is
//                              what paint reads.
//   2. the INK                 the run format inside a measured TextField (G48). Read
//                              with getTextFormat(), not textColor: a run outranks it.
//   3. PAINT-TIME reads        `n.pal()` inside a widget (the progress bar's accent).
//                              A scoped widget that still called `Theme.tokens()`
//                              would paint the global colour -- the pixel samples at
//                              (26,88) and (346,88) catch exactly that.
//   4. FACTORY-BAKED colours   a StyleRefinement built while describing: the table's
//                              header fill (surfaceMuted) and header ink (textBody).
//                              This is what `themeScope`'s describe-time push exists
//                              for; without it the scope's table stays global.
//   5. INHERITANCE + OVERRIDE  a nested `themeScope` inside the sepia panel is dark,
//                              and the sepia panel's OWN background is sepia.
//
// AND THREE THINGS THAT MUST NOT HAPPEN:
//   * a GLOBAL swap must not repaint a scope. After `setTheme(dark)` the sepia panel is
//     still #F5EFE4 and its label still #2B2117 -- a scope is a palette, not a modifier.
//   * a global swap must not CHURN the scope: the same palette value must resolve to the
//     same ScopedTheme object (`Theme.scopeFor` caches by value), or every frame would
//     rebuild a kind table and move every baseline pointer in the subtree.
//   * geometry must not move -- neither on a global swap nor when a scope is involved.
//     The rects are captured once and compared at every phase.
//
// HAND ARITHMETIC (window 640x320):
//   root row, no padding: left panel (0,0,320,320) | sepia panel (320,0,320,320)
//   each panel: padding 16, gap 8, column, so children start at x=16 / x=336
//     btn (x,16,120,32)   text (x,56,280,20)   progress (x,84,120,12)
//     table (x,104,280,52) -> header row (x,104,280,26), 2 equal columns of 140
//     nest (336,164,280,20)   [sepia panel only]
//   y: 16 | +32+8 = 56 | +20+8 = 84 | +12+8 = 104 | +52+8 = 164
//
// PIXELS (each in a gap of its widget -- clear of glyphs, of the rounded corners, and
// of the table's header text, which is left-aligned and never reaches x+100):
//                          global light  global dark  sepia      what it is
//   (300,300) panel        #FFFFFF      #111827       -          surface, factory-baked
//   (126, 32) button       #F1F3F5      #1F2937       -          controlSurface, baseline
//   (116,116) table header #F3F4F6      #1F2937       -          surfaceMuted, factory
//   ( 26, 88) progress     #2563EB      #60A5FA       -          accent, paint-time
//   (620,300) sepia panel  #F5EFE4      #F5EFE4       #F5EFE4    the scope's OWN surface
//   (446, 32) sepia button #EDE4D3      #EDE4D3       #EDE4D3    the scope's baseline
//   (436,116) sepia header #EFE6D5      #EFE6D5       #EFE6D5    the scope's surfaceMuted
//   (346, 88) sepia prog   #8A5A00      #8A5A00       #8A5A00    the scope's accent
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

var W:int = 640;
var H:int = 320;
var OUT:String = "theme-scope";

// ---- the palette every module-level initialiser must live above showWindow -----
// A custom palette built by cloning the shipped light one and moving the slots this
// probe asserts. Deliberately NOT a second ThemeTokens vocabulary: a scope is another
// VALUE of the same 45 slots.
var SEPIA:ThemeTokens = sepiaPalette();

function sepiaPalette():ThemeTokens
{
    var t:ThemeTokens = ThemeTokens.light();
    t.surface = 0xF5EFE4;
    t.controlSurface = 0xEDE4D3;
    t.surfaceMuted = 0xEFE6D5;
    t.surfaceSoft = 0xE3D6BE;
    t.border = 0xE0D3B8;
    t.borderStrong = 0xD8C9AC;
    t.borderInput = 0xD8C9AC;
    t.text = 0x2B2117;
    t.textDefault = 0x2B2117;
    t.textControl = 0x2B2117;
    t.textBody = 0x4A3A28;
    t.accent = 0x8A5A00;
    t.accentText = 0x6B4600;
    t.accentSoft = 0xF0E0C0;
    return t;
}

var POINTS_X:Array = [300, 126, 116, 26, 620, 446, 436, 346];
var POINTS_Y:Array = [300, 32, 116, 88, 300, 32, 116, 88];
var LIGHT:Array = [0xFFFFFF, 0xF1F3F5, 0xF3F4F6, 0x2563EB,
                   0xF5EFE4, 0xEDE4D3, 0xEFE6D5, 0x8A5A00];
var DARK:Array = [0x111827, 0x1F2937, 0x1F2937, 0x60A5FA,
                  0xF5EFE4, 0xEDE4D3, 0xEFE6D5, 0x8A5A00];
var NAMES:Array = ["global panel", "global button", "global table header",
                   "global progress fill", "sepia panel", "sepia button",
                   "sepia table header", "sepia progress fill"];
var RECT_KEYS:Array = ["left", "right", "gbtn", "sbtn", "gtext", "stext",
                       "gpg", "spg", "gtbl", "stbl", "nest"];

class ThemeScopeProbe extends View
{
    override public function render():Node
    {
        // The GLOBAL panel's colour is rebuilt per render from the global palette --
        // a const would be captured once and could never follow `setTheme` (the lesson
        // the theme probe's header records).
        var leftStyle:StyleRefinement = StyleRefinement.from({
            size: [320, 320], padding: 16, gap: 8, alignItems: "flex-start",
            background: Theme.tokens().surface
        });
        return row({ key: "root", style: ROOT, ariaName: "theme scope probe" }, [
            column({ key: "left", style: leftStyle }, [
                button({ key: "gbtn", label: "Run", style: BTN }),
                text("Global light", { key: "gtext", style: TXT }),
                progress("", { key: "gpg", value: 0.5, style: PG }),
                table([{ key: "name", title: "Name" }, { key: "qty", title: "Qty" }],
                      [{ name: "A", qty: 1 }], { key: "gtbl", style: TBL, rowHeight: 26 })
            ]),
            // ★ THE SCOPE. The builder runs INSIDE the factory, with the palette pushed
            // onto Theme's describe stack, so the table's header fill above is sepia
            // rather than the global light.
            themeScope(SEPIA, buildSepia, {
                key: "right", size: [320, 320], padding: 16, gap: 8,
                alignItems: "flex-start", flexDirection: "column",
                background: SEPIA.surface
            })
        ]);
    }

    // A top-level function, not an inline closure: the builder is called on every
    // describe, and an inline `function():Array {...}` would allocate a closure per
    // frame. (It is passed by reference, so this costs nothing.)
    private static function buildSepia():Array
    {
        return [
            button({ key: "sbtn", label: "Run", style: BTN }),
            text("Scoped sepia", { key: "stext", style: TXT }),
            progress("", { key: "spg", value: 0.5, style: PG }),
            table([{ key: "name", title: "Name" }, { key: "qty", title: "Qty" }],
                  [{ name: "A", qty: 1 }], { key: "stbl", style: TBL, rowHeight: 26 }),
            // A NESTED scope: dark inside sepia. This is the "sidebar is darker than the
            // page" case, one level down -- and it must not disturb its parent.
            themeScope(ThemeTokens.dark(), buildNested, { key: "nest", style: NEST })
        ];
    }

    private static function buildNested():Array
    {
        return [ text("Nested dark", { key: "ntext", style: NT }) ];
    }

    private static const ROOT:StyleRefinement = StyleRefinement.from({
        size: [640, 320], flexDirection: "row", alignItems: "flex-start"
    });
    private static const BTN:StyleRefinement = StyleRefinement.from({ size: [120, 32] });
    private static const TXT:StyleRefinement = StyleRefinement.from({ size: [280, 20] });
    private static const PG:StyleRefinement = StyleRefinement.from({ size: [120, 12] });
    private static const TBL:StyleRefinement = StyleRefinement.from({ size: [280, 52] });
    private static const NEST:StyleRefinement = StyleRefinement.from({
        size: [280, 20], background: 0x111827
    });
    private static const NT:StyleRefinement = StyleRefinement.from({ size: [280, 20] });

    public function ThemeScopeProbe():void { super(); }
}

var view:ThemeScopeProbe = new ThemeScopeProbe();
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

var problems:String = "";
var log:String = "";
var rectsBefore:String = "";
var scope0:ScopedTheme = null;

setTimeout(lightPhase, 900);
stage.showWindow(W, H, "probe theme-scope");

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

function node(key:String):UiNode
{
    var n:UiNode = app.findByKey(key);
    if (n == null) bad("no node " + key);
    return n;
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

// A node's ink as the PAINTER sees it (the run format), not as `textColor` claims.
function inkOfKey(key:String):uint
{
    var n:UiNode = app.findByKey(key);
    if (n == null || n.tf == null) { bad("no text field on " + key); return 0xFFFFFFFF; }
    var f:TextFormat = n.tf.getTextFormat();
    return f == null ? 0xFFFFFFFF : uint(f.color);
}

// The colour a node resolved for a slot, so a failure names the mechanism that broke
// (baseline vs ink vs factory) instead of only a pixel.
function resolvedTextColor(key:String):uint
{
    var n:UiNode = app.findByKey(key);
    if (n == null) return 0xFFFFFFFF;
    return isNaN(n.resolved.text.color) ? 0xFFFFFFFE : uint(n.resolved.text.color);
}

function resolvedBg(key:String):uint
{
    var n:UiNode = app.findByKey(key);
    if (n == null || n.resolved.background == null) return 0xFFFFFFFF;
    return n.resolved.background.rgb() & 0xFFFFFF;
}

// ==================== phase 1: global light + a sepia scope ================
function lightPhase():void
{
    check(Theme.isTheme(ThemeTokens.light()), "the starting palette is not ThemeTokens.light()");

    // 1. geometry, once, by hand.
    var rows:Array = [["left", 0, 0, 320, 320], ["right", 320, 0, 320, 320],
                      ["gbtn", 16, 16, 120, 32], ["sbtn", 336, 16, 120, 32],
                      ["gtext", 16, 56, 280, 20], ["stext", 336, 56, 280, 20],
                      ["gpg", 16, 84, 120, 12], ["spg", 336, 84, 120, 12],
                      ["gtbl", 16, 104, 280, 52], ["stbl", 336, 104, 280, 52],
                      ["nest", 336, 164, 280, 20]];
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
    rectsBefore = rectsNow();

    // 2. the BASELINE: same kind, two palettes, at the same time.
    check(resolvedBg("gbtn") == 0xF1F3F5,
        "the global button's surface is " + hex(resolvedBg("gbtn")) + " not #F1F3F5");
    check(resolvedBg("sbtn") == 0xEDE4D3,
        "the scoped button's surface is " + hex(resolvedBg("sbtn"))
        + " not the sepia controlSurface #EDE4D3");
    check(uint(node("gbtn").resolved.text.color) == 0x202020,
        "the global button's label slot is " + hex(resolvedTextColor("gbtn")) + " not #202020");
    check(uint(node("sbtn").resolved.text.color) == 0x2B2117,
        "the scoped button's label slot is " + hex(resolvedTextColor("sbtn"))
        + " not the sepia textControl #2B2117");
    check(uint(node("gbtn").resolved.borderColor) == 0xD0D0D0,
        "the global button's border is " + hex(uint(node("gbtn").resolved.borderColor)));
    check(uint(node("sbtn").resolved.borderColor) == 0xD8C9AC,
        "the scoped button's border is " + hex(uint(node("sbtn").resolved.borderColor))
        + " not the sepia borderStrong #D8C9AC");

    // 3. the INK (the fifth channel), on the same two buttons.
    check(inkOfKey("gbtn") == 0x202020,
        "the global button's ink is " + hex(inkOfKey("gbtn")) + " not #202020");
    check(inkOfKey("sbtn") == 0x2B2117,
        "the scoped button's ink is " + hex(inkOfKey("sbtn"))
        + " not the sepia textControl #2B2117");
    // The nested scope's label: dark, inside a sepia parent.
    check(resolvedTextColor("ntext") == 0xE5E7EB,
        "the nested scope's text is " + hex(resolvedTextColor("ntext"))
        + " not the dark text #E5E7EB");
    check(inkOfKey("ntext") == 0xE5E7EB,
        "the nested scope's ink is " + hex(inkOfKey("ntext")) + " not #E5E7EB");

    // 4. FACTORY-BAKED: the table header, whose fill and ink are refinements built
    //    while describing -- the only channel a describe-time palette can reach.
    // The table BOX itself paints nothing (its header row carries the fill), so the
    // factory-baked evidence is the header PIXEL above plus the ink slot below.
    check(uint(node("gtext").resolved.text.color) == 0x1A1A1A,
        "the global text node is " + hex(resolvedTextColor("gtext")) + " not #1A1A1A");
    check(uint(node("stext").resolved.text.color) == 0x2B2117,
        "the scoped text node is " + hex(resolvedTextColor("stext")) + " not #2B2117");

    // 5. the pixels (fills, paint-time accent, both panels).
    checkPoints(LIGHT, "light");

    // 6. the global palette is untouched by all of this.
    check(Theme.tokens().surface == 0xFFFFFF,
        "the global surface moved to " + hex(Theme.tokens().surface));
    check(Theme.tokens().accent == 0x2563EB,
        "the global accent moved to " + hex(Theme.tokens().accent));

    // 7. a scope is CACHED BY VALUE and is NOT an alias of the caller's instance.
    var right:UiNode = app.findByKey("right");
    scope0 = right == null ? null : right.scope;
    check(scope0 != null, "the scoped panel has no scope");
    check(scope0 != null && scope0.tokens().surface == 0xF5EFE4,
        "the scope's palette is not the sepia surface");
    var again:ScopedTheme = Theme.scopeFor(SEPIA);
    check(again == scope0, "Theme.scopeFor did not cache by palette value");
    var alias:ThemeTokens = ThemeTokens.light();
    var aliasScope:ScopedTheme = Theme.scopeFor(alias);
    alias.accent = 0x00FF00;
    check(aliasScope.tokens().accent != 0x00FF00,
        "the scope ALIASED the caller's palette (mutating it recoloured the scope)");

    // 8. inheritance: the panel's children carry the panel's scope, the global ones do not.
    check(node("sbtn").scope == scope0, "the scoped button did not inherit the panel's scope");
    check(node("gbtn").scope == null, "the global button picked up a scope");
    check(node("ntext").scope != scope0 && node("ntext").scope != null,
        "the nested scope did not override its parent's");

    // 9. the describe stack is balanced (a leak would recolour every later factory).
    check(Theme.describeDepth() == 0,
        "the describe stack leaked: depth " + Theme.describeDepth());

    // 10. contracts.
    threw("themeScope(null, fn)", function ():void {
        themeScope(null, function ():Array { return []; });
    });
    threw("themeScope(pal, null)", function ():void {
        themeScope(SEPIA, null);
    });
    // A THROWING BUILDER MUST UNWIND THE STACK. Without the catch-and-pop this push
    // would stay on the stack and every factory in the rest of the frame would get the
    // wrong palette -- silently, and only after some unrelated error.
    try
    {
        themeScope(SEPIA, function ():Array {
            throw new Error("probe: builder failed on purpose");
        });
        bad("a throwing builder did not throw");
    }
    catch (e:Error) { say("refused: " + e.message); }
    check(Theme.describeDepth() == 0,
        "a throwing builder leaked the describe stack: depth " + Theme.describeDepth());

    Theme.setTheme(ThemeTokens.dark());
    setTimeout(darkPhase, 350);
}

// ==================== phase 2: the global palette flips ====================
function darkPhase():void
{
    check(Theme.isTheme(ThemeTokens.dark()), "the live palette is not ThemeTokens.dark()");
    checkPoints(DARK, "dark");

    var after:String = rectsNow();
    check(after == rectsBefore, "the global swap moved the layout: " + after);

    // THE SCOPE DID NOT FOLLOW. This is the whole point: a scope is a palette, not a
    // modifier of the global one.
    check(uint(node("sbtn").resolved.text.color) == 0x2B2117,
        "the global swap overwrote the scoped button's label ("
        + hex(resolvedTextColor("sbtn")) + ")");
    check(resolvedBg("sbtn") == 0xEDE4D3,
        "the global swap overwrote the scoped button's surface (" + hex(resolvedBg("sbtn")) + ")");
    check(inkOfKey("sbtn") == 0x2B2117,
        "the global swap overwrote the scoped button's INK (" + hex(inkOfKey("sbtn")) + ")");
    check(uint(node("stext").resolved.text.color) == 0x2B2117,
        "the global swap overwrote the scoped text (" + hex(resolvedTextColor("stext")) + ")");
    // ... while the global side followed.
    check(inkOfKey("gbtn") == 0xE5E7EB,
        "the global button's ink is " + hex(inkOfKey("gbtn")) + " not the dark #E5E7EB");
    check(resolvedBg("gbtn") == 0x1F2937,
        "the global button's surface is " + hex(resolvedBg("gbtn")) + " not the dark #1F2937");

    // NO CHURN: the same palette value still resolves to the same scope object.
    var right:UiNode = app.findByKey("right");
    check(right != null && right.scope == scope0,
        "the global swap rebuilt the scope object (a new kind table every frame)");
    check(node("sbtn").scope == scope0, "the scoped button's scope moved");

    Theme.setTheme(ThemeTokens.light());
    setTimeout(backPhase, 350);
}

// ==================== phase 3: back to light ===============================
function backPhase():void
{
    checkPoints(LIGHT, "light #2");
    var after:String = rectsNow();
    check(after == rectsBefore, "the second swap moved the layout: " + after);
    check(inkOfKey("gbtn") == 0x202020,
        "after the round trip the global button's ink is " + hex(inkOfKey("gbtn")));
    check(inkOfKey("sbtn") == 0x2B2117,
        "after the round trip the scoped button's ink is " + hex(inkOfKey("sbtn")));
    finish();
}

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
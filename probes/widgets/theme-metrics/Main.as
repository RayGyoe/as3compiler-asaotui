// probes/widgets/theme-metrics -- the GEOMETRY half of a skin (2026-11-15).
//
// Output prefix MUST equal the directory name (`theme-metrics`).
//
// WHAT THIS PROVES. `ThemeMetrics` is the numbers a skin changes that are not colours:
// padding, corner radii, border widths and the type scale. They are LAYOUT inputs, so
// the acceptance is different from the palette probe's:
//
//   1. THE SLOTS ARE CONSUMED, not stored. `Theme.setMetrics(compact())` must change
//      what a node RESOLVES (padding / radii / border widths / font size) and where the
//      text inside a control SITS. The exact coordinate is the INPUT: a `textField` is
//      left-aligned and top-aligned, so `tf.x` is `borderWidth + padLeft` and `tf.y` is
//      `borderWidth + padTop` -- 1+10=11 / 1+7=8 at base, 1+7=8 / 1+4=5 at compact, and
//      1+10=11 / 1+7=8 again with no hairline. A BUTTON cannot be read that way: its
//      label is CENTRED, so `tf.x` is `(boxW - textW)/2` and moves with the FONT as well
//      as with the padding (measured: 67 at base, 68.5 at compact). That is why the
//      button's padding is proven through HEIGHT (point 3) and its slot through
//      `resolved.padding` -- not through a coordinate it does not own.
//   2. THE TREE IS RE-SOLVED, not repainted. A palette swap must never re-run layout
//      (UiApp.markThemeDirty documents the cost); a metrics swap must ALWAYS re-run it.
//      The proof is an AUTO-HEIGHT button: its box gets shorter, and the sibling under
//      it moves up by EXACTLY the same amount. That relation needs no font knowledge,
//      which is why it is asserted here and not as a hand-computed rect.
//   3. A METRICS SLOT REACHES LAYOUT IN BOTH AXES. The square phase changes ONLY the
//      border width (1 -> 0) and the radius, so an AUTO-WIDTH button must come out
//      exactly 2px narrower than at base -- hand arithmetic no font metric can move,
//      because the type scale is identical in those two phases.
//   4. THE CORNER PIXEL IS THE RADIUS. At `radiusMd = 6` the exact top-left pixel of a
//      160x40 button is outside the rounded corner (the pixel centre is 7.78px from the
//      corner circle's centre, radius 6); at 0 it is the fill. A radius slot that
//      nothing read would leave that pixel unchanged.
//   5. A SCOPED SUBTREE FOLLOWS THE APP'S METRICS. The panel at the bottom is a
//      `themeScope` with a palette of its own; its density is still the app's.
//      `Theme.setMetrics` rebuilds every cached scope's kind table -- skipping that
//      leaves a scoped subtree on the previous padding, invisible until you look.
//   6. THE NO-OPS: `setMetrics(null)` throws, and `setMetrics` with the CURRENT bundle
//      does not bump `metricsEpoch` (a no-op swap that re-solves the tree is a per-frame
//      layout pass waiting to be written by accident).
//
// HAND ARITHMETIC (window 480x300):
//   root column, padding 12, gap 10
//     row1 (12,12,456,40): btn (12,12,160,40) | ti (182,12,200,40)   [160 + gap 10]
//     col2 (12,62,456,auto)  [12 + 40 + 10]
//       autoBtn (12,62,160,auto)  below (...,160,auto)  autoW (auto width, 40 tall)
//     scoped (12, 62+col2H+10, 456,40)   -- its y is NOT hand-computable (col2 is auto),
//                                            so it is reported but not pinned.
//
// PIXELS -- the LAST phase is the one in expect.json (radius 0, border 0), so the
// corner pixel is the fill while phases 1 and 2 assert in-program that it was the
// background. Interior points are clear of every glyph:
//   (470,290)  panel surface   #FFFFFF
//   ( 12, 12)  button corner   #F1F3F5   (radius 6 -> the background; radius 0 -> fill)
//   ( 30, 32)  button interior #F1F3F5
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

var W:int = 480;
var H:int = 300;
var OUT:String = "theme-metrics";

// ---- module-level state (EVERY initialiser must live above showWindow) ------
var PANEL:uint = 0xFFFFFF;      // light surface, the panel behind every widget
var BTN_FILL:uint = 0xF1F3F5;   // light controlSurface

var problems:String = "";
var log:String = "";
var baseBtnH:Number = -1;
var baseBelowY:Number = -1;
var baseAutoW:Number = -1;

class MetricsProbe extends View
{
    override public function render():Node
    {
        // The panel colour is rebuilt per render from the live palette (a const could
        // never follow a swap) -- the same rule the theme probe records.
        var panel:StyleRefinement = StyleRefinement.from({
            size: [480, 300], padding: 12, gap: 10,
            background: Theme.tokens().surface
        });
        return column({ key: "root", style: panel, ariaName: "theme metrics probe" }, [
            row({ key: "row1", style: ROW1 }, [
                button({ key: "btn", label: "Run", style: PINNED }),
                textField({ key: "ti", style: PINNED200 })
            ]),
            column({ key: "col2", style: COL2 }, [
                // AUTO HEIGHT on purpose: this is the box that must get shorter when the
                // density changes, and whose sibling below is the sliding witness.
                button({ key: "autoBtn", label: "Auto", style: AUTO }),
                text("below", { key: "below", style: AUTO }),
                // AUTO WIDTH: the square phase changes only the border width, so this
                // box must come out exactly 2px narrower -- a layout delta no font
                // metric can hide.
                button({ key: "autoW", label: "W", style: AUTO_W })
            ]),
            // A SCOPED subtree with its own palette: its COLOURS are its own, its
            // geometry must still be the app's.
            themeScope(ThemeTokens.light().clone(), buildScoped, {
                key: "scoped", size: [456, 40], flexDirection: "row", gap: 10
            })
        ]);
    }

    private static function buildScoped():Array
    {
        return [ button({ key: "sbtn", label: "Scoped", style: PINNED }) ];
    }

    private static const ROW1:StyleRefinement = StyleRefinement.from({
        size: [456, 40], flexDirection: "row", gap: 10
    });
    private static const COL2:StyleRefinement = StyleRefinement.from({ width: 456 });
    private static const PINNED:StyleRefinement = StyleRefinement.from({ size: [160, 40] });
    private static const PINNED200:StyleRefinement = StyleRefinement.from({ size: [200, 40] });
    private static const AUTO:StyleRefinement = StyleRefinement.from({ size: [160, null] });
    private static const AUTO_W:StyleRefinement = StyleRefinement.from({ height: 40 });

    public function MetricsProbe():void { super(); }
}

var view:MetricsProbe = new MetricsProbe();
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

setTimeout(basePhase, 900);
stage.showWindow(W, H, "probe theme-metrics");

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
function node(key:String):UiNode
{
    var n:UiNode = app.findByKey(key);
    if (n == null) bad("no node " + key);
    return n;
}

// The INSIDE of a control: `tf.x` is border + padding, so it is hand arithmetic.
function tfX(key:String):Number
{
    var n:UiNode = app.findByKey(key);
    if (n == null || n.tf == null) { bad("no text field on " + key); return -1; }
    return n.tf.x;
}
function tfY(key:String):Number
{
    var n:UiNode = app.findByKey(key);
    if (n == null || n.tf == null) { bad("no text field on " + key); return -1; }
    return n.tf.y;
}

// Every slot the button's baseline reads, plus the one line that ties them to a pixel.
function checkButton(when:String, m:ThemeMetrics):void
{
    var n:UiNode = node("btn");
    if (n == null) return;
    var s:Style = n.resolved;
    check(s.padding.top == m.buttonPadY && s.padding.right == m.buttonPadX
          && s.padding.bottom == m.buttonPadY && s.padding.left == m.buttonPadX,
        when + ": the button's padding is " + s.padding.top + "/" + s.padding.right
        + ", want " + m.buttonPadY + "/" + m.buttonPadX);
    check(s.cornerRadii.topLeft == m.radiusMd && s.cornerRadii.bottomRight == m.radiusMd,
        when + ": the button's radius is " + s.cornerRadii.topLeft + ", want " + m.radiusMd);
    check(s.borderWidths.top == m.borderWidth && s.borderWidths.left == m.borderWidth,
        when + ": the button's border is " + s.borderWidths.top + ", want " + m.borderWidth);
    check(s.text.fontSize == m.font,
        when + ": the button's font size is " + s.text.fontSize + ", want " + m.font);
    // NO tf.x / tf.y HERE: a button's label is centred, so its field origin is
    // (boxW - textW)/2 and moves with the font too. The padding reaches layout through
    // the auto-height box instead (phase 2's exact sibling relation).
}

function checkInput(when:String, m:ThemeMetrics):void
{
    var n:UiNode = node("ti");
    if (n == null) return;
    var s:Style = n.resolved;
    check(s.padding.top == m.inputPadY && s.padding.left == m.inputPadX,
        when + ": the input's padding is " + s.padding.top + "/" + s.padding.left
        + ", want " + m.inputPadY + "/" + m.inputPadX);
    check(s.cornerRadii.topLeft == m.radiusSm,
        when + ": the input's radius is " + s.cornerRadii.topLeft + ", want " + m.radiusSm);
    check(s.text.fontSize == m.font,
        when + ": the input's font size is " + s.text.fontSize + ", want " + m.font);
    check(tfX("ti") == m.borderWidth + m.inputPadX,
        when + ": the input's text starts at x " + tfX("ti") + ", want "
        + (m.borderWidth + m.inputPadX) + " (border + padLeft)");
    check(tfY("ti") == m.borderWidth + m.inputPadY,
        when + ": the input's text starts at y " + tfY("ti") + ", want "
        + (m.borderWidth + m.inputPadY) + " (border + padTop)");
}

// A scope keeps ITS palette but takes the APP's geometry: skipping the rebuild in
// setMetrics leaves exactly this node on the previous padding.
function checkScoped(when:String, m:ThemeMetrics):void
{
    var n:UiNode = node("sbtn");
    if (n == null) return;
    check(n.resolved.padding.left == m.buttonPadX && n.resolved.cornerRadii.topLeft == m.radiusMd,
        when + ": the SCOPED button's padding/radius is " + n.resolved.padding.left + "/"
        + n.resolved.cornerRadii.topLeft + ", want " + m.buttonPadX + "/" + m.radiusMd
        + " (setMetrics must rebuild every scope)");
    check(n.resolved.text.fontSize == m.font,
        when + ": the SCOPED button's font size is " + n.resolved.text.fontSize
        + ", want " + m.font);
}

// ==================== phase 1: the shipped metrics =========================
function basePhase():void
{
    var rows:Array = [["root", 0, 0, 480, 300], ["row1", 12, 12, 456, 40],
                      ["btn", 12, 12, 160, 40], ["ti", 182, 12, 200, 40]];
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

    var m:ThemeMetrics = ThemeMetrics.base();
    check(Theme.metrics().same(m), "the live metrics are not ThemeMetrics.base()");
    checkButton("base", m);
    checkInput("base", m);
    checkScoped("base", m);

    var bd:BitmapData = frame();
    check(rgbAt(bd, 470, 290) == PANEL,
        "base: the panel is " + hex(rgbAt(bd, 470, 290)) + " not " + hex(PANEL));
    check(rgbAt(bd, 12, 12) == PANEL,
        "base: the button's corner pixel is " + hex(rgbAt(bd, 12, 12))
        + " -- with radius 6 that pixel is OUTSIDE the rounded corner and must show the panel");
    check(rgbAt(bd, 30, 32) == BTN_FILL,
        "base: the button's interior is " + hex(rgbAt(bd, 30, 32)) + " not " + hex(BTN_FILL));

    baseBtnH = node("autoBtn").absH;
    baseBelowY = node("below").absY;
    var aw:UiNode = app.findByKey("autoW");
    if (aw == null) { bad("no node autoW (an auto-width button)"); finish(); return; }
    baseAutoW = aw.absW;
    say("base: auto button " + baseBtnH + "px tall, sibling at y " + baseBelowY
        + ", auto-width button " + baseAutoW + "px wide");

    // THE NO-OPS, before anything moves.
    var e0:int = Theme.metricsEpoch();
    Theme.setMetrics(Theme.metrics().clone());
    check(Theme.metricsEpoch() == e0,
        "a no-op setMetrics bumped the epoch (" + e0 + " -> " + Theme.metricsEpoch()
        + ") -- that is a full re-solve for the same numbers");
    try
    {
        Theme.setMetrics(null);
        bad("setMetrics(null) did not throw");
    }
    catch (e:Error) { say("refused: " + e.message); }

    Theme.setMetrics(ThemeMetrics.compact());
    setTimeout(compactPhase, 350);
}

// ==================== phase 2: a denser skin ===============================
function compactPhase():void
{
    var m:ThemeMetrics = ThemeMetrics.compact();
    check(Theme.metrics().same(m), "the live metrics are not ThemeMetrics.compact()");
    checkButton("compact", m);
    checkInput("compact", m);
    checkScoped("compact", m);

    // THE RE-SOLVE. No font knowledge needed: the sibling's move IS the box's shrink.
    var h:Number = node("autoBtn").absH;
    var y:Number = node("below").absY;
    var dH:Number = baseBtnH - h;
    var dY:Number = baseBelowY - y;
    check(dH > 0, "compact: the auto-height button did not get shorter (" + baseBtnH
        + " -> " + h + ")");
    check(dH >= 8, "compact: the auto-height button lost " + dH
        + "px, want at least the 8px of vertical padding it sheds");
    check(Math.abs(dY - dH) < 0.51, "compact: the sibling below moved " + dY
        + "px while the button shrank " + dH + "px -- the layout never re-ran (a repaint"
        + " cannot move a box)");

    var bd:BitmapData = frame();
    check(rgbAt(bd, 12, 12) == PANEL,
        "compact: the corner pixel is " + hex(rgbAt(bd, 12, 12))
        + " -- radius 4 still rounds that pixel out (the centre is 4.95px from the corner"
        + " circle's centre)");
    check(rgbAt(bd, 30, 32) == BTN_FILL,
        "compact: the button's interior is " + hex(rgbAt(bd, 30, 32)));

    Theme.setMetrics(squareMetrics());
    setTimeout(squarePhase, 350);
}

// A skin is a VALUE: square corners, no hairline. Not a preset, because "sharp" is a
// style decision the app makes, not a density the kit ships.
function squareMetrics():ThemeMetrics
{
    var m:ThemeMetrics = ThemeMetrics.base();
    m.radiusMd = 0;
    m.borderWidth = 0;
    return m;
}

// ==================== phase 3: square corners, no hairline =================
function squarePhase():void
{
    var m:ThemeMetrics = squareMetrics();
    checkButton("square", m);
    checkInput("square", m);
    checkScoped("square", m);

    var bd:BitmapData = frame();
    check(rgbAt(bd, 12, 12) == BTN_FILL,
        "square: the corner pixel is " + hex(rgbAt(bd, 12, 12)) + " not the fill "
        + hex(BTN_FILL) + " -- the radius slot is not being read");
    // Padding is back to base and the type scale is identical to base, but the hairline
    // is gone: the auto-height box must be EXACTLY 2px shorter (one border per side).
    check(Math.abs(node("autoBtn").absH - (baseBtnH - 2 * (1 - m.borderWidth))) < 0.51,
        "square: the auto button is " + node("autoBtn").absH + "px, want "
        + (baseBtnH - 2 * (1 - m.borderWidth))
        + " (the base height minus the two 1px borders; the geometry did not come back)");
    check(Math.abs(node("autoW").absW - (baseAutoW - 2)) < 0.51,
        "square: the auto-width button is " + node("autoW").absW + "px wide, want "
        + (baseAutoW - 2)
        + " -- only the border width changed, so the box must lose one pixel per side");
    finish();
}

function finish():void
{
    var bd:BitmapData = frame();
    var keys:Array = ["root", "row1", "btn", "ti", "autoBtn", "below", "autoW",
                      "scoped", "sbtn"];
    var lines:String = "";
    for (var i:int = 0; i < keys.length; i++)
    {
        var n:UiNode = app.findByKey(String(keys[i]));
        if (n == null) { lines = lines + keys[i] + " MISSING" + String.fromCharCode(10); continue; }
        lines = lines + keys[i] + " " + n.absX + "," + n.absY + "," + n.absW + ","
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
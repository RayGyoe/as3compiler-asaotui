// probes/widgets/i18n/Main.as -- the message catalog (I18n) and what UNLOCKS it:
// the epoch the app watches, the memo slot that has to be dropped with it, and the
// layout direction that follows the locale.
//
// Output prefix MUST equal the directory name (`i18n`).
//
// WHY THIS PROBE EXISTS
// ---------------------
// A translation layer fails in three ways that no screenshot shows:
//   * it renders the DEFAULT language when the app asked for another one
//     (a fallback chain that stops too early -- or an epoch nobody watches, so the
//     first frame after setLocale still shows English);
//   * it renders MARKERS ([[key]]) where a key exists somewhere in the chain, or
//     it silently renders the key itself;
//   * it keeps a cached subtree in the old language (View.memo hit across a locale
//     switch), which looks correct until exactly the part the app memoized is the
//     part the user re-languages.
// The first two are asserted on catalog answers and on RENDERED text; the third is
// asserted on a memoized node after a real, frame-boundary locale switch -- the
// probe never calls app.invalidate() for that, because the wiring under test is
// UiApp.onEnterFrame noticing the epoch.
//
// The geometry half is the RTL sentence: a locale must be able to mirror the
// layout, and the ONLY thing that may decide that is the locale (UiApp.solveRoot
// reads I18n.isRTL() -- it used to pass LayoutConstants.DIR_LTR as a constant).
//
// WHAT IS NOT COVERED, ON PURPOSE: bidi text shaping and TextField.direction (the
// runtime has neither, compiler-gaps), localeCompare / collation (same), font
// fallback for CJK, and CLDR plural rules beyond the shipped table.
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

var W:int = 400;
var H:int = 420;
var OUT:String = 'i18n';

var checks:int = 0;
var failures:String = "";

// ---- phase 0: the catalog, before any window exists -----------------------
//
// The catalog is pure data and microseconds of work, so its contract is asserted
// FIRST and synchronously: if the chain is wrong, every later phase would be
// measuring the wrong language rather than failing.
//
// A tag with a sub-tag resolves through its parent tags: "zh-Hant-TW" -> "zh-Hant"
// -> "zh" -> the default. That IS the whole design (no CLDR data, no wildcard
// matching), so it is measured directly.
I18n.addMessages("zh-Hant", { "app.zhh": "繁體" });
I18n.addMessages("zh", { "app.zh": "简体" });
I18n.addMessages("en", {
    "app.hello": "Hello {name}",
    "app.override": "shipped",
    "cart#one": "{n} item",
    "cart#other": "{n} items"
});
I18n.addMessages("zh-CN", {
    "app.override": "内置",
    "cart#other": "{n} 项"
});

expect(I18n.locale() == "en", "the default locale is '" + I18n.locale() + "', want 'en'");
expect(I18n.defaultLocale() == "en", "the default default-locale is '" + I18n.defaultLocale() + "'");
expect(I18n.t("app.hello", { name: "Ada" }) == "Hello Ada",
    "a single placeholder gives '" + I18n.t("app.hello", { name: "Ada" }) + "'");
expect(I18n.t("app.hello", { name: "Ada", other: "x" }) == "Hello Ada",
    "an UNUSED parameter leaked into the text");
// The kit's own strings are installed at startup: an app that configures nothing
// still gets them (the same "honest floor" rule as the desktop Env).
expect(I18n.t("kit.select.placeholder") == "Select...",
    "the kit's select hint is '" + I18n.t("kit.select.placeholder") + "'");
// An app registration WINS over the kit's for the same key.
expect(I18n.t("app.override") == "shipped", "a later registration of the same key did not win");

// -- the fallback chain --
I18n.setLocale("zh-Hant-TW");
expect(I18n.locale() == "zh-Hant-TW", "setLocale did not keep the tag's case");
expect(I18n.t("app.zhh") == "繁體", "a sub-tag did not fall back to its parent ('" + I18n.t("app.zhh") + "')");
expect(I18n.t("app.zh") == "简体", "a sub-tag did not fall back two levels ('" + I18n.t("app.zh") + "')");
expect(I18n.t("app.hello", { name: "Ada" }) == "Hello Ada",
    "a missing key did not fall back to the default locale ('" + I18n.t("app.hello", { name: "Ada" }) + "')");
// zh-CN is a SIBLING of zh-Hant-TW, not an ancestor: its strings must NOT be used.
expect(I18n.t("app.override") == "shipped", "a sibling locale's catalog was used as a fallback");
// An unknown locale is legal: it resolves to the default, not to a marker and not
// to an exception (an app that ships 3 of its 6 locales must still run).
I18n.setLocale("qq-ZZ");
expect(I18n.t("app.override") == "shipped", "an unknown locale did not fall back to the default");
expect(I18n.t("probe.absent") == "[[probe.absent]]",
    "a key nobody has renders as '" + I18n.t("probe.absent") + "', want [[probe.absent]]");
expect(!I18n.has("probe.absent"), "has() claimed a key nobody has");
expect(I18n.has("app.hello"), "has() denied a key that exists");

// -- the missing list, and strict mode --
I18n.clearMissing();
I18n.t("probe.absent");
I18n.t("probe.absent");
var miss:Array = I18n.missingKeys();
expect(miss.length == 1, "missingKeys() has " + miss.length + " entries for ONE missing key");
expect(miss.length == 1 && miss[0] == "probe.absent", "missingKeys() does not name the key");
I18n.setStrict(true);
var threw:Boolean = false;
try { I18n.t("probe.absent"); }
catch (err:Error) { threw = true; }
expect(threw, "strict mode did not throw for a missing key");
expect(I18n.t("app.hello", { name: "OK" }) == "Hello OK", "strict mode broke a resolvable key");
I18n.setStrict(false);
I18n.clearMissing();

// -- numbers and plurals --
// Back to English first: an unknown locale (`qq-ZZ` above) is a legal state, and its
// plural category is "other" -- asserting `n == 1` against it would measure the
// FALLBACK, not the rule.
I18n.setLocale("en");
expect(I18n.number(1234567.891, 2) == "1,234,567.89",
    "number(1234567.891, 2) is '" + I18n.number(1234567.891, 2) + "'");
expect(I18n.number(-1234) == "-1,234", "number(-1234) is '" + I18n.number(-1234) + "'");
expect(I18n.number(12.5, 1) == "12.5", "number(12.5, 1) is '" + I18n.number(12.5, 1) + "'");
expect(I18n.number(0.25) == "0.25", "number(0.25) is '" + I18n.number(0.25) + "'");
expect(I18n.number(1e21) == "1e+21", "an exponent was grouped into '" + I18n.number(1e21) + "'");
expect(I18n.tn("cart", 1) == "1 item", "tn(cart, 1) is '" + I18n.tn("cart", 1) + "'");
expect(I18n.tn("cart", 3) == "3 items", "tn(cart, 3) is '" + I18n.tn("cart", 3) + "'");
I18n.setLocale("zh-CN");
// A language with ONE plural form: n == 1 must not pick a "#one" entry that does
// not exist, and must not fall back to English.
expect(I18n.tn("cart", 1) == "1 项", "tn(cart, 1) in zh-CN is '" + I18n.tn("cart", 1) + "'");
expect(I18n.tn("cart", 3) == "3 项", "tn(cart, 3) in zh-CN is '" + I18n.tn("cart", 3) + "'");
expect(I18n.t("app.override") == "内置", "zh-CN did not read its own catalog");

// -- the epoch is the whole signal --
//
// Every change that can alter a rendered string must move it, and it must move
// MONOTONICALLY: UiApp and the memo slot compare it for inequality.
var e0:int = I18n.epoch();
I18n.addMessages("en", { "app.late": "late" });
var e1:int = I18n.epoch();
expect(e1 > e0, "addMessages did not move the epoch (" + e0 + " -> " + e1 + ")");
I18n.setLocale("en");
var e2:int = I18n.epoch();
expect(e2 > e1, "setLocale did not move the epoch");
I18n.setLocale("en");
expect(I18n.epoch() == e2, "setLocale to the SAME tag moved the epoch (a needless re-describe)");
I18n.setDefault("zh-CN");
var e3:int = I18n.epoch();
expect(e3 > e2, "setDefault did not move the epoch");
I18n.setDefault("en");

// Back to the shipped state: the phases below are about the RENDERED tree, and a
// probe-specific catalog left installed would make them measure different text
// than an app that only ever calls setLocale.
I18n.reset();
expect(I18n.t("app.hello", { name: "x" }) == "[[app.hello]]", "reset() kept an app catalog");

// ---- the tree ------------------------------------------------------------
//
// Every kit surface that renders one of the kit's own strings is in here, so a
// literal left un-translated in a factory shows up as English text in a zh-CN
// window. `mtext` is inside View.memo (the cache that must NOT outlive a locale
// switch) and `absent` renders a marker on purpose.
class I18nProbe extends View
{
    private static const ROOT:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", padding: 8, gap: 8, size: [400, 420],
        background: 0xFFFFFF, text: { fontSize: 12, color: 0x111827 }
    });
    // 200 wide, two 40-wide boxes: under RTL the row mirrors, so b1 lands at
    // x = 160. The width is fixed on purpose -- a mirrored row that is also
    // auto-width would prove nothing.
    private static const MIR:StyleRefinement = StyleRefinement.from({
        flexDirection: "row", size: [200, 40], background: 0xDDDDDD
    });
    private static const B1:StyleRefinement = StyleRefinement.from({ size: [40, 20], background: 0x3366CC });
    private static const B2:StyleRefinement = StyleRefinement.from({ size: [40, 20], background: 0xCC3366 });

    public function I18nProbe():void { super(); }

    override public function render():Node
    {
        return column({ key: "root", style: ROOT }, [
            pagination(3, 10, { key: "pg" }),
            select({ key: "sel", width: 200, options: ["A", "B"] }),
            datePicker({ key: "dp", year: 2026, month: 10, open: true, width: 200 }),
            skeleton({ key: "sk" }),
            table([{ key: "i", title: "#" }], [], { key: "tb" }),
            row({ key: "mir", style: MIR }, [
                box({ key: "b1", style: B1 }),
                box({ key: "b2", style: B2 })
            ]),
            // The cache under test. Its version is CONSTANT, so the only thing that
            // can drop the entry is the epoch.
            memo("mtext", "v1", function ():Node {
                return text(I18n.t("kit.table.label"), { key: "mtext" });
            }),
            text(I18n.t("probe.absent"), { key: "absent" })
        ]);
    }
}

var view:I18nProbe = new I18nProbe();
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(view);

app.mount(stage);
app.attachRoot();

setTimeout(settle, 900);
stage.showWindow(W, H, "probe i18n");

// ---- phase 1: English, the state every app starts in --------------------
function settle():void
{
    stageMark("en baseline");
    expect(aria("prev") == "previous page", "the prev chip is named '" + aria("prev") + "'");
    expect(aria("next") == "next page", "the next chip is named '" + aria("next") + "'");
    expect(aria("pg3") == "page 3", "the page-3 chip is named '" + aria("pg3") + "'");
    expect(aria("pg") == "pagination", "the pagination node is named '" + aria("pg") + "'");
    expect(aria("sel") == "select", "the select is named '" + aria("sel") + "'");
    expect(aria("dp") == "date picker", "the date picker is named '" + aria("dp") + "'");
    expect(aria("sk") == "loading placeholder", "the skeleton is named '" + aria("sk") + "'");
    expect(aria("tb") == "table", "the table is named '" + aria("tb") + "'");
    expect(textOf("sel:label") == "Select...", "the select hint is '" + textOf("sel:label") + "'");
    expect(textOf("dp:title") == "October 2026", "the month title is '" + textOf("dp:title") + "'");
    expect(textOf("dp:wd0:t") == "Su", "the first weekday (Sunday-first) is '" + textOf("dp:wd0:t") + "'");
    expect(textOf("dp:wd1:t") == "Mo", "the second weekday is '" + textOf("dp:wd1:t") + "'");
    // 2026-10-01 is a Thursday (weekday 4) -> column 4 with a Sunday-first week.
    expect(colOf("dp:d01") == 4, "day 1 of October 2026 sits in column " + colOf("dp:d01") + ", want 4");
    expect(textOf("mtext") == "table", "the memoized text is '" + textOf("mtext") + "'");
    expect(textOf("absent") == "[[probe.absent]]", "an unresolvable key renders as '" + textOf("absent") + "'");
    // English is LTR: the row's first box is at its main-start (the left edge).
    expect(xOf("b1") == xOf("mir"), "under LTR b1 is at " + xOf("b1") + ", want the row's x " + xOf("mir"));

    writeText(OUT + ".rects.txt", rectLines());
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    writeBmp(OUT + ".bmp", bd);
    setTimeout(phaseZh, 300);
}

// ---- phase 2: zh-CN, without anyone calling invalidate ------------------
//
// setLocale is the ONLY action here. Everything that follows (a re-describe, the
// memo miss, the new strings) has to come from UiApp noticing the epoch at the
// next frame boundary.
function phaseZh():void
{
    stageMark("setLocale zh-CN");
    I18n.clearMissing();
    I18n.setLocale("zh-CN");
    setTimeout(checkZh, 300);
}

function checkZh():void
{
    stageMark("zh-CN applied");
    expect(textOf("sel:label") == "请选择", "the select hint is still '" + textOf("sel:label") + "'");
    expect(textOf("dp:title") == "2026年10月", "the month title is '" + textOf("dp:title") + "'");
    expect(aria("prev") == "上一页", "the prev chip is still named '" + aria("prev") + "'");
    expect(aria("pg3") == "第 3 页", "the page-3 chip is named '" + aria("pg3") + "'");
    expect(aria("sk") == "加载占位", "the skeleton is still named '" + aria("sk") + "'");
    expect(aria("tb") == "表格", "the table is still named '" + aria("tb") + "'");
    // A MONDAY-FIRST week: column 0 is 一, and 2026-10-01 (Thursday) moves from
    // column 4 to column 3.
    expect(textOf("dp:wd0:t") == "一", "zh-CN's first weekday is '" + textOf("dp:wd0:t") + "'");
    expect(textOf("dp:wd6:t") == "日", "zh-CN's last weekday is '" + textOf("dp:wd6:t") + "'");
    expect(colOf("dp:d01") == 3, "with a Monday-first week day 1 sits in column "
        + colOf("dp:d01") + ", want 3");
    // THE MEMO SLOT. Its version is unchanged, so a hit here means the cache
    // outlived the language it was built in.
    expect(textOf("mtext") == "表格", "the memoized text kept '" + textOf("mtext") + "' after the switch");
    // Nothing rendered a marker: every key the kit asks for exists. The probe's own
    // `absent` node is the ONE deliberate hole, so the list must hold exactly it --
    // any other entry is a real untranslated string.
    var miss:Array = I18n.missingKeys();
    expect(miss.length == 1 && miss[0] == "probe.absent",
        "zh-CN left " + miss.length + " unresolved key(s): " + joinStrings(miss));
    setTimeout(phaseRtl, 300);
}

// ---- phase 3: an RTL locale mirrors the layout --------------------------
function phaseRtl():void
{
    stageMark("setLocale ar (RTL)");
    I18n.setLocale("ar");
    setTimeout(checkRtl, 300);
}

function checkRtl():void
{
    stageMark("ar applied");
    expect(I18n.isRTL(), "isRTL() is false for ar");
    // No Arabic catalog exists, so every kit string resolves through the DEFAULT
    // locale -- English text in a mirrored box, which is exactly right: the app
    // has not translated it yet, and the layout may not wait for the copy.
    expect(textOf("sel:label") == "Select...", "an untranslated locale did not fall back to the default");
    // b1 goes to the RIGHT edge: 200 - 40 (its own width) -- measured against the
    // row's own solved rect, not a hardcoded number.
    expect(xOf("b1") == xOf("mir") + 160, "under RTL b1 is at " + xOf("b1")
        + ", want " + xOf("mir") + "+160 (the right edge)");
    expect(xOf("b2") == xOf("mir") + 120, "under RTL b2 is at " + xOf("b2") + ", want " + xOf("mir") + "+120");
    // The direction is a LAYOUT input, so it has to survive a re-solve -- and the date
    // GRID mirrors with everything else: the Sunday-first week is a row, so a Thursday
    // cell in LTR column 4 lands in visual column 2. That is the standard RTL calendar,
    // and it is why `firstDay` (week order) and `isRTL` (visual order) are two inputs:
    // they compose, they do not override each other.
    expect(colOf("dp:d01") == 2, "under RTL day 1 sits in column " + colOf("dp:d01")
        + ", want 2 (the mirror of the LTR column 4)");
    setTimeout(phaseBack, 300);
}

// ---- phase 4: back to English, and the cache is rebuilt AGAIN -----------
function phaseBack():void
{
    stageMark("setLocale en");
    I18n.setLocale("en");
    setTimeout(checkBack, 300);
}

function checkBack():void
{
    stageMark("en again");
    expect(!I18n.isRTL(), "isRTL() stayed true after leaving an RTL locale");
    expect(textOf("sel:label") == "Select...", "the select hint did not come back");
    expect(textOf("mtext") == "table", "the memoized text did not come back ('" + textOf("mtext") + "')");
    expect(xOf("b1") == xOf("mir"), "the row did not un-mirror (b1 at " + xOf("b1") + ")");
    setTimeout(finish, 250);
}

function finish():void
{
    writeText(OUT + ".rects.txt", rectLines());
    writeText(OUT + ".done", failures == "" ? "PASS" : "FAIL " + failures);
}

// ---- helpers --------------------------------------------------------------

function expect(ok:Boolean, msg:String):void
{
    checks = checks + 1;
    if (!ok) failures = failures + msg + "; ";
}

function aria(key:String):String
{
    var n:UiNode = app.findByKey(key);
    if (n == null) { expect(false, "no node '" + key + "'"); return "MISSING"; }
    return n.ariaName == null ? "" : n.ariaName;
}

function textOf(key:String):String
{
    var n:UiNode = app.findByKey(key);
    if (n == null) { expect(false, "no text node '" + key + "'"); return "MISSING"; }
    if (n.tf == null) { expect(false, "node '" + key + "' has no TextField"); return "NO-TF"; }
    return n.tf.text;
}

function xOf(key:String):Number
{
    var n:UiNode = app.findByKey(key);
    return n == null ? -1 : n.absX;
}

// The COLUMN a day cell sits in: the cell's x measured from the grid's LEADING edge
// (the leftmost weekday cell -- under RTL that is Saturday, not Sunday), divided by the
// cell width. Derived from the solved rects so no pixel and no week ORDER is hardcoded:
// a mirrored grid still reports a column, and the number changes only if the mirror
// happens on purpose.
function colOf(key:String):int
{
    var cell:UiNode = app.findByKey(key);
    if (cell == null) { expect(false, "no node '" + key + "'"); return -1; }
    var lead:Number = -1;
    for (var i:int = 0; i < 7; i++)
    {
        var w:UiNode = app.findByKey("dp:wd" + i);
        if (w == null) continue;
        if (lead < 0 || w.absX < lead) lead = w.absX;
    }
    if (lead < 0) { expect(false, "the weekday row is missing"); return -1; }
    return int(Math.round((cell.absX - lead) / OverlayChrome.DAY_W));
}

function rectLines():String
{
    var keys:Array = ["root", "pg", "sel", "dp", "dp:panel", "sk", "tb", "mir", "b1", "b2", "mtext"];
    var out:String = "";
    for (var i:int = 0; i < keys.length; i++)
    {
        var n:UiNode = app.findByKey(keys[i]);
        out = out + keys[i] + " " + (n == null ? "MISSING" : n.absX + "," + n.absY + "," + n.absW + "," + n.absH) + "\n";
    }
    return out;
}

function joinStrings(a:Array):String
{
    var out:String = "";
    for (var i:int = 0; i < a.length; i++) out = out + (i == 0 ? "" : ",") + String(a[i]);
    return out;
}

// The stage survives in `<name>.step`, never in `.done`: tools/probe.cjs only prints
// the breadcrumb when the verdict never arrived.
function stageMark(label:String):void
{
    writeText(OUT + ".step", label + "\n");
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
    var y:int;
    var x:int;
    for (y = h - 1; y >= 0; y--)
    {
        for (x = 0; x < w; x++)
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

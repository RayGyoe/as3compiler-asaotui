// probes/widgets/navstack/Main.as -- the phone navigation skeleton: a stack of pages,
// one on top, back intent from the platform key, and PAGE STATE THAT SURVIVES.
//
// Output prefix MUST equal the directory name (`navstack`).
//
// WHAT IS BEING MEASURED. A stack is easy to fake: mount only the top page and
// everything looks right until you go back and find the list scrolled to the top
// again. So this probe measures BOTH halves:
//
//   * THE STACK IS REAL: three pages, three node boxes at the stack's box, and
//     only the top one visible -- read from `UiNode.visible`, not from a flag.
//   * STATE SURVIVES: page B's scrollView is wheeled while B is on top, then C is
//     pushed and popped, and the SAME PIXELS must still show row 3, in the SAME
//     NODES. Both halves are asserted, because they are different promises: the
//     offset is remembered by the author's model mirrored from `onScroll` (that is
//     how every scrollView here is driven), and what the STACK owes the page is that
//     it is not rebuilt -- `sv` and `svr0` must be the same UiNode objects after the
//     round trip, so hover/focus/in-flight animation/layout caches inside a page
//     are not thrown away on a push. A stack that unmounted the page and re-created
//     it would pass the pixel check and fail the identity one.
//   * HIDDEN PAGES ARE INERT: a click on a pixel that page B owns must do nothing
//     while C is on top (UiApp.pickAt rejects an invisible node), and must work the
//     moment B is back on top.
//   * A HIDDEN STACK IS LIFELESS: the BACK key is a STAGE listener, so every mounted
//     stack hears it. The one in a hidden tab must not pop the tab the user cannot
//     see -- that is the "one stack per tab" composition, and a kit that ignores it
//     unwinds four histories with one gesture.
//   * AN EMPTY STACK IS LEGAL: `pages: []` mounts nothing and must not crash.
//
// HAND ARITHMETIC (window 320x260; root column, padding 20, background white):
//
//   nav          at (20,20), size 240x160 (explicit)
//   wrappers     absolute inset 0 inside nav -> (20,20,240,160) each
//   page B's sv  at (20,20) inside B, size 240x120, wheelStep 60, rows 20 tall
//   row i        background 0x101010 * (i + 1) -> r0 #101010, r3 #404040
//
//   pixel (30,30)   page background: C #333333 / B #222222 after a pop
//   pixel (30,25)   top of B's scrollView: r0 #101010 before the wheel, r3
//                   #404040 after one notch (60px = 3 rows)
//
// Protocol (tools/probe.cjs): dir name == output prefix; write <OUT>.rects.txt,
// <OUT>.bmp, <OUT>.done (PASS | FAIL <reason>).
import asaot.ui.*;
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
import flash.ui.Keyboard;
import flash.utils.ByteArray;
import flash.utils.setTimeout;

var W:int = 320;
var H:int = 260;
var OUT:String = 'navstack';
var ROW_H:int = 20;

class NavModel extends Observable
{
    public var depth:int = 3;   // how many of the three pages are in the stack
    public var off:Number = 0;  // page B's scroll position, mirrored from onScroll
}

var model:NavModel = new NavModel();
var view:NavProbe = null;
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;

// The author's stack: three page descriptions, back-most first.
function pagesNow():Array
{
    return model.depth >= 3 ? [pageA(), pageB(), pageC()]
         : model.depth == 2 ? [pageA(), pageB()]
         : [pageA()];
}

function pageA():Node
{
    return box({ key: "pa", style: StyleRefinement.from({ background: 0x111111 }) });
}

// Page B owns the scrollView whose offset must survive a push/pop. The model mirrors
// the viewport (`offsetY: model.off` + onScroll), which is the authoring style the
// kit documents -- see ScrollViewNode's header: a description that still carries the
// value from before the user scrolled is read as "go back there".
// The viewport reports BOTH axes: onScroll(x, y). (One argument here is the trap --
// it would receive the x, which is always 0 on this single-column viewport.)
function bScrolled(x:Number, y:Number):void
{
    model.off = y;
}

function pageB():Node
{
    return box({ key: "pb", onClick: bClicked,
                 style: StyleRefinement.from({ background: 0x222222 }) }, [
        scrollView({ key: "sv", wheelStep: 60, offsetY: model.off, onScroll: bScrolled,
                     style: StyleRefinement.from({ size: [240, 120] }) }, [
            column({ key: "svc", style: StyleRefinement.from({
                size: [Length.px(240), Length.px(300)] }) }, rowsFor())
        ])
    ]);
}

function rowsFor():Array
{
    var out:Array = [];
    for (var i:int = 0; i < 15; i++)
    {
        out.push(box({ key: "svr" + i, style: StyleRefinement.from({
            size: [Length.px(240), Length.px(ROW_H)], background: 0x101010 * (i + 1) }) }));
    }
    return out;
}

function pageC():Node
{
    return box({ key: "pc", style: StyleRefinement.from({ background: 0x333333 }) });
}

// The stack in a tab that is not showing. Its own history is plausible (two pages);
// what matters is that a BACK press must leave it alone.
function pageH():Node
{
    return box({ key: "ph1", style: StyleRefinement.from({ background: 0x444444 }) });
}

function pageH2():Node
{
    return box({ key: "ph2", style: StyleRefinement.from({ background: 0x555555 }) });
}

function hiddenBack():void
{
    hiddenCount = hiddenCount + 1;
}

class NavProbe extends View
{
    public var model:NavModel;

    private static const ROOT:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", alignItems: "flex-start",
        padding: 20, gap: 10, size: [320, 260], background: 0xFFFFFF
    });

    public function NavProbe(m:NavModel):void
    {
        super();
        this.model = m;
    }

    override public function render():Node
    {
        return column({ key: "root", style: ROOT, ariaName: "navstack probe" }, [
            navStack(pagesNow(), { key: "nav", size: [240, 160],
                                   activeIndex: model.depth - 1,
                                   onBack: backPressed }),
            // The two probe-only stacks live in an ABSOLUTE 0x0 shelf: they must be
            // in the tree (the BACK key is a stage listener, so being mounted is the
            // whole point) without taking height from the column -- three 160px
            // siblings shrank every child of a 260px column to 66.67 in the first
            // version of this probe. (`display: "none"` would be the obvious
            // spelling and the AS3 engine does not implement it: it throws.)
            box({ key: "shelf", style: StyleRefinement.from({
                position: "absolute", inset: 0, size: [0, 0] }) }, [
                // THE HIDDEN TAB's own stack: mounted, listening, and off screen.
                navStack([pageH(), pageH2()], { key: "navH", visible: false,
                                               size: [240, 160], onBack: hiddenBack }),
                // AN EMPTY STACK: no pages at all must be a legal value, not a crash.
                navStack([], { key: "navE", visible: false, size: [240, 160],
                               onBack: hiddenBack })
            ])
        ]);
    }
}

view = new NavProbe(model);
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

var problems:String = "";
var log:String = "";
var backCount:int = 0;
var hiddenCount:int = 0;
var svSeen:UiNode = null;
var rowSeen:UiNode = null;
var bClicks:int = 0;

function say(s:String):void
{
    log = log + s + "\n";
    trace(s);
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

// The author's pop: remove the top page and re-render. `activeIndex` is -1 here
// (the top of whatever the stack is), which is the spelling a real app uses.
function backPressed():void
{
    backCount = backCount + 1;
    if (model.depth > 1)
    {
        model.depth = model.depth - 1;
        view.invalidate(Dirty.ALL);
    }
}

function bClicked():void
{
    bClicks = bClicks + 1;
}

function key(code:int):void
{
    var e:KeyboardEvent = new KeyboardEvent(KeyboardEvent.KEY_DOWN, true, true,
        0, code, 0, false, false, false, false, false, false);
    stage.dispatchEvent(e);
}

function node(k:String):UiNode
{
    return app.findByKey(k);
}

setTimeout(ready, 900);
stage.showWindow(W, H, "probe navstack");

function ready():void
{
    var bd:BitmapData = frame();
    var nav:UiNode = node("nav");
    if (nav == null) { fail("the navStack never mounted"); finish(); return; }

    // (a) THE STACK IS A STACK: three pages, all the stack's box, one visible.
    if (nav.absX != 20 || nav.absY != 20 || nav.absW != 240 || nav.absH != 160)
        fail("nav is " + nav.absX + "," + nav.absY + "," + nav.absW + "," + nav.absH
            + " not 20,20,240,160");
    var pages:Array = ["pa", "pb", "pc"];
    var allThere:Boolean = true;
    for (var i:int = 0; i < pages.length; i++)
    {
        var w:UiNode = node(String(pages[i]));
        if (w == null) { fail("page " + pages[i] + " is missing"); allThere = false; continue; }
        if (w.absX != 20 || w.absY != 20 || w.absW != 240 || w.absH != 160)
            fail("page " + pages[i] + " is " + w.absX + "," + w.absY + ","
                + w.absW + "," + w.absH + " not 20,20,240,160 (absolute inset 0)");
    }
    var pa:UiNode = node("pa");
    var pb:UiNode = node("pb");
    var pc:UiNode = node("pc");
    if (pa != null) check(!pa.visible, "page A is visible while C is on top");
    if (pb != null) check(!pb.visible, "page B is visible while C is on top");
    if (pc != null) check(pc.visible, "the top page C is not visible");

    // (a2) THE TWO OTHER STACKS: one hidden with pages, one empty.
    var navH:UiNode = node("navH");
    if (navH == null) { fail("the hidden stack never mounted"); }
    else
    {
        check(!navH.visible, "the hidden stack is visible");
        check(navH.children.length == 2, "the hidden stack has " + navH.children.length
            + " pages, want 2");
    }
    var navE:UiNode = node("navE");
    if (navE == null) { fail("an EMPTY pages array did not mount the stack"); }
    else
    {
        check(navE.children.length == 0, "the empty stack mounted "
            + navE.children.length + " children");
    }
    // ... and the TOP page is the one that paints: (30,30) is inside the stack.
    var c2:uint = rgbAt(bd, 30, 30);
    check(c2 == 0x333333, "the pixel inside the stack is " + hex(c2)
        + ", want C's #333333");

    // A stack that did not mount every page has failed at the one thing this probe
    // is about; the later phases dereference pages by key and would only crash.
    if (!allThere) { finish(); return; }

    // (b) A CLICK ON A HIDDEN PAGE IS A MISS: (30,30) belongs to B too (it fills the
    // stack), so a stack that merely drew C on top of B would still deliver this.
    stage.dispatchMouse(30, 170, "click");
    setTimeout(afterHiddenClick, 200);
}

function afterHiddenClick():void
{
    check(bClicks == 0, "a click on a HIDDEN page delivered to page B (" + bClicks + ")");
    // (c) POP: the author removes the top page; B becomes the top and is live.
    model.depth = 2;
    view.invalidate(Dirty.ALL);
    setTimeout(afterPop, 200);
}

function afterPop():void
{
    var bd:BitmapData = frame();
    var pb:UiNode = node("pb");
    var pc:UiNode = node("pc");
    if (pb == null) { fail("page B vanished after the pop"); finish(); return; }
    check(pb.visible, "page B is not visible after the pop");
    check(pc == null, "page C is still mounted after being popped");
    // (30,170) is inside page B but below its scrollView (which covers y 20..140),
    // so this is B's own background and nothing else.
    var c0:uint = rgbAt(bd, 30, 170);
    check(c0 == 0x222222, "after the pop the stack shows " + hex(c0) + ", want B's #222222");
    // the click now lands, because B is the visible page
    stage.dispatchMouse(30, 170, "click");
    setTimeout(afterLiveClick, 200);
}

function afterLiveClick():void
{
    check(bClicks == 1, "a click on the VISIBLE page B did not reach it (" + bClicks + ")");
    // (d) WHEEL B's scrollView: 60px = 3 rows.
    var bd0:BitmapData = frame();
    var top0:uint = rgbAt(bd0, 30, 25);
    check(top0 == 0x101010, "before the wheel, B's scrollView top is " + hex(top0)
        + ", want row 0's #101010");
    stage.dispatchWheel(100, 45, -1);
    setTimeout(afterWheel, 350);
}

function afterWheel():void
{
    svSeen = node("sv");
    rowSeen = node("svr0");
    var bd:BitmapData = frame();
    var top:uint = rgbAt(bd, 30, 25);
    check(top == 0x404040, "after one wheel notch (60px = 3 rows) B's scrollView top is "
        + hex(top) + ", want row 3's #404040");
    // (e0) A PLAIN RE-RENDER MUST NOT DISTURB THE OFFSET (the isolation step: if this
    // one already resets, the stack's visibility flip is not the cause). On THIS
    // library it passes because the model mirrors; the point of the step is that a
    // re-render alone never moves a viewport, so (e) can blame the stack.
    view.invalidate(Dirty.ALL);
    setTimeout(afterPlainRender, 250);
}

function afterPlainRender():void
{
    var b0:BitmapData = frame();
    var t0:uint = rgbAt(b0, 30, 25);
    // ... AND IT IS THE SAME NODE: a stack that rebuilt the page would also "keep"
    // the offset by copying it, so identity is the thing being asserted here.
    var sv2:UiNode = node("sv");
    check(sv2 === svSeen && node("svr0") === rowSeen,
        "page B's scrollView was rebuilt by an unrelated re-render");
    check(t0 == 0x404040, "a plain re-render reset B's scrollView to " + hex(t0));

    // (e) PUSH C AGAIN, THEN POP IT: B's pixels must be untouched by the round trip,
    // and B's nodes must be the same objects.
    model.depth = 3;
    view.invalidate(Dirty.ALL);
    setTimeout(afterPush, 250);
}

function afterPush():void
{
    var bd:BitmapData = frame();
    var pc:UiNode = node("pc");
    check(pc != null && pc.visible, "the pushed page C is not on top");
    var c:uint = rgbAt(bd, 30, 30);
    check(c == 0x333333, "after the push the stack shows " + hex(c) + ", want C's #333333");
    var svn:UiNode = node("sv");
    check(svn === svSeen, "pushing a page rebuilt the page below it");
    check(!node("pb").visible, "page B is visible while C is on top");
    model.depth = 2;
    view.invalidate(Dirty.ALL);
    setTimeout(afterRoundTrip, 250);
}

// THE ASSERTION THE WHOLE DESIGN EXISTS FOR.
function afterRoundTrip():void
{
    var bd:BitmapData = frame();
    var top:uint = rgbAt(bd, 30, 25);
    check(top == 0x404040, "page B's scrollView came back at " + hex(top)
        + ", want the scrolled row 3's #404040 (a rebuilt page would show #101010)");
    var pb:UiNode = node("pb");
    check(pb != null && pb.visible, "page B is not on top after the round trip");
    // (f) BACK INTENT: the platform key, with NO focus anywhere -- that is the whole
    // reason this is a stage listener and not WidgetKeys.
    key(65);                       // 'A' -- somebody else's key
    setTimeout(afterOtherKey, 120);
}

function afterOtherKey():void
{
    check(backCount == 0, "a non-BACK key raised onBack (" + backCount + ")");
    key(Keyboard.BACK);
    setTimeout(afterBack, 250);
}

function afterBack():void
{
    check(backCount == 1, "the BACK key raised onBack " + backCount + " times, want 1");
    // The stage listener heard it in every stack; only the ON-SCREEN one may act.
    check(hiddenCount == 0, "the BACK key reached a HIDDEN stack (" + hiddenCount
        + " callbacks) -- one gesture would unwind every tab's history");
    check(model.depth == 1, "the author's back handler did not pop (depth " + model.depth + ")");
    var pb:UiNode = node("pb");
    check(pb == null, "page B is still mounted after the back pop");
    var bd:BitmapData = frame();
    var a:uint = rgbAt(bd, 30, 30);
    check(a == 0x111111, "after BACK the stack shows " + hex(a) + ", want A's #111111");
    finish();
}

function finish():void
{
    var bd:BitmapData = frame();
    var names:Array = ["root", "nav", "pa", "sv", "svr0", "svr3"];
    var lines:String = "";
    for (var i:int = 0; i < names.length; i++)
    {
        var n:UiNode = app.findByKey(names[i]);
        if (n == null) { lines = lines + names[i] + " MISSING\n"; continue; }
        lines = lines + names[i] + " " + n.absX + "," + n.absY + "," + n.absW + "," + n.absH + "\n";
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

// probes/widgets/env/Main.as -- the platform facts arrive through ONE interface and
// are consumed in ONE place: `Env` (MOBILE.md E1) and the root's safe-area padding (E2).
//
// Output prefix MUST equal the directory name (`env`).
//
// WHY THIS PROBE EXISTS
// ---------------------
// E1/E2 are foundation, and foundation is where a "works on my desk" claim is
// cheapest to make and hardest to keep honest. Two things must be measured:
//
//   * that the INTERFACE is wired: `UiApp.bindEnv` really moves `hasHover` (the one
//     verdict behind 103 hover branches), really subscribes (one notification, no
//     double-notify), and really drops the old subscription on a rebind;
//   * that the INSET is consumed as PADDING on the node that asked for it, on the
//     edges it asked for, ADDING to the author's own padding, with the node's box
//     still filling the window (so its background goes under the status bar and only
//     the content moves).
//
// The desktop answers are asserted too, because they are what every app in this
// repo gets without saying anything: zeros, a mouse, and no pretence of a real
// device-pixel-ratio.
//
// The geometry is HAND-COMPUTED in expect.json (root padding 4 + inset 47 top /
// 34 bottom; children 30/40/20/20 tall in a column) so a regression in the fold is
// a number in the report, not a screenshot someone squints at.
//
// WHAT IS NOT COVERED, ON PURPOSE: the real numbers a phone gives (MOBILE.md B9 --
// this box has no iOS/Android SDK), the keyboard-rect consumer (S7), appState/停帧
// (E7), reduceMotion (E8), isDark (E5) and locale/RTL (E6). All of those read the
// SAME Env and none of them is claimed here.
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
import flash.system.Capabilities;
import flash.utils.ByteArray;
import flash.utils.setTimeout;

var W:int = 320;
var H:int = 240;
var OUT:String = 'env';

var checks:int = 0;
var failures:String = "";

// The platform, simulated. A FakeEnv is the whole reason this is checkable at all:
// a desktop window answers zeros, so the only way to see the fold is to be a phone.
var fake:FakeEnv;

// Notification counters. `envChanges` is UiApp's own (a double-notify in a producer
// shows up here as 2 where the caller did 1); `probeNotifies` is a plain subscriber's.
var probeNotifies:int = 0;
var secondEnv:FakeEnv;
var secondNotifies:int = 0;

class FakeEnv extends EnvBase
{
    public function FakeEnv(t:Number, r:Number, b:Number, l:Number):void
    {
        super();
        this.setSafeArea(t, r, b, l);
    }
}

class EnvProbe extends View
{
    private static const ROOT:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", padding: 4, gap: 0, size: [320, 240],
        background: 0xFFFFFF, text: { fontSize: 12, color: 0x111827 }
    });
    // The root's content box: 320 - 4 - 4 wide, 240 - (4+47) - (4+34) tall.
    private static const A:StyleRefinement = StyleRefinement.from({ size: [312, 30], background: 0xCCCCCC });
    private static const PLAIN:StyleRefinement = StyleRefinement.from({ size: [312, 40], padding: 4, background: 0xF5F5F5 });
    private static const INNER:StyleRefinement = StyleRefinement.from({ size: [304, 10], background: 0x999999 });
    private static const PART:StyleRefinement = StyleRefinement.from({ size: [312, 60], padding: 1, background: 0xDDDDDD });
    private static const PCHILD:StyleRefinement = StyleRefinement.from({ size: [310, 10], background: 0x999999 });
    private static const NONEBG:StyleRefinement = StyleRefinement.from({ size: [312, 20], padding: 4, background: 0xEEEEEE });
    private static const NCHILD:StyleRefinement = StyleRefinement.from({ size: [304, 10], background: 0x999999 });

    public function EnvProbe():void { super(); }

    override public function render():Node
    {
        return column({ key: "root", style: ROOT, safeArea: true }, [
            box({ key: "a", style: A }),
            // NO opt: must be untouched even though it sits inside an inset root
            // (padding does not cascade -- E2's "one place, no scattering").
            box({ key: "plain", style: PLAIN }, [
                box({ key: "inner", style: INNER })
            ]),
            // PARTIAL: only the top edge is claimed, so a bottom-only change must
            // leave this node exactly where it is.
            box({ key: "part", style: PART, safeArea: ["top"] }, [
                box({ key: "pchild", style: PCHILD })
            ]),
            // EXPLICIT OFF, for the author who wants the old behaviour on one node.
            box({ key: "none", style: NONEBG, safeArea: false }, [
                box({ key: "nchild", style: NCHILD })
            ])
        ]);
    }
}

var view:EnvProbe = new EnvProbe();
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(view);

// ---- phase 0: the floor every app gets before it says anything -------------
//
// Asserted BEFORE bindEnv, because "an app that never binds still has an Env" is the
// contract; the alternative (a null Env and an author-side null check) is the thing
// this interface exists to remove.
var floorEnv:Env = app.env;
expect(floorEnv != null, "UiApp did not create a DesktopEnv");
expect(floorEnv is DesktopEnv, "the default Env is not a DesktopEnv");
expect(floorEnv.safeArea.top == 0 && floorEnv.safeArea.right == 0
    && floorEnv.safeArea.bottom == 0 && floorEnv.safeArea.left == 0,
    "the desktop safe area is not all zero");
expect(floorEnv.keyboardRect.width == 0 && floorEnv.keyboardRect.height == 0,
    "the desktop keyboard rect is not empty");
expect(floorEnv.pixelRatio == 1, "the desktop pixel ratio is " + floorEnv.pixelRatio + ", want 1");
expect(floorEnv.hasTouch == false, "the desktop claims a touch source");
expect(floorEnv.hasHover == true, "the desktop claims no hovering pointer");
expect(floorEnv.appState == "active", "the desktop app state is " + floorEnv.appState);
expect(floorEnv.isDark == false, "the desktop claims a dark system");
// locale is REAL (Capabilities.language), so this is a mirror of what AIR answers.
expect(floorEnv.locale == Capabilities.language,
    "the desktop locale " + floorEnv.locale + " is not Capabilities.language " + Capabilities.language);

// A phone-shaped environment: 47pt status bar, 34pt home indicator, nothing on the
// sides. These are MOBILE.md M2's acceptance numbers.
fake = new FakeEnv(47, 0, 34, 0);

// A plain subscriber, to prove the channel is the library's Observable and that ONE
// platform change is ONE notification.
probeNotifies = 0;
fake.subscribe(function (d:int):void { probeNotifies = probeNotifies + 1; });

app.bindEnv(fake);
app.mount(stage);
app.attachRoot();

// Declared before showWindow: a file-scope initializer is emitted in source order, and
// showWindow blocks for the life of the window.
setTimeout(settle, 900);
stage.showWindow(W, H, "probe env");

function settle():void
{
    writeText(OUT + ".rects.txt",
        "root " + rectOf(app.findByKey("root")) + "\n"
        + "a " + rectOf(app.findByKey("a")) + "\n"
        + "plain " + rectOf(app.findByKey("plain")) + "\n"
        + "inner " + rectOf(app.findByKey("inner")) + "\n"
        + "part " + rectOf(app.findByKey("part")) + "\n"
        + "pchild " + rectOf(app.findByKey("pchild")) + "\n"
        + "none " + rectOf(app.findByKey("none")) + "\n"
        + "nchild " + rectOf(app.findByKey("nchild")) + "\n");
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    writeBmp(OUT + ".bmp", bd);
    setTimeout(phaseFold, 260);
}

// ---- phase 1: the inset is IN the padding, not beside it ------------------
function phaseFold():void
{
    stageMark("fold");
    var root:UiNode = app.findByKey("root");
    var p:Edges = root.resolved.padding;
    // 4 (author) + 47 (env, top) and 4 + 34 (bottom); sides keep the author's 4,
    // because the mask does not claim left/right.
    expect(p.top == 51, "root padding top is " + p.top + ", want 4+47=51");
    expect(p.bottom == 38, "root padding bottom is " + p.bottom + ", want 4+34=38");
    expect(p.left == 4, "root padding left is " + p.left + ", want the author's 4");
    expect(p.right == 4, "root padding right is " + p.right + ", want the author's 4");
    // The BOX still fills the window: the background has to go under the status bar.
    expect(root.absX == 0 && root.absY == 0 && root.absW == W && root.absH == H,
        "the inset shrank the root box instead of padding it (" + rectOf(root) + ")");
    // A node that did NOT ask keeps its own padding -- nothing cascaded into it.
    var plainPad:Edges = app.findByKey("plain").resolved.padding;
    expect(plainPad.top == 4, "the inset leaked into a child's padding (" + plainPad.top + ")");
    expect(app.env == fake, "app.env is not the bound env");
    setTimeout(phaseZero, 260);
}

// ---- phase 2: the platform takes the insets back (a rotation) -------------
function phaseZero():void
{
    stageMark("safe area -> 0");
    var before:int = app.envChanges;
    var pBefore:int = probeNotifies;
    fake.setSafeArea(0, 0, 0, 0);
    // COMPARE-BEFORE-NOTIFY: one platform change is one notification, and the app
    // folds it once. 2 here means a producer double-notified.
    expect(app.envChanges == before + 1,
        "one safe-area change produced " + (app.envChanges - before) + " notifications, want 1");
    expect(probeNotifies == pBefore + 1,
        "a plain subscriber heard " + (probeNotifies - pBefore) + " notifications, want 1");
    setTimeout(checkZero, 260);
}

function checkZero():void
{
    stageMark("safe area 0 applied");
    var a:UiNode = app.findByKey("a");
    // 4 + 0: the fold recomputes from the AUTHOR's padding, so a disappearing
    // inset restores it exactly instead of drifting.
    expect(a.absY == 4, "with no safe area the first row is at y " + a.absY + ", want 4");
    var root:UiNode = app.findByKey("root");
    expect(root.resolved.padding.top == 4, "root padding top is " + root.resolved.padding.top + ", want 4");
    setTimeout(phasePartial, 260);
}

// ---- phase 3: an edge you did not claim must not move --------------------
function phasePartial():void
{
    stageMark("bottom-only inset");
    // Top is 0, bottom is 34. `part` claims ["top"] only -- so it must NOT shift,
    // and the pchild inside it must stay exactly where phase 1 put it.
    fake.setSafeArea(0, 0, 34, 0);
    setTimeout(checkPartial, 260);
}

function checkPartial():void
{
    stageMark("partial applied");
    var part:UiNode = app.findByKey("part");
    var pchild:UiNode = app.findByKey("pchild");
    // The COLUMN legitimately moves up (the root's top inset went to 0), so the
    // claim is RELATIVE: the top-only node keeps its author padding of 1 and gains
    // nothing from a bottom-only inset.
    expect(pchild.absY == part.absY + 1, "the top-only child is at y " + pchild.absY
        + ", want the part's own y " + part.absY + " + its author padding 1");
    expect(part.absY == 74, "with the top inset gone the third row is at y " + part.absY + ", want 74");
    // And the root, which claims all four, did take the bottom one.
    var root:UiNode = app.findByKey("root");
    expect(root.resolved.padding.bottom == 38, "root padding bottom is " + root.resolved.padding.bottom + ", want 38");
    expect(root.resolved.padding.top == 4, "root padding top is " + root.resolved.padding.top + ", want 4");
    // Put the phone back the way the rest of the probe expects it.
    fake.setSafeArea(47, 0, 34, 0);
    setTimeout(phaseHover, 260);
}

// ---- phase 4: hasHover is ONE verdict, and it comes from the Env ---------
function phaseHover():void
{
    stageMark("hover via env");
    // A real engine pointer first: this is the derived-hover path the whole kit reads.
    stage.dispatchMouse(100, 60, "mouseMove");
    var aNode:UiNode = app.findByKey("a");
    expect(app.getHover() == aNode, "the engine pointer did not hover the first row");
    expect(aNode.state.hover == 1, "the hovered row has no hover state");
    // A finger: no hover at all. This is the verdict behind all 103 branches.
    fake.setHasHover(false);
    expect(app.hasHover() == false, "Env.hasHover(false) did not reach UiApp");
    expect(app.getHover() == null, "hasHover=false left the hover chain lit");
    expect(aNode.state.hover == 0, "hasHover=false left a row painted hovered");
    // ...and a pointer move on a touch-first window must not revive it.
    stage.dispatchMouse(100, 60, "mouseMove");
    expect(app.getHover() == null, "a pointer move revived hover on a hasHover=false window");
    // The platform says the mouse came back.
    fake.setHasHover(true);
    stage.dispatchMouse(100, 60, "mouseMove");
    expect(app.getHover() == aNode, "hover did not come back when the Env regained a pointer");
    expect(aNode.state.hover == 1, "the row did not get its hover state back");
    setTimeout(phaseRebind, 260);
}

// ---- phase 5: a rebind drops the old subscription ------------------------
function phaseRebind():void
{
    stageMark("rebind");
    secondEnv = new FakeEnv(0, 0, 0, 0);
    secondNotifies = 0;
    secondEnv.subscribe(function (d:int):void { secondNotifies = secondNotifies + 1; });
    var before:int = app.envChanges;
    app.bindEnv(secondEnv);
    expect(app.env == secondEnv, "bindEnv did not swap the env");
    // bindEnv folds the new answers immediately, so the swap itself is one change.
    expect(app.envChanges == before + 1,
        "bindEnv produced " + (app.envChanges - before) + " app notifications, want 1");
    secondEnv.setSafeArea(10, 0, 0, 0);
    expect(app.envChanges == before + 2,
        "the new env produced " + (app.envChanges - before - 1) + " app notifications, want 1");
    // THE OLD ENV MUST BE SILENT. A leaked subscription is invisible on screen and
    // shows up only as work done for a platform nobody is listening to.
    var mid:int = app.envChanges;
    fake.setSafeArea(99, 0, 0, 0);
    expect(app.envChanges == mid, "the OLD env still notifies the app after a rebind");
    // A SECOND bind of the same env must not stack a second subscription: one change
    // would then arrive twice.
    app.bindEnv(secondEnv);
    expect(app.envChanges == mid + 1,
        "re-binding produced " + (app.envChanges - mid) + " notifications, want 1");
    secondEnv.setSafeArea(20, 0, 0, 0);
    expect(app.envChanges == mid + 2,
        "re-binding the same env stacked a listener (" + (app.envChanges - mid - 1)
        + " notifications for one change, want 1)");
    fake = secondEnv;
    setTimeout(phaseDesktop, 260);
}

// ---- phase 6: a null Env is refused, not silently replaced --------------
function phaseDesktop():void
{
    stageMark("desktop floor again");
    var threw:Boolean = false;
    try { app.bindEnv(null); }
    catch (err:Error) { threw = true; }
    expect(threw, "bindEnv(null) was accepted instead of throwing");
    var d:DesktopEnv = new DesktopEnv(2);
    expect(d.pixelRatio == 2, "DesktopEnv(2).pixelRatio is " + d.pixelRatio);
    app.bindEnv(d);
    setTimeout(checkDesktop, 260);
}

function checkDesktop():void
{
    stageMark("desktop applied");
    // 10 (the second fake) must be gone: binding a zero-inset Env restores the
    // author's padding, exactly like phase 2 did from a notification.
    var aNode:UiNode = app.findByKey("a");
    expect(aNode.absY == 4, "back on a DesktopEnv the first row is at y " + aNode.absY + ", want 4");
    var root:UiNode = app.findByKey("root");
    expect(root.resolved.padding.top == 4, "root padding top is " + root.resolved.padding.top + ", want 4");
    expect(app.hasHover() == true, "a DesktopEnv did not restore hover");
    setTimeout(finish, 200);
}

function finish():void
{
    writeText(OUT + ".done", failures == "" ? "PASS" : "FAIL " + failures);
}

// ---- helpers --------------------------------------------------------------

function expect(ok:Boolean, msg:String):void
{
    checks = checks + 1;
    if (!ok) failures = failures + msg + "; ";
}

function rectOf(n:UiNode):String
{
    if (n == null) return "MISSING";
    return n.absX + "," + n.absY + "," + n.absW + "," + n.absH;
}

// The stage survives in `<name>.step`, never in `.done`: tools/probe.cjs only prints the
// breadcrumb when the verdict never arrived.
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

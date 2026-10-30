// probes/lifecycle/Main.as -- what a TORN-DOWN node must do with a pointer event.
//
// Output prefix MUST equal the directory name (`lifecycle`), because tools/probe.cjs
// derives the expected file names from it.
//
// WHY THIS PROBE EXISTS
// ---------------------
// `destroySubtree()` takes a node's backing off the display list and nulls the
// fields that point into the live app (`app`, `extra`, `backing`, `desc`). It does
// NOT -- and cannot -- unregister the anonymous mouse listeners the node installed on
// its own backing, so the closures are still reachable from that display object.
//
// AIR reaches them. A roll-out is delivered to the object that WAS under the pointer
// when the frame ends that removed it (`mouseOut` arrives one beat AFTER the node
// died), and the listener used to run straight into a nulled field:
//
//     TypeError: Error #1009: Cannot access a property or method of a null object
//     reference.
//         at asaot.ui::UiNode/setHover()
//         at Function/UiNode.as$1::anonymous()
//
// -- once per click, on every page whose click tears down the control it was made on
// (measured on adl 51.4.1: accordion 1x, dialog 4x, drawer 3x, menu 3x). While G25 was
// open our own AOT never dispatched roll-over/roll-out at all, so it never reproduced and
// every AOT page stayed green; the reference runtime was the only place the bug showed
// up. G25 was fixed in v0.4.239 (roll/mouse events now arrive with AIR's ordering), so an
// AOT run CAN reach this class of bug now -- which is exactly why it is pinned here.
//
// 2026-10-26: the roll listeners are GONE -- hover is DERIVED from one stage MOUSE_MOVE
// listener (UiApp), using the click's own hit test. That is a design choice, not a
// workaround (see the note in UiApp), and the hazard just moved: the app now holds
// backing -> node for the hit test, so a destroyed node can be reached through a
// STALE REGISTRY ENTRY, and a destroyed node left in the hover chain would run
// `app.markPaint` on a null app on the very next mouse move. Both are pinned here.
//
// What it pins -- for EVERY kind that installs a backing listener (not just the
// remaining UiNode ones, because a widget may add its own: menu's row-hover,
// scrollView's bar hover):
//   * dispatching mouseDown / mouseUp / click at a backing whose node is already
//     destroyed throws NOTHING. mouseOver/mouseOut are dispatched too, as the negative
//     control: no library listener is attached to them, so if one of them ever starts
//     throwing, something re-hooked hover per object without the teardown guard;
//   * the destroyed node ignores the event in the stronger sense too: `state.hover`
//     stays 0, and an author's `onClick` never runs;
//   * destroying nodes does NOT grow the pointer registry (a stale entry keeps the
//     node -- and its whole subtree -- alive in a Dictionary that is a GC root);
//   * the guard is a no-op for LIVE nodes -- hovering a live control through the
//     real pointer path still sets its state, and a real click still runs its
//     handler and still reaches the screen. Without that half, "return early every
//     time" would pass.
import asaot.ui.*;
import asaot.ui.style.*;
import flash.display.BitmapData;
import flash.display.DisplayObject;
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

var W:int = 240;
var H:int = 180;
var OUT:String = 'lifecycle';

class LifecycleProbe extends View
{
    private static const ROOT:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", padding: 10, gap: 10, size: [240, 180],
        background: 0xF3F4F6, text: { fontSize: 12, color: 0x111827 }
    });
    private static const N32:StyleRefinement = StyleRefinement.from({ size: [200, 32] });

    // The live half of the contract: a click through the real routing path must
    // still reach this handler after all the destroyed-node traffic.
    public var clicks:int = 0;

    public function LifecycleProbe():void
    {
        super();
    }

    override public function render():Node
    {
        var self:LifecycleProbe = this;
        return column({ key: "root", style: ROOT, ariaName: "lifecycle" }, [
            button({ key: "live", label: "Live", style: N32,
                onClick: function ():void { self.clicks = self.clicks + 1; } }),
            text({ key: "note", text: "torn-down nodes ignore the pointer" })
        ]);
    }
}

var view:LifecycleProbe = new LifecycleProbe();
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

var problems:String = "";

// Every kind that installs a listener of its own on its backing. `box` and `text`
// are here as the negative controls: they have none beyond UiNode's five.
var KINDS:Array = ["box", "text", "button", "slider", "list", "menu", "scrollView",
    "select", "accordion", "tabs"];
// The one instance of each kind's Node class, kept alive by KINDS, purely to make the
// registry ready (see ensureRegistered).
var SEEDS:Array = [];

// The five types a backing can receive, named exactly as the constants spell them.
var TYPES:Array = [MouseEvent.MOUSE_OVER, MouseEvent.MOUSE_OUT, MouseEvent.MOUSE_DOWN,
    MouseEvent.MOUSE_UP, MouseEvent.CLICK];

// Exceptions from the destroyed-node dispatches, collected instead of thrown: an
// uncaught one would kill the setTimeout chain and the tool would report an opaque
// TIMEOUT instead of naming the kind and the event.
var threw:String = "";
// Whether an author handler that must never run did run.
var strayClicks:int = 0;

// DECLARED BEFORE showWindow: a file-scope initializer is emitted in SOURCE ORDER
// between the top-level statements, and showWindow blocks for the life of the
// window -- anything initialised after it would stay null forever (measured).
setTimeout(settle, 900);
stage.showWindow(W, H, "probe lifecycle");

function settle():void
{
    var n:UiNode = app.findByKey("live");
    if (n == null)
    {
        writeText(OUT + ".done", "FAIL the live button is missing");
        return;
    }
    writeText(OUT + ".rects.txt", "live " + n.absX + "," + n.absY + "," + n.absW + "," + n.absH + "\n");
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    writeBmp(OUT + ".bmp", bd);
    setTimeout(destroyedTraffic, 250);
}

// ---- phase 1: the pointer arrives at a node that is already gone -----------
// The kind -> Widget registry is filled LAZILY, from each Node class's constructor
// (Widgets.register runs there), so a kind this probe only names as a String is not
// registered yet and `new UiNode(kind, app)` dies with a hard "no Widget registered"
// error -- the whole probe would TIMEOUT with nothing named. Touch the classes under
// test and then ASSERT the registry, so a kind that stopped registering is a failure
// here instead of a probe that quietly tests nine kinds out of ten.
function ensureRegistered():void
{
    // TextNode/ButtonNode/SliderNode take their label in the constructor (the factory
    // passes it); the empty string is never rendered, these instances exist only to run
    // Widgets.register.
    SEEDS = [new BoxNode(), new TextNode(""), new ButtonNode(""), new SliderNode(""),
        new ListNode(), new MenuNode(), new ScrollViewNode(), new SelectNode(),
        new AccordionNode(), new TabsNode()];
    for (var k:int = 0; k < KINDS.length; k++)
    {
        if (!Widgets.has(String(KINDS[k])))
        {
            problems = problems + "kind " + KINDS[k] + " never registered its widget; ";
        }
    }
}

function destroyedTraffic():void
{
    stageMark("destroyed traffic");
    ensureRegistered();
    var regBefore:int = app.hoverRegistryCount();
    for (var k:int = 0; k < KINDS.length; k++)
    {
        for (var t:int = 0; t < TYPES.length; t++)
        {
            var kind:String = String(KINDS[k]);
            var type:String = String(TYPES[t]);
            // A THROWAWAY node, never attached to the tree: that is exactly the state
            // AIR's late roll-out finds its target in (off the display list, fields
            // nulled), and tearing it down cannot corrupt the app under test.
            var dead:UiNode = new UiNode(kind, app);
            if (dead.backing == null)
            {
                problems = problems + kind + ": no backing; ";
                continue;
            }
            var bak:DisplayObject = dead.backing;
            if (app.hoverRegistryCount() != regBefore + 1)
            {
                problems = problems + kind + " never entered the pointer registry; ";
            }
            dead.destroySubtree();
            if (app.hoverRegistryCount() != regBefore)
            {
                problems = problems + kind + " stayed in the pointer registry after teardown; ";
            }
            try
            {
                bak.dispatchEvent(new MouseEvent(type));
            }
            catch (err:Error)
            {
                threw = threw + kind + " " + type + " -> " + err.name + " " + err.message + "; ";
            }
            // The event must not even have been OBSERVED: a guard placed after the
            // state write would swallow the exception and still move the node.
            if (dead.state.hover != 0)
            {
                problems = problems + kind + " " + type + " moved state.hover of a destroyed node; ";
            }
        }
    }

    // A destroyed node's own onClick must never run, however the event arrives.
    var armed:UiNode = new UiNode("button", app);
    var armedBacking:DisplayObject = armed.backing;
    armed.onClick = function ():void { strayClicks = strayClicks + 1; };
    armed.destroySubtree();
    try
    {
        armedBacking.dispatchEvent(new MouseEvent(MouseEvent.CLICK));
    }
    catch (err2:Error)
    {
        threw = threw + "armed button click -> " + err2.name + " " + err2.message + "; ";
    }
    if (strayClicks != 0)
    {
        problems = problems + "a destroyed node ran its onClick; ";
    }
    setTimeout(liveTraffic, 250);
}

// ---- phase 2: the guard must be invisible to a live node -------------------
function liveTraffic():void
{
    stageMark("live hover");
    var n:UiNode = app.findByKey("live");
    if (n == null)
    {
        problems = problems + "the live button disappeared while nodes were destroyed; ";
        finish();
        return;
    }
    // Hover arrives through the REAL pointer path (one stage MOUSE_MOVE, the same
    // call the window backend makes), not as a roll event at the backing: the library
    // derives hover from the shared hit test, so a roll event at a backing would be the
    // second definition this design exists to avoid. This half of the probe exists so
    // "destroyed nodes return early" cannot be satisfied by also breaking live ones.
    // (110,26) is inside the 200x32 button at 10,10.
    send(110, 26, "mouseMove");
    if (n.state.hover != 1)
    {
        problems = problems + "mouseMove over a live node did not set hover (got " + n.state.hover + "); ";
    }
    // …and off it again. (5,175) is the root's padding, over no child.
    send(5, 175, "mouseMove");
    if (n.state.hover != 0)
    {
        problems = problems + "moving off a live node did not clear hover (got " + n.state.hover + "); ";
    }
    // The node tree is untouched: same rect as the settle frame.
    if (n.absX != 10 || n.absY != 10 || n.absW != 200 || n.absH != 32)
    {
        problems = problems + "the live button moved to " + n.absX + "," + n.absY + " "
            + n.absW + "x" + n.absH + " (the destroyed-node traffic must not reflow); ";
    }
    setTimeout(liveClick, 250);
}

function liveClick():void
{
    stageMark("live click");
    // The real routing path (stage hit test + the glue's CLICK), which is what a
    // user's press does. y = 26 is inside the 10..42 box.
    send(110, 26, "mouseDown");
    send(110, 26, "mouseUp");
    send(110, 26, "click");
    if (view.clicks != 1)
    {
        problems = problems + "a click on the live button ran its onClick " + view.clicks
            + " times (want 1); ";
    }
    setTimeout(livePixels, 250);
}

function livePixels():void
{
    stageMark("live pixels");
    // The app still renders: the column's own background above the button.
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    problems = problems + expectStr(bd, 120, 4, 0xF3F4F6, "the column background");
    problems = problems + expectStr(bd, 120, 120, 0xF3F4F6, "the column background below the note");
    finish();
}

function finish():void
{
    if (threw != "") problems = problems + "a destroyed-node event threw: " + threw;
    writeText(OUT + ".done", problems == "" ? "PASS" : "FAIL " + problems);
}

// The stage survives in `<name>.step`, never in `.done`: tools/probe.cjs only prints
// the breadcrumb when the verdict never arrived, and a probe that writes .done early
// would be reported as finished (see probes/widgets/scrollbar).
function stageMark(label:String):void
{
    writeText(OUT + ".step", label + "\n");
}

function send(x:Number, y:Number, type:String):void
{
    try
    {
        stage.dispatchMouse(x, y, type);
    }
    catch (err:Error)
    {
        threw = threw + type + " at (" + x + "," + y + "): " + err.message + "; ";
    }
}

function expectStr(bd:BitmapData, x:int, y:int, rgb:uint, what:String):String
{
    var got:uint = bd.getPixel(x, y) & 0xFFFFFF;
    if (got == rgb) return "";
    return what + " is " + hex(got) + " not " + hex(rgb) + " at (" + x + "," + y + "); ";
}

function hex(v:uint):String
{
    var s:String = (v & 0xFFFFFF).toString(16);
    while (s.length < 6) s = "0" + s;
    return "#" + s;
}

function writeText(path:String, t:String):void
{
    var f:File = File.applicationDirectory.resolvePath(path);
    var fs:FileStream = new FileStream();
    fs.open(f, FileMode.WRITE);
    fs.writeUTFBytes(t);
    fs.close();
}

// 32-bit bottom-up BMP written by hand (copied verbatim from
// probes/widgets/callback/Main.as): this runtime has BitmapData but no PNG encoder.
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
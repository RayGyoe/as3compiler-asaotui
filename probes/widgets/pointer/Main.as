// probes/widgets/pointer/Main.as -- hover is SYNTHESIZED from the pointer, and the
// pointer shape comes with it.
//
// Output prefix MUST equal the directory name (`pointer`).
//
// WHY THIS PROBE EXISTS
// ---------------------
// Our AOT runtime never dispatches mouseOver/mouseOut -- the string does not occur in
// src/emit.ts at all (G25 in compiler-gaps.md). Until 2026-10-26 every node hung its
// hover off exactly those two events, so EVERY hover state in the library was dead on
// our own builds while it worked under adl: 41 gallery pages, every AOT probe and every
// pixel comparison were green, because nothing ever asked the pointer to move.
//
// The fix is one stage MOUSE_MOVE listener in UiApp (the event both arms deliver, which
// bubbles and falls back to the stage), the runtime's own hit test, and a backing ->
// node registry. This probe pins what that rewrite must keep true:
//
//   * hover reaches the NODE UNDER THE POINTER (not the stage, not the first child);
//   * it also reaches every ANCESTOR -- AIR's mouseOver bubbles, so a card with a
//     hover background must light while the pointer is over the card's children;
//   * moving between two nodes clears the one left behind, in the SAME move (no frame
//     of double-hover);
//   * leaving the window (MOUSE_LEAVE) clears everything, cursor included;
//   * the OS pointer shape follows the chain: MouseCursor's names, inherited down the
//     tree, back to "auto" when nothing asks -- a stale "hand" stuck on the process is
//     what makes a whole window feel broken;
//   * hover still REFLOWS NOTHING (design doc 3.3): the solved rects are identical
//     before and after, and no measure/arrange pass ran;
//   * a node destroyed while hovered does not survive in the app's hover chain (its
//     `app` is null, so painting it is a #1009 in a mouse move).
import asaot.ui.*;
import asaot.ui.style.*;
import flash.display.BitmapData;
import flash.display.Stage;
import flash.display.StageAlign;
import flash.display.StageScaleMode;
import flash.events.Event;
import flash.filesystem.File;
import flash.filesystem.FileMode;
import flash.filesystem.FileStream;
import flash.geom.Rectangle;
import flash.ui.Mouse;
import flash.utils.ByteArray;
import flash.utils.setTimeout;

var W:int = 300;
var H:int = 200;
var OUT:String = 'pointer';

var checks:int = 0;
var failures:String = "";

// The model. `showBtn` exists so a node can be DESTROYED while it is hovered: that is
// the one path a synthesized hover can walk that the old event listeners could not.
var st:Object = { showBtn: true, clicks: 0 };

class PointerProbe extends View
{
    private static const ROOT:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", padding: 10, gap: 8, size: [300, 200],
        background: 0xFFFFFF, text: { fontSize: 12, color: 0x111827 }
    });
    // The card is 200x60 with NO padding, so the inner box sits at the card's origin and
    // every rect below is arithmetic instead of a font measurement.
    private static const CARD:StyleRefinement = StyleRefinement.from({
        size: [200, 60], background: 0xEEEEEE
    });
    private static const INNER:StyleRefinement = StyleRefinement.from({
        size: [80, 20], background: 0xDDDDDD, cursor: "ibeam"
    });
    private static const BTN:StyleRefinement = StyleRefinement.from({
        size: [120, 32], background: 0x2563EB
    });

    public function PointerProbe():void { super(); }

    override public function render():Node
    {
        var kids:Array = [
            box({ key: "card", style: CARD }, [
                box({ key: "inner", style: INNER })
            ])
        ];
        if (st.showBtn)
        {
            kids.push(button({
                key: "btn", label: "Go", style: BTN,
                onClick: function ():void { st.clicks = st.clicks + 1; }
            }));
        }
        return column({ key: "root", style: ROOT, ariaName: "pointer probe" }, kids);
    }
}

var view:PointerProbe = new PointerProbe();
var stage:Stage = new Stage();
stage.scaleMode = StageScaleMode.NO_SCALE;
stage.align = StageAlign.TOP_LEFT;
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

// DECLARED BEFORE showWindow: a file-scope initializer is emitted in SOURCE ORDER
// between the top-level statements, and showWindow blocks for the life of the window.
setTimeout(settle, 900);
stage.showWindow(W, H, "probe pointer");

function settle():void
{
    var n:UiNode = app.findByKey("btn");
    if (n == null)
    {
        writeText(OUT + ".done", "FAIL the button is missing");
        return;
    }
    writeText(OUT + ".rects.txt",
        "root " + rectOf(app.findByKey("root")) + "\n"
        + "card " + rectOf(app.findByKey("card")) + "\n"
        + "inner " + rectOf(app.findByKey("inner")) + "\n"
        + "btn " + rectOf(n) + "\n");
    var bd:BitmapData = new BitmapData(W, H, true, 0xFF000000);
    bd.draw(stage);
    writeBmp(OUT + ".bmp", bd);
    setTimeout(phaseHoverButton, 250);
}

// ---- phase 1: the pointer sits on a leaf, with an ancestor above it ---------
function phaseHoverButton():void
{
    stageMark("hover button");
    // btn rect (10,78,120,32) -> (70,94) is its middle.
    send(70, 94);
    var btn:UiNode = app.findByKey("btn");
    expect(btn.state.hover == 1, "the button under the pointer is not hovered");
    expect(app.getHover() == btn, "the app's hover target is not the button");
    // Ancestors bubble exactly like AIR's mouseOver.
    expect(app.findByKey("root").state.hover == 1, "the root (an ancestor) did not get the bubbled hover");
    expect(app.findByKey("card").state.hover == 0, "a SIBLING of the button got the hover");
    // The pointer shape: `button` earns a hand from the theme (Theme.CLICKABLE).
    expect(Mouse.cursor == "hand", "the pointer over a button is " + Mouse.cursor + " not hand");
    // Hover must not reflow (design doc 3.3).
    expect(rectOf(btn) == "10,78,120,32", "the button moved on hover: " + rectOf(btn));
    setTimeout(phaseHoverInner, 250);
}

// ---- phase 2: moving between two nodes clears the one left behind -----------
function phaseHoverInner():void
{
    stageMark("hover inner");
    // inner rect (10,10,80,20) -> (50,20).
    send(50, 20);
    var inner:UiNode = app.findByKey("inner");
    var card:UiNode = app.findByKey("card");
    expect(inner.state.hover == 1, "the inner box under the pointer is not hovered");
    // The card is NOT the hit target, it is an ancestor -- and it must light, because a
    // card's hover background is how a whole card reacts to its children.
    expect(card.state.hover == 1, "the card (an ancestor of the inner box) did not get the bubbled hover");
    expect(app.findByKey("btn").state.hover == 0, "the button stayed hovered after the pointer left it");
    expect(app.findByKey("root").state.hover == 1, "the root lost its hover while the pointer is still inside it");
    expect(Mouse.cursor == "ibeam", "an explicit cursor:\"ibeam\" did not reach Mouse.cursor (got " + Mouse.cursor + ")");
    setTimeout(phaseInherit, 250);
}

// ---- phase 3: no explicit shape -> back to "auto" -------------------------
function phaseInherit():void
{
    stageMark("hover inherit");
    // (150,50) is inside the card but right of the inner box (which ends at x=90).
    send(150, 50);
    expect(app.findByKey("card").state.hover == 1, "the card did not hover over its own area");
    expect(app.findByKey("inner").state.hover == 0, "the inner box stayed hovered (hover is sticky)");
    // The card sets NO cursor, so the shape must fall back to "auto" -- the runtime's
    // own rule. A stale "ibeam" here is the exact bug this check exists for: Mouse.cursor
    // is process-wide, so nothing would ever clear it again.
    expect(Mouse.cursor == "auto", "leaving a cursor-declaring node left " + Mouse.cursor + " on the process");
    setTimeout(phaseOff, 250);
}

// ---- phase 4: off every control, still inside the window ------------------
function phaseOff():void
{
    stageMark("hover off");
    // (280,190) is inside the root's box (300x200) and over no child.
    send(280, 190);
    expect(app.getHover() == app.findByKey("root"), "the hover target off the children is not the root");
    expect(app.findByKey("card").state.hover == 0, "the card stayed hovered off its area");
    expect(Mouse.cursor == "auto", "the pointer is " + Mouse.cursor + " over a plain area");
    setTimeout(phaseLeave, 250);
}

// ---- phase 5: the pointer leaves the window -------------------------------
function phaseLeave():void
{
    stageMark("pointer leave");
    send(70, 94);
    expect(app.findByKey("btn").state.hover == 1, "the button did not re-hover before the leave test");
    try
    {
        stage.dispatchEvent(new Event(Event.MOUSE_LEAVE));
    }
    catch (err:Error)
    {
        failures = failures + "MOUSE_LEAVE threw " + err.name + ": " + err.message + "; ";
    }
    expect(app.getHover() == null, "the window lost the pointer but still has a hover target");
    expect(app.findByKey("root").state.hover == 0, "the root stayed hovered after the pointer left the window");
    expect(app.findByKey("btn").state.hover == 0, "the button stayed hovered after the pointer left the window");
    expect(Mouse.cursor == "auto", "the pointer left the window but the shape is still " + Mouse.cursor);
    setTimeout(phaseDestroyed, 250);
}

// ---- phase 6: the hovered node is destroyed under the pointer -------------
function phaseDestroyed():void
{
    stageMark("destroyed under the pointer");
    send(70, 94);
    var btn:UiNode = app.findByKey("btn");
    expect(app.getHover() == btn, "the button is not the hover target before it is removed");
    var reg:int = app.hoverRegistryCount();
    st.showBtn = false;
    app.invalidate(Dirty.STRUCTURE);
    app.reflow();
    // The reconciler tore the node down; if it is still the hover target, the next
    // mouse move paints a node whose `app` is null (TypeError #1009 inside a mouse
    // event, i.e. only a console line thanks to the frame guard).
    expect(app.getHover() == null, "a destroyed node is still the app's hover target");
    expect(btn.app == null, "the removed button was not torn down at all");
    expect(app.hoverRegistryCount() == reg - 1,
        "the pointer registry kept the destroyed backing (" + app.hoverRegistryCount() + " vs " + (reg - 1) + ")");
    // …and the next move must still work: no exception, and the card catches it.
    send(150, 50);
    expect(app.findByKey("card").state.hover == 1, "hover stopped working after a node was destroyed under it");
    setTimeout(finish, 250);
}

function finish():void
{
    writeText(OUT + ".done", failures == "" ? "PASS" : "FAIL " + failures);
}

// ---- helpers --------------------------------------------------------------

// One REAL pointer move at stage coordinates. This is the whole point of the probe:
// the runtime hit-tests and then UiApp derives the hover chain from the target.
function send(x:Number, y:Number):void
{
    try
    {
        stage.dispatchMouse(x, y, "mouseMove");
    }
    catch (err:Error)
    {
        failures = failures + "mouseMove at (" + x + "," + y + ") threw " + err.name + ": " + err.message + "; ";
    }
}

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
    var f:File = new File(path);
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
    var f:File = new File(path);
    var fs:FileStream = new FileStream();
    fs.open(f, FileMode.WRITE);
    fs.writeBytes(ba, 0, 0);
    fs.close();
}
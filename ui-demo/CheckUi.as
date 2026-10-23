// CheckUi.as -- self-check for the asaot.ui toolkit (Deliverable 3).
//
// Every assertion throws on failure; if any fail we throw a summary Error at the
// end, and the AOT runtime exits non-zero on an uncaught Error (verified: the
// `Uncaught exception:` path returns 1). Running this through `--run` therefore
// gives an exit code a CI can gate on, with no human looking at a window.
//
// What is pinned:
//   * reconcile identity: same (kind, key) => the SAME UiNode pointer; a kind
//     change => rebuild; duplicate key under one parent => throws
//   * steady state: a reflow with nothing dirty does NOT describe, does NOT
//     reconcile and does NOT call the layout engine
//   * hover is decoration only: it paints but never re-solves layout
//   * hand-computed layout rects for a demo-shaped tree
import asaot.ui.*;
import asaot.ui.style.*;

var failures:int = 0;
var checks:int = 0;

function check(name:String, ok:Boolean, detail:String):void
{
    checks = checks + 1;
    if (ok) trace("PASS  " + name);
    else
    {
        failures = failures + 1;
        trace("FAIL  " + name + "  (" + detail + ")");
    }
}

function approx(a:Number, b:Number):Boolean
{
    var d:Number = a - b;
    if (d < 0) d = -d;
    return d < 0.01;
}

function checkRect(name:String, n:UiNode, x:Number, y:Number, w:Number, h:Number):void
{
    check(name, approx(n.absX, x) && approx(n.absY, y) && approx(n.absW, w) && approx(n.absH, h),
        n.absX + "," + n.absY + "," + n.absW + "," + n.absH + " want " + x + "," + y + "," + w + "," + h);
}

// ---- the test view: a scriptable description tree -------------------------
class CheckView extends View
{
    private static const SZ_520_60:StyleRefinement = StyleRefinement.from({ size: [520, 60] });
    private static const SZ_200_100:StyleRefinement = StyleRefinement.from({ size: [200, 100] });
    private static const GROW:StyleRefinement = StyleRefinement.from({ flexGrow: 1 });
    private static const LAYOUT_ROOT:StyleRefinement = StyleRefinement.from({
        flexDirection: "column", padding: 20, gap: 10, size: [560, 460]
    });
    private static const LAYOUT_BODY:StyleRefinement = StyleRefinement.from({
        flexDirection: "row", gap: 10, size: [520, 100]
    });

    public var mode:String = "base";

    override public function render():Node
    {
        if (mode == "dupKey")
        {
            return column({ key: "root" }, [
                box({ key: "dup", size: [40, 20] }),
                box({ key: "dup", size: [40, 20] })
            ]);
        }
        if (mode == "kindChange")
        {
            return column({ key: "root" }, [
                button({ key: "a", label: "now a button" }),
                box({ key: "b", size: [50, 20] })
            ]);
        }
        if (mode == "reorder")
        {
            return column({ key: "root" }, [
                box({ key: "b", size: [50, 20] }),
                box({ key: "a", size: [100, 40] })
            ]);
        }
        if (mode == "layout")
        {
            return column({ key: "root", style: LAYOUT_ROOT }, [
                box({ key: "header", style: SZ_520_60 }),
                row({ key: "body", style: LAYOUT_BODY }, [
                    box({ key: "left", style: SZ_200_100 }),
                    box({ key: "right", style: GROW })
                ])
            ]);
        }
        return column({ key: "root" }, [
            box({ key: "a", size: [100, 40] }),
            box({ key: "b", size: [50, 20] })
        ]);
    }
}

var view:CheckView = new CheckView();
var stage:Stage = new Stage();
var app:UiApp = new UiApp(view);
app.mount(stage);
app.attachRoot();

// ---- 1. initial solve ------------------------------------------------------
check("initial solve ran once", app.layoutSolves == 1, "solves=" + app.layoutSolves);
check("initial describe ran once", app.describeCalls == 1, "describes=" + app.describeCalls);

var a1:UiNode = app.findByKey("a");
var b1:UiNode = app.findByKey("b");
checkRect("a rect", a1, 0, 0, 100, 40);
checkRect("b rect", b1, 0, 40, 50, 20);

// ---- 2. steady state: nothing dirty => no describe, no reconcile, no solve --
var d0:int = app.describeCalls;
var s0:int = app.layoutSolves;
var v0:int = app.reconcileVisits;
app.reflow();
check("steady reflow did not describe", app.describeCalls == d0, "describes=" + app.describeCalls);
check("steady reflow did not reconcile", app.reconcileVisits == v0, "visits=" + app.reconcileVisits);
check("steady reflow did not re-solve layout", app.layoutSolves == s0, "solves=" + app.layoutSolves);

// ---- 3. keyed reorder reuses the SAME UiNode pointers ----------------------
view.mode = "reorder";
app.invalidate(Dirty.STRUCTURE);
app.reflow();
var a2:UiNode = app.findByKey("a");
var b2:UiNode = app.findByKey("b");
check("reorder reused node 'a' by key", a2 === a1, "pointer differs");
check("reorder reused node 'b' by key", b2 === b1, "pointer differs");
checkRect("reorder moved 'a' down", a2, 0, 20, 100, 40);
checkRect("reorder moved 'b' up", b2, 0, 0, 50, 20);

// ---- 4. kind change rebuilds the node at that key --------------------------
view.mode = "kindChange";
app.invalidate(Dirty.STRUCTURE);
app.reflow();
var a3:UiNode = app.findByKey("a");
var b3:UiNode = app.findByKey("b");
check("kind change rebuilt node 'a'", a3 !== a1, "pointer reused across kinds");
check("kind change produced a button", a3.kind == "button", "kind=" + a3.kind);
check("kind change left 'b' untouched", b3 === b1, "b was rebuilt");

// ---- 5. duplicate key under one parent is a hard error ---------------------
view.mode = "dupKey";
app.invalidate(Dirty.STRUCTURE);
var threw:Boolean = false;
var msg:String = "";
try
{
    app.reflow();
}
catch (e:Error)
{
    threw = true;
    msg = e.message;
}
check("duplicate key throws", threw, "no throw");
check("duplicate key message names the key", msg.length > 0 && msg.indexOf("dup") >= 0, msg);

// ---- 6. hover is decoration only (paints, never re-solves) -----------------
view.mode = "base";
app.invalidate(Dirty.STRUCTURE);
app.reflow();
var s1:int = app.layoutSolves;
var p1:int = app.paintPasses;
var hov:UiNode = app.findByKey("a");
hov.setHover(true);
app.reflow();
check("hover painted", app.paintPasses == p1 + 1, "paints=" + app.paintPasses);
check("hover did NOT re-solve layout", app.layoutSolves == s1, "solves=" + app.layoutSolves);

// ---- 7. hand-computed demo-shaped layout ----------------------------------
view.mode = "layout";
app.invalidate(Dirty.STRUCTURE);
app.reflow();
var root:UiNode = app.getRoot();
checkRect("root rect", root, 0, 0, 560, 460);
checkRect("header rect", app.findByKey("header"), 20, 20, 520, 60);
checkRect("body rect", app.findByKey("body"), 20, 90, 520, 100);
checkRect("left rect", app.findByKey("left"), 20, 90, 200, 100);
checkRect("right rect", app.findByKey("right"), 230, 90, 310, 100);

// ---- 8. an Array-valued `background` must not kill the process -------------
// TWO subjects, one root cause. (a) The crash assertion is the SEQUENCE: an Array
// in an Object-typed parameter used to be a bare pointer, so `is Fill` inside
// Fill.fromAny read the array header as a vtable and took the process down
// (0xC0000005, compiler-gaps.md G14, probe case 26) -- and a dead process prints
// nothing, so reaching the checks below IS the result. What we then pin is the
// observable value: a stop list means a gradient, gradients are deferred, so the
// answer is "no fill" -- which is also AIR's answer today (its own `fromAny`
// returns null for an Array), i.e. alignment, not invention. (b) Fixed in
// as3compiler 阶段二百五十三, the slot's identity is now answerable too: the
// `arraySlot` checks at the end of this section ask the questions that used to be
// either a compile-time lie (`is Array` folded to false) or a crash (`is Fill`).
var arrBg:StyleRefinement = StyleRefinement.from({ background: [255, 0, 0] });
check("array background yields no fill (deferred gradient)", arrBg.background == null,
    "argb=" + (arrBg.background == null ? "null" : String(arrBg.background.argb)));
// The other side of the nail: the scalar path must be untouched by the new branch.
var scalarBg:StyleRefinement = StyleRefinement.from({ background: 0x2563EB });
check("scalar background still yields an opaque solid fill",
    scalarBg.background != null && scalarBg.background.argb == 0xFF2563EB,
    "argb=" + (scalarBg.background == null ? "null" : String(scalarBg.background.argb)));
var viaAny:Fill = Fill.fromAny(0x2563EB);
check("Fill.fromAny(scalar) still solid", viaAny != null && viaAny.argb == 0xFF2563EB,
    "argb=" + (viaAny == null ? "null" : String(viaAny.argb)));

var diffPair:StyleRefinement = StyleRefinement.from({ background: [1, 2, 3], borderColor: 0x111111 });
check("an array background does not swallow the sibling fields",
    diffPair.background == null && diffPair.borderColor == 0x111111,
    "borderColor=" + diffPair.borderColor);

// Since G14 was fixed (as3compiler 阶段二百五十三, v0.4.217) the slot's IDENTITY is
// answerable too, and that is what the two lines above could only observe from the
// outside. Before the fix `o is Array` was folded to a compile-time `false` and the
// `is Fill` test below took the process down with 0xC0000005, so neither could be
// written at all. The expected values are AIR 51.4.1's (probes/obj-array-identity,
// 26/26 cases agreeing after the fix).
var arraySlot:Object = [1, 2, 3];
check("an Object slot still answers `is Array`", (arraySlot is Array),
    "is Array=" + (arraySlot is Array));
check("an Object slot is `is Fill` false, not a 0xC0000005", !(arraySlot is Fill),
    "is Fill=" + (arraySlot is Fill));
check("an Object slot answers .length and indexing",
    arraySlot.length == 3 && arraySlot[1] == 2,
    "length=" + arraySlot.length + " [1]=" + arraySlot[1]);
check("an Object slot dispatches Array methods", arraySlot.join("-") == "1-2-3",
    "join=" + arraySlot.join("-"));
check("an Object slot stringifies as an Array", String(arraySlot) == "1,2,3",
    "String=" + String(arraySlot));

trace("CHECKUI: " + checks + " checks, " + failures + " failures");
if (failures > 0)
{
    throw new Error("CheckUi FAILED: " + failures + " of " + checks + " assertions failed");
}
trace("RESULT: PASS");
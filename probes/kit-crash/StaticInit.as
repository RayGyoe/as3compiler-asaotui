// probes/kit-crash/StaticInit.as -- isolate the CRASH in ui-demo/CheckUi.as.
//
// Step.as proved the toolkit's whole pipeline is fine (describe -> reconcile ->
// measure -> solve -> arrange -> paint all ran, rect correct, exit 0). So the
// crash is in something CheckUi does that Step.as does NOT. Diffing the two, the
// only structurally different construct is CheckView's
//
//     private static const SZ_520_60:StyleRefinement = StyleRefinement.from({ size: [520, 60] });
//
// i.e. a STATIC FIELD INITIALIZER that calls a static factory of ANOTHER class,
// with an object literal containing an array. That is the shape probed here, in
// three escalating wrappers, one log line apart, so the crashing statement is
// named by the last surviving line:
//
//   (1) the same call at TOP LEVEL            -- no static init involved
//   (2) the same call as a static const of a PLAIN class, then instantiated
//   (3) the same call as a static const of a class that EXTENDS View
//
// Whichever wrapper loses its next log line is the trigger.
import asaot.ui.*;
import asaot.ui.style.*;
import flash.filesystem.File;
import flash.filesystem.FileMode;
import flash.filesystem.FileStream;

var LOGFILE:File = File.applicationDirectory.resolvePath("static.txt");
function step(msg:String):void
{
    var fs:FileStream = new FileStream();
    try { fs.open(LOGFILE, FileMode.APPEND); fs.writeUTFBytes(msg + "\n"); fs.close(); }
    catch (e:Error) { }
}

// (2) static const on a plain class
class PlainHolder
{
    public static const SZ:StyleRefinement = StyleRefinement.from({ size: [200, 100] });
    public function PlainHolder():void { }
}

// (3) static const on a View subclass -- CheckView's exact shape
// (`SZ2` is private exactly as CheckView's are; getSZ() is how the outside reads
// it, so a private static const is exercised the same way.)
class ViewHolder extends View
{
    private static const SZ2:StyleRefinement = StyleRefinement.from({ size: [520, 60] });
    public static function getSZ():StyleRefinement { return SZ2; }
    override public function render():Node
    {
        return box({ key: "v", style: SZ2 });
    }
}

step("T0 start");

// ---- (1) top level --------------------------------------------------------
var r1:StyleRefinement = StyleRefinement.from({ size: [520, 60] });
step("T1 top-level StyleRefinement.from([520,60]) ok");

// ---- (2) static const of a plain class ------------------------------------
var h:PlainHolder = new PlainHolder();
step("T2 new PlainHolder ok (its static const initializer has run by now)");
var r2:StyleRefinement = PlainHolder.SZ;
step("T3 read PlainHolder.SZ ok");

// ---- (3) static const of a View subclass ----------------------------------
var v:ViewHolder = new ViewHolder();
step("T4 new ViewHolder ok (View subclass w/ static const initializer)");
var r3:StyleRefinement = ViewHolder.getSZ();
step("T5 read ViewHolder static const via accessor ok");

step("DONE static-init shapes all survived");

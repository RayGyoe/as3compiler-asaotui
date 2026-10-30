// Does an AS3 Array keep its identity when it travels through an `Object`-typed
// parameter or slot?  asaotui's style layer (Size/LengthEdges/Edges/Corners/Fill/
// Style) splits `fromAny(o:Object)` (scalar only) from `fromArray(a:Array)` on the
// claim that `o is Array` becomes FALSE for an Array in an `Object` slot, and that
// a following `o is <userClass>` can even SIGSEGV.  This probe measures the claim
// against the CURRENT compiler (run: see README.md).

import flash.filesystem.File;
import flash.filesystem.FileMode;
import flash.filesystem.FileStream;

// stdout is lost when a process dies on a SIGSEGV, so every line goes to a FILE
// and is appended+flushed immediately (the "invisible != fine" rule).
var LOG:String = "objarr.log.txt";
function log(s:String):void
{
    var f:File = File.applicationDirectory.resolvePath(LOG);
    var fs:FileStream = new FileStream();
    fs.open(f, FileMode.APPEND);
    fs.writeUTFBytes(s + "\n");
    fs.close();
}

class Marker { public var tag:String = "M"; }
class Other  { public var tag:String = "O"; }

function idObj(o:Object):void
{
    log("  Object param: is Array  = " + (o is Array));
    log("  Object param: is Object = " + (o is Object));
    log("  Object param: is Marker = " + (o is Marker));
    log("  Object param: is Other  = " + (o is Other));
}

function idStar(o:*):void
{
    log("  * param: is Array  = " + (o is Array));
    log("  * param: is Marker = " + (o is Marker));
}

log("STEP 1: about to declare the Array");
var a:Array = [1, 2, 3];
log("STEP 2: a is Array = " + (a is Array) + " len = " + a.length);

log("STEP 3: entering Object-typed parameter");
idObj(a);
log("STEP 4: returned from Object-typed parameter");

log("STEP 5: entering *-typed parameter");
idStar(a);
log("STEP 6: returned from *-typed parameter");

var b:Array = a as Array;
log("STEP 7: as-cast back: b is Array = " + (b is Array) + " len = " + (b != null ? b.length : -1));

log("STEP 8: Array(a).length = " + Array(a).length);

log("STEP 9: a user class through the SAME Object parameter");
var m:Marker = new Marker();
idObj(m);
log("STEP 10: returned from user-class Object parameter");

log("DONE");
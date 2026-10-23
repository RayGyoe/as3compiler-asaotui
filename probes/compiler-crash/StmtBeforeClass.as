// probes/compiler-crash/StmtBeforeClass.as -- minimal repro for 0xC0000005.
//
// EVIDENCE THAT STARTED THIS: ui-demo/CheckUi.exe is GREEN (status 0, 25 lines,
// "RESULT: PASS"), while ui-demo/CheckUiDbg.exe -- the same program with logging
// added -- dies instantly with status 3221225477 (0xC0000005,
// EXCEPTION_ACCESS_VIOLATION) and prints NOTHING to stdout. An access violation
// with no output is a codegen-class failure, not an authoring mistake, so it is
// worth a minimal repro.
//
// The one structural thing CheckUiDbg does that neither the working CheckUi.as nor
// the other probes do: it runs an EXECUTABLE top-level statement BEFORE a `class`
// declaration in the same script file:
//
//     log("START");                       <-- executable statement, class not seen yet
//     ...
//     class CheckView extends View { ... }  <-- the class it later instantiates
//     var view:CheckView = new CheckView();
//
// This file reproduces exactly that ordering with nothing else in the picture: no
// toolkit, no View, no layout -- a plain class, one statement before it, one
// instantiation after.
import flash.filesystem.File;
import flash.filesystem.FileMode;
import flash.filesystem.FileStream;

var LOGFILE:File = File.applicationDirectory.resolvePath("stmt.txt");
function log(msg:String):void
{
    var fs:FileStream = new FileStream();
    try { fs.open(LOGFILE, FileMode.APPEND); fs.writeUTFBytes(msg + "\n"); fs.close(); }
    catch (e:Error) { }
}

log("before class: statement ran");

class C
{
    public var n:int;
    public function C():void { this.n = 7; }
    public function twice():int { return this.n * 2; }
}

var c:C = new C();
log("after class: c.twice() = " + c.twice());
log("DONE");

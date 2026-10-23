// Two experiments:
//  (1) push an instance of a script-level CLASS into a script-scope array
//  (2) does the timer pump survive an exception thrown inside a timer callback?
import flash.filesystem.File;
import flash.filesystem.FileMode;
import flash.filesystem.FileStream;
import flash.utils.setTimeout;

var LOG:String = "arrpush2.log.txt";

class ZPt
{
    public var x:int;
    public function ZPt():void { this.x = 0; }
}

function log(s:String):void
{
    var f:File = new File(LOG);
    var fs:FileStream = new FileStream();
    fs.open(f, FileMode.APPEND);
    fs.writeUTFBytes(s + "\n");
    fs.close();
}

log("A start");

// ---- experiment 1: array of class instances --------------------------------
var pts:Array = [];
log("B pts declared");
var i:int = 0;
while (i < 5)
{
    var p:ZPt = new ZPt();
    p.x = 100 + i;
    log("C before push " + i);
    pts.push(p);
    log("D pushed " + i + ", len=" + pts.length);
    i = i + 1;
}
log("E after loop len=" + pts.length);
var back:ZPt = ZPt(pts[2]);
log("F read back [2].x=" + back.x);

// ---- experiment 2: does the pump survive a throwing callback? --------------
function boom():void
{
    log("G boom entering");
    var bad:* = null;
    bad.nope = 1;          // deliberately throws
    log("H boom survived (NOT reached if it throws)");
}

function after():void
{
    log("I after() ran -- the timer pump survived");
}

function next():void
{
    log("J next() ran");
    log("K DONE");
}

setTimeout(boom, 200);
setTimeout(after, 500);
setTimeout(next, 700);

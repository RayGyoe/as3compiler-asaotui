// Minimal repro: which Array operation on a SCRIPT-SCOPE array kills the process?
import flash.filesystem.File;
import flash.filesystem.FileMode;
import flash.filesystem.FileStream;

var LOG:String = "arrpush.log.txt";

function log(s:String):void
{
    var f:File = new File(LOG);
    var fs:FileStream = new FileStream();
    fs.open(f, FileMode.APPEND);
    fs.writeUTFBytes(s + "\n");
    fs.close();
}

log("A start");

var empty:Array = [];
log("B empty declared, len=" + empty.length);

empty.push(1);
log("C pushed 1, len=" + empty.length);

empty.push(2);
log("D pushed 2, len=" + empty.length + " [0]=" + empty[0] + " [1]=" + empty[1]);

var lit:Array = [7, 8, 9];
log("E literal len=" + lit.length + " [0]=" + lit[0] + " [2]=" + lit[2]);

lit.push(10);
log("F lit pushed, len=" + lit.length + " [3]=" + lit[3]);

var typed:Array = new Array();
log("G new Array() len=" + typed.length);
typed.push(5);
log("H typed pushed, len=" + typed.length);

var i:int = 0;
while (i < 3) { empty.push(100 + i); i = i + 1; }
log("I loop pushed, len=" + empty.length);

log("J DONE");

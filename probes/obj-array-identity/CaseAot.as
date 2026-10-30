// CaseAot.as -- AOT arm driver (top-level script; our compiler).
//
// Reads the case id from `select.txt`, writes ONE line of result to `out.txt`.
// One process per case on purpose: a case that SIGSEGVs must not take the rest
// of the table with it (that is exactly how the Array-identity bug shows up).
import flash.filesystem.File;
import flash.filesystem.FileMode;
import flash.filesystem.FileStream;

function readAll(name:String):String
{
    var f:File = File.applicationDirectory.resolvePath(name);
    var fs:FileStream = new FileStream();
    fs.open(f, FileMode.READ);
    var s:String = fs.readUTFBytes(fs.bytesAvailable);
    fs.close();
    return s;
}

function writeAll(name:String, s:String):void
{
    var f:File = File.applicationDirectory.resolvePath(name);
    var fs:FileStream = new FileStream();
    fs.open(f, FileMode.WRITE);
    fs.writeUTFBytes(s);
    fs.close();
}

var id:int = int(readAll("select.txt"));
var line:String = Cases.one(id);
writeAll("out.txt", line + "\n");

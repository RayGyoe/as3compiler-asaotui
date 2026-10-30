// BenchAot.as -- AOT arm driver (top-level script; our compiler).
import flash.filesystem.File;
import flash.filesystem.FileMode;
import flash.filesystem.FileStream;

var f:File = File.applicationDirectory.resolvePath("vec-aot.txt");
var fs:FileStream = new FileStream();
fs.open(f, FileMode.WRITE);
fs.writeUTFBytes(BenchCore.run());
fs.close();
trace(BenchCore.run());
// Probe: does route 1 (runtime File/FileStream read) work on our own AOT?
import flash.filesystem.File;
import flash.filesystem.FileStream;
import flash.filesystem.FileMode;

var f:File = new File('../asaotui/diff-check/spec/cases.txt');
trace('nativePath=' + f.nativePath);
trace('exists=' + f.exists);
var fs:FileStream = new FileStream();
fs.open(f, FileMode.READ);
var all:String = fs.readUTFBytes(fs.bytesAvailable);
fs.close();
trace('len=' + all.length);
trace('first=' + all.substr(0, 20));
trace('PROBE_OK');

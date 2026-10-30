// AotMain.as -- AOT arm driver (top-level script; our compiler).
//
// The loop bound mirrors AirMain: the same GetFmtCases.one(id) calls, written to
// the same line format, so the two output files can be diffed line for line.
// `COUNT` is read as a literal on purpose -- it keeps this driver independent of
// any static-init behaviour, so a failure can only come from getTextFormat().
import flash.filesystem.File;
import flash.filesystem.FileMode;
import flash.filesystem.FileStream;

var i:int = 1;
while (i <= 30)
{
    var f:File = File.applicationDirectory.resolvePath("g21-gettextformat-aot.txt");
    var st:FileStream = new FileStream();
    st.open(f, FileMode.APPEND);
    st.writeUTFBytes("id=" + i + " " + GetFmtCases.one(i) + "\n");
    st.close();
    i++;
}
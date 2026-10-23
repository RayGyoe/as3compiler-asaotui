// AotMain.as -- AOT arm driver (top-level script; our compiler).
//
// Same case table, same file format as the AIR arm. Each line is appended
// IMMEDIATELY, so a mid-run crash still shows how far it got. The runner sets cwd
// to this directory, so the relative name lands next to the probe.
import flash.filesystem.File;
import flash.filesystem.FileMode;
import flash.filesystem.FileStream;

var i:int = 1;
while (i <= NullCases.COUNT)
{
    var f:File = new File("g16-ternary-null-aot.txt");
    var st:FileStream = new FileStream();
    st.open(f, FileMode.APPEND);
    st.writeUTFBytes("id=" + i + " " + NullCases.one(i) + "\n");
    st.close();
    i++;
}

// AotMain.as -- AOT arm driver (top-level script; our compiler).
//
// Runs every case in ONE process and appends each line to `style-fromany-aot.txt`
// IMMEDIATELY, so a mid-run crash still shows how far it got. Windows drew no
// console here, hence the file. (Same shape as probes/obj-array-identity/CaseAot.as,
// except that no case is expected to crash any more -- if one does, the line count
// is the evidence.) The runner sets cwd to this directory, so the relative name
// lands next to the probe.
import flash.filesystem.File;
import flash.filesystem.FileMode;
import flash.filesystem.FileStream;

var i:int = 1;
while (i <= StyleCases.COUNT)
{
    var f:File = File.applicationDirectory.resolvePath("style-fromany-aot.txt");
    var st:FileStream = new FileStream();
    st.open(f, FileMode.APPEND);
    st.writeUTFBytes("id=" + i + " " + StyleCases.one(i) + "\n");
    st.close();
    i++;
}

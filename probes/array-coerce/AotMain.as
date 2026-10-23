// AOT arm driver: same Cases, evidence is a file (no console on a window build).
import flash.filesystem.File;
import flash.filesystem.FileMode;
import flash.filesystem.FileStream;

for (var i:int = 1; i <= Cases.COUNT; i++)
{
    var f:File = new File("arr-aot.txt");
    var st:FileStream = new FileStream();
    st.open(f, FileMode.APPEND);
    st.writeUTFBytes("id=" + i + " " + Cases.one(i) + "\n");
    st.close();
}

// AotMain.as -- AOT arm driver (top-level script; our compiler).
//
// The loop bound is a literal on purpose: reading `ClosureCases.SOME_STATIC`
// here would run that class's `_cinit()` through the normal (guarded) path and
// hide the very defect this probe measures.
import flash.filesystem.File;
import flash.filesystem.FileMode;
import flash.filesystem.FileStream;

var i:int = 1;
while (i <= 10)
{
    var f:File = new File("g22-closure-statics-aot.txt");
    var st:FileStream = new FileStream();
    st.open(f, FileMode.APPEND);
    st.writeUTFBytes("id=" + i + " " + ClosureCases.one(i) + "\n");
    st.close();
    i++;
}
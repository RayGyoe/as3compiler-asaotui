// CaseAir.as -- AIR arm driver (document class; mxmlc -> adl).
//
// Runs EVERY case in one process and appends each line to `objarr-air.txt`
// immediately, so the file survives even a crash. Windows `adl.exe` has no
// console, hence the file (measured, see ../../air-check/README.md).
package
{
    import flash.desktop.NativeApplication;
    import flash.display.Sprite;
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;

    public class CaseAir extends Sprite
    {
        public function CaseAir()
        {
            var path:String = File.applicationDirectory.nativePath + File.separator + "objarr-air.txt";
            for (var id:int = 1; id <= Cases.COUNT; id++)
            {
                var f:File = new File(path);
                var st:FileStream = new FileStream();
                st.open(f, FileMode.APPEND);
                st.writeUTFBytes("id=" + id + " " + Cases.one(id) + "\n");
                st.close();
            }
            NativeApplication.nativeApplication.exit();
        }
    }
}

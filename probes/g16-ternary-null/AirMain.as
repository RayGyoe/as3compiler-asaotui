// AirMain.as -- AIR arm driver (document class; mxmlc -> adl). This is the
// REFERENCE arm: whatever it prints IS the AS3 semantics. The AIR debug launcher has
// no console on Windows, so the evidence is a file.
package
{
    import flash.desktop.NativeApplication;
    import flash.display.Sprite;
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;

    public class AirMain extends Sprite
    {
        public function AirMain()
        {
            // `File(".")` is an ArgumentError #2004 under the AIR debug launcher
            // (measured); the app directory is the portable anchor, and under
            // `adl app.xml` it IS this probe directory.
            var path:String = File.applicationDirectory.nativePath + File.separator + "g16-ternary-null-air.txt";
            for (var i:int = 1; i <= NullCases.COUNT; i++)
            {
                var f:File = File.applicationDirectory.resolvePath(path);
                var st:FileStream = new FileStream();
                st.open(f, FileMode.APPEND);
                st.writeUTFBytes("id=" + i + " " + NullCases.one(i) + "\n");
                st.close();
            }
            NativeApplication.nativeApplication.exit();
        }
    }
}

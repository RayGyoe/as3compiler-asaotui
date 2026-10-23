// AirMain.as -- AIR arm driver (document class; mxmlc -> adl).
//
// Same case table, same file format, different runtime: this is the REFERENCE
// arm. `adl.exe` has no console on Windows, so the evidence is a file.
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
            // `File(".")` is an ArgumentError #2004 under adl (measured) -- the app
            // directory is the portable anchor, and under `adl app.xml` it IS this
            // probe directory.
            var path:String = File.applicationDirectory.nativePath + File.separator + "style-fromany-air.txt";
            for (var i:int = 1; i <= StyleCases.COUNT; i++)
            {
                var f:File = new File(path);
                var st:FileStream = new FileStream();
                st.open(f, FileMode.APPEND);
                st.writeUTFBytes("id=" + i + " " + StyleCases.one(i) + "\n");
                st.close();
            }
            NativeApplication.nativeApplication.exit();
        }
    }
}

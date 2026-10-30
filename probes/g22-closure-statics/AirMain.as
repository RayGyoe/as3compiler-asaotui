// AirMain.as -- AIR arm driver (document class; mxmlc -> adl). REFERENCE arm.
//
// Same case table and file format as the AOT arm. The AIR debug launcher has no
// console on Windows, so the evidence is a file.
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
            // `new File("relative.txt")` is ArgumentError #2004 under adl; the
            // application directory is the portable anchor and under
            // `adl app.xml` it IS this probe directory.
            var path:String = File.applicationDirectory.nativePath + File.separator + "g22-closure-statics-air.txt";
            for (var i:int = 1; i <= 10; i++)
            {
                var f:File = File.applicationDirectory.resolvePath(path);
                var st:FileStream = new FileStream();
                st.open(f, FileMode.APPEND);
                st.writeUTFBytes("id=" + i + " " + ClosureCases.one(i) + "\n");
                st.close();
            }
            NativeApplication.nativeApplication.exit();
        }
    }
}
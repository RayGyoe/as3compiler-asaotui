// BenchAir.as -- AIR arm driver (document class; mxmlc -> adl).
package
{
    import flash.desktop.NativeApplication;
    import flash.display.Sprite;
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;

    public class BenchAir extends Sprite
    {
        public function BenchAir()
        {
            var p:String = File.applicationDirectory.nativePath + File.separator + "vec-air.txt";
            var f:File = File.applicationDirectory.resolvePath(p);
            var st:FileStream = new FileStream();
            st.open(f, FileMode.WRITE);
            st.writeUTFBytes(BenchCore.run());
            st.close();
            NativeApplication.nativeApplication.exit();
        }
    }
}
// G9Air.as -- AIR arm: mxmlc compiles this + G9Cases.as, adl runs it.
// Result goes to a FILE because adl.exe on Windows has no console (measured,
// see ../../air-check/README.md). Throwaway probe, not a library test.
package
{
    import flash.desktop.NativeApplication;
    import flash.display.Sprite;
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;

    public class G9Air extends Sprite
    {
        public function G9Air()
        {
            var body:String = G9Cases.run();
            var dir:String = File.applicationDirectory.nativePath;
            var f:File = File.applicationDirectory.resolvePath(dir + File.separator + "g9-air.txt");
            var st:FileStream = new FileStream();
            st.open(f, FileMode.WRITE);
            st.writeUTFBytes("AIR " + NativeApplication.nativeApplication.runtimeVersion);
            st.writeUTFBytes(String.fromCharCode(10));
            st.writeUTFBytes(body);
            st.writeUTFBytes(String.fromCharCode(10));
            st.close();
            NativeApplication.nativeApplication.exit();
        }
    }
}
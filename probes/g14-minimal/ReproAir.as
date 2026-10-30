// probes/g14-minimal/ReproAir.as -- the same three steps on real AIR (mxmlc + adl),
// so the expected answers in ReproAot.as are measured against the reference runtime
// rather than asserted from memory.
//
// Windows `adl.exe` has no console, so the evidence goes to a file (same shape as
// ../../air-check/README.md explains).
package
{
    import flash.desktop.NativeApplication;
    import flash.display.Sprite;
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;

    public class ReproAir extends Sprite
    {
        public function ReproAir()
        {
            var path:String = File.applicationDirectory.nativePath + File.separator + "g14-air.txt";
            var o:Object = [1, 2, 3];
            emit(path, "is Array  = " + (o is Array) + "     (AS3 rule: true)");
            emit(path, "is Marker = " + (o is Marker) + "     (AS3 rule: false)");
            emit(path, "REACHED THE END (no crash)");
            NativeApplication.nativeApplication.exit();
        }

        private function emit(path:String, line:String):void
        {
            var f:File = File.applicationDirectory.resolvePath(path);
            var st:FileStream = new FileStream();
            st.open(f, FileMode.APPEND);
            st.writeUTFBytes(line + "\n");
            st.close();
        }
    }
}

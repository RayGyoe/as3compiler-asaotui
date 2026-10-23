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
            var path:String = File.applicationDirectory.nativePath + File.separator + "arr-air.txt";
            for (var i:int = 1; i <= Cases.COUNT; i++)
            {
                var f:File = new File(path);
                var st:FileStream = new FileStream();
                st.open(f, FileMode.APPEND);
                st.writeUTFBytes("id=" + i + " " + Cases.one(i) + "\n");
                st.close();
            }
            NativeApplication.nativeApplication.exit();
        }
    }
}

// AirMain.as — AIR arm driver (document class; `adl app.xml` has no console on
// Windows, so the evidence is the file SetFmtCases.report writes).
package
{
    import flash.desktop.NativeApplication;
    import flash.display.Sprite;

    public class AirMain extends Sprite
    {
        public function AirMain()
        {
            SetFmtCases.report("g20-settextformat-air.txt");
            NativeApplication.nativeApplication.exit();
        }
    }
}
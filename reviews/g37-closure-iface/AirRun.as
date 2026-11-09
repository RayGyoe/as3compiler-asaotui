package
{
    import flash.display.Sprite;
    import flash.desktop.NativeApplication;
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;
    import flash.utils.Timer;
    import flash.events.TimerEvent;

    public class Repro3Main extends Sprite
    {
        public function Repro3Main()
        {
            out("start");
            follow(new EnvImpl());
            out("end");
            var t:Timer = new Timer(200, 1);
            t.addEventListener(TimerEvent.TIMER, function (ev:TimerEvent):void { NativeApplication.nativeApplication.exit(0); });
            t.start();
        }
        private function follow(e:IEnv):void
        {
            e.subscribe(function (d:int):void { out("cb " + e.locale + d); });
        }
        public static function out(s:String):void
        {
            var f:File = File.applicationStorageDirectory.resolvePath("g37.out");
            var st:FileStream = new FileStream();
            st.open(f, FileMode.APPEND);
            st.writeUTFBytes(s + "\n");
            st.close();
        }
    }
}
interface IEnv { function get locale():String; function subscribe(f:Function):void; }
class EnvImpl implements IEnv
{
    public function get locale():String { return "zh-CN"; }
    public function subscribe(f:Function):void { f(1); }
}

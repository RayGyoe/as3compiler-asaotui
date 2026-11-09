function follow(e:IEnv):void
{
    var first:String = e.locale;
    trace(first);
    e.subscribe(function (d:int):void {
        var tag:String = e.locale;
        trace(tag + d);
    });
}
var x:IEnv = new EnvImpl();
follow(x);
interface IEnv { function get locale():String; function subscribe(f:Function):void; }
class EnvImpl implements IEnv
{
    public function get locale():String { return "zh-CN"; }
    public function subscribe(f:Function):void { f(1); }
}

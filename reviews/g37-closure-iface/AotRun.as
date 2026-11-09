function follow(e:IEnv):void
{
    e.subscribe(function (d:int):void { trace(e.locale + d); });
}
follow(new EnvImpl());
interface IEnv { function get locale():String; function subscribe(f:Function):void; }
class EnvImpl implements IEnv
{
    public function get locale():String { return "zh-CN"; }
    public function subscribe(f:Function):void { f(1); }
}

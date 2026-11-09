var t:IThing = new Thing();
trace(t.label);
var g:Function = function (d:int):void {
    var s:String = t.label;
    trace(s + d);
};
var h:Function = function (d:int):void { trace(IThing(t).name()); };
g(1);
h(2);
interface IThing { function get label():String; function name():String; }
class Thing implements IThing
{
    public function get label():String { return "L"; }
    public function name():String { return "N"; }
}

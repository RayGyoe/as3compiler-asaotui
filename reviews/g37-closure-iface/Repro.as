var t:IThing = new Thing();
var g:Function = function ():String { return t.name(); };
var s:String = g();
interface IThing { function name():String; }
class Thing implements IThing { public function name():String { return "ok"; } }

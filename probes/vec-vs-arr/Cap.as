import flash.utils.getTimer;
var a:Array = [];
var v:Vector.<int> = new Vector.<int>();
var w:Vector.<Number> = new Vector.<Number>();
var i:int = 0;
while (i < 5) { a.push(i); v.push(i); w.push(i * 1.5); i++; }
trace("array len", a.length, "vector len", v.length, "numvec len", w.length);
trace("v[2]=", v[2], "w[2]=", w[2], "a[2]=", a[2]);
var t0:int = getTimer();
var s:Number = 0;
for (var k:int = 0; k < w.length; k++) s = s + w[k];
trace("sum", s, "ms", getTimer() - t0);

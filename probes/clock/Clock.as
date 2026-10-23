// probes/clock/Clock.as -- which wall clock can an AS3 source reach?
//
// NEADED BY: the animation seam. A tween must advance on WALL TIME, not on frame
// count -- a frame-counted tween runs at a different speed on a 60Hz and a
// 120Hz machine. `View.tick(nowMs)` therefore hands the view a millisecond
// value, and UiApp has to produce it. This probe measures which of the three
// plausible spellings actually works in our AOT, so UiApp does not depend on a
// guess.
import flash.utils.getTimer;
import flash.filesystem.File;
import flash.filesystem.FileMode;
import flash.filesystem.FileStream;

var a:Number = new Date().getTime();
var b:Number = getTimer();
var c:Number = new Date().getTime();   // Date.now() is NOT available (Codegen error: undefined static method 'now')

var out:String = "";
out = out + "Date.getTime = " + a + "\n";
out = out + "getTimer()   = " + b + "\n";
out = out + "Date.now()   = " + c + "\n";
out = out + "getTimer-a   = " + (b - a) + "\n";
out = out + "Date.now-b   = " + (c - b) + "\n";
out = out + "a > 1e12     = " + (a > 1000000000000) + "\n";

// getTimer() is documented as "ms since the program started", so a 0 read at
// startup is plausible. Spin until WALL TIME advances 300ms and read it again:
// if it is still 0 it is a stub; if it advanced ~300 it is real.
var t0:Number = getTimer();
var start:Number = new Date().getTime();
var spin:int = 0;
while (new Date().getTime() - start < 300) { spin = spin + 1; }
var t1:Number = getTimer();
out = out + "--- after a 300ms wall-clock spin ---" + "\n";
out = out + "getTimer before/after = " + t0 + "/" + t1 + "\n";
out = out + "advanced              = " + (t1 - t0) + "\n";
out = out + "spin iterations       = " + spin + "\n";

var f:File = new File("clock.txt");
var s:FileStream = new FileStream();
s.open(f, FileMode.WRITE);
s.writeUTFBytes(out);
s.close();
trace(out);
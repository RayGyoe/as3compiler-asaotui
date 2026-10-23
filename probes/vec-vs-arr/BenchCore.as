// BenchCore.as -- ONE benchmark body, shared by BOTH arms (our AOT, and real AIR
// through mxmlc/adl). Same N, same loops, same timing primitive (`getTimer`), so
// a difference is a runtime difference and not a harness difference.
//
// Reported number = best (minimum) of R runs, in ms. Best-of is used because we
// want the cost of the WORK, not the cost of whatever else the process was doing.
package
{
    import flash.utils.getTimer;

    public class BenchCore
    {
        public static const N:int = 1000000;   // elements per run
        public static const R:int = 5;         // runs; best is reported

        // ---- fill (push) + sum by index ------------------------------------
        private static function arrFillSum():int
        {
            var a:Array = [];
            var i:int = 0;
            while (i < N) { a.push(i); i++; }
            var s:Number = 0;
            var k:int = 0;
            while (k < N) { s = s + Number(a[k]); k++; }
            return s > 0 ? 1 : 0;   // consume the result so nothing is dead
        }

        private static function vecIntFillSum():int
        {
            var v:Vector.<int> = new Vector.<int>();
            var i:int = 0;
            while (i < N) { v.push(i); i++; }
            var s:Number = 0;
            var k:int = 0;
            while (k < N) { s = s + v[k]; k++; }
            return s > 0 ? 1 : 0;
        }

        private static function vecNumFillSum():int
        {
            var v:Vector.<Number> = new Vector.<Number>();
            var i:int = 0;
            while (i < N) { v.push(i); i++; }
            var s:Number = 0;
            var k:int = 0;
            while (k < N) { s = s + v[k]; k++; }
            return s > 0 ? 1 : 0;
        }

        // ---- preallocated (new Vector.<T>(N)) + write-by-index + read ------
        private static function vecIntPrealloc():int
        {
            var v:Vector.<int> = new Vector.<int>(N);
            var i:int = 0;
            while (i < N) { v[i] = i; i++; }
            var s:Number = 0;
            var k:int = 0;
            while (k < N) { s = s + v[k]; k++; }
            return s > 0 ? 1 : 0;
        }

        private static function arrPrealloc():int
        {
            var a:Array = [];
            a.length = N;
            var i:int = 0;
            while (i < N) { a[i] = i; i++; }
            var s:Number = 0;
            var k:int = 0;
            while (k < N) { s = s + Number(a[k]); k++; }
            return s > 0 ? 1 : 0;
        }

        // ---- read-only sum over a vector built once ------------------------
        public static function run():String
        {
            var out:String = "";
            out += "N=" + N + "  best of " + R + "  (ms)\n";
            out += line("Array           fill+sum ", best(arrFillSum));
            out += line("Vector.<int>    fill+sum ", best(vecIntFillSum));
            out += line("Vector.<Number> fill+sum ", best(vecNumFillSum));
            out += line("Array           prealloc ", best(arrPrealloc));
            out += line("Vector.<int>    prealloc ", best(vecIntPrealloc));
            return out;
        }

        // Generic dispatch through a Function value: measured separately (below)
        // so the benchmark body itself costs the same in both arms.
        private static function best(f:Function):int
        {
            var b:int = -1;
            var r:int = 0;
            while (r < R)
            {
                var t0:int = getTimer();
                var sink:int = f();
                var dt:int = getTimer() - t0;
                if (dt <= 0) dt = 1;              // getTimer() has 1 ms granularity
                if (b < 0 || dt < b) b = dt;
                r++;
                if (sink < 0) throw new Error("unreachable");
            }
            return b;
        }

        private static function line(label:String, ms:int):String
        {
            return "  " + label + String(ms) + "\n";
        }
    }
}

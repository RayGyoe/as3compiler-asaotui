// demo/LiveMarket.as -- the simulated market the live page runs on: 22 quotes,
// each with a short price series, ticking on the app's own frame clock.
//
// WHY SIMULATED. A UI toolkit's demo must not need a network, credentials or a
// market calendar to show a moving list. Every number here is generated; the page
// says so in its footer, and nothing pretends to be a real quote.
//
// WHY THE DATA IS MUTATED IN PLACE. This is the page that showcases the toolkit's
// frame cost, so the demo must not be the thing that is slow: `step()` allocates
// nothing (the series arrays are fixed-length ring buffers, shifted in place) and
// the sparkline is handed the SAME array each render plus a bump of `rev`, which is
// exactly the "mutated in place" form SparklineNode documents. A version counter
// per symbol is one int; a fresh 24-number array per symbol per tick would be 22
// allocations 10 times a second purely to be thrown away.
//
// THE PRICE MODEL is a mean-reverting random walk: a small pull back toward the
// previous close plus a per-symbol volatility shock. It gives what a watchlist
// needs -- some names up, some down, all of them moving, none of them exploding.
package demo
{
    public class LiveMarket
    {
        // How often the page asks for a new tick. 100 ms is the honest middle: fast
        // enough to read as live, slow enough that the frame cost is what it is.
        public static const TICK_MS:int = 100;
        // Points kept per symbol. A sparkline is a shape, not a history.
        public static const SERIES:int = 24;
        // The composite index's opening level; the percentage is against THIS.
        public static const INDEX_BASE:Number = 10000;

        public var rows:Array;      // { code, name, prev, last, high, low, vol, size, turn, series, rev, chg }
        public var clock:int;       // simulated seconds since 09:30:00
        public var ticks:int;       // quote ticks produced so far
        public var level:Number;    // the composite index
        public var up:int;          // advancers
        public var flat:int;        // unchanged
        public var down:int;        // decliners

        public function LiveMarket():void
        {
            this.rows = [];
            this.reset();
        }

        // A fresh session. Called once, and again whenever the page is re-entered
        // from a cold model (the tour renders every page in one process).
        public function reset():void
        {
            this.rows = [];
            this.clock = 0;
            this.ticks = 0;
            add("AURX", "Auriga Robotics", 128.40, 0.0021, 1.3);
            add("BLCT", "Bluetick Logistics", 46.15, 0.0012, 1.0);
            add("CRDN", "Cordon Health", 87.30, 0.0009, 1.1);
            add("DTHX", "Ditherix Labs", 15.80, 0.0028, 0.8);
            add("EVRA", "Evora Materials", 62.45, 0.0016, 1.0);
            add("FLOR", "Florin Bank", 34.20, 0.0008, 1.4);
            add("GRNT", "Granite Peak Energy", 98.75, 0.0014, 1.1);
            add("HLYN", "Hollyn Foods", 22.60, 0.0007, 0.9);
            add("ISLM", "Isolux Optics", 141.05, 0.0026, 1.0);
            add("JUNO", "Juno Analytics", 74.90, 0.0019, 1.2);
            add("KAVA", "Kavara Coffee", 18.35, 0.0011, 0.8);
            add("LRCH", "Larchwood Homes", 53.10, 0.0013, 1.0);
            add("MESA", "Mesa Verde Water", 39.85, 0.0006, 1.1);
            add("NXTG", "Nextgen Devices", 112.70, 0.0024, 1.2);
            add("ORCA", "Orca Freight", 67.25, 0.0015, 1.0);
            add("PLTO", "Pluto Media", 29.95, 0.0022, 0.9);
            add("QVST", "Quvisit Payments", 84.60, 0.0018, 1.3);
            add("RIDG", "Ridgeline Air", 57.40, 0.0017, 1.0);
            add("SOLN", "Solenne Pharma", 93.15, 0.0010, 1.1);
            add("TRVL", "Travelmere", 41.80, 0.0014, 0.9);
            add("UMBR", "Umbra Security", 106.30, 0.0020, 1.2);
            add("VELD", "Velden Textiles", 26.75, 0.0010, 0.8);
            this.recount();
        }

        private function add(code:String, name:String, prev:Number, vol:Number, size:Number):void
        {
            var s:Object = {};
            s.code = code;
            s.name = name;
            s.prev = prev;
            // A random opening gap, so the first frame already has a direction.
            s.last = prev * (1 + (Math.random() - 0.5) * 0.012);
            s.high = s.last;
            s.low = s.last;
            s.vol = vol;
            s.size = size;
            s.turn = prev * size * 1000;
            s.rev = 0;
            s.series = [];
            s.chg = 0;
            this.seed(s);
            this.rows.push(s);
        }

        // A plausible 24-point history ENDING at `last`: a walk from a start near
        // the previous close, with the final point pinned so the line's tip and the
        // quote can never disagree.
        private function seed(s:Object):void
        {
            var first:Number = Number(s.prev) * (1 + (Math.random() - 0.5) * 0.01);
            var step:Number = (Number(s.last) - first) / SERIES;
            var v:Number = first;
            for (var i:int = 0; i < SERIES; i++)
            {
                v = v + step + (Math.random() - 0.5) * Number(s.prev) * Number(s.vol) * 1.6;
                s.series.push(v);
            }
            s.series[SERIES - 1] = s.last;
        }

        // One quote tick. Prices move, the series shift by one, the composite is
        // recomputed from the prices -- never accumulated, so it cannot drift.
        public function step():void
        {
            var n:int = this.rows.length;
            var sum:Number = 0;
            for (var i:int = 0; i < n; i++)
            {
                var s:Object = this.rows[i];
                var last:Number = Number(s.last);
                var prev:Number = Number(s.prev);
                // Mean reversion (3% of the gap, per tick) + a volatility shock.
                var drift:Number = ((prev - last) / prev) * 0.03;
                var shock:Number = (Math.random() - 0.5) * Number(s.vol);
                last = last * (1 + drift + shock);
                if (last < 1) last = 1;
                s.last = last;
                if (last > Number(s.high)) s.high = last;
                if (last < Number(s.low)) s.low = last;
                s.turn = Number(s.turn) + Math.random() * Number(s.size) * 100;
                var series:Array = s.series as Array;
                series.push(last);
                if (series.length > SERIES) series.shift();
                s.rev = int(s.rev) + 1;
                s.chg = (last - prev) / prev * 100;
                sum = sum + last / prev;
            }
            if (n > 0) this.level = INDEX_BASE * (sum / n);
            this.ticks = this.ticks + 1;
            // Three simulated seconds per tick: a session is 6.5 hours, so a full
            // day plays out in about thirteen real minutes.
            this.clock = (this.clock + 3) % 23400;
            this.recount();
        }

        // Advancers / unchanged / decliners, and the level at rest (before the
        // first tick, the composite still has to read something sensible).
        public function recount():void
        {
            var n:int = this.rows.length;
            var sum:Number = 0;
            var u:int = 0, f:int = 0, d:int = 0;
            for (var i:int = 0; i < n; i++)
            {
                var s:Object = this.rows[i];
                var chg:Number = (Number(s.last) - Number(s.prev)) / Number(s.prev);
                s.chg = chg * 100;
                sum = sum + 1 + chg;
                if (s.chg > 0.005) u = u + 1;
                else if (s.chg < -0.005) d = d + 1;
                else f = f + 1;
            }
            this.up = u; this.down = d; this.flat = f;
            if (n > 0) this.level = INDEX_BASE * (sum / n);
        }

        // ---- formatting (the page's own number voice) -----------------------
        public static function price(v:Number):String
        {
            return Number(v).toFixed(2);
        }

        public static function signed(v:Number):String
        {
            return (v < 0 ? "" : "+") + Number(v).toFixed(2);
        }

        // 10,432.15 -- a six-figure index reads as a number only when it is grouped.
        public static function grouped(v:Number):String
        {
            var s:String = Number(v).toFixed(2);
            var dot:int = s.indexOf(".");
            var whole:String = s.substring(0, dot);
            var frac:String = s.substring(dot);
            var out:String = "";
            var n:int = whole.length;
            for (var i:int = 0; i < n; i++)
            {
                if (i > 0 && (n - i) % 3 == 0) out = out + ",";
                out = out + whole.charAt(i);
            }
            return out + frac;
        }

        // 09:30:00 + `clock`, as a session clock.
        public static function time(clock:int):String
        {
            var t:int = 9 * 3600 + 30 * 60 + clock;
            var h:int = int(t / 3600) % 24;
            var m:int = int(t / 60) % 60;
            var s:int = t % 60;
            return pad(h) + ":" + pad(m) + ":" + pad(s);
        }

        private static function pad(v:int):String
        {
            return v < 10 ? "0" + v : String(v);
        }
    }
}
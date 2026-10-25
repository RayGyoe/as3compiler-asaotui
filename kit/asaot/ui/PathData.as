// asaot.ui.PathData -- SVG path data ("M4 12 H20") into a flat command list.
//
// WHY THIS IS IN THE LIBRARY AND NOT IN THE COMPILER. The engine has `moveTo`,
// `lineTo` and a QUADRATIC `curveTo` -- no cubic and no `drawPath` (compiler-gaps.md
// G26). Icon sets are authored as SVG paths, and the overwhelming majority of their
// curves are CUBIC, so something has to bridge the two. Doing it here, in AS3, means
// both arms (our AOT and `adl`) run the SAME subdivision and therefore draw the SAME
// pixels: a difference between the arms would be a difference between two runs of one
// program, which is not possible.
//
// WHAT IS SUPPORTED, AND WHAT THROWS
// ----------------------------------
//   M m  L l  H h  V v  Z z      exact (straight segments)
//   Q q  T t                     exact (the engine's own quadratic + reflection)
//   C c  S s                     converted to quadratics, see below
//   A a                          THROWS. An SVG arc is not a bezier; the standard route
//                                is arc -> cubic -> quadratic, and the cubic step is
//                                the one the engine lacks. Refusing is the honest
//                                outcome: silently drawing a straight chord for an
//                                arc is exactly the "looks like it works" failure this
//                                project refuses. Use Q/T, or a circle, or a filled
//                                icon set whose data has no arcs.
//   anything else                THROWS, with the offset.
//
// CUBIC -> QUADRATIC IS A MEASUREMENT, NOT A GUESS. A cubic B with controls
// P0..P3 is replaced by the quadratic with the same endpoints and control
// (3(P1+P2) - (P0+P3)) / 4; the standard bound on the deviation is
//     (sqrt(3)/36) * |P0 - 3 P1 + 3 P2 - P3|   ~=   0.0481 * |D|.
// If that bound is above the tolerance the cubic is split in half (de Casteljau) and
// both halves are tried again, so the emitted quads are within `tol` of the real
// curve. The split point of the FIRST subdivision is the cubic's own t = 0.5 point,
// so the mid-point of a curve is exact to the pixel -- which is what the icon probe
// asserts.
//
// The tolerance is passed in VIEWBOX units by the caller, which knows the render
// scale: IconWidget asks for 0.25 / scale, i.e. a quarter of a rendered pixel at any
// size.
package asaot.ui
{
    public class PathData
    {
        // Op codes of the returned commands. Each entry is an Array:
        //   MOVE / LINE  [op, x, y]
        //   QUAD         [op, cx, cy, x, y]      (control point first, like curveTo)
        //   CLOSE        [op]
        public static const MOVE:int = 1;
        public static const LINE:int = 2;
        public static const QUAD:int = 3;
        public static const CLOSE:int = 4;

        // Offsets into a command array, so callers never index by magic numbers.
        public static const X:int = 1;
        public static const Y:int = 2;
        public static const CX:int = 1;
        public static const CY:int = 2;

        // Recursion stops here whatever the tolerance says: an icon that needs more
        // than this many halves has a degenerate control polygon (P1 == P2 in the
        // middle of a straight line), and 2^8 quads would be a bug, not detail.
        private static const MAX_DEPTH:int = 8;

        private var src:String;
        private var i:int;
        private var len:int;
        private var out:Array;
        private var tol:Number;
        private var cx:Number;          // current point
        private var cy:Number;
        private var sx:Number;          // subpath start (the target of Z)
        private var sy:Number;
        private var qcx:Number;         // last quadratic control (for T)
        private var qcy:Number;
        private var c2x:Number;         // last CUBIC second control (for S)
        private var c2y:Number;
        private var prevCmd:String;     // for the S/T reflection rules

        public function PathData(data:String, tolerance:Number)
        {
            this.src = data == null ? "" : data;
            this.i = 0;
            this.len = this.src.length;
            this.out = [];
            this.tol = tolerance > 0 ? tolerance : 0.25;
            this.cx = 0; this.cy = 0; this.sx = 0; this.sy = 0;
            this.qcx = 0; this.qcy = 0; this.c2x = 0; this.c2y = 0;
            this.prevCmd = "";
        }

        public static function parse(data:String, tolerance:Number = 0.25):Array
        {
            return new PathData(data, tolerance).run();
        }

        public function run():Array
        {
            this.skip();
            if (this.i >= this.len) throw new Error("asaot.ui.icon: empty path data");
            var cmd:String = "";
            while (this.i < this.len)
            {
                var ch:String = this.src.charAt(this.i);
                if (isCommand(ch))
                {
                    cmd = ch;
                    this.i++;
                }
                else if (cmd == "")
                {
                    throw this.fail("path data must start with a command, found '" + ch + "'");
                }
                // The promotion of an implicit repeat happens ONLY once the next
                // character is known to start a number: otherwise `M0 0 X1 1` would be
                // read as a lineto and report "expected a number" at the junk instead of
                // naming it.
                else if (!startsNumber(ch))
                {
                    throw this.fail("unexpected '" + ch + "'");
                }
                else if (cmd == "M") cmd = "L";      // implicit repeat of a moveto is a lineto
                else if (cmd == "m") cmd = "l";

                // A relative command adds the current point to EVERY coordinate it
                // reads, and the reads happen one at a time, so the additions must be
                // made as the numbers arrive (not at the end).
                // (`toLowerCase` is not in this runtime's String surface -- the kit has
                // zero uses of it -- so the relative set is spelled out.)
                var rel:Boolean = cmd == "m" || cmd == "l" || cmd == "h" || cmd == "v"
                    || cmd == "c" || cmd == "s" || cmd == "q" || cmd == "t" || cmd == "a";
                var c:String = cmd.toUpperCase();
                var x:Number;
                var y:Number;
                if (c == "Z")
                {
                    this.closeSubpath();
                    this.prevCmd = c;
                }
                else if (c == "M")
                {
                    x = this.num(); y = this.num();
                    if (rel) { x += this.cx; y += this.cy; }
                    this.moveTo(x, y);
                    this.prevCmd = c;
                }
                else if (c == "L")
                {
                    x = this.num(); y = this.num();
                    if (rel) { x += this.cx; y += this.cy; }
                    this.lineTo(x, y);
                    this.prevCmd = c;
                }
                else if (c == "H")
                {
                    x = this.num();
                    if (rel) x += this.cx;
                    this.lineTo(x, this.cy);
                    this.prevCmd = c;
                }
                else if (c == "V")
                {
                    y = this.num();
                    if (rel) y += this.cy;
                    this.lineTo(this.cx, y);
                    this.prevCmd = c;
                }
                else if (c == "Q")
                {
                    var qx:Number = this.num();
                    var qy:Number = this.num();
                    x = this.num(); y = this.num();
                    if (rel) { qx += this.cx; qy += this.cy; x += this.cx; y += this.cy; }
                    this.quadTo(qx, qy, x, y);
                    this.prevCmd = c;
                }
                else if (c == "T")
                {
                    x = this.num(); y = this.num();
                    if (rel) { x += this.cx; y += this.cy; }
                    // The implicit control is the previous quadratic control mirrored
                    // through the current point; after anything but Q/T there is no
                    // previous one, and the spec says to use the current point.
                    var tx:Number = this.cx;
                    var ty:Number = this.cy;
                    if (this.prevCmd == "Q" || this.prevCmd == "T")
                    {
                        tx = 2 * this.cx - this.qcx;
                        ty = 2 * this.cy - this.qcy;
                    }
                    this.quadTo(tx, ty, x, y);
                    this.prevCmd = c;
                }
                else if (c == "C")
                {
                    var c1x:Number = this.num();
                    var c1y:Number = this.num();
                    var c22x:Number = this.num();
                    var c22y:Number = this.num();
                    x = this.num(); y = this.num();
                    if (rel) { c1x += this.cx; c1y += this.cy; c22x += this.cx; c22y += this.cy; x += this.cx; y += this.cy; }
                    this.cubic(this.cx, this.cy, c1x, c1y, c22x, c22y, x, y, 0);
                    this.c2x = c22x; this.c2y = c22y;
                    this.prevCmd = c;
                }
                else if (c == "S")
                {
                    var s2x:Number = this.num();
                    var s2y:Number = this.num();
                    x = this.num(); y = this.num();
                    if (rel) { s2x += this.cx; s2y += this.cy; x += this.cx; y += this.cy; }
                    // Reflected first control: mirror of the previous cubic's second
                    // control, or the current point when the previous segment was not a
                    // cubic at all.
                    var r1x:Number = this.cx;
                    var r1y:Number = this.cy;
                    if (this.prevCmd == "C" || this.prevCmd == "S")
                    {
                        r1x = 2 * this.cx - this.c2x;
                        r1y = 2 * this.cy - this.c2y;
                    }
                    this.cubic(this.cx, this.cy, r1x, r1y, s2x, s2y, x, y, 0);
                    this.c2x = s2x; this.c2y = s2y;
                    this.prevCmd = c;
                }
                else if (c == "A")
                {
                    throw this.fail("the 'A' (elliptical arc) command is not supported -- see compiler-gaps.md G26. "
                        + "An arc has to go arc -> cubic -> quadratic, and the engine has no cubic; "
                        + "drawing a chord instead would be a silent approximation. Use Q/T, or an arc-free icon set.");
                }
                else
                {
                    throw this.fail("unknown command '" + cmd + "'");
                }
                this.skip();
            }
            return this.out;
        }

        // ---- emission ----------------------------------------------------

        private function moveTo(x:Number, y:Number):void
        {
            this.out.push([MOVE, x, y]);
            this.cx = x; this.cy = y;
            this.sx = x; this.sy = y;
        }

        private function lineTo(x:Number, y:Number):void
        {
            this.out.push([LINE, x, y]);
            this.cx = x; this.cy = y;
        }

        private function quadTo(qx:Number, qy:Number, x:Number, y:Number):void
        {
            this.out.push([QUAD, qx, qy, x, y]);
            this.cx = x; this.cy = y;
            this.qcx = qx; this.qcy = qy;
        }

        private function closeSubpath():void
        {
            this.out.push([CLOSE]);
            this.cx = this.sx; this.cy = this.sy;
        }

        // Cubic -> quadratics, recursively. See the header for the bound.
        private function cubic(x0:Number, y0:Number, x1:Number, y1:Number,
                              x2:Number, y2:Number, x3:Number, y3:Number, depth:int):void
        {
            var dx:Number = x0 - 3 * x1 + 3 * x2 - x3;
            var dy:Number = y0 - 3 * y1 + 3 * y2 - y3;
            var err:Number = 0.0481 * Math.sqrt(dx * dx + dy * dy);
            if (err <= this.tol || depth >= MAX_DEPTH)
            {
                var qx:Number = (3 * (x1 + x2) - (x0 + x3)) / 4;
                var qy:Number = (3 * (y1 + y2) - (y0 + y3)) / 4;
                this.quadTo(qx, qy, x3, y3);
                return;
            }
            // de Casteljau at t = 0.5.
            var ax:Number = (x0 + x1) / 2, ay:Number = (y0 + y1) / 2;
            var bx:Number = (x1 + x2) / 2, by:Number = (y1 + y2) / 2;
            var ccx:Number = (x2 + x3) / 2, ccy:Number = (y2 + y3) / 2;
            var dx1:Number = (ax + bx) / 2, dy1:Number = (ay + by) / 2;
            var dx2:Number = (bx + ccx) / 2, dy2:Number = (by + ccy) / 2;
            var mx:Number = (dx1 + dx2) / 2, my:Number = (dy1 + dy2) / 2;
            this.cubic(x0, y0, ax, ay, dx1, dy1, mx, my, depth + 1);
            this.cubic(mx, my, dx2, dy2, ccx, ccy, x3, y3, depth + 1);
        }

        // ---- scanning ----------------------------------------------------

        private function skip():void
        {
            while (this.i < this.len)
            {
                var ch:String = this.src.charAt(this.i);
                if (ch == " " || ch == "\t" || ch == "\n" || ch == "\r" || ch == ",") this.i++;
                else return;
            }
        }

        // One number. Signs, a decimal point and an exponent are all accepted; the
        // exponent is applied by multiplication so a value like 1e-7 does not depend on
        // the string-to-number conversion of this runtime.
        private function num():Number
        {
            this.skip();
            var start:int = this.i;
            var ch:String = this.src.charAt(this.i);
            if (ch == "+" || ch == "-") this.i++;
            var digits:int = 0;
            while (this.i < this.len && isDigit(this.src.charAt(this.i))) { this.i++; digits++; }
            if (this.i < this.len && this.src.charAt(this.i) == ".")
            {
                this.i++;
                while (this.i < this.len && isDigit(this.src.charAt(this.i))) { this.i++; digits++; }
            }
            if (digits == 0) throw this.fail("expected a number, found '" + ch + "'");
            var v:Number = Number(this.src.substring(start, this.i));
            var e:String = this.i < this.len ? this.src.charAt(this.i) : "";
            if (e == "e" || e == "E")
            {
                this.i++;
                var sign:Number = 1;
                var es:String = this.src.charAt(this.i);
                if (es == "+") this.i++;
                else if (es == "-") { sign = -1; this.i++; }
                var eStart:int = this.i;
                while (this.i < this.len && isDigit(this.src.charAt(this.i))) this.i++;
                if (eStart == this.i) throw this.fail("exponent without digits");
                var exp:int = int(Number(this.src.substring(eStart, this.i))) * int(sign);
                while (exp > 0) { v = v * 10; exp--; }
                while (exp < 0) { v = v / 10; exp++; }
            }
            return v;
        }

        private function fail(msg:String):Error
        {
            return new Error("asaot.ui.icon: bad path data at offset " + this.i + ": " + msg);
        }

        private static function isDigit(ch:String):Boolean
        {
            // `"0" <= ch <= "9"` would be a string comparison; the kit has none, so it
            // goes through a literal table instead.
            return ch.length == 1 && "0123456789".indexOf(ch) >= 0;
        }

        private static function startsNumber(ch:String):Boolean
        {
            return isDigit(ch) || ch == "." || ch == "+" || ch == "-";
        }

        private static function isCommand(ch:String):Boolean
        {
            if (ch == "") return false;
            var u:String = ch.toUpperCase();
            return u == "M" || u == "L" || u == "H" || u == "V" || u == "C"
                || u == "S" || u == "Q" || u == "T" || u == "A" || u == "Z";
        }
    }
}
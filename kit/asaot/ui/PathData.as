// asaot.ui.PathData -- SVG path data ("M4 12 H20") into a flat command list.
//
// WHY THIS IS IN THE LIBRARY AND NOT IN THE COMPILER. SVG is the format icon sets are
// authored in, and `Graphics` is the format the engine draws; something has to translate.
// Doing it here, in AS3, means both arms (our AOT and `adl`) run the SAME translation
// and therefore draw the SAME pixels: a difference between the arms would be a
// difference between two runs of one program, which is not possible.
//
// HISTORY, BECAUSE IT CHANGED THE SHAPE OF THIS FILE. Until compiler-gaps.md G26 was
// fixed the engine had `moveTo` / `lineTo` / a QUADRATIC `curveTo` and nothing else, so
// C and S were APPROXIMATED by subdividing the cubic into quadratic segments, and A
// (elliptical arc) had to THROW -- it needs a cubic step the engine did not have. That
// was the honest thing to do with the tools available, and it is now gone: the engine
// draws cubics, so C and S are emitted as cubics (exact, one command each) and A is
// converted to cubics and drawn. No command in the SVG grammar is approximated any more.
//
// WHAT IS SUPPORTED, AND WHAT THROWS
// ----------------------------------
//   M m  L l  H h  V v  Z z      exact (straight segments)
//   Q q  T t                     exact (the engine's own quadratic + reflection)
//   C c  S s                     exact (Graphics.cubicCurveTo)
//   A a                          exact to within 2.7e-4 of the radius, see below
//   anything else                THROWS, with the offset.
//
// THE ARC IS THE ONE PLACE A CURVE IS STILL APPROXIMATED, AND IT HAS TO BE. AIR's
// Graphics has no arc either (this is not a gap in our compiler: the SVG arc is simply
// not an API that existed), so "arc" must become beziers. SVG 1.1 F.6.5 gives the
// endpoint -> centre parameterisation used below, and F.6.6 the radius correction. The
// sweep is split into pieces of at most 90 degrees and each piece is one cubic with the
// standard 4/3 * tan(d/4) handle; for a 90-degree piece that is within 2.7e-4 * r of the
// true arc, i.e. a fortieth of a pixel on a 48px icon, which is why there is no
// tolerance parameter any more -- the error is far below anything a raster can show.
//
// FLAGS ARE READ ONE CHARACTER AT A TIME. The SVG grammar allows an arc's two flags to
// be written without separators ("a1 1 0 011 1"), and icon files in the wild use it. A
// general "read a number" would turn "011" into eleven and then misparse the rest of the
// path, so `flag()` takes exactly one '0' or '1'.
package asaot.ui
{
    public class PathData
    {
        // Op codes of the returned commands. Each entry is an Array:
        //   MOVE / LINE  [op, x, y]
        //   QUAD         [op, cx, cy, x, y]            (control point first, like curveTo)
        //   CUBIC        [op, c1x, c1y, c2x, c2y, x, y] (like cubicCurveTo)
        //   CLOSE        [op]
        public static const MOVE:int = 1;
        public static const LINE:int = 2;
        public static const QUAD:int = 3;
        public static const CLOSE:int = 4;
        public static const CUBIC:int = 5;

        // Offsets into a command array, so callers never index by magic numbers.
        public static const X:int = 1;
        public static const Y:int = 2;
        public static const CX:int = 1;
        public static const CY:int = 2;

        private var src:String;
        private var i:int;
        private var len:int;
        private var out:Array;
        private var cx:Number;          // current point
        private var cy:Number;
        private var sx:Number;          // subpath start (the target of Z)
        private var sy:Number;
        private var qcx:Number;         // last quadratic control (for T)
        private var qcy:Number;
        private var c2x:Number;         // last CUBIC second control (for S)
        private var c2y:Number;
        private var prevCmd:String;     // for the S/T reflection rules

        public function PathData(data:String)
        {
            this.src = data == null ? "" : data;
            this.i = 0;
            this.len = this.src.length;
            this.out = [];
            this.cx = 0; this.cy = 0; this.sx = 0; this.sy = 0;
            this.qcx = 0; this.qcy = 0; this.c2x = 0; this.c2y = 0;
            this.prevCmd = "";
        }

        public static function parse(data:String):Array
        {
            return new PathData(data).run();
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
                    this.cubicTo(c1x, c1y, c22x, c22y, x, y);
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
                    this.cubicTo(r1x, r1y, s2x, s2y, x, y);
                    this.c2x = s2x; this.c2y = s2y;
                    this.prevCmd = c;
                }
                else if (c == "A")
                {
                    // rx ry x-axis-rotation large-arc-flag sweep-flag x y
                    var arx:Number = this.num();
                    var ary:Number = this.num();
                    var arot:Number = this.num();
                    var alarge:Boolean = this.flag();
                    var asweep:Boolean = this.flag();
                    x = this.num(); y = this.num();
                    // The radii and the rotation are NOT relative: only the end point is.
                    if (rel) { x += this.cx; y += this.cy; }
                    this.arcTo(arx, ary, arot, alarge, asweep, x, y);
                    this.prevCmd = c;
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

        private function cubicTo(c1x:Number, c1y:Number, c2x:Number, c2y:Number,
                                 x:Number, y:Number):void
        {
            this.out.push([CUBIC, c1x, c1y, c2x, c2y, x, y]);
            this.cx = x; this.cy = y;
        }

        private function closeSubpath():void
        {
            this.out.push([CLOSE]);
            this.cx = this.sx; this.cy = this.sy;
        }

        // ---- the one approximation: SVG arc -> cubics (SVG 1.1 F.6.5 / F.6.6) ----

        private function arcTo(rxIn:Number, ryIn:Number, rotDeg:Number,
                              large:Boolean, sweep:Boolean, x:Number, y:Number):void
        {
            var x0:Number = this.cx;
            var y0:Number = this.cy;
            // F.6.2: identical endpoints mean the arc is omitted, not drawn as a dot.
            if (x0 == x && y0 == y) return;
            var rx:Number = Math.abs(rxIn);
            var ry:Number = Math.abs(ryIn);
            // F.6.6: a zero radius degenerates to the straight line, which is what the
            // author asked for ("no curvature here"), not an error.
            if (rx == 0 || ry == 0) { this.lineTo(x, y); return; }

            var phi:Number = rotDeg * Math.PI / 180;
            var cosP:Number = Math.cos(phi);
            var sinP:Number = Math.sin(phi);
            // Step 1: the chord's midpoint in the ellipse's own (unrotated) frame.
            var hdx:Number = (x0 - x) / 2;
            var hdy:Number = (y0 - y) / 2;
            var x1p:Number =  cosP * hdx + sinP * hdy;
            var y1p:Number = -sinP * hdx + cosP * hdy;
            // Step 2/F.6.6: radii too small to span the endpoints are SCALED UP, not
            // clamped -- that is the spec's answer and it keeps the arc joinable.
            var lam:Number = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry);
            if (lam > 1)
            {
                var sl:Number = Math.sqrt(lam);
                rx = rx * sl;
                ry = ry * sl;
            }
            // Step 3: the centre, in the same frame ...
            var rx2:Number = rx * rx;
            var ry2:Number = ry * ry;
            var num:Number = rx2 * ry2 - rx2 * y1p * y1p - ry2 * x1p * x1p;
            var den:Number = rx2 * y1p * y1p + ry2 * x1p * x1p;
            var coef:Number = num > 0 && den > 0 ? Math.sqrt(num / den) : 0;
            if (large == sweep) coef = -coef;
            var cxp:Number =  coef * rx * y1p / ry;
            var cyp:Number = -coef * ry * x1p / rx;
            // ... and back in user space.
            var ccx:Number = cosP * cxp - sinP * cyp + (x0 + x) / 2;
            var ccy:Number = sinP * cxp + cosP * cyp + (y0 + y) / 2;
            // Step 4: start angle and sweep, as signed angles on the unit circle.
            var ux:Number = (x1p - cxp) / rx;
            var uy:Number = (y1p - cyp) / ry;
            var vx:Number = (-x1p - cxp) / rx;
            var vy:Number = (-y1p - cyp) / ry;
            var th0:Number = Math.atan2(uy, ux);
            var dth:Number = Math.atan2(ux * vy - uy * vx, ux * vx + uy * vy);
            if (!sweep && dth > 0) dth = dth - 2 * Math.PI;
            else if (sweep && dth < 0) dth = dth + 2 * Math.PI;

            // At most 90 degrees per cubic: the 4/3*tan(d/4) handle is within 2.7e-4 of
            // the radius there and gets worse fast beyond it.
            var n:int = int(Math.ceil(Math.abs(dth) / (Math.PI / 2)));
            if (n < 1) n = 1;
            var d:Number = dth / n;
            var k:Number = 4 / 3 * Math.tan(d / 4);
            for (var i:int = 0; i < n; i++)
            {
                var a0:Number = th0 + i * d;
                var a1:Number = a0 + d;
                var cs0:Number = Math.cos(a0);
                var sn0:Number = Math.sin(a0);
                var cs1:Number = Math.cos(a1);
                var sn1:Number = Math.sin(a1);
                // Point on the ellipse, rotated into user space.
                var px0:Number = ccx + rx * cs0 * cosP - ry * sn0 * sinP;
                var py0:Number = ccy + rx * cs0 * sinP + ry * sn0 * cosP;
                var px1:Number = ccx + rx * cs1 * cosP - ry * sn1 * sinP;
                var py1:Number = ccy + rx * cs1 * sinP + ry * sn1 * cosP;
                // d(point)/d(angle), same frame: the handle is k times this.
                var dx0:Number = -rx * sn0 * cosP - ry * cs0 * sinP;
                var dy0:Number = -rx * sn0 * sinP + ry * cs0 * cosP;
                var dx1:Number = -rx * sn1 * cosP - ry * cs1 * sinP;
                var dy1:Number = -rx * sn1 * sinP + ry * cs1 * cosP;
                // The last segment is snapped to the COMMAND's end point: the
                // trigonometry is accurate to ~1e-15, but an icon is drawn from the
                // data, so the data's own numbers are what the caller asked for.
                var ex:Number = i == n - 1 ? x : px1;
                var ey:Number = i == n - 1 ? y : py1;
                this.cubicTo(px0 + k * dx0, py0 + k * dy0,
                             px1 - k * dx1, py1 - k * dy1,
                             ex, ey);
            }
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

        // One arc flag: EXACTLY one character, never a number. See the header.
        private function flag():Boolean
        {
            this.skip();
            var ch:String = this.src.charAt(this.i);
            if (ch == "1") { this.i++; return true; }
            if (ch == "0") { this.i++; return false; }
            throw this.fail("expected an arc flag (0 or 1), found '" + ch + "'");
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
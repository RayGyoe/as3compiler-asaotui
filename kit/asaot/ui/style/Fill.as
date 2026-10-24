// asaot.ui.style.Fill -- a paint fill: a SOLID colour, or a two-or-more stop
// LINEAR GRADIENT.
//
// WHY GRADIENTS LIVE HERE NOW (2026-10-25)
// ----------------------------------------
// The header used to say "gradients are deferred", and `fromArray` returned null
// because AIR itself answers null for an Array handed to a Fill-shaped API. That
// was the right call while the draw path could not paint one. It can now:
// `Graphics.beginGradientFill` is a real implementation in the runtime
// (src/emit.ts, two-or-more-stop LINEAR, endpoints derived from the matrix the
// same way `Matrix.createGradientBox` places them) and it reports the shapes it
// cannot honour instead of painting a different gradient. So the toolkit paints
// what it can and REFUSES the rest here, at construction:
//
//   radial / focal / multi-colour-space  -> THROW ("this backend paints linear only")
//   fewer than two stops                 -> THROW (beginGradientFill would blank)
//   non-ascending / out-of-range ratios  -> THROW (AIR's contract is 0..255 ascending)
//
// NO SILENT FALLBACK (AGENTS.md 2.5): a `Fill` that cannot be drawn is never
// turned into a solid colour. `argb` survives only for the solid case, plus as
// the FIRST STOP for code that needs one colour from a fill (a divider's hairline
// colour, the animator's baseline).
//
// `argb` is 0xAARRGGBB so a single Number carries colour and alpha, matching the
// doc's `background: Fill.solid(0xFFFFFFFF)`.
//
// NO PACKAGE-LEVEL `fill(...)` HELPER: mxmlc requires one externally-visible
// definition per file named after it, and `fill.as` cannot coexist with
// `Fill.as` on a case-insensitive filesystem. Use `Fill.solid(argb)` or
// `Fill.gradient([...])`.
package asaot.ui.style
{
    public class Fill
    {
        public var argb:Number;

        // ---- gradient (all null/NaN on a solid fill) ----------------------
        public var colors:Array;      // Array of 0xRRGGBB
        public var alphas:Array;      // Array of 0..1
        public var ratios:Array;      // Array of 0..255, ascending
        public var gradientType:String; // "linear"
        public var angle:Number;      // degrees; 0 = left->right, 90 = top->bottom

        public function Fill(a:Number):void
        {
            // A 6-digit colour (0xRRGGBB, i.e. <= 0xFFFFFF) is treated as OPAQUE,
            // because that is how authors write colours and an alpha of 0 would
            // make every such fill invisible (the demo's blue button came out
            // white before this). For a translucent fill use a value with the
            // alpha byte set (> 0xFFFFFF) or `Fill.fromArgb`.
            var v:Number = a;
            if (v >= 0 && v <= 0xFFFFFF) v = v + 0xFF000000;
            this.argb = v;
            this.colors = null;
            this.alphas = null;
            this.ratios = null;
            this.gradientType = null;
            this.angle = 0;
        }

        public static function solid(argb:Number):Fill { return new Fill(argb); }

        public static function fromArgb(a:Number, r:Number, g:Number, b:Number):Fill
        {
            // Assign AFTER construction so an explicit alpha of 0 survives the
            // opaque-by-default normalisation above.
            var f:Fill = new Fill(0xFF000000);
            f.argb = Number(((a & 0xFF) << 24) | ((r & 0xFF) << 16) | ((g & 0xFF) << 8) | (b & 0xFF));
            return f;
        }

        // ---- gradients -----------------------------------------------------
        //
        //   Fill.gradient([0xFF0000, 0x0000FF])                       right
        //   Fill.gradient([0xFF0000, 0x0000FF], { angle: 90 })        down
        //   Fill.gradient([0x00FF00, 0xFFFF00], { alphas: [1, 0.2] })
        //
        // `ratios` defaults to evenly spaced 0..255; `alphas` defaults to all 1.
        public static function gradient(colors:Array, opts:Object = null):Fill
        {
            if (colors == null || colors.length < 2)
            {
                throw new Error("asaot.ui: Fill.gradient needs at least 2 colours (got "
                    + (colors == null ? 0 : colors.length) + ")");
            }
            var n:int = colors.length;
            var f:Fill = new Fill(0xFF000000);
            f.colors = [];
            f.alphas = [];
            f.ratios = [];
            f.gradientType = "linear";
            f.angle = 0;
            var i:int;
            for (i = 0; i < n; i++) f.colors.push(uint(Number(colors[i])) & 0xFFFFFF);
            for (i = 0; i < n; i++) f.alphas.push(1.0);
            for (i = 0; i < n; i++) f.ratios.push(Math.round(i * 255 / (n - 1)));
            if (opts != null)
            {
                if (opts.angle != null) f.angle = Number(opts.angle);
                if (opts.type != null && String(opts.type) != "linear")
                {
                    throw new Error("asaot.ui: Fill.gradient type \"" + opts.type
                        + "\" is not supported by this backend (accepted: linear)");
                }
                if (opts.alphas != null)
                {
                    var a:Array = opts.alphas as Array;
                    if (a == null || a.length != n)
                    {
                        throw new Error("asaot.ui: Fill.gradient alphas must be an array of "
                            + n + " numbers");
                    }
                    for (i = 0; i < n; i++)
                    {
                        var av:Number = Number(a[i]);
                        if (isNaN(av) || av < 0 || av > 1)
                        {
                            throw new Error("asaot.ui: Fill.gradient alpha must be 0..1 (got " + a[i] + ")");
                        }
                        f.alphas[i] = av;
                    }
                }
                if (opts.ratios != null)
                {
                    var r:Array = opts.ratios as Array;
                    if (r == null || r.length != n)
                    {
                        throw new Error("asaot.ui: Fill.gradient ratios must be an array of "
                            + n + " numbers");
                    }
                    var prev:Number = -1;
                    for (i = 0; i < n; i++)
                    {
                        var rv:Number = Number(r[i]);
                        if (isNaN(rv) || rv < 0 || rv > 255)
                        {
                            throw new Error("asaot.ui: Fill.gradient ratio must be 0..255 (got " + r[i] + ")");
                        }
                        if (rv <= prev)
                        {
                            throw new Error("asaot.ui: Fill.gradient ratios must be strictly ascending (got "
                                + r[i] + " after " + prev + ")");
                        }
                        prev = rv;
                        f.ratios[i] = rv;
                    }
                }
                if (opts.focalPointRatio != null && Number(opts.focalPointRatio) != 0)
                {
                    throw new Error("asaot.ui: Fill.gradient focalPointRatio is not supported by this backend");
                }
            }
            f.argb = Number(0xFF000000) | Number(f.colors[0]);
            return f;
        }

        // The typed array entry point: an ARRAY of colours is a gradient. This is
        // the path `background: [0xFF0000, 0x0000FF]` takes (Fill.fromAny routes
        // arrays here), and the reason `fromArray` stayed on this class through the
        // deferred period.
        public static function fromArray(a:Array):Fill
        {
            return gradient(a);
        }

        public static function fromAny(o:Object):Fill
        {
            if (o == null) return null;
            // The array branch is dispatched HERE, so `Fill.fromAny(x)` is total (it
            // accepts every documented shape). This check used to be impossible: an
            // Array put into an Object-typed parameter was not boxed, our AOT
            // constant-folded `is Array` to FALSE, and the next line (`is Fill`) then
            // read the array header as a vtable and died with 0xC0000005 -- measured,
            // not assumed (compiler-gaps.md G14, probes/obj-array-identity/ case 26).
            // G14 is FIXED (compiler 阶段二百五十三); `probes/style-fromany/`
            // re-measures this on BOTH runtimes, so the guard is live again.
            if (o is Array) return fromArray(o as Array);
            if (o is Number) return solid(Number(o));
            if (o is Fill) return Fill(o);
            // A gradient written longhand: { colors: [...], angle: 90, ... }.
            if (o.colors != null) return gradient(o.colors as Array, o);
            return null;
        }

        public function isGradient():Boolean
        {
            return this.ratios != null;
        }

        // The single colour a caller needs when it can only use one: the solid
        // fill's, or the FIRST STOP's.
        public function rgb():uint
        {
            if (this.ratios != null && this.colors != null && this.colors.length > 0)
            {
                return uint(Number(this.colors[0])) & 0xFFFFFF;
            }
            return uint(this.argb) & 0xFFFFFF;
        }

        public function alpha():Number
        {
            if (this.ratios != null && this.alphas != null && this.alphas.length > 0)
            {
                return Number(this.alphas[0]);
            }
            return Number((uint(this.argb) >>> 24) & 0xFF) / 255.0;
        }

        // Value equality, used by Style.diffFlags. Two gradients are equal when
        // every stop, the angle and the type agree -- otherwise a describe pass that
        // rebuilds the same array would repaint forever.
        public function equals(o:Fill):Boolean
        {
            if (o == null) return false;
            if (this.ratios == null || o.ratios == null)
            {
                return this.ratios == null && o.ratios == null && this.argb == o.argb;
            }
            if (this.gradientType != o.gradientType || this.angle != o.angle) return false;
            if (this.colors.length != o.colors.length) return false;
            for (var i:int = 0; i < this.colors.length; i++)
            {
                if (Number(this.colors[i]) != Number(o.colors[i])) return false;
                if (Number(this.alphas[i]) != Number(o.alphas[i])) return false;
                if (Number(this.ratios[i]) != Number(o.ratios[i])) return false;
            }
            return true;
        }
    }
}
// asaot.ui.anim.Ease -- named easing curves for the tween core (Anim.as).
//
// WHY STRING-KEYED AND WHY IT THROWS
// ----------------------------------
// A style names its curve with a plain string (`transitionEase: "outCubic"`)
// because a StyleRefinement is a data record, not a function reference -- and an
// AS3 style constant is built once at class-load time, so it cannot capture a
// closure. The lookup is therefore name -> curve.
//
// An unknown name THROWS instead of falling back to `linear`: a typo in a style
// would otherwise be a silent wrong-velocity animation, and AGENTS.md 2.5 says
// never silently fall back to wrong semantics. `null` is the one documented
// default (linear), because "no ease written" is a legitimate, unset value.
//
// `t` is clamped to [0,1] first, so a caller may pass a raw progress value
// without pre-clamping. Every curve maps 0 -> 0 and 1 -> 1 exactly, which is what
// lets the tween land EXACTLY on its target rather than one step short.
package asaot.ui.anim
{
    public final class Ease
    {
        public static function apply(name:String, t:Number):Number
        {
            var x:Number = t;
            if (x < 0) x = 0;
            if (x > 1) x = 1;
            if (name == null || name == "" || name == "linear") return x;
            if (name == "outQuad") return outQuad(x);
            if (name == "outCubic") return outCubic(x);
            if (name == "inOutCubic") return inOutCubic(x);
            throw new Error("Ease.apply: unknown easing '" + name
                + "' (accepted: linear | outQuad | outCubic | inOutCubic)");
        }

        // 1 - (1-t)^2
        public static function outQuad(t:Number):Number
        {
            var u:Number = 1 - t;
            return 1 - u * u;
        }

        // 1 - (1-t)^3
        public static function outCubic(t:Number):Number
        {
            var u:Number = 1 - t;
            return 1 - u * u * u;
        }

        // 4t^3 for t < 1/2, else 1 - (-2t+2)^3 / 2
        public static function inOutCubic(t:Number):Number
        {
            if (t < 0.5) return 4 * t * t * t;
            var u:Number = -2 * t + 2;
            return 1 - u * u * u / 2;
        }

        // Non-throwing membership test, for diagnostics / tests.
        public static function has(name:String):Boolean
        {
            return name == null || name == "" || name == "linear"
                || name == "outQuad" || name == "outCubic" || name == "inOutCubic";
        }
    }
}
// asaot.ui.style.Length -- the LENGTH TRICHOTOMY, borrowed from GPUI.
//
// WHY THREE CLASSES / A UNIT TAG
// ------------------------------
// GPUI splits lengths into `AbsoluteLength` (independent of the parent's font
// size: font size, border width, corner radius), `DefiniteLength` (absolute OR
// a *fraction* of the parent size: padding, gap, line height) and `Length`
// (definite OR `auto`, decided by content/context: size, min/max, margin, inset,
// flex basis).
//   * asaotui/gpui-src/crates/gpui/src/geometry.rs:3310  AbsoluteLength
//   * asaotui/gpui-src/crates/gpui/src/geometry.rs:3472  DefiniteLength
//   * asaotui/gpui-src/crates/gpui/src/geometry.rs:3623  Length
//
// AS3 has no `Option<T>` and no generics over value types, so instead of three
// nominal types we carry ONE `Length` value with an explicit `unit` tag. The
// tag is exactly the engine's UNIT_* trichotomy, so passing a length through
// the `LayoutEngine` seam is a straight mapping -- no re-derivation.
//
// A `Fraction` is 0..1 (NOT 0..100) on the AUTHOR side; `applyTo` multiplies by
// 100 because the opaque layout seam keeps Yoga's 0..100 spelling (see
// seam/asaot/ui/LayoutConstants.as). Keeping the author-facing number 0..1 is
// what `pct(0.5)` means in the API design (section 2.2).
package asaot.ui.style
{
    public class Length
    {
        public static const UNIT_AUTO:int = 0;
        public static const UNIT_POINT:int = 1;
        public static const UNIT_PERCENT:int = 2;

        // One shared Auto instance: hoisting it means `auto()` allocates nothing.
        public static const AUTO:Length = new Length(UNIT_AUTO, 0);

        public var unit:int;
        public var value:Number;

        public function Length(u:int, v:Number):void
        {
            this.unit = u;
            this.value = v;
        }

        public static function px(n:Number):Length { return new Length(UNIT_POINT, n); }
        // 1rem == 16px is the browser default; we do NOT introduce a second DPR
        // scale here (the render scale stays ASC_render_scale, see emit.ts).
        public static function rem(n:Number):Length { return new Length(UNIT_POINT, n * 16.0); }
        public static function pct(f:Number):Length { return new Length(UNIT_PERCENT, f); }

        public function isAuto():Boolean { return this.unit == UNIT_AUTO; }
        public function isDefinite():Boolean { return this.unit != UNIT_AUTO; }

        // Fraction (0..1) -> the seam's 0..100 percent spelling.
        public function toEngineUnit():int
        {
            if (this.unit == UNIT_POINT) return UNIT_POINT;
            if (this.unit == UNIT_PERCENT) return UNIT_PERCENT;
            return UNIT_AUTO;
        }

        public function toEngineValue():Number
        {
            if (this.unit == UNIT_PERCENT) return this.value * 100.0;
            return this.value;
        }
    }
}

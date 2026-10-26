// asaot.ui.NumberInputNode -- a numeric field with steppers.
//
// WHY THIS IS NOT `textField` + `Number()`: the kit's rule is that a control owns
// its whole contract, and a number has three parts a text field does not -- a
// RANGE (min/max, clamped on every write), a STEP, and a ROUNDING. An author who
// assembles those by hand re-implements the same clamp in every form and gets it
// slightly different each time, which is exactly how "the quantity field accepts
// -3" ships.
//
// THE MODEL IS A NUMBER, the field is its text. `value` is always in
// [min, max] and always a multiple of `step` relative to `min`? -- NO: see
// NumberInputWidget's header, the step is applied to the VALUE, not to a grid, so
// a typed 7 stays 7 under step 5. Snapping typed input to a grid would silently
// change what the user wrote.
//
// `min`/`max` default to NaN = UNSET (not 0/Infinity): an unset bound is not a
// bound, and a control that claims 0..100 by default would clamp the first honest
// negative value an author types. The widget skips a bound only when it is NaN.
package asaot.ui
{
    import asaot.ui.kind.NumberInputWidget;

    public class NumberInputNode extends Control
    {
        public var label:String;
        public var value:Number;
        public var min:Number;        // NaN = unbounded
        public var max:Number;        // NaN = unbounded
        public var step:Number;       // how much one arrow / one stepper press moves
        public var decimals:int;      // digits kept after the point (0 = integers)
        public var binding:Binding;   // optional: value read from / written to
        public var onChange:Function; // function (v:Number)
        public var onCommit:Function; // function (v:Number) -- Enter or blur

        private static var registered:Boolean = false;

        public function NumberInputNode(label:String):void
        {
            super("numberInput");
            if (!registered) { registered = true; Widgets.register("numberInput", new NumberInputWidget()); }
            this.role = "spinButton";
            this.tabEnabled = true;
            this.label = label;
            this.value = 0;
            this.min = NaN;
            this.max = NaN;
            this.step = 1;
            this.decimals = 0;
            this.binding = null;
            this.onChange = null;
            this.onCommit = null;
        }

        // The ONE clamp, shared by the factory's initial value and every write the
        // widget makes. A NaN bound is "unset", not "zero": `if (min < v)` is
        // deliberately not used because NaN makes every comparison false, which is
        // the right answer by accident and a trap for the next reader.
        public static function clamp(min:Number, max:Number, v:Number):Number
        {
            var out:Number = v;
            if (!isNaN(min) && out < min) out = min;
            if (!isNaN(max) && out > max) out = max;
            return out;
        }

        // Round to `decimals` places without Math.pow: a loop over a multiplier is
        // the same arithmetic and one less runtime dependency to trust.
        public static function roundTo(v:Number, decimals:int):Number
        {
            if (decimals <= 0) return Math.round(v);
            var m:Number = 1;
            for (var i:int = 0; i < decimals; i++) m = m * 10;
            return Math.round(v * m) / m;
        }
    }
}
// asaot.ui.numberInput -- the author-facing factory for NumberInputNode.
//
//   numberInput("Qty", { value: 3, min: 1, max: 99, step: 2,
//                        onChange: function (v:Number):void { ... },
//                        onCommit: function (v:Number):void { ... } })
//
// `value` accepts a Number OR a Binding, exactly like slider/checkbox.
//
// REFUSES, DOES NOT GUESS. A `step` of 0 or less would make the arrow keys a
// no-op, and a negative `decimals` has no meaning; both throw here rather than
// being silently corrected, because the author's next question would be "why does
// the + button do nothing" (AGENTS.md 2.5).
package asaot.ui
{
    public function numberInput(label:String, opts:Object = null):Node
    {
        var n:NumberInputNode = new NumberInputNode(label);
        OptionSupport.applyOpts(n, opts);
        if (n.ariaName == null || n.ariaName == "") n.ariaName = label;
        if (opts != null)
        {
            if (opts.value is Binding)
            {
                n.binding = Binding(opts.value);
                // `*`, NOT `Object`: an Object slot would box the value once per read
                // (see slider.as for the whole note).
                var bv:* = n.binding.get();
                n.value = bv == null ? 0 : Number(bv);
            }
            else if (opts.value != null) n.value = Number(opts.value);
            if (opts.min != null) n.min = Number(opts.min);
            if (opts.max != null) n.max = Number(opts.max);
            if (opts.step != null) n.step = Number(opts.step);
            if (opts.decimals != null) n.decimals = int(opts.decimals);
            if (opts.onChange != null) n.onChange = (opts.onChange as Function);
            if (opts.onCommit != null) n.onCommit = (opts.onCommit as Function);
        }

        if (!(n.step > 0))
        {
            throw new Error("asaot.ui.numberInput: `step` must be a positive number (got "
                + n.step + "). A zero step makes every arrow key and both steppers dead,"
                + " which is never what the author drew.");
        }
        if (n.decimals < 0)
        {
            throw new Error("asaot.ui.numberInput: `decimals` must be 0 or more (got "
                + n.decimals + ").");
        }
        if (!isNaN(n.min) && !isNaN(n.max) && n.min > n.max)
        {
            throw new Error("asaot.ui.numberInput: `min` (" + n.min + ") is greater than"
                + " `max` (" + n.max + ") -- the range is empty, so every value would be"
                + " clamped to one of the two.");
        }
        if (isNaN(n.value)) n.value = 0;

        // The initial value obeys the same two rules every later write obeys, so the
        // first paint can never show something a stepper press would immediately
        // change: clamp into range, then round.
        n.value = NumberInputNode.clamp(n.min, n.max, n.value);
        n.value = NumberInputNode.roundTo(n.value, n.decimals);
        return n;
    }
}
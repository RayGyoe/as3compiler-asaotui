// asaot.ui.rangeSlider -- the author-facing factory for RangeSliderNode.
//
//   rangeSlider("Price", { value: 0.2, value2: 0.8, step: 0.05,
//                          onRange: function (lo:Number, hi:Number):void { ... } })
//
// THE PAIR IS NORMALISED HERE, ONCE: each value is clamped into 0..1 and the two are
// swapped if they arrived backwards. Doing it in the factory is what lets the widget
// assume `low <= high` on every frame; doing it only in the widget would leave the
// FIRST frame (the one painted before any interaction) with an inverted band.
//
// `onRange` takes TWO arguments, so it is graded as a pair callback by
// `tools/callback-arity.cjs` (same class as `onSort`/`onColumnResize`): a one-argument
// declaration against a two-argument call is `#1063`, and that class of defect is
// invisible until somebody drags the thumb.
package asaot.ui
{
    public function rangeSlider(label:String, opts:Object = null):Node
    {
        var n:RangeSliderNode = new RangeSliderNode(label);
        OptionSupport.applyOpts(n, opts);
        if (n.ariaName == null || n.ariaName == "") n.ariaName = label;
        if (opts != null)
        {
            if (opts.value != null) n.value = Number(opts.value);
            if (opts.value2 != null) n.value2 = Number(opts.value2);
            if (opts.step != null) n.step = Number(opts.step);
            if (opts.onRange != null) n.onRange = (opts.onRange as Function);
        }

        if (!(n.step > 0))
        {
            throw new Error("asaot.ui.rangeSlider: `step` must be a positive number (got "
                + n.step + "). It is the keyboard increment -- a zero step makes every"
                + " arrow key a no-op.");
        }
        if (isNaN(n.value)) n.value = 0;
        if (isNaN(n.value2)) n.value2 = 1;

        var lo:Number = n.value;
        var hi:Number = n.value2;
        if (lo < 0) lo = 0;
        if (lo > 1) lo = 1;
        if (hi < 0) hi = 0;
        if (hi > 1) hi = 1;
        if (lo > hi)
        {
            // SWAP, not throw: `value: 0.8, value2: 0.2` is an obvious authoring slip
            // with exactly one sensible reading, and the pair carries no identity that
            // a swap could confuse (unlike, say, two named endpoints).
            var t:Number = lo;
            lo = hi;
            hi = t;
        }
        n.value = lo;
        n.value2 = hi;
        return n;
    }
}
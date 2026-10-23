// asaot.ui.slider -- the author-facing slider factory (see SliderNode.as for why
// the class is `SliderNode` and this file is lowercase).
//
// `opts.value` accepts a Number OR an `asaot.ui.Binding`. `opts.onChange` is
// called on every value change caused by a click.
package asaot.ui
{
    public function slider(label:String, opts:Object = null):Node
    {
        var n:SliderNode = new SliderNode(label);
        OptionSupport.applyOpts(n, opts);
        if (n.ariaName == null) n.ariaName = label;
        if (opts != null)
        {
            if (opts.value is Binding)
            {
                n.binding = Binding(opts.value);
                // `*`, NOT `Object`, like the boolean siblings: an `Object` slot would
                // BOX whatever the binding holds (one allocation per read). G9 is FIXED
                // (阶段二百四十八) and so is G14 (阶段二百五十三), so neither is a
                // correctness workaround any more -- `*` is simply the right default for
                // "a value of unknown type", and it stays the cheapest.
                var v:* = n.binding.get();
                n.value = v == null ? 0 : Number(v);
            }
            else if (opts.value != null) n.value = Number(opts.value);
            if (opts.onChange != null) n.onChange = (opts.onChange as Function);
            if (opts.onClick != null) n.onClick = (opts.onClick as Function);
        }
        return n;
    }
}
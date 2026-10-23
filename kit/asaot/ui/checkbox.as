// asaot.ui.checkbox -- the checkbox factory (design doc section 4.2).
package asaot.ui
{
    public function checkbox(opts:Object = null):Node
    {
        var n:CheckboxNode = new CheckboxNode(OptionSupport.opt(opts, "label", ""));
        OptionSupport.applyOpts(n, opts);
        if (n.ariaName == null) n.ariaName = n.label;
        if (opts != null)
        {
            if (opts.checked is Binding)
            {
                n.binding = Binding(opts.checked);
                // `*`, NOT `Object`: a binding value can be anything, and an `Object`
                // slot BOXES it (one allocation per read). Both of the old reasons to
                // spell this `*` are now historical -- G9 (Boolean lowering) is FIXED in
                // 阶段二四八 and G14 (Array identity) in 阶段二百五十三 -- so `*` is simply
                // the cheapest correct default for "a value of unknown type".
                var c:* = n.binding.get();
                n.checked = c != null && Boolean(c);
            }
            else if (opts.checked != null) n.checked = Boolean(opts.checked);
            if (opts.onChange != null) n.onChange = (opts.onChange as Function);
            if (opts.onClick != null) n.onClick = (opts.onClick as Function);
        }
        return n;
    }
}

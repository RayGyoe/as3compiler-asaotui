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
                // `*`, NOT `Object`: a binding value can be anything. `Object` would BOX
                // it (one allocation per read) and an Array would lose its identity there
                // (compiler-gaps.md G9 + G14). G9's Boolean-lowering bug is FIXED
                // (阶段二四八), so this is no longer a correctness workaround.
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

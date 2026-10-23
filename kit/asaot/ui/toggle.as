// asaot.ui.toggle -- the author-facing factory for SwitchNode.
//
// WHY NOT `switch`: `switch` is a reserved word in AS3, so it can be neither a
// function name nor a same-named file. The kind/role stay "switch"; only the
// author-facing function is `toggle(...)`. (Same precedent as `bindTo` vs the
// documented `bind`, and `withPatch` vs `with`.)
//
// `opts.checked` accepts a boolean OR an `asaot.ui.Binding`, exactly like
// `checkbox`.
package asaot.ui
{
    public function toggle(label:String, opts:Object = null):Node
    {
        var n:SwitchNode = new SwitchNode(label);
        OptionSupport.applyOpts(n, opts);
        if (n.ariaName == null) n.ariaName = label;
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
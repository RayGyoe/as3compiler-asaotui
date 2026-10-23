// asaot.ui.radio -- the author-facing radio factory (see RadioNode.as for why
// the class is `RadioNode` and this file is lowercase).
//
// `opts.selected` accepts a boolean OR an `asaot.ui.Binding` (the checkbox
// convention): a Binding is stored on the node and read/written through, so a
// click reaches the model via `Binding.set` -> `Observable.notify`.
package asaot.ui
{
    public function radio(label:String, opts:Object = null):Node
    {
        var n:RadioNode = new RadioNode(label);
        OptionSupport.applyOpts(n, opts);
        if (n.ariaName == null) n.ariaName = label;
        if (opts != null)
        {
            if (opts.selected is Binding)
            {
                n.binding = Binding(opts.selected);
                // `*`, NOT `Object`: a binding value can be anything. `Object` would BOX
                // it (one allocation per read) and an Array would lose its identity there
                // (compiler-gaps.md G9 + G14). G9's Boolean-lowering bug is FIXED
                // (阶段二四八), so this is no longer a correctness workaround.
                var s:* = n.binding.get();
                n.selected = s != null && Boolean(s);
            }
            else if (opts.selected != null) n.selected = Boolean(opts.selected);
            if (opts.group != null) n.group = String(opts.group);
            if (opts.value != null) n.value = String(opts.value);
            if (opts.onChange != null) n.onChange = (opts.onChange as Function);
            if (opts.onClick != null) n.onClick = (opts.onClick as Function);
        }
        return n;
    }
}
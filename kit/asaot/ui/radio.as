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
                // `*`, NOT `Object`: a binding value can be anything, and an `Object`
                // slot BOXES it (one allocation per read). Both of the old reasons to
                // spell this `*` are now historical -- G9 (Boolean lowering) is FIXED in
                // 阶段二四八 and G14 (Array identity) in 阶段二百五十三 -- so `*` is simply
                // the cheapest correct default for "a value of unknown type".
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
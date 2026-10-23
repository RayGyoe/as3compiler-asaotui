// asaot.ui.tabs -- the author-facing factory for TabsNode (see TabsNode.as for
// why the file is lowercase and the class is not).
//
//   tabs(["One", "Two", "Three"], { key: "t", style: { size: [240, 32] }, gap: 6,
//                                    selectedIndex: bindTo(model, "page"),
//                                    onChange: function(i:int):void { ... } })
//
// `opts.selectedIndex` accepts a Number OR a Binding. `opts.gap` is the space
// between segments and is stored on the node's own `gap` field, so an explicit
// `style` refinement (which takes the OTHER branch of OptionSupport.applyOpts)
// cannot silently drop it.
package asaot.ui
{
    public function tabs(labels:Array, opts:Object = null):Node
    {
        var n:TabsNode = new TabsNode();
        n.labels = labels == null ? [] : labels;
        OptionSupport.applyOpts(n, opts);
        if (n.ariaName == null || n.ariaName == "") n.ariaName = "tabs";
        if (opts != null)
        {
            if (opts.selectedIndex is Binding)
            {
                n.binding = Binding(opts.selectedIndex);
                // `*`, NOT `Object`: see compiler-gaps.md G9 -- Boolean(x) with x
                // declared `Object` lowers to a pointer test, so a bound FALSE
                // would read as true. (Number(x) is unaffected, but the value can
                // be anything, so keep the readboxing honest.)
                var v:* = n.binding.get();
                n.selectedIndex = v == null ? 0 : Number(v);
            }
            else if (opts.selectedIndex != null) n.selectedIndex = Number(opts.selectedIndex);
            if (opts.onChange != null) n.onChange = (opts.onChange as Function);
            if (opts.gap != null) n.gap = Number(opts.gap);
        }
        return n;
    }
}
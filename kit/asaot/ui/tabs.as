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
                // `*`, NOT `Object`: an `Object` slot would box the value once per read.
                // Number() never depended on the G9 fix (阶段二四八) and the G14 Array-identity
                // hazard (阶段二百五十三) is closed too, so `*` is now purely the cheaper default.
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
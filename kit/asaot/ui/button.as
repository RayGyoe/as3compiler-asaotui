// asaot.ui.button -- the button factory (design doc section 4.2).
package asaot.ui
{
    public function button(opts:Object = null):Node
    {
        var n:ButtonNode = new ButtonNode(OptionSupport.opt(opts, "label", ""));
        OptionSupport.applyOpts(n, opts);
        if (n.ariaName == null) n.ariaName = n.label;
        if (opts != null && opts.onClick != null) n.onClick = (opts.onClick as Function);
        if (opts != null && opts.action != null) n.action = String(opts.action);
        if (opts != null && opts.tabEnabled != null) n.tabEnabled = Boolean(opts.tabEnabled);
        return n;
    }
}

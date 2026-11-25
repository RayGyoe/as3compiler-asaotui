// asaot.ui.colorWheel -- the author-facing factory for ColorWheelNode (lowercase file).
package asaot.ui
{
    public function colorWheel(label:String, opts:Object = null):Node
    {
        var n:ColorWheelNode = new ColorWheelNode(label);
        OptionSupport.applyOpts(n, opts);
        if (opts != null)
        {
            if (opts.value != null) n.value = Number(opts.value);
            if (opts.spread != null) n.spread = Number(opts.spread);
            if (opts.onChange != null) n.onChange = (opts.onChange as Function);
        }
        if (n.ariaName == null) n.ariaName = label;
        return n;
    }
}
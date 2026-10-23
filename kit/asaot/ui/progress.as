// asaot.ui.progress -- the author-facing progress factory (see ProgressNode.as
// for why the class is `ProgressNode` and this file is lowercase).
package asaot.ui
{
    public function progress(label:String, opts:Object = null):Node
    {
        var n:ProgressNode = new ProgressNode(label);
        OptionSupport.applyOpts(n, opts);
        if (n.ariaName == null) n.ariaName = label;
        if (opts != null && opts.value != null) n.value = Number(opts.value);
        return n;
    }
}
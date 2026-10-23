// asaot.ui.chip -- the author-facing factory for ChipNode (see ChipNode.as for
// why the file is lowercase and the class is not).
package asaot.ui
{
    public function chip(label:String, opts:Object = null):Node
    {
        var n:ChipNode = new ChipNode(label);
        OptionSupport.applyOpts(n, opts);
        if (opts != null && opts.tone != null) n.tone = String(opts.tone);
        if (n.ariaName == null) n.ariaName = label;
        return n;
    }
}
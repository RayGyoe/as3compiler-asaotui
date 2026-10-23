// asaot.ui.tooltip -- the author-facing factory for TooltipNode (see
// TooltipNode.as for why the file is lowercase and the class is not, and for where
// a tooltip actually goes).
//
//   tooltip("Saved just now", { key: "t", arrow: "down" })
//
// The first parameter is a LABEL STRING, not a child node, exactly like
// chip/badge/radio: this widget draws its own text.
package asaot.ui
{
    public function tooltip(text:String, opts:Object = null):Node
    {
        var n:TooltipNode = new TooltipNode();
        OptionSupport.applyOpts(n, opts);
        n.text = text == null ? "" : text;
        if (n.ariaName == null || n.ariaName == "") n.ariaName = n.text;
        if (opts != null)
        {
            if (opts.arrow != null) n.arrow = String(opts.arrow);
            if (opts.tone != null) n.tone = Number(opts.tone);
        }
        return n;
    }
}

// asaot.ui.badge -- the author-facing factory for BadgeNode (see BadgeNode.as
// for why the file is lowercase and the class is not).
//
//   badge("3")
//   badge("99+", { tone: "danger", style: { cornerRadii: 99 } })
package asaot.ui
{
    public function badge(label:String, opts:Object = null):Node
    {
        var n:BadgeNode = new BadgeNode(label);
        OptionSupport.applyOpts(n, opts);
        if (opts != null && opts.tone != null) n.tone = String(opts.tone);
        if (n.ariaName == null || n.ariaName == "") n.ariaName = label;
        return n;
    }
}
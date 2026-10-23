// asaot.ui.divider -- the author-facing factory for DividerNode (see
// DividerNode.as for why the file is lowercase and the class is not).
//
//   divider()
//   divider({ orientation: "vertical", style: { size: [1, 40], background: 0xDDDDDD } })
package asaot.ui
{
    public function divider(opts:Object = null):Node
    {
        var n:DividerNode = new DividerNode();
        OptionSupport.applyOpts(n, opts);
        if (opts != null && opts.orientation != null) n.orientation = String(opts.orientation);
        if (n.ariaName == null || n.ariaName == "") n.ariaName = "separator";
        return n;
    }
}

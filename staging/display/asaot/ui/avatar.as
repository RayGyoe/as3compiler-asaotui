// asaot.ui.avatar -- the author-facing factory for AvatarNode (see AvatarNode.as
// for why the file is lowercase and the class is not).
//
//   avatar("Ada Lovelace", { style: { size: [48, 48] } })
//   avatar("Grace Hopper", { tone: "info" })
package asaot.ui
{
    public function avatar(name:String, opts:Object = null):Node
    {
        var n:AvatarNode = new AvatarNode(name);
        OptionSupport.applyOpts(n, opts);
        if (opts != null && opts.tone != null) n.tone = String(opts.tone);
        if (n.ariaName == null || n.ariaName == "") n.ariaName = name;
        return n;
    }
}
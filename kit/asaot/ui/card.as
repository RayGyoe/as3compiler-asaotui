// asaot.ui.card -- the author-facing factory for CardNode (see CardNode.as for
// why the file is lowercase and the class is not).
//
//   card({ title: "Details", style: { padding: 12 } }, [
//       text("a child laid out by the engine")
//   ])
package asaot.ui
{
    public function card(opts:Object = null, children:Array = null):Node
    {
        var n:CardNode = new CardNode();
        OptionSupport.applyOpts(n, opts);
        if (opts != null && opts.title != null) n.title = String(opts.title);
        OptionSupport.addChildren(n, children);
        return n;
    }
}
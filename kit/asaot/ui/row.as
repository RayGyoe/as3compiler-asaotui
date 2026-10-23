// asaot.ui.row -- box shorthand for `direction: "row"`.
package asaot.ui
{
    public function row(opts:Object, children:Array = null):Node
    {
        var n:BoxNode = new BoxNode();
        OptionSupport.applyOpts(n, opts);
        n.direction = "row";
        OptionSupport.addChildren(n, children);
        return n;
    }
}
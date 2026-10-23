// asaot.ui.column -- box shorthand for `direction: "column"`.
package asaot.ui
{
    public function column(opts:Object, children:Array = null):Node
    {
        var n:BoxNode = new BoxNode();
        OptionSupport.applyOpts(n, opts);
        n.direction = "column";
        OptionSupport.addChildren(n, children);
        return n;
    }
}
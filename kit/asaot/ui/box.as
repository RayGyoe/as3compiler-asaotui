// asaot.ui.box -- the container factory (design doc section 4.2). One file per
// package-level function: mxmlc requires the definition name to match the file.
package asaot.ui
{
    public function box(opts:Object, children:Array = null):Node
    {
        var n:BoxNode = new BoxNode();
        OptionSupport.applyOpts(n, opts);
        OptionSupport.addChildren(n, children);
        return n;
    }
}

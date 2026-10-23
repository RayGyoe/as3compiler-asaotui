// asaot.ui.text -- the text factory (design doc section 4.2). A Text node's
// ariaName defaults to its content.
package asaot.ui
{
    public function text(content:String, opts:Object = null):Node
    {
        var n:TextNode = new TextNode(content);
        OptionSupport.applyOpts(n, opts);
        if (n.ariaName == null) n.ariaName = content;
        return n;
    }
}

// asaot.ui.label -- an alias of `text` (reads better inside form rows).
package asaot.ui
{
    public function label(content:String, opts:Object = null):Node
    {
        return text(content, opts);
    }
}
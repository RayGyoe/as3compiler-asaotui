// asaot.ui.textArea -- the multi-line editable field factory.
//
//   textArea({ value: "hello", rows: 4, style: { size: [320, NaN] }, onChange: fn })
//
// `value` accepts a String or a Binding (a Binding is stored on the node so edits
// write through, exactly as textField does).
package asaot.ui
{
    public function textArea(opts:Object = null):Node
    {
        var n:TextAreaNode = new TextAreaNode();
        OptionSupport.applyOpts(n, opts);
        if (opts != null)
        {
            if (opts.value is Binding)
            {
                n.binding = Binding(opts.value);
                var v:Object = n.binding.get();
                n.value = v == null ? "" : String(v);
            }
            else if (opts.value != null) n.value = String(opts.value);
            if (opts.placeholder != null) n.placeholder = String(opts.placeholder);
            if (opts.rows != null) n.rows = int(Number(opts.rows));
            if (opts.onCommit != null) n.onCommit = (opts.onCommit as Function);
            if (opts.onChange != null) n.onChange = (opts.onChange as Function);
        }
        if (n.ariaName == null) n.ariaName = "";
        return n;
    }
}
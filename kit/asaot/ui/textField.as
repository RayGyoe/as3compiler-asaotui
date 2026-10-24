// asaot.ui.textField -- the editable-text factory (design doc section 4.2). A
// Binding passed as `opts.value` is stored on the node so edits write through.
package asaot.ui
{
    public function textField(opts:Object = null):Node
    {
        var n:TextInput = new TextInput();
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
            if (opts.password != null) n.password = Boolean(opts.password);
            if (opts.onCommit != null) n.onCommit = (opts.onCommit as Function);
            // Fires on every edit (typed text, paste, cut, backspace) with the new
            // value -- the runtime dispatches Event.CHANGE on the field and
            // InputWidget forwards it here. Distinct from onCommit, which is
            // Enter / blur only.
            if (opts.onChange != null) n.onChange = (opts.onChange as Function);
            if (opts.onClick != null) n.onClick = (opts.onClick as Function);
        }
        if (n.ariaName == null) n.ariaName = "";
        return n;
    }
}
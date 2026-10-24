// asaot.ui.combobox -- the author-facing factory for ComboBoxNode.
//
//   combobox({ key: "city", value: queryText, options: allCities, open: open,
//              placeholder: "Type a city",
//              onQuery: function (t:String):void { model.q = t; },   // filter the options
//              onSelect: function (i:int):void { ... },              // i indexes `options`
//              onOpenChange: function (open:Boolean):void { ... }, width: 220 })
//
// STRUCTURE (ComboBoxWidget depends on it):
//   combo node      style SELECT_TRIGGER (row, 34 high, padding [10,0])
//     ├─ [0] textField  flexGrow 1, white, no border -- the focus target
//     └─ [1] dropdown   absolute, MENU_PANEL; the widget writes its insets
//
// THE DROPDOWN IS ALWAYS THE LAST CHILD (the same contract select()/dialog() keep), so
// the widget takes it from the end and no index constant goes stale.
//
// `query` IS NOT FILTERED HERE. The factory renders whatever `options` it is given;
// filtering by `query` is the AUTHOR's one-liner in `onQuery`. Doing it here would
// mean the library guesses the matching rule (case? accents? word-start?), and a
// combobox over 10k server-side rows could not use it anyway.
package asaot.ui
{
    import asaot.ui.style.Length;
    import asaot.ui.style.Size;
    import asaot.ui.style.StyleRefinement;

    public function combobox(opts:Object = null):Node
    {
        var n:ComboBoxNode = new ComboBoxNode();
        OptionSupport.applyOpts(n, opts);
        if (opts == null) opts = {};
        if (opts.open != null) n.open = Boolean(opts.open);
        if (opts.value != null) n.query = String(opts.value);
        if (opts.placeholder != null) n.placeholder = String(opts.placeholder);
        if (opts.options != null) n.options = OptionSupport.list(opts.options);
        if (opts.width != null) n.width = Number(opts.width);
        // The G16 rule again: never `cond ? null : value` for an object/Function.
        if (opts.onSelect != null) n.onSelect = (opts.onSelect as Function);
        if (opts.onQuery != null) n.onQuery = (opts.onQuery as Function);
        if (opts.onOpenChange != null) n.onOpenChange = (opts.onOpenChange as Function);
        if (n.ariaName == null) n.ariaName = "combobox";

        // The trigger: still select's geometry, so the caret and the dropdown insets
        // below are the same numbers as a select's.
        var trig:StyleRefinement = new StyleRefinement();
        trig.size = Size.of(Length.px(n.width), null);
        n.style = (n.style == null ? new StyleRefinement() : n.style)
            .withPatch(OverlayChrome.SELECT_TRIGGER.withPatch(trig));

        var base:String = n.key == null ? "combo" : String(n.key);

        // The editable trigger. Its own widget owns CHANGE -> onQuery, so the factory
        // only has to hand the callback over -- and the field keeps the typing across
        // the re-render that the callback causes (the reconciler does not re-assign an
        // identical text).
        var fieldStyle:StyleRefinement = StyleRefinement.from({
            flexGrow: 1, background: 0xFFFFFF, borderWidths: 0, padding: [4, 2]
        });
        n.addChild(textField({ key: base + ":q", value: n.query == null ? "" : n.query,
                               placeholder: n.placeholder, style: fieldStyle,
                               ariaName: n.placeholder,
                               onChange: n.onQuery }));

        var dropStyle:StyleRefinement = new StyleRefinement();
        dropStyle.size = Size.of(Length.px(n.width), null);
        dropStyle.position = "absolute";
        var drop:Node = box({ key: base + ":drop",
                              style: OverlayChrome.MENU_PANEL.withPatch(dropStyle),
                              ariaName: "", visible: n.open });

        var options:Array = n.options == null ? [] : n.options;
        for (var j:int = 0; j < options.length; j++)
        {
            var label:String = OverlayList.labelOf(options[j]);
            var rowNode:Node = box({ key: base + ":i" + j, style: OverlayChrome.MENU_ITEM,
                                     ariaName: label });
            rowNode.addChild(text(label, { key: base + ":i" + j + ":t",
                                           style: OverlayChrome.MENU_TEXT, ariaName: "" }));
            drop.addChild(rowNode);
        }
        n.addChild(drop);
        return n;
    }
}
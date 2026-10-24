// asaot.ui.datePicker -- the author-facing factory for DatePickerNode.
//
//   datePicker({ key: "due", value: "2026-10-24", open: open, year: 2026, month: 10,
//                placeholder: "Pick a date", width: 200,
//                onSelect: function (iso:String):void { ... },
//                onMonthChange: function (y:int, m:int):void { ... },
//                onOpenChange: function (open:Boolean):void { ... } })
//
// STRUCTURE (DatePickerWidget depends on it):
//   dp node       style SELECT_TRIGGER (row, 34 high, padding [10,0]), width `width`
//     ├─ [0] label text    the value, or the placeholder (SELECT_LABEL: flexGrow 1)
//     └─ [1] panel  absolute, MENU_PANEL, width = 7 cells + the panel's own padding
//              ├─ head   row of DAY_H:  "<" | "2026-10" | ">"
//              └─ 6 weeks row of DAY_H: seven DAY_W cells each
//
// THE GRID IS ALWAYS SIX WEEKS, even when a month would fit in five. A fixed row count
// keeps the panel's height constant across months, so paging with the arrows does not
// make the panel (and everything under it) jump by 26pt.
//
// A blank cell keeps a key too (`:xN`): the reconciler needs stable identity, and the
// widget needs to distinguish "a blank cell was clicked" from "the click missed the
// grid" -- both are non-events, but only one of them should be reported as a miss.
package asaot.ui
{
    import asaot.ui.style.Length;
    import asaot.ui.style.Size;
    import asaot.ui.style.StyleRefinement;

    public function datePicker(opts:Object = null):Node
    {
        var n:DatePickerNode = new DatePickerNode();
        OptionSupport.applyOpts(n, opts);
        if (opts == null) opts = {};
        if (opts.open != null) n.open = Boolean(opts.open);
        if (opts.value != null) n.value = String(opts.value);
        if (opts.placeholder != null) n.placeholder = String(opts.placeholder);
        if (opts.width != null) n.width = Number(opts.width);
        if (opts.year != null) n.year = int(opts.year);
        if (opts.month != null) n.month = int(opts.month);
        // Option guards, as in every factory: absent leaves the node's default. (A
        // `cond ? null : value` ternary was the compiler-gaps G16 shape until stage
        // 266 fixed it; the guard is kept because it is the shorter spelling.)
        if (opts.onSelect != null) n.onSelect = (opts.onSelect as Function);
        if (opts.onMonthChange != null) n.onMonthChange = (opts.onMonthChange as Function);
        if (opts.onOpenChange != null) n.onOpenChange = (opts.onOpenChange as Function);
        if (n.ariaName == null) n.ariaName = "date picker";

        // A month with no year/month given still has to show SOMETHING: fall back to the
        // selected value's own month, then to the epoch. (The author is expected to keep
        // year/month in the model; this only stops a first render from showing 1970.)
        if ((opts.year == null || opts.month == null) && n.value != null && n.value.length >= 7)
        {
            n.year = int(n.value.substring(0, 4));
            n.month = int(n.value.substring(5, 7));
        }
        if (n.month < 1) n.month = 1;
        if (n.month > 12) n.month = 12;

        var base:String = n.key == null ? "datepicker" : String(n.key);

        var trig:StyleRefinement = new StyleRefinement();
        trig.size = Size.of(Length.px(n.width), null);
        n.style = (n.style == null ? new StyleRefinement() : n.style)
            .withPatch(OverlayChrome.SELECT_TRIGGER.withPatch(trig));

        var shown:String = n.value == null || n.value == "" ? n.placeholder : n.value;
        n.addChild(text(shown, { key: base + ":label", style: OverlayChrome.SELECT_LABEL,
                                 ariaName: "" }));

        // The panel is border-box: 7 cells + MENU_PANEL's 4pt padding on each side +
        // its 1pt border on each side. Getting this wrong squeezes the seven cells and
        // the whole grid reflows (the probe asserts cell rects, not just the panel).
        var inner:Number = OverlayChrome.DAY_W * 7;
        var panelStyle:StyleRefinement = new StyleRefinement();
        panelStyle.size = Size.of(Length.px(inner + 10), null);
        panelStyle.position = "absolute";
        var panel:Node = box({ key: base + ":panel",
                               style: OverlayChrome.MENU_PANEL.withPatch(panelStyle),
                               ariaName: "", visible: n.open });

        // ---- the month header ---------------------------------------------
        // row(), not box(): a BoxNode's `direction` field overrides the style's
        // flexDirection and defaults to "column" (see the note in tree.as).
        var head:Node = row({ key: base + ":head", ariaName: "",
                              style: StyleRefinement.from({
                                  alignItems: "center", height: OverlayChrome.DAY_H
                              }) });
        head.addChild(DatePickerParts.nav(base + ":prev", "\u2039"));
        head.addChild(text(DateMath.iso(n.year, n.month, 1).substring(0, 7),
                           { key: base + ":title", style: OverlayChrome.DP_TITLE, ariaName: "" }));
        head.addChild(DatePickerParts.nav(base + ":next", "\u203A"));
        panel.addChild(head);

        // ---- the six week rows --------------------------------------------
        var days:Array = [];
        var first:int = DateMath.weekday(n.year, n.month, 1);   // 0..6, Sunday-first
        var total:int = DateMath.daysInMonth(n.year, n.month);
        var cell:int = 0;
        for (var w:int = 0; w < 6; w++)
        {
            var weekStyle:StyleRefinement = StyleRefinement.from({
                height: OverlayChrome.DAY_H
            });
            var week:Node = row({ key: base + ":w" + w, style: weekStyle, ariaName: "" });
            for (var c:int = 0; c < 7; c++)
            {
                var dayNo:int = cell - first + 1;
                var muted:Boolean = dayNo < 1 || dayNo > total;
                var cellKey:String = muted
                    ? base + ":x" + cell
                    : base + ":d" + DateMath.pad2(dayNo);
                // A day cell is a COLUMN that centres its number in both axes.
                var cellStyle:StyleRefinement = StyleRefinement.from({
                    width: OverlayChrome.DAY_W, height: OverlayChrome.DAY_H,
                    alignItems: "center", justifyContent: "center"
                });
                if (n.value != null && n.value != ""
                    && n.value == DateMath.iso(n.year, n.month, dayNo))
                {
                    cellStyle = cellStyle.withPatch(StyleRefinement.from({
                        background: OverlayChrome.ITEM_SELECTED
                    }));
                }
                var cellNode:Node = box({ key: cellKey, style: cellStyle, ariaName: "" });
                if (!muted)
                {
                    cellNode.addChild(text(String(dayNo), {
                        key: cellKey + ":t", style: OverlayChrome.DAY_TEXT, ariaName: "" }));
                }
                week.addChild(cellNode);
                days.push({ key: cellKey, day: muted ? 0 : dayNo });
                cell = cell + 1;
            }
            panel.addChild(week);
        }
        n.days = days;

        n.addChild(panel);
        return n;
    }
}
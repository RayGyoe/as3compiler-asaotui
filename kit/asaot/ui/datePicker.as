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
//              ├─ head   row of DAY_H:  "<" | the month title | ">"
//              ├─ weekday row of DAY_H: seven labels, in the locale's week order
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
        if (n.ariaName == null || n.ariaName == "") n.ariaName = I18n.t("kit.date.label");

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
        // RUNS OF 3 ARGUMENTS ARE DELIBERATE: the month name and the day the week
        // starts on are LOCALE data, so nothing here may hardcode an English name or
        // a Sunday-first column. A locale that cannot be resolved still renders: the
        // title falls back to [[key]] (loud in the probe) and the grid to Sunday.
        var firstDay:int = int(I18n.t("kit.date.firstDay"));
        if (firstDay < 0 || firstDay > 6) firstDay = 0;

        // row(), not box(): box() honours the style's flexDirection, but row() also
        // PINS the axis, so nothing merged in later can stack the month header.
        var head:Node = row({ key: base + ":head", ariaName: "",
                              style: StyleRefinement.from({
                                  alignItems: "center", height: OverlayChrome.DAY_H
                              }) });
        head.addChild(DatePickerParts.nav(base + ":prev", "\u2039"));
        // THREE PARAMETERS, because "October 2026" and "2026年10月" need different
        // pieces: the name for the first, the number for the second.
        var title:String = I18n.t("kit.date.title", {
            year: n.year,
            month: I18n.t("kit.date.month." + n.month),
            monthNumber: n.month
        });
        head.addChild(text(title,
                           { key: base + ":title", style: OverlayChrome.DP_TITLE, ariaName: "" }));
        head.addChild(DatePickerParts.nav(base + ":next", "\u203A"));
        panel.addChild(head);

        // ---- the weekday row ----------------------------------------------
        // Without it the grid's column order is unmarked, and a Monday-first locale
        // (zh-CN) would silently reorder the month under a Sunday-first header. Same
        // DAY_W/DAY_H cells as the days, so the columns LINE UP; the cells take no
        // clicks (no onClick), and they are not focusable.
        var wdRow:Node = row({ key: base + ":wh", ariaName: "",
                               style: StyleRefinement.from({ height: OverlayChrome.DAY_H }) });
        for (var wdCol:int = 0; wdCol < 7; wdCol++)
        {
            var wd:int = (firstDay + wdCol) % 7;
            var wdStyle:StyleRefinement = StyleRefinement.from({
                width: OverlayChrome.DAY_W, height: OverlayChrome.DAY_H,
                alignItems: "center", justifyContent: "center"
            });
            var wdCell:Node = box({ key: base + ":wd" + wdCol, style: wdStyle, ariaName: "" });
            wdCell.addChild(text(I18n.t("kit.date.weekday." + wd), {
                key: base + ":wd" + wdCol + ":t",
                style: OverlayChrome.DAY_NAV_TEXT, ariaName: "" }));
            wdRow.addChild(wdCell);
        }
        panel.addChild(wdRow);

        // ---- the six week rows --------------------------------------------
        var days:Array = [];
        var first:int = DateMath.weekday(n.year, n.month, 1);   // 0..6, Sunday-based
        // Columns before day 1: `first` rotated so that column 0 is the locale's
        // first day of the week. Under the default (Sunday-first, `firstDay == 0`)
        // this is exactly `first`, which is why the English layout is unchanged.
        var lead:int = (first - firstDay + 7) % 7;
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
                var dayNo:int = cell - lead + 1;
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
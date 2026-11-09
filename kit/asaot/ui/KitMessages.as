// asaot.ui.KitMessages -- the kit's OWN user-visible strings, per locale.
//
// WHY THESE LIVE IN THE LIBRARY AND NOT IN AN APP CATALOG
// ------------------------------------------------------
// The kit renders strings no author ever writes: the `select` / `multiSelect` /
// `datePicker` empty-field hints, the date grid's month title / weekday labels /
// first day, and one default accessibility name per widget kind (`pagination`,
// `table`, `previous page`, `page 3`, `loading placeholder`, ...). An app that
// translates its own copy but still says "Pick a date" -- or still announces
// "separator" to a screen reader -- has not been translated, so the kit must
// ship these. They are the FLOOR: an app overrides any of them by registering
// the same key (I18n.addMessages merges per locale, later registration wins).
//
// The English values are BYTE-IDENTICAL to the literals they replaced, so an app
// that never calls I18n sees exactly the strings it saw before.
//
// FORMAT (machine-read by tools/i18n-check.cjs)
// -------------------------------------------
// One `"key": "value"` pair per line, so the checker can parse the shipped key
// set without importing this module from the AOT. Keys are namespaced `kit.`
// (reserved: an app key must not start with `kit.` unless it means to override).
//
// NOTHING HERE IS LOCALE-NEUTRAL DATA EXCEPT `kit.number.*` and
// `kit.date.firstDay`, which are STRINGS on purpose: the catalog is the only
// per-locale table the library has, and a second (typed) table for two scalars
// would be a second thing to keep in sync. I18n reads them with int()/as-is.
package asaot.ui
{
    public final class KitMessages
    {
        public static function en():Object
        {
            return {
                "kit.select.placeholder": "Select...",
                "kit.multiselect.placeholder": "Select",
                "kit.multiselect.label": "multi select",
                "kit.date.placeholder": "Pick a date",
                "kit.date.label": "date picker",
                "kit.date.title": "{month} {year}",
                "kit.date.month.1": "January",
                "kit.date.month.2": "February",
                "kit.date.month.3": "March",
                "kit.date.month.4": "April",
                "kit.date.month.5": "May",
                "kit.date.month.6": "June",
                "kit.date.month.7": "July",
                "kit.date.month.8": "August",
                "kit.date.month.9": "September",
                "kit.date.month.10": "October",
                "kit.date.month.11": "November",
                "kit.date.month.12": "December",
                "kit.date.weekday.0": "Su",
                "kit.date.weekday.1": "Mo",
                "kit.date.weekday.2": "Tu",
                "kit.date.weekday.3": "We",
                "kit.date.weekday.4": "Th",
                "kit.date.weekday.5": "Fr",
                "kit.date.weekday.6": "Sa",
                "kit.date.firstDay": "0",
                "kit.pagination.label": "pagination",
                "kit.pagination.prev": "previous page",
                "kit.pagination.next": "next page",
                "kit.pagination.page": "page {n}",
                "kit.table.label": "table",
                "kit.skeleton.label": "loading placeholder",
                "kit.accordion.label": "accordion",
                "kit.appbar.label": "toolbar",
                "kit.breadcrumb.label": "breadcrumb",
                "kit.combobox.label": "combobox",
                "kit.divider.label": "separator",
                "kit.icon.label": "icon",
                "kit.image.label": "image",
                "kit.list.label": "list",
                "kit.menu.label": "menu",
                "kit.navstack.label": "navigation",
                "kit.overlay.label": "overlay",
                "kit.popover.label": "popover",
                "kit.scrollview.label": "scrollable region",
                "kit.select.label": "select",
                "kit.sparkline.label": "sparkline",
                "kit.spinner.label": "loading",
                "kit.splitpane.label": "split pane",
                "kit.tabs.label": "tabs",
                "kit.toasthost.label": "notifications",
                "kit.tree.label": "tree",
                "kit.virtuallist.label": "list of {n}",
                "kit.number.group": ",",
                "kit.number.decimal": "."
            };
        }

        // Simplified Chinese: Monday-first grid, `2026年11月` title, and a
        // comma/period pair the runtime's own number formatting already matches.
        public static function zhCN():Object
        {
            return {
                "kit.select.placeholder": "请选择",
                "kit.multiselect.placeholder": "请选择",
                "kit.multiselect.label": "多选框",
                "kit.date.placeholder": "选择日期",
                "kit.date.label": "日期选择器",
                "kit.date.title": "{year}年{monthNumber}月",
                "kit.date.month.1": "一月",
                "kit.date.month.2": "二月",
                "kit.date.month.3": "三月",
                "kit.date.month.4": "四月",
                "kit.date.month.5": "五月",
                "kit.date.month.6": "六月",
                "kit.date.month.7": "七月",
                "kit.date.month.8": "八月",
                "kit.date.month.9": "九月",
                "kit.date.month.10": "十月",
                "kit.date.month.11": "十一月",
                "kit.date.month.12": "十二月",
                "kit.date.weekday.0": "日",
                "kit.date.weekday.1": "一",
                "kit.date.weekday.2": "二",
                "kit.date.weekday.3": "三",
                "kit.date.weekday.4": "四",
                "kit.date.weekday.5": "五",
                "kit.date.weekday.6": "六",
                "kit.date.firstDay": "1",
                "kit.pagination.label": "分页",
                "kit.pagination.prev": "上一页",
                "kit.pagination.next": "下一页",
                "kit.pagination.page": "第 {n} 页",
                "kit.table.label": "表格",
                "kit.skeleton.label": "加载占位",
                "kit.accordion.label": "折叠面板",
                "kit.appbar.label": "工具栏",
                "kit.breadcrumb.label": "面包屑导航",
                "kit.combobox.label": "组合框",
                "kit.divider.label": "分隔线",
                "kit.icon.label": "图标",
                "kit.image.label": "图片",
                "kit.list.label": "列表",
                "kit.menu.label": "菜单",
                "kit.navstack.label": "导航",
                "kit.overlay.label": "浮层",
                "kit.popover.label": "浮层卡片",
                "kit.scrollview.label": "可滚动区域",
                "kit.select.label": "选择框",
                "kit.sparkline.label": "走势图",
                "kit.spinner.label": "加载中",
                "kit.splitpane.label": "分栏",
                "kit.tabs.label": "标签页",
                "kit.toasthost.label": "通知",
                "kit.tree.label": "树",
                "kit.virtuallist.label": "列表，共 {n} 项",
                "kit.number.group": ",",
                "kit.number.decimal": "."
            };
        }

        public function KitMessages() { }
    }
}

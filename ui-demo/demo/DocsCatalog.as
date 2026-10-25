// demo/DocsCatalog.as -- the index of the docs app: which pages exist, in which
// group, and what each one says about itself.
//
// TWO HALVES, ON PURPOSE:
//   * `pages()` is CHEAP and always available: 42 tiny data objects. The sidebar
//     reads it on every render, and it must not construct a single widget.
//   * `sections(view, id)` builds the selected page's examples on demand. That is
//     where the factories are actually CALLED -- one page at a time, and only for
//     the page on screen.
//
// WHY data objects and not 41 classes: a page is a title, a blurb and a list of
// sections, and the sections need the live model (a demo reports into it). Making
// each page a class would add 41 files that differ only in their bodies.
//
// The coverage gate (tools/kind-coverage.cjs) scans this tree for factory CALLS,
// so a component that is registered but never documented is a red gate, not a
// missing page nobody notices.
package demo
{
    public final class DocsCatalog
    {
        public static const GROUPS:Array = [
            "Getting started", "Layout", "Text & badges", "Controls",
            "Pickers", "Data", "Navigation", "Feedback", "Overlay"
        ];

        private static var _pages:Array;

        private static function ensure():void
        {
            if (_pages != null) return;
            _pages = [
                new DocPage("start", "Getting started", 0,
                    "Describe a tree in render(); UiApp reconciles it into a retained one."),

                new DocPage("box", "box", 1, "The plain container: direction, padding, gap, background, border."),
                new DocPage("column", "column", 1, "box with direction \"column\" -- the default flow."),
                new DocPage("row", "row", 1, "box with direction \"row\"."),
                new DocPage("card", "card", 1, "A bordered, optionally titled surface for grouped content."),
                new DocPage("overlay", "overlay", 1, "The root of the SECOND retained tree (View.renderOverlay)."),

                new DocPage("text", "text", 2, "A run of text: the only node that owns a string."),
                new DocPage("label", "label", 2, "text() with a form-row name. An alias, not a kind."),
                new DocPage("chip", "chip", 2, "A small tonal tag: neutral, info or danger."),
                new DocPage("badge", "badge", 2, "A count pill, usually pinned to a corner."),
                new DocPage("avatar", "avatar", 2, "A circular initial from a name."),
                new DocPage("divider", "divider", 2, "A hairline rule, horizontal or vertical."),

                new DocPage("button", "button", 3, "A pressable label. Variants are styles, not kinds."),
                new DocPage("textField", "textField", 3, "Editable text, optionally bound, masked or ghosted."),
                new DocPage("textArea", "textArea", 3, "A multi-line field: Enter inserts a newline, the box is `rows` lines tall."),
                new DocPage("checkbox", "checkbox", 3, "A boolean with a label. Bound or plain."),
                new DocPage("radio", "radio", 3, "One of N in a named group."),
                new DocPage("toggle", "toggle", 3, "A switch: the `switch` kind, spelled around the keyword."),

                new DocPage("slider", "slider", 4, "A value dragged along a track."),
                new DocPage("select", "select", 4, "A list of options behind a trigger."),
                new DocPage("combobox", "combobox", 4, "A select whose options are filtered by typing."),
                new DocPage("datePicker", "datePicker", 4, "A calendar panel behind a trigger."),
                new DocPage("pagination", "pagination", 4, "Page numbers with ellipses, as chips."),

                new DocPage("list", "list", 5, "items -> rows, mapped once per render."),
                new DocPage("table", "table", 5, "Columns and rows, aligned by the layout engine."),
                new DocPage("tree", "tree", 5, "A flattened, expandable hierarchy."),
                new DocPage("virtualList", "virtualList", 5, "Only the visible rows exist as nodes."),
                new DocPage("scrollView", "scrollView", 5, "A clipped viewport over content taller than itself."),

                new DocPage("tabs", "tabs", 6, "A strip that writes its index back through a Binding."),
                new DocPage("breadcrumb", "breadcrumb", 6, "A trail of crumbs; the last one is current."),
                new DocPage("accordion", "accordion", 6, "Headers that open one panel -- or several, with mode: 'multi'."),

                new DocPage("progress", "progress", 7, "A determinate bar with a label."),
                new DocPage("spinner", "spinner", 7, "An indeterminate ring."),
                new DocPage("skeleton", "skeleton", 7, "Loading placeholders in text/circle/rect shapes."),
                new DocPage("tooltip", "tooltip", 7, "A small bubble with an arrow."),
                new DocPage("image", "image", 7, "A picture -- a BitmapData or a `src` -- scaled into its box."),
                new DocPage("icon", "icon", 7, "An SVG path drawn into its box: stroke or fill, any colour, any size."),

                new DocPage("dialog", "dialog", 8, "A scrim plus a centred panel -- overlay tree only."),
                new DocPage("drawer", "drawer", 8, "An edge sheet: the window's own gutter."),
                new DocPage("popover", "popover", 8, "A panel anchored to a key, sized by its content."),
                new DocPage("menu", "menu", 8, "A list of actions anchored to a trigger."),
                new DocPage("toast", "toast", 8, "A transient corner message."),
                new DocPage("toastHost", "toastHost", 8, "The bottom-right stack toasts drop into.")
            ];
        }

        public static function pages():Array
        {
            ensure();
            return _pages;
        }

        public static function page(id:String):DocPage
        {
            ensure();
            for (var i:int = 0; i < _pages.length; i++)
            {
                var p:DocPage = DocPage(_pages[i]);
                if (p.id == id) return p;
            }
            return null;
        }

        // The live examples of one page. Every factory call the docs make is in
        // one of these builders, so a page that stopped being listed is caught by
        // the coverage gate rather than by a reader.
        public static function sections(view:DocsView, id:String):Array
        {
            var s:Array = DocsStart.sections(view, id);
            if (s != null) return s;
            s = DocsLayout.sections(view, id);
            if (s != null) return s;
            s = DocsText.sections(view, id);
            if (s != null) return s;
            s = DocsControls.sections(view, id);
            if (s != null) return s;
            s = DocsPickers.sections(view, id);
            if (s != null) return s;
            s = DocsData.sections(view, id);
            if (s != null) return s;
            s = DocsNav.sections(view, id);
            if (s != null) return s;
            s = DocsFeedback.sections(view, id);
            if (s != null) return s;
            return DocsOverlay.sections(view, id);
        }
    }
}

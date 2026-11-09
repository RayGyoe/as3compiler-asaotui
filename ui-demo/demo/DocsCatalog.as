// demo/DocsCatalog.as -- the index of the docs app: which pages exist, in which
// group, and what each one says about itself.
//
// TWO HALVES, ON PURPOSE:
//   * `pages()` is CHEAP and always available: one tiny data object per page. The sidebar
//     reads it on every render, and it must not construct a single widget.
//   * `sections(view, id)` builds the selected page's examples on demand. That is
//     where the factories are actually CALLED -- one page at a time, and only for
//     the page on screen.
//
// WHY data objects and not one class per page: a page is a title, a blurb and a list of
// sections, and the sections need the live model (a demo reports into it). Making
// each page a class would add files that differ only in their bodies.
//
// The coverage gate (tools/kind-coverage.cjs) scans this tree for factory CALLS,
// so a component that is registered but never documented is a red gate, not a
// missing page nobody notices.
package demo
{
    public final class DocsCatalog
    {
        public static const GROUPS:Array = [
            "Apps", "Getting started", "Layout", "Text & badges", "Controls",
            "Pickers", "Data", "Navigation", "Feedback", "Overlay",
            "Motion", "System"
        ];

        // The page the three entry points land on. ONE constant: DocsMain, DocsAir
        // and DocsWeb each set `model.doc`, and a literal in three files is a
        // landing page that drifts. The tour asserts hand-computed rects on `start`
        // (DocsModel's own default) and only THEN navigates here -- so moving this
        // constant does not move a single assertion.
        public static const LANDING:String = "live";

        private static var _pages:Array;

        private static function ensure():void
        {
            if (_pages != null) return;
            _pages = [
                // THE APP. One page, first in the index, and what the shell opens on:
                // a live board is the only way to see what a frame costs.
                new DocPage("live", "live", 0,
                    "22 ticking quotes, 22 sparklines and the frame's own numbers."),

                new DocPage("start", "Getting started", 1,
                    "Describe a tree in render(); UiApp reconciles it into a retained one."),

                new DocPage("box", "box", 2, "The plain container: direction, padding, gap, background, border."),
                new DocPage("column", "column", 2, "box with direction \"column\" -- the default flow."),
                new DocPage("row", "row", 2, "box with direction \"row\"."),
                new DocPage("card", "card", 2, "A bordered, optionally titled surface for grouped content."),
                new DocPage("splitPane", "splitPane", 2, "Two panes and a grip: one ratio, a minSize floor, and a drag that reports it."),
                new DocPage("overlay", "overlay", 2, "The root of the SECOND retained tree (View.renderOverlay)."),

                new DocPage("text", "text", 3, "A run of text: the only node that owns a string."),
                new DocPage("label", "label", 3, "text() with a form-row name. An alias, not a kind."),
                new DocPage("chip", "chip", 3, "A small tonal tag: neutral, info or danger."),
                new DocPage("badge", "badge", 3, "A count pill, usually pinned to a corner."),
                new DocPage("avatar", "avatar", 3, "A circular initial from a name."),
                new DocPage("divider", "divider", 3, "A hairline rule, horizontal or vertical."),

                new DocPage("button", "button", 4, "A pressable label. Variants are styles, not kinds."),
                new DocPage("textField", "textField", 4, "Editable text, optionally bound, masked or ghosted."),
                new DocPage("textArea", "textArea", 4, "A multi-line field: Enter inserts a newline, the box is `rows` lines tall."),
                new DocPage("checkbox", "checkbox", 4, "A boolean with a label. Bound or plain."),
                new DocPage("radio", "radio", 4, "One of N in a named group."),
                new DocPage("toggle", "toggle", 4, "A switch: the `switch` kind, spelled around the keyword."),
                new DocPage("numberInput", "numberInput", 4, "A number in a box: steppers, a clamp range and a step."),

                new DocPage("slider", "slider", 5, "A value dragged along a track."),
                new DocPage("rangeSlider", "rangeSlider", 5, "Two thumbs on one track: a low and a high value."),
                new DocPage("select", "select", 5, "A list of options behind a trigger."),
                new DocPage("multiSelect", "multiSelect", 5, "A select whose menu stays open and reports each toggle."),
                new DocPage("combobox", "combobox", 5, "A select whose options are filtered by typing."),
                new DocPage("datePicker", "datePicker", 5, "A calendar panel behind a trigger."),
                new DocPage("pagination", "pagination", 5, "Page numbers with ellipses, as chips."),

                new DocPage("list", "list", 6, "items -> rows, mapped once per render."),
                new DocPage("table", "table", 6, "Columns and rows, aligned by the layout engine."),
                new DocPage("tree", "tree", 6, "A flattened, expandable hierarchy."),
                new DocPage("virtualList", "virtualList", 6, "Only the visible rows exist as nodes."),
                new DocPage("scrollView", "scrollView", 6, "A clipped viewport over content taller than itself."),
                new DocPage("sparkline", "sparkline", 6, "A series in a box: the shape of a day, a hundred points wide."),

                new DocPage("tabs", "tabs", 7, "A strip that writes its index back through a Binding."),
                new DocPage("breadcrumb", "breadcrumb", 7, "A trail of crumbs; the last one is current."),
                new DocPage("accordion", "accordion", 7, "Headers that open one panel -- or several, with mode: 'multi'."),
                new DocPage("navStack", "navStack", 7, "Pages that overlap and stay mounted: only the top one is visible."),
                new DocPage("appBar", "appBar", 7, "Leading/title/trailing, and a large title folded away by one number."),
                new DocPage("tabBar", "tabBar", 7, "An equal-cell bottom bar: one selected, each tap reports its own index."),

                new DocPage("progress", "progress", 8, "A determinate bar with a label."),
                new DocPage("spinner", "spinner", 8, "An indeterminate ring."),
                new DocPage("skeleton", "skeleton", 8, "Loading placeholders in text/circle/rect shapes."),
                new DocPage("tooltip", "tooltip", 8, "A small bubble with an arrow."),
                new DocPage("image", "image", 8, "A picture -- a BitmapData or a `src` -- scaled into its box."),
                new DocPage("icon", "icon", 8, "An SVG path drawn into its box: stroke or fill, any colour, any size."),

                new DocPage("dialog", "dialog", 9, "A scrim plus a centred panel -- overlay tree only."),
                new DocPage("drawer", "drawer", 9, "An edge sheet: the window's own gutter."),
                new DocPage("popover", "popover", 9, "A panel anchored to a key, sized by its content."),
                new DocPage("menu", "menu", 9, "A list of actions anchored to a trigger."),
                new DocPage("toast", "toast", 9, "A transient corner message."),
                new DocPage("toastHost", "toastHost", 9, "The bottom-right stack toasts drop into."),

                // MOTION. Two pages about TIME rather than about a box: the tween core
                // every style field already reaches, and the pointer a drag or a
                // hit-slop is built on. Both shipped long before they were documented
                // (`transition*` was on the style page; nothing else was anywhere).
                new DocPage("animation", "animation", 10,
                    "Style transitions and the tween core: one mechanism, every widget."),
                new DocPage("gesture", "gesture", 10,
                    "hitSlop, pointerEvents and the pointer a drag is built on."),

                // The SIX pages about the framework itself, not about one widget.
                // They are LAST in the sidebar because they are the reference you
                // reach for after a kind's page answered "what does it look like":
                // these answer "which field do I write to make it do that".
                new DocPage("style", "style", 11,
                    "The 35 fields: size, flex, spacing, box model, paint, transitions."),
                new DocPage("theme", "theme", 11,
                    "Four layers -- control default, theme slot, inherited text, author style."),
                new DocPage("state", "state", 11,
                    "Bindings, notify(dirty) and the Subscription: who owns a value."),
                new DocPage("events", "events", 11,
                    "Right click with its stage point, double click behind a runtime flag."),
                new DocPage("keyboard", "keyboard", 11,
                    "The focus ring, Tab, Enter/Space, the per-kind key map, and the keymap."),
                new DocPage("env", "env", 11,
                    "The platform's answers -- hasHover, safeArea, pixelRatio -- and who reads them."),

                // THE SEVENTH FRAMEWORK PAGE, and the only one whose subject is the
                // TEXT rather than the layout: `I18n` plus this app's own prose table.
                // It is here (not in its own group) because it answers the same kind
                // of question the other six do -- "which field do I write" -- and
                // because the switcher at the bottom of the index is its live demo.
                new DocPage("i18n", "i18n", 11,
                    "Message catalogs, one locale per window, and text that mirrors with it.")
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
            var s:Array = DocsLive.sections(view, id);
            if (s != null) return s;
            s = DocsStart.sections(view, id);
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
            s = DocsSystem.sections(view, id);
            if (s != null) return s;
            s = DocsI18n.sections(view, id);
            if (s != null) return s;
            s = DocsMotion.sections(view, id);
            if (s != null) return s;
            return DocsOverlay.sections(view, id);
        }
    }
}

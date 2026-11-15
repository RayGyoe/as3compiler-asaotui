// asaot.ui.ThemeMetrics -- the GEOMETRY half of a theme: the numbers a skin changes
// that are not colours.
//
// WHY THIS IS A SEPARATE TYPE. `ThemeTokens` is 45 colours and two mix knobs; a real
// skin also moves padding, corner radii, border widths and the type scale, and every
// one of those is a LAYOUT input. Keeping them apart is not tidiness -- it is the
// difference between "repaint" and "re-solve": a palette swap must never re-run layout
// (UiApp.markThemeDirty documents the cost), while a metrics swap must ALWAYS re-run it
// (a button really did get shorter). Two types, two epochs, two handlers.
//
// THE DEFAULTS REPRODUCE THE KIT'S OWN LITERALS, value for value. Before this type,
// `Theme.makeButton` hardcoded `Edges.of(9, 14, 9, 14)` / `Corners.all(6)` /
// `fontSize = 14` and five other builders did the same. `base()` is that exact table,
// so shipping this changed NO pixel of any existing app -- which is why the whole
// probe suite is the regression test for it.
//
// A SKIN IS A VALUE, NOT A MODE. `compact()` is a starting point, not a switch: take
// `base()`, change the four numbers your design changes, hand it to `Theme.setMetrics`.
// Nothing here is read directly by a widget -- `Theme.buildBaselines` consumes it, so a
// metrics bundle reaches every kind through the same baseline table colours do.
//
// NOT SCOPED (deliberate). A palette is a subtree's business (a darker sidebar), but
// density is a device/app-wide decision, and a scoped density would have to reach
// measurement, not just paint -- i.e. every widget's `measure` would start asking
// "which scope am I in" and the answer could differ between two passes of the same
// node. `themeScope` carries a palette only; this type is global by construction.
package asaot.ui
{
    public class ThemeMetrics
    {
        // The type scale. `font` is what every control baseline uses; the other two are
        // here so a skin can state its scale in one place instead of scattering 12/16
        // through the app (the kit itself does not read them yet).
        public var font:int;
        public var fontSm:int;
        public var fontLg:int;

        // Per-kind control padding. NOT derived from a shared base + ratio: 9/14 and
        // 7/10 are not a clean multiple, and inventing a ratio would silently move the
        // kit the day someone changed one number.
        public var buttonPadY:int;
        public var buttonPadX:int;
        public var inputPadY:int;
        public var inputPadX:int;
        public var chipPadY:int;
        public var chipPadX:int;
        public var badgePadY:int;
        public var badgePadX:int;

        // Corner radii: `radiusMd` is the button (and every kind that draws a control
        // surface), `radiusSm` the text input.
        public var radiusMd:int;
        public var radiusSm:int;

        // The control outline. A skin that wants square corners and no hairline can set
        // this to 0 -- the border is applied by the baseline, so 0 really means none.
        public var borderWidth:int;

        public function ThemeMetrics():void
        {
            this.font = 14;
            this.fontSm = 12;
            this.fontLg = 16;
            this.buttonPadY = 9;
            this.buttonPadX = 14;
            this.inputPadY = 7;
            this.inputPadX = 10;
            this.chipPadY = 2;
            this.chipPadX = 8;
            this.badgePadY = 0;
            this.badgePadX = 6;
            this.radiusMd = 6;
            this.radiusSm = 4;
            this.borderWidth = 1;
        }

        // The kit's shipped geometry, value for value. Every number below appears in a
        // `Theme.make*` baseline as a literal before this type existed.
        public static function base():ThemeMetrics
        {
            return new ThemeMetrics();
        }

        // A denser skin: the same design at ~80% of its air. Deliberately a PRESET, so
        // an app can hand one line to `Theme.setMetrics(ThemeMetrics.compact())` and
        // see its whole tree tighten.
        public static function compact():ThemeMetrics
        {
            var m:ThemeMetrics = new ThemeMetrics();
            m.font = 13;
            m.fontSm = 11;
            m.fontLg = 15;
            m.buttonPadY = 4;
            m.buttonPadX = 9;
            m.inputPadY = 4;
            m.inputPadX = 7;
            m.chipPadY = 1;
            m.chipPadX = 6;
            m.badgePadY = 0;
            m.badgePadX = 4;
            m.radiusMd = 4;
            m.radiusSm = 3;
            return m;
        }

        // A 4pt-GRID skin (theme-tokens-vs-cui.md §2.2), opt-in. Every padding and type
        // size is a multiple of 4, so controls land on the grid instead of the shipped
        // 9/7/2. It is a VALUE like any other skin: `setMetrics(grid4()` re-solves the
        // tree; the DEFAULT stays `base()` so no existing pixel moves. Control HEIGHTS
        // are not a slot -- they derive from padding + line height, which is why the
        // grid is expressed through the paddings and the type scale, not a height table.
        public static function grid4():ThemeMetrics
        {
            var m:ThemeMetrics = new ThemeMetrics();
            m.font = 16;
            m.fontSm = 12;
            m.fontLg = 20;
            m.buttonPadY = 8;
            m.buttonPadX = 16;
            m.inputPadY = 8;
            m.inputPadX = 12;
            m.chipPadY = 4;
            m.chipPadX = 8;
            m.badgePadY = 0;
            m.badgePadX = 8;
            m.radiusMd = 8;
            m.radiusSm = 4;
            return m;
        }

        // CONCENTRIC CORNERS (theme-tokens-vs-cui.md §2.1): an inner control's radius
        // must not exceed the outer container's radius minus the gap between them, or
        // the inner corners "poke" through the outer curve. This is the RULE, not a
        // value: a skin that nests controls computes the inner radius from the outer
        // one and the padding, instead of picking two unrelated numbers. Clamped at 0.
        public static function innerRadius(outer:int, gap:int):int
        {
            var r:int = outer - gap;
            return r > 0 ? r : 0;
        }

        // Read every field, in every method that copies or compares. A slot that is
        // forgotten here is a slot that silently never changes (copyFrom) or never
        // repaints (same) -- the same class of bug the box-tag rule in AGENTS.md names.
        public function copyFrom(o:ThemeMetrics):void
        {
            this.font = o.font;
            this.fontSm = o.fontSm;
            this.fontLg = o.fontLg;
            this.buttonPadY = o.buttonPadY;
            this.buttonPadX = o.buttonPadX;
            this.inputPadY = o.inputPadY;
            this.inputPadX = o.inputPadX;
            this.chipPadY = o.chipPadY;
            this.chipPadX = o.chipPadX;
            this.badgePadY = o.badgePadY;
            this.badgePadX = o.badgePadX;
            this.radiusMd = o.radiusMd;
            this.radiusSm = o.radiusSm;
            this.borderWidth = o.borderWidth;
        }

        public function clone():ThemeMetrics
        {
            var m:ThemeMetrics = new ThemeMetrics();
            m.copyFrom(this);
            return m;
        }

        public function same(o:ThemeMetrics):Boolean
        {
            if (o == null) return false;
            return this.font == o.font && this.fontSm == o.fontSm && this.fontLg == o.fontLg
                && this.buttonPadY == o.buttonPadY && this.buttonPadX == o.buttonPadX
                && this.inputPadY == o.inputPadY && this.inputPadX == o.inputPadX
                && this.chipPadY == o.chipPadY && this.chipPadX == o.chipPadX
                && this.badgePadY == o.badgePadY && this.badgePadX == o.badgePadX
                && this.radiusMd == o.radiusMd && this.radiusSm == o.radiusSm
                && this.borderWidth == o.borderWidth;
        }
    }
}
// asaot.ui.ThemeTokens -- the ONE palette the whole kit paints from.
//
// WHY A PHOTOCOPY OF THE OLD LITERALS IS THE SPEC: `light()` must reproduce, value
// for value, the colours that were hard-coded in Theme / OverlayChrome / TableNode /
// AccordionNode / BreadcrumbNode / ScrollViewNode / PaintKit and in the eighteen
// self-painting widgets. A token layer introduced by ALSO nudging the colours would
// be a theme change nobody asked for, and every pixel probe that pins "#FFFFFF" would
// have to be re-derived -- which is how a refactor quietly becomes a redesign. So the
// bar for `light()` is: same numbers, no exceptions. The probes prove it.
//
// WHY SO MANY SLOTS (and not twelve semantic ones): the old code used 0xE5E7EB for
// four different jobs -- a panel border, a slider track, the badge background and the
// skeleton bar. Those four must be able to DIVERGE in a dark theme (a border is a
// line over a surface; a track is a surface under a thumb), and they cannot diverge
// if they share a slot. Splitting them now costs lines and buys a theme that does not
// have to make "the badge looks like a border" compromises. A slot that no theme ever
// needs to move independently can be merged later; a shared slot that must split
// cannot be fixed without touching every call site.
//
// WHAT IS NOT HERE: geometry, radii, spacing, type scale. This class is colour plus
// the two state-mix knobs. `Theme` owns the per-kind baselines that USE these values.
//
// MUTATION CONTRACT: fields are `public var` so a theme is a plain typed object and
// a typo is a COMPILE error (a string-keyed table would move that to run time). But
// appearance code must treat the instance returned by `Theme.tokens()` as READ-ONLY:
// painting reads it every frame and nothing re-resolves behind your back. To change
// something, build a palette (`ThemeTokens.dark()` / `Theme.tokens().clone()`),
// assign fields, then `Theme.setTheme(that)` -- that is what bumps the epoch and
// repaints the tree.
package asaot.ui
{
    public final class ThemeTokens
    {
        // ---- surfaces ------------------------------------------------------
        public var surface:uint;         // panels, inputs, knobs: the page's own plane
        public var controlSurface:uint;  // a button's resting fill
        public var surfaceMuted:uint;    // table head, item hover band, select trigger
        public var surfaceSunken:uint;   // zebra stripe (one step BELOW the surface)
        public var surfaceSoft:uint;     // badge/chip default, tabs off segment, skeleton
        public var surfaceInverse:uint;  // tooltip bubble (inverted against the page)
        public var surfaceToast:uint;    // toast body
        public var knob:uint;            // the dot/thumb of a checkbox, radio, switch
        public var track:uint;           // slider / range / progress groove
        public var trackOff:uint;        // switch groove when off
        public var scrim:uint;           // modal dim, ARGB (alpha in the top byte)

        // ---- lines ---------------------------------------------------------
        public var border:uint;          // hairline: panel edge, grid line, divider
        public var borderStrong:uint;    // a control's outline at rest
        public var borderInput:uint;     // text field outline
        public var borderSoft:uint;      // checkbox outline when off
        public var divider:uint;         // a rule BETWEEN items (list separator)
        public var neutral:uint;         // mid grey that is NOT text: radio ring, avatar

        // ---- text ----------------------------------------------------------
        public var text:uint;            // the plain-text baseline
        public var textDefault:uint;     // what an unset style paints (0x000000)
        public var textControl:uint;     // a control's label at rest
        public var textStrong:uint;      // titles, table header, icon default
        public var textItem:uint;        // menu / tree / date rows
        public var textBody:uint;        // dialog body, badge text, tabs off label
        public var textMuted:uint;       // caret, twisty, secondary label
        public var textDisabled:uint;    // disabled row, neighbouring-month day
        public var placeholder:uint;     // empty-field hint
        public var onInverse:uint;       // text on surfaceInverse / surfaceToast
        public var onAccent:uint;        // text on an accent fill

        // ---- accent and status ---------------------------------------------
        public var accent:uint;          // the one brand colour
        public var accentCheck:uint;     // checkbox tick fill (historically 0x2F80ED)
        public var accentSoft:uint;      // selected-row band, badge info fill
        public var accentText:uint;      // text on accentSoft
        public var danger:uint;
        public var dangerSoft:uint;
        public var dangerText:uint;
        public var dangerStrong:uint;    // toast body when it is an error
        public var success:uint;         // switch on
        public var successStrong:uint;   // toast body when it is an ack
        public var neutralStrong:uint;   // spinner's neutral tone

        // ---- chrome --------------------------------------------------------
        public var focus:uint;           // the focus ring
        public var scrollBar:uint;       // thumb at rest
        public var scrollBarHover:uint;  // thumb hovered or dragged
        public var scrollTrack:uint;     // the groove behind the thumb

        // ---- state mixing (numbers, not colours) ---------------------------
        // A hover lifts the surface toward `hoverTint` by `hoverPct` percent; a press
        // pushes it toward `pressTint` by `pressPct`. On a light surface that is
        // white/black, which is what the kit always did. On a DARK surface pushing
        // toward black is invisible -- so the dark palette tints BOTH ways toward
        // white and makes press the stronger of the two. That is the one piece of
        // theme semantics that is not a colour swap.
        public var hoverTint:uint;
        public var pressTint:uint;
        public var hoverPct:int;
        public var pressPct:int;

        // The slot names in declaration order. Kept as data so a probe, the docs page
        // and the gate can iterate the table without reflect(). `tools/theme-tokens.cjs`
        // asserts this list is EXACTLY the declared fields -- it is a derived check,
        // not two hand-kept copies.
        public static const SLOT_NAMES:Array = [
            "surface", "controlSurface", "surfaceMuted", "surfaceSunken", "surfaceSoft",
            "surfaceInverse", "surfaceToast", "knob", "track", "trackOff", "scrim",
            "border", "borderStrong", "borderInput", "borderSoft", "divider", "neutral",
            "text", "textDefault", "textControl", "textStrong", "textItem", "textBody",
            "textMuted", "textDisabled", "placeholder", "onInverse", "onAccent",
            "accent", "accentCheck", "accentSoft", "accentText",
            "danger", "dangerSoft", "dangerText", "dangerStrong",
            "success", "successStrong", "neutralStrong",
            "focus", "scrollBar", "scrollBarHover", "scrollTrack",
            "hoverTint", "pressTint", "hoverPct", "pressPct"
        ];

        public function ThemeTokens() { }

        // The palette every release has shipped: the literals the kit used before it
        // had a token layer. DO NOT "tidy" these numbers -- see the header.
        public static function light():ThemeTokens
        {
            var t:ThemeTokens = new ThemeTokens();
            t.surface = 0xFFFFFF;
            t.controlSurface = 0xF1F3F5;
            t.surfaceMuted = 0xF3F4F6;
            t.surfaceSunken = 0xF9FAFB;
            t.surfaceSoft = 0xE5E7EB;
            t.surfaceInverse = 0x1F2937;
            t.surfaceToast = 0x111827;
            t.knob = 0xFFFFFF;
            t.track = 0xE5E7EB;
            t.trackOff = 0xD1D5DB;
            t.scrim = 0x66000000;

            t.border = 0xE5E7EB;
            t.borderStrong = 0xD0D0D0;
            t.borderInput = 0xCCCCCC;
            t.borderSoft = 0xBBBBBB;
            t.divider = 0xD1D5DB;
            t.neutral = 0x9CA3AF;

            t.text = 0x1A1A1A;
            t.textDefault = 0x000000;
            t.textControl = 0x202020;
            t.textStrong = 0x111827;
            t.textItem = 0x1F2937;
            t.textBody = 0x374151;
            t.textMuted = 0x6B7280;
            t.textDisabled = 0x9CA3AF;
            t.placeholder = 0x9A9A9A;
            t.onInverse = 0xFFFFFF;
            t.onAccent = 0xFFFFFF;

            t.accent = 0x2563EB;
            t.accentCheck = 0x2F80ED;
            t.accentSoft = 0xDBEAFE;
            t.accentText = 0x1D4ED8;
            t.danger = 0xDC2626;
            t.dangerSoft = 0xFEE2E2;
            t.dangerText = 0xB91C1C;
            t.dangerStrong = 0x991B1B;
            t.success = 0x34D399;
            t.successStrong = 0x065F46;
            t.neutralStrong = 0x64748B;

            t.focus = 0x2563EB;
            t.scrollBar = 0xB9C2D0;
            t.scrollBarHover = 0x8A97AB;
            t.scrollTrack = 0xE8EDF5;

            t.hoverTint = 0xFFFFFF;
            t.pressTint = 0x000000;
            t.hoverPct = 8;
            t.pressPct = 12;
            return t;
        }

        // The dark palette. This has NO AIR counterpart -- AIR has no theme switch, so
        // per AGENTS.md this is an enhancement: it is opt-in (the default stays light),
        // it is explicit (`Theme.setTheme(ThemeTokens.dark())`), and every value here
        // is a deliberate choice, not a derived one. Huess are the same slate family the
        // light palette already uses (0x0F172A..0x9CA3AF), so a page does not look like
        // a different product in the dark.
        //
        // The two decisions worth arguing about:
        //   * the knobs stay WHITE. A white dot on a grey track is the affordance; a
        //     dark knob on a dark track is a hole.
        //   * hover AND press both tint toward white (pressPct > hoverPct). Pushing a
        //     dark surface toward black -- the light-theme rule -- is invisible, and a
        //     button that does not answer a press is worse than one with the wrong tint.
        public static function dark():ThemeTokens
        {
            var t:ThemeTokens = new ThemeTokens();
            t.surface = 0x111827;
            t.controlSurface = 0x1F2937;
            t.surfaceMuted = 0x1F2937;
            t.surfaceSunken = 0x0D1424;
            t.surfaceSoft = 0x374151;
            t.surfaceInverse = 0x374151;
            t.surfaceToast = 0x1F2937;
            t.knob = 0xFFFFFF;
            t.track = 0x374151;
            t.trackOff = 0x4B5563;
            t.scrim = 0xCC000000;

            t.border = 0x374151;
            t.borderStrong = 0x4B5563;
            t.borderInput = 0x4B5563;
            t.borderSoft = 0x4B5563;
            t.divider = 0x4B5563;
            t.neutral = 0x6B7280;

            t.text = 0xE5E7EB;
            t.textDefault = 0xE5E7EB;
            t.textControl = 0xE5E7EB;
            t.textStrong = 0xF9FAFB;
            t.textItem = 0xE5E7EB;
            t.textBody = 0xD1D5DB;
            t.textMuted = 0x9CA3AF;
            t.textDisabled = 0x6B7280;
            t.placeholder = 0x6B7280;
            t.onInverse = 0xFFFFFF;
            t.onAccent = 0xFFFFFF;

            t.accent = 0x60A5FA;
            t.accentCheck = 0x60A5FA;
            t.accentSoft = 0x1E3A8A;
            t.accentText = 0xBFDBFE;
            t.danger = 0xEF4444;
            t.dangerSoft = 0x7F1D1D;
            t.dangerText = 0xFCA5A5;
            t.dangerStrong = 0x991B1B;
            t.success = 0x34D399;
            t.successStrong = 0x065F46;
            t.neutralStrong = 0x94A3B8;

            t.focus = 0x60A5FA;
            t.scrollBar = 0x4B5563;
            t.scrollBarHover = 0x6B7280;
            t.scrollTrack = 0x1F2937;

            t.hoverTint = 0xFFFFFF;
            t.pressTint = 0xFFFFFF;
            t.hoverPct = 8;
            t.pressPct = 18;
            return t;
        }

        public function clone():ThemeTokens
        {
            var t:ThemeTokens = new ThemeTokens();
            t.copyFrom(this);
            return t;
        }

        public function copyFrom(o:ThemeTokens):void
        {
            if (o == null) throw new Error("asaot.ui: ThemeTokens.copyFrom(null)");
            this.surface = o.surface;
            this.controlSurface = o.controlSurface;
            this.surfaceMuted = o.surfaceMuted;
            this.surfaceSunken = o.surfaceSunken;
            this.surfaceSoft = o.surfaceSoft;
            this.surfaceInverse = o.surfaceInverse;
            this.surfaceToast = o.surfaceToast;
            this.knob = o.knob;
            this.track = o.track;
            this.trackOff = o.trackOff;
            this.scrim = o.scrim;

            this.border = o.border;
            this.borderStrong = o.borderStrong;
            this.borderInput = o.borderInput;
            this.borderSoft = o.borderSoft;
            this.divider = o.divider;
            this.neutral = o.neutral;

            this.text = o.text;
            this.textDefault = o.textDefault;
            this.textControl = o.textControl;
            this.textStrong = o.textStrong;
            this.textItem = o.textItem;
            this.textBody = o.textBody;
            this.textMuted = o.textMuted;
            this.textDisabled = o.textDisabled;
            this.placeholder = o.placeholder;
            this.onInverse = o.onInverse;
            this.onAccent = o.onAccent;

            this.accent = o.accent;
            this.accentCheck = o.accentCheck;
            this.accentSoft = o.accentSoft;
            this.accentText = o.accentText;
            this.danger = o.danger;
            this.dangerSoft = o.dangerSoft;
            this.dangerText = o.dangerText;
            this.dangerStrong = o.dangerStrong;
            this.success = o.success;
            this.successStrong = o.successStrong;
            this.neutralStrong = o.neutralStrong;

            this.focus = o.focus;
            this.scrollBar = o.scrollBar;
            this.scrollBarHover = o.scrollBarHover;
            this.scrollTrack = o.scrollTrack;

            this.hoverTint = o.hoverTint;
            this.pressTint = o.pressTint;
            this.hoverPct = o.hoverPct;
            this.pressPct = o.pressPct;
        }

        // True when every slot of `a` equals the same slot of `b`.
        //
        // WRITTEN OUT FIELD BY FIELD, not `a[k] != b[k]` over SLOT_NAMES: this class is
        // SEALED, and `a[k]` on a sealed class is not a property read -- it compiles to
        // an undefined-property access (mxmlc rejects it; the AOT would look it up as a
        // dynamic key on a value that has no key table). Being explicit is also what
        // keeps a typo a compile error, which is the whole reason the slots are typed
        // fields instead of a string-keyed table.
        public static function same(a:ThemeTokens, b:ThemeTokens):Boolean
        {
            if (a == null || b == null) return a == b;
            if (a.surface != b.surface) return false;
            if (a.controlSurface != b.controlSurface) return false;
            if (a.surfaceMuted != b.surfaceMuted) return false;
            if (a.surfaceSunken != b.surfaceSunken) return false;
            if (a.surfaceSoft != b.surfaceSoft) return false;
            if (a.surfaceInverse != b.surfaceInverse) return false;
            if (a.surfaceToast != b.surfaceToast) return false;
            if (a.knob != b.knob) return false;
            if (a.track != b.track) return false;
            if (a.trackOff != b.trackOff) return false;
            if (a.scrim != b.scrim) return false;

            if (a.border != b.border) return false;
            if (a.borderStrong != b.borderStrong) return false;
            if (a.borderInput != b.borderInput) return false;
            if (a.borderSoft != b.borderSoft) return false;
            if (a.divider != b.divider) return false;
            if (a.neutral != b.neutral) return false;

            if (a.text != b.text) return false;
            if (a.textDefault != b.textDefault) return false;
            if (a.textControl != b.textControl) return false;
            if (a.textStrong != b.textStrong) return false;
            if (a.textItem != b.textItem) return false;
            if (a.textBody != b.textBody) return false;
            if (a.textMuted != b.textMuted) return false;
            if (a.textDisabled != b.textDisabled) return false;
            if (a.placeholder != b.placeholder) return false;
            if (a.onInverse != b.onInverse) return false;
            if (a.onAccent != b.onAccent) return false;

            if (a.accent != b.accent) return false;
            if (a.accentCheck != b.accentCheck) return false;
            if (a.accentSoft != b.accentSoft) return false;
            if (a.accentText != b.accentText) return false;
            if (a.danger != b.danger) return false;
            if (a.dangerSoft != b.dangerSoft) return false;
            if (a.dangerText != b.dangerText) return false;
            if (a.dangerStrong != b.dangerStrong) return false;
            if (a.success != b.success) return false;
            if (a.successStrong != b.successStrong) return false;
            if (a.neutralStrong != b.neutralStrong) return false;

            if (a.focus != b.focus) return false;
            if (a.scrollBar != b.scrollBar) return false;
            if (a.scrollBarHover != b.scrollBarHover) return false;
            if (a.scrollTrack != b.scrollTrack) return false;

            if (a.hoverTint != b.hoverTint) return false;
            if (a.pressTint != b.pressTint) return false;
            if (a.hoverPct != b.hoverPct) return false;
            if (a.pressPct != b.pressPct) return false;
            return true;
        }
    }
}
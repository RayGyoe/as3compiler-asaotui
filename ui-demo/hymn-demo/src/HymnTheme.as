// hymn/HymnTheme.as -- ONE place for the palette, the metrics and every STRUCTURAL
// style the hymn app renders with.
//
// The upstream app (Rust/GPUI) keeps its colours in `src/theme.rs` and its numbers at
// the call sites. That split does not survive a port: here every rect is reasoned about
// while LOOKING at a screenshot, so the numbers live beside the colours and the view
// never spells a literal.
//
// WHAT IS *NOT* HERE, AND WHY: single-line chrome (a pill, a badge, a segment) is not a
// constant. Its width is `padX + advance + padX`, measured with the painter's own face,
// and that number changes with the label -- so it is built on demand by HymnView.plate()
// and cached per geometry. A style constant could only carry a GUESSED width, and a
// guessed width is exactly how a pill ends up narrower than its text.
//
// TWO INSTANCES, NOT STATIC CONSTANTS. The app ships a light AND a dark palette
// (upstream does too, and the titlebar's gear button is not decorative), and a
// StyleRefinement is immutable once built. So each palette is an INSTANCE built once at
// startup; switching themes is `model.theme = ...` plus one invalidate, with no style
// object allocated per frame.
package hymn
{
    import asaot.ui.ThemeTokens;
    import asaot.ui.style.Length;
    import asaot.ui.style.StyleRefinement;

    public class HymnTheme
    {
        // ---- window (src/ui/mod.rs, src/ui/titlebar.rs) -------------------
        public static const WIN_W:Number = 1280;
        public static const WIN_H:Number = 820;
        // The window's own frame: 12pt around the panels and between them, and the
        // titlebar owns the top edge (the panels start AT its bottom, not 12 below it).
        public static const PAD:Number = 12;
        public static const GAP:Number = 12;
        public static const TB_H:Number = 52;
        public static const CARD_R:Number = 24;
        public static const PLAYER_H:Number = 100;
        public static const PLAYER_R:Number = 26;

        // ---- library (src/ui/library.rs) ---------------------------------
        public static const LIB_W:Number = 380;
        public static const LIB_PAD:Number = 20;
        public static const ROW_H:Number = 68;
        public static const ROW_PX:Number = 10;
        public static const ROW_PY:Number = 3;
        public static const ROW_R:Number = 14;
        public static const ROW_PIN:Number = 12;
        public static const TILE:Number = 42;
        public static const TILE_R:Number = 12;
        public static const SEARCH_H:Number = 46;
        public static const SEG_H:Number = 30;
        // The filter row is `p(3)` inside a `gap(4)` row of two `flex_1` segments; the
        // widths are computed from these so a segment is never a percentage child.
        public static const SEG_PAD:Number = 3;
        public static const SEG_GAP:Number = 4;

        // ---- reader (src/ui/reader.rs) -----------------------------------
        public static const TOOLBAR_H:Number = 64;
        public static const TOOL_PAD:Number = 32;
        public static const CONTENT_MAX:Number = 780;
        public static const CONTENT_PAD:Number = 40;
        public static const TITLE_FS:Number = 40;
        public static const TITLE_LH:Number = 46;
        public static const TITLE_PB:Number = 36;
        public static const CHIP_H:Number = 26;
        public static const BLOCK_PB:Number = 26;
        public static const GUTTER_W:Number = 48;
        public static const DISC:Number = 28;
        public static const LINE_GAP:Number = 12;   // between a voice pill and its line
        public static const LINE_RATIO:Number = 1.62;
        public static const DIM:Number = 0.42;
        public static const MIN_LYRIC:Number = 16;
        public static const MAX_LYRIC:Number = 34;

        // ---- player (src/ui/player.rs) -----------------------------------
        public static const MAP_H:Number = 26;
        public static const MAP_GAP:Number = 3;
        public static const MAP_MIN_W:Number = 18;
        // Corner radii are REAL numbers here, never 999. The painter asks Flash for
        // drawRoundRect(0, 0, w, h, r*2, r*2), and Flash clamps that ELLIPSE DIAMETER to
        // the box: on a 69x30 pill r=999 becomes a 69x30 ellipse and the caps bow into an
        // oval (measured: every pill in the window read as an ellipse). A stadium is
        // exactly h/2.
        public static const PL_TILE:Number = 52;
        public static const PL_CENTER_W:Number = 600;
        // 4 x 30 voice discs + the 44 play button + 4 x 6 gaps = 188. Upstream asks for
        // 170 and lets the row squeeze; a squeezed play button is 39 wide, not 44, and
        // an off-round transport is exactly what the screenshot shows as "hangs low".
        public static const PL_SIDE_W:Number = 188;

        // ---- the palette itself (src/theme.rs) ---------------------------
        public var name:String;
        public var bg:uint;
        public var panel:uint;
        public var raised:uint;
        public var hover:uint;
        public var line:uint;
        public var text:uint;
        public var text2:uint;
        public var text3:uint;
        public var accent:uint;
        public var accentSoft:uint;
        public var onAccent:uint;
        public var gold:uint;
        public var ink:uint;

        // ---- structural styles (built once, in the constructor) ----------
        public var ROOT:StyleRefinement;
        public var MID:StyleRefinement;
        public var BAND:StyleRefinement;
        public var TB:StyleRefinement;
        public var BRAND_ROW:StyleRefinement;
        public var BRAND_COL:StyleRefinement;
        public var CTRL_ROW:StyleRefinement;
        public var LIB:StyleRefinement;
        public var LIB_HEAD:StyleRefinement;
        public var LIB_TITLE_ROW:StyleRefinement;
        public var LIB_COUNT_ROW:StyleRefinement;
        public var SEARCH:StyleRefinement;
        public var SEARCH_TEXT:StyleRefinement;
        public var FILTERS:StyleRefinement;
        public var LIST:StyleRefinement;
        public var ROW:StyleRefinement;
        public var ROW_IN:StyleRefinement;
        public var ROW_IN_ON:StyleRefinement;
        public var ROW_COL:StyleRefinement;
        public var SLOT:StyleRefinement;
        public var READER:StyleRefinement;
        public var TOOLBAR:StyleRefinement;
        public var TOOL_LEFT:StyleRefinement;
        public var SEGCTL:StyleRefinement;
        public var READ_SCROLL:StyleRefinement;
        public var DOC:StyleRefinement;
        public var CHIPS:StyleRefinement;
        public var BLOCK:StyleRefinement;
        public var BLOCK_DIM:StyleRefinement;
        public var VERSE:StyleRefinement;
        public var VERSE_RULE:StyleRefinement;
        public var VERSE_RULE_OFF:StyleRefinement;
        public var GUTTER:StyleRefinement;
        public var LINES:StyleRefinement;
        public var LINE:StyleRefinement;
        public var CHORUS:StyleRefinement;
        public var CHORUS_ON:StyleRefinement;
        // The same two boxes and the verse row, faded: while a tune is playing the
        // sounding block stays at full opacity and the rest drop to DIM (upstream
        // reader.rs `Focus::Dim => view.opacity(DIMMED)`, DIMMED 0.42). A PATCHED COPY
        // rather than a second hand-written list of fields -- the dim state must differ
        // from its lit twin in opacity and in NOTHING else, or the block would jump as
        // the transport crosses it.
        public var VERSE_DIM:StyleRefinement;
        public var CHORUS_DIM:StyleRefinement;
        public var PLAYER:StyleRefinement;
        public var PL_LEFT:StyleRefinement;
        public var PL_CENTER:StyleRefinement;
        public var PL_TOP:StyleRefinement;
        public var VOICES:StyleRefinement;
        public var INSTR:StyleRefinement;
        public var PL_MAPROW:StyleRefinement;
        public var PL_MAP:StyleRefinement;
        public var PL_RIGHT:StyleRefinement;
        public var SEG:StyleRefinement;
        public var MAPSEG:StyleRefinement;
        public var MAPSEG_ON:StyleRefinement;
        public var MAPSEG_OFF:StyleRefinement;
        public var SPLASH:StyleRefinement;
        public var SPLASH_COL:StyleRefinement;
        public var LOADER:StyleRefinement;
        public var LOADER_BAR:StyleRefinement;

        public function HymnTheme(palette:String)
        {
            this.name = palette;
            var dark:Boolean = palette != "light";
            if (dark)
            {
                this.bg = 0x08090C;
                this.panel = 0x121419;
                this.raised = 0x1B1E26;
                this.hover = 0x1F222B;
                this.line = 0x24262E;
                this.text = 0xEEEFF2;
                this.text2 = 0xA6AAB6;
                this.text3 = 0x6C7180;
                this.accent = 0xF0B35A;
                this.accentSoft = 0x2F2922;
                this.onAccent = 0x1A1204;
                this.gold = 0xF0B35A;
                this.ink = 0x14161C;
            }
            else
            {
                this.bg = 0xE9EAEE;
                this.panel = 0xFFFFFF;
                this.raised = 0xF2F3F6;
                this.hover = 0xEDEFF4;
                this.line = 0xDFE1E8;
                this.text = 0x14161C;
                this.text2 = 0x4C515C;
                this.text3 = 0x848A97;
                this.accent = 0xB86A0B;
                this.accentSoft = 0xF7EBDC;
                this.onAccent = 0xFFFFFF;
                this.gold = 0xB86A0B;
                this.ink = 0x14161C;
            }
            this.build();
        }

        // ---- the KIT's palette, derived from ours ------------------------
        //
        // asaot.ui does not only take colours from a Style: some chrome is painted by
        // the WIDGET from `Theme.tokens()` -- the scroll bars, the placeholder ghost, a
        // control's base skin -- and those tokens are the kit's LIGHT defaults unless
        // told otherwise. Measured on this window: a white scrollbar thumb down the
        // reader and a 0xCCCCCC outline around the search field, on a 0x08090C page.
        // `Theme.setTheme()` swaps that palette at run time; this maps our semantic
        // colours onto its slots so the two agree.
        //
        // It is a COPY of the nearest kit palette with our colours over the slots we
        // own, not a table built from scratch: the slots we do not touch keep the kit's
        // own values and cannot silently turn black.
        public function kitPalette():ThemeTokens
        {
            var t:ThemeTokens = this.name == "light" ? ThemeTokens.light() : ThemeTokens.dark();
            t.surface = panel;
            t.controlSurface = raised;
            t.surfaceMuted = hover;
            t.surfaceSunken = bg;
            t.surfaceSoft = raised;
            t.surfaceInverse = text;
            t.surfaceToast = raised;
            t.knob = panel;
            t.track = raised;
            t.trackOff = raised;
            t.border = line;
            t.borderStrong = line;
            t.borderInput = line;
            t.borderSoft = line;
            t.divider = line;
            t.neutral = raised;
            t.neutralStrong = text3;
            t.text = text;
            t.textDefault = text;
            t.textControl = text;
            t.textStrong = text;
            t.textItem = text;
            t.textBody = text2;
            t.textMuted = text3;
            t.textDisabled = text3;
            t.placeholder = text3;
            t.onInverse = bg;
            t.onAccent = onAccent;
            t.accent = accent;
            t.accentCheck = accent;
            t.accentSoft = accentSoft;
            t.accentText = accent;
            t.focus = accent;
            // Upstream's scroll thumb is "white at 12%", and a token is a solid colour,
            // so it is pre-blended against the panel it sits on.
            t.scrollBar = this.mix(text, panel, 0.12);
            t.scrollBarHover = this.mix(text, panel, 0.22);
            t.scrollTrack = panel;
            return t;
        }

        public function mix(fg:uint, bgc:uint, a:Number):uint
        {
            var r:int = int((((fg >> 16) & 0xFF) * a) + (((bgc >> 16) & 0xFF) * (1 - a)));
            var g:int = int((((fg >> 8) & 0xFF) * a) + (((bgc >> 8) & 0xFF) * (1 - a)));
            var b:int = int(((fg & 0xFF) * a) + ((bgc & 0xFF) * (1 - a)));
            return (r << 16) | (g << 8) | b;
        }

        // A soft tint of the accent over the surface it lands on. Upstream writes
        // `Rgba { a: 0.18, ..p.accent }` and lets the compositor blend; a Fill here is
        // an opaque colour, so the blend happens now and the value stays literal.
        public function tint(base:uint, a:Number):uint
        {
            return this.mix(accent, base, a);
        }

        // The LINES column at an EXPLICIT measure. The wrap (`HymnWrap.lines`) and the
        // box must be the same number, and a flex-derived width is not that number: it
        // is whatever the row's free space happens to be after the solver distributes
        // it, so the boxes and the wrap can disagree (measured: block 1 of one hymn
        // came out 628 wide and 10pt right of the rest while resolving an identical
        // style). Width here is border-box, so it is the wrap measure verbatim.
        public function lines(w:Number):StyleRefinement
        {
            return StyleRefinement.from({
                flexDirection: "column", size: [Length.px(w), null], gap: 2
            });
        }

        // Every structural style in one pass. Read it top to bottom and you have the
        // whole shell; nothing in HymnView spells a size for a CONTAINER.
        private function build():void
        {
            // The page frame: 12pt on both sides and the bottom, gap 12 between the
            // titlebar, the panels and the player. NO TOP PADDING -- the titlebar is the
            // first child and owns the top edge, exactly as upstream's root does.
            ROOT = StyleRefinement.from({
                flexDirection: "column", position: "relative", gap: GAP,
                size: [Length.pct(1), Length.pct(1)], padding: [0, PAD, PAD, PAD],
                background: bg
            });
            MID = StyleRefinement.from({
                flexDirection: "column", flexGrow: 1, flexBasis: 0,
                size: [Length.pct(1), null], gap: GAP
            });
            BAND = StyleRefinement.from({
                flexDirection: "row", flexGrow: 1, flexBasis: 0, size: [Length.pct(1), null]
            });

            TB = StyleRefinement.from({
                flexDirection: "row", alignItems: "center", justifyContent: "space-between",
                size: [Length.pct(1), Length.px(TB_H)], padding: [0, 20, 0, 20]
            });
            BRAND_ROW = StyleRefinement.from({
                flexDirection: "row", alignItems: "center", gap: 12
            });
            BRAND_COL = StyleRefinement.from({
                flexDirection: "column", justifyContent: "center",
                size: [null, Length.px(34)], gap: 0
            });
            CTRL_ROW = StyleRefinement.from({
                flexDirection: "row", alignItems: "center", gap: 4
            });

            LIB = StyleRefinement.from({
                flexDirection: "column", size: [Length.px(LIB_W), Length.pct(1)],
                background: panel, cornerRadii: CARD_R,
                borderWidths: 1, borderColor: line, overflow: "hidden"
            });
            LIB_HEAD = StyleRefinement.from({
                flexDirection: "column", gap: 14, size: [Length.pct(1), null],
                padding: [LIB_PAD, LIB_PAD, 10, LIB_PAD]
            });
            LIB_TITLE_ROW = StyleRefinement.from({
                flexDirection: "row", alignItems: "center", justifyContent: "space-between",
                size: [Length.pct(1), Length.px(36)]
            });
            LIB_COUNT_ROW = StyleRefinement.from({
                flexDirection: "row", alignItems: "center", gap: 6
            });
            SEARCH = StyleRefinement.from({
                flexDirection: "row", alignItems: "center", gap: 10,
                size: [Length.pct(1), Length.px(SEARCH_H)], padding: [0, 8, 0, 16],
                background: raised, cornerRadii: SEARCH_H / 2
            });
            // EVERY chrome field is written out, because the kit MERGES its per-kind
            // base style UNDER this refinement: an unset borderWidths stays the kit
            // base's 1px 0xCCCCCC input outline, and an unset background stays its white
            // surface. That is how a dark app grew a white rectangle around its own text
            // field (measured: 0xCCCCCC on all four sides).
            SEARCH_TEXT = StyleRefinement.from({
                flexGrow: 1, flexBasis: 0, size: [null, Length.px(20)],
                padding: [0, 0, 0, 0], borderWidths: 0, cornerRadii: 0,
                background: raised
            });
            FILTERS = StyleRefinement.from({
                flexDirection: "row", gap: SEG_GAP, size: [Length.pct(1), Length.px(SEG_H + SEG_PAD * 2)],
                padding: [SEG_PAD, SEG_PAD, SEG_PAD, SEG_PAD],
                background: raised, cornerRadii: (SEG_H + SEG_PAD * 2) / 2
            });
            LIST = StyleRefinement.from({
                flexGrow: 1, flexBasis: 0, size: [Length.pct(1), null],
                padding: [0, 0, 8, 0]
            });
            ROW = StyleRefinement.from({
                size: [Length.pct(1), Length.px(ROW_H)],
                padding: [ROW_PY, ROW_PX, ROW_PY, ROW_PX]
            });
            ROW_IN = StyleRefinement.from({
                flexDirection: "row", alignItems: "center", gap: 14,
                size: [Length.pct(1), Length.pct(1)], padding: [0, ROW_PIN, 0, ROW_PIN],
                cornerRadii: ROW_R, background: panel
            });
            ROW_IN_ON = StyleRefinement.from({
                flexDirection: "row", alignItems: "center", gap: 14,
                size: [Length.pct(1), Length.pct(1)], padding: [0, ROW_PIN, 0, ROW_PIN],
                cornerRadii: ROW_R, background: accentSoft
            });
            ROW_COL = StyleRefinement.from({
                flexDirection: "column", flexGrow: 1, flexBasis: 0,
                size: [null, null], gap: 2, justifyContent: "center"
            });

            // The sidebar slot: 380 + the 12pt gap to the reader, CLIPPED, so the pane
            // slides out from under the reader instead of shrinking it.
            SLOT = StyleRefinement.from({
                flexDirection: "row", size: [Length.px(LIB_W + GAP), Length.pct(1)],
                overflow: "hidden"
            });

            READER = StyleRefinement.from({
                flexDirection: "column", flexGrow: 1, flexBasis: 0,
                size: [null, Length.pct(1)], background: panel, cornerRadii: CARD_R,
                borderWidths: 1, borderColor: line, overflow: "hidden"
            });
            TOOLBAR = StyleRefinement.from({
                flexDirection: "row", alignItems: "center", justifyContent: "space-between",
                size: [Length.pct(1), Length.px(TOOLBAR_H)],
                padding: [0, TOOL_PAD, 0, TOOL_PAD]
            });
            TOOL_LEFT = StyleRefinement.from({
                flexDirection: "row", alignItems: "center", gap: 10
            });
            // The A-/A+ pair is a segmented control: a padded pill that CONTAINS the two
            // buttons, so the raised surface reads as one track.
            SEGCTL = StyleRefinement.from({
                flexDirection: "row", alignItems: "center",
                padding: [3, 3, 3, 3], background: raised, cornerRadii: 19
            });
            READ_SCROLL = StyleRefinement.from({
                flexGrow: 1, flexBasis: 0, size: [Length.pct(1), null]
            });
            // The document column: max 780 wide, 40pt of side padding, centred. The
            // 780 is a MAXIMUM upstream (a wide window keeps the measure); here the pane
            // is sized from the window, so it is an exact width and the wrap arithmetic
            // stays a constant.
            DOC = StyleRefinement.from({
                flexDirection: "column", alignItems: "center",
                size: [Length.pct(1), null], padding: [0, CONTENT_PAD, 0, CONTENT_PAD]
            });
            CHIPS = StyleRefinement.from({
                flexDirection: "row", flexWrap: "wrap", gap: 8,
                size: [Length.pct(1), null], margin: [14, 0, 0, 0]
            });
            BLOCK = StyleRefinement.from({
                flexDirection: "column", size: [Length.pct(1), null]
            });
            BLOCK_DIM = StyleRefinement.from({
                flexDirection: "column", size: [Length.pct(1), null], opacity: DIM
            });
            // The verse marker lives in the MARGIN (a negative left margin plus the same
            // padding back), so the 2pt rule appears and disappears without the text
            // moving. THE RULE IS ITS OWN CHILD, NOT A LEFT BORDER: PaintKit strokes a
            // box with ONE line width -- it reads borderWidths.top for the whole
            // rectangle -- so a per-side width list is a zero-width stroke in all
            // four directions and paints nothing (measured: no accent rule at all).
            VERSE = StyleRefinement.from({
                flexDirection: "row", position: "relative", size: [Length.pct(1), null],
                margin: [0, 0, 0, -14], padding: [0, 0, 0, 12]
            });
            VERSE_RULE = StyleRefinement.from({
                position: "absolute", inset: [0, null, 0, 0], size: [Length.px(2), null],
                cornerRadii: 1, background: accent
            });
            VERSE_RULE_OFF = StyleRefinement.from({
                position: "absolute", inset: [0, null, 0, 0], size: [Length.px(2), null],
                cornerRadii: 1, background: panel
            });
            GUTTER = StyleRefinement.from({
                flexDirection: "column", size: [Length.px(GUTTER_W), null]
            });
            LINES = StyleRefinement.from({
                flexDirection: "column", flexGrow: 1, flexBasis: 0,
                size: [null, null], gap: 2
            });
            LINE = StyleRefinement.from({
                flexDirection: "row", alignItems: "flex-start", gap: LINE_GAP,
                size: [Length.pct(1), null]
            });
            CHORUS = StyleRefinement.from({
                flexDirection: "column", gap: 10, size: [Length.pct(1), null],
                padding: [22, 22, 22, 22], cornerRadii: 20,
                background: accentSoft, borderWidths: 1, borderColor: accentSoft
            });
            CHORUS_ON = StyleRefinement.from({
                flexDirection: "column", gap: 10, size: [Length.pct(1), null],
                padding: [22, 22, 22, 22], cornerRadii: 20,
                background: accentSoft, borderWidths: 1, borderColor: accent
            });
            // The faded twins. `withPatch` copies the parent's refined values and lays the
            // patch on top, so identity changes (the reconciler needs that: a new pointer
            // is what tells it to re-resolve a block when the song moves) while geometry
            // stays bit-identical.
            var dimOnly:StyleRefinement = StyleRefinement.from({ opacity: DIM });
            VERSE_DIM = VERSE.withPatch(dimOnly);
            CHORUS_DIM = CHORUS.withPatch(dimOnly);

            PLAYER = StyleRefinement.from({
                flexDirection: "row", alignItems: "center", gap: 24,
                size: [Length.pct(1), Length.px(PLAYER_H)],
                padding: [0, 16, 0, 16], background: panel, cornerRadii: PLAYER_R,
                borderWidths: 1, borderColor: line
            });
            PL_LEFT = StyleRefinement.from({
                flexDirection: "row", alignItems: "center", gap: 14,
                flexGrow: 1, flexBasis: 0, size: [null, Length.pct(1)]
            });
            PL_CENTER = StyleRefinement.from({
                flexDirection: "column", alignItems: "center", gap: 10,
                size: [Length.px(PL_CENTER_W), null]
            });
            PL_TOP = StyleRefinement.from({
                flexDirection: "row", alignItems: "center", justifyContent: "center", gap: 16,
                size: [Length.pct(1), null]
            });
            // Both side groups hug the play button: the voices from the left, the
            // instruments from the right. Left-aligned content in a fixed 188pt box puts
            // 50pt of dead space beside the transport and shifts its optical centre off
            // the panel's (measured: 15px left of centre at 150% DPI).
            VOICES = StyleRefinement.from({
                flexDirection: "row", gap: 6, size: [Length.px(PL_SIDE_W), null],
                alignItems: "center", justifyContent: "flex-end"
            });
            INSTR = StyleRefinement.from({
                flexDirection: "row", gap: 2, size: [Length.px(PL_SIDE_W), null],
                alignItems: "center", justifyContent: "flex-start"
            });
            PL_MAPROW = StyleRefinement.from({
                flexDirection: "row", alignItems: "center", gap: 10,
                size: [Length.pct(1), null]
            });
            PL_MAP = StyleRefinement.from({
                flexDirection: "row", alignItems: "center", gap: MAP_GAP,
                flexGrow: 1, flexBasis: 0, size: [null, Length.px(MAP_H)]
            });
            PL_RIGHT = StyleRefinement.from({
                flexDirection: "column", alignItems: "flex-end", justifyContent: "center",
                gap: 8, flexGrow: 1, flexBasis: 0, size: [null, Length.pct(1)]
            });
            SEG = StyleRefinement.from({
                flexDirection: "row", alignItems: "center", justifyContent: "center",
                // A real radius, never 999: the painter asks Flash for an ELLIPSE of
                // r*2 inside the box, so an oversized r becomes an oval (see the note
                // at the top of this file). Half the 30pt segment is the capsule.
                cornerRadii: SEG_H / 2
            });
            MAPSEG = StyleRefinement.from({
                flexDirection: "row", position: "relative", size: [null, Length.px(MAP_H)],
                cornerRadii: 8, overflow: "hidden", background: raised
            });
            MAPSEG_ON = StyleRefinement.from({
                flexDirection: "row", position: "relative", size: [null, Length.px(MAP_H)],
                cornerRadii: 8, overflow: "hidden", background: accent
            });

            // ---- splash -------------------------------------------------
            SPLASH = StyleRefinement.from({
                position: "absolute", inset: [0, 0, 0, 0],
                alignItems: "center", justifyContent: "center", background: bg
            });
            SPLASH_COL = StyleRefinement.from({
                flexDirection: "column", alignItems: "center", gap: 8
            });
            LOADER = StyleRefinement.from({
                size: [Length.px(140), Length.px(3)], cornerRadii: 2,
                background: raised, overflow: "hidden", flexDirection: "row"
            });
            LOADER_BAR = StyleRefinement.from({
                size: [Length.px(56), Length.px(3)], cornerRadii: 2, background: accent
            });
        }
    }
}

// asaot.ui.Theme -- control baselines, the author-override layer, and the four-layer
// style resolution (design doc section 2.3).
//
// RESOLUTION ORDER (low -> high priority):
//   1. controlDefault(kind)        // static table, REBUILT when the palette changes
//   2. theme slot                  // the author's `setControlDefault` override
//   3. parent's INHERITED subset   // only text.* + visibility + cursor
//   4. node.style (the refinement) // author's explicit override
//
// WHY LAYOUT DEFAULTS ARE NOT INHERITED: flexbox properties do not cascade; only
// the typography subset does. Making `size`/`padding` inherit would "look right"
// on a shallow tree and then diverge from every browser. This table is the
// concrete expression of the doc's warning.
//
// THE PALETTE (2026-10-27): every colour below now comes from `ThemeTokens`, and
// `setTheme()` swaps the whole palette at RUN time. Three rules make that safe:
//   * `light()` reproduces the old literals exactly, so the default build is
//     unchanged (the pixel probes are the proof, not this comment);
//   * the live palette is a PRIVATE copy -- a caller's `ThemeTokens` instance is
//     copied in, so mutating it afterwards cannot silently repaint half the tree;
//   * every swap bumps `themeEpoch()`, and `UiApp` turns an epoch change into
//     "re-describe + mark every node's style stale + repaint". Re-describing is what
//     refreshes the factory-built refinements (they are rebuilt with the new palette);
//     the stale bit is what re-resolves the nodes whose style pointer did not move.
//
// `setControlDefault` IS AN OVERRIDE LAYER, NOT A TABLE WRITE. It used to write
// straight into `_defaults`, which meant a theme swap silently erased the author's
// customisation. Overrides now live in `_overrides`, survive every swap, and are
// re-applied on top. The flip side is documented in setControlDefault: an override
// is a LITERAL Style, so it does not follow a theme swap (build it from
// `Theme.tokens()` inside a factory if it must).
//
// THE RESOLVE WRITES INTO A CALLER BUFFER (`out`), and the two scratch Styles are
// reused statics, so no per-node `Style` is allocated here. Composite buffers
// (Size/Edges/Corners) may still be allocated when a refinement actually
// changes -- and that only happens on a frame where a style pointer changed,
// never in a steady frame (the resolver's pointer-identity test skips first).
package asaot.ui
{
    import asaot.ui.style.Corners;
    import asaot.ui.style.Edges;
    import asaot.ui.style.Fill;
    import asaot.ui.style.Length;
    import asaot.ui.style.Size;
    import asaot.ui.style.Style;
    import asaot.ui.style.StyleRefinement;
    import asaot.ui.style.TextStyle;

    public final class Theme
    {
        private static var _scratch1:Style;
        private static var _scratch2:Style;
        private static var _defaults:Object;    // kind -> Style, from the palette
        private static var _overrides:Object;   // kind -> Style, from the author
        private static var _overrideCount:int;  // kept rather than counted: no for-in
        private static var _palette:ThemeTokens;
        private static var _epoch:int;

        // Kinds whose whole region IS the interactive thing. They hand the pointer
        // the hand shape (the same affordance AIR gives a SimpleButton). The list
        // is deliberately short: a scroll view, a list, a table and a tree are
        // SELECTABLE REGIONS, not buttons -- a hand over every pixel of a 400px
        // list claims every pixel is clickable, which is exactly the kind of lie
        // that makes a pointer feel broken. Roles that are clickable only when the
        // author says so (image / avatar / card / box) set `cursor` themselves.
        private static const CLICKABLE:Array = ["button", "checkbox", "radio", "switch",
            "slider", "select", "combobox", "tabs", "menu", "accordion", "pagination",
            "breadcrumb", "chip", "datePicker"];
        private static var _clickable:Style;

        // ---- the palette --------------------------------------------------

        // The live palette. READ-ONLY by contract: painting reads it every frame
        // and nothing re-resolves behind your back, so mutating this instance
        // changes the next repaint without bumping the epoch. Use
        // `Theme.setTheme(Theme.tokens().clone())` after mutating a clone.
        public static function tokens():ThemeTokens
        {
            ensure();
            return _palette;
        }

        // Changes only when the palette is swapped. `UiApp` compares it once per
        // frame; that comparison is the whole "a theme switch happened" signal.
        public static function themeEpoch():int
        {
            ensure();
            return _epoch;
        }

        public static function setTheme(t:ThemeTokens):void
        {
            if (t == null)
            {
                throw new Error("asaot.ui: Theme.setTheme(null) -- pass ThemeTokens.light() / "
                    + "ThemeTokens.dark() / Theme.tokens().clone()");
            }
            ensure();
            // COPY, do not alias: the caller keeps its instance and may keep
            // mutating it, and an appearance that changes without an epoch bump is
            // exactly the silent inconsistency this layer exists to prevent.
            _palette.copyFrom(t);
            buildDefaults();
            // The one class that bakes colours into StyleRefinement VALUES (styles are
            // resolved earlier than paint, so a paint-time read cannot fix them).
            OverlayChrome.rebuild();
            _epoch = _epoch + 1;
        }

        public static function isTheme(t:ThemeTokens):Boolean
        {
            ensure();
            return ThemeTokens.same(_palette, t);
        }

        // ---- control baselines --------------------------------------------

        private static function ensure():void
        {
            if (_scratch1 != null) return;
            _scratch1 = new Style();
            _scratch2 = new Style();
            _palette = ThemeTokens.light();
            _overrides = {};
            _overrideCount = 0;
            _epoch = 0;
            buildDefaults();
        }

        private static function buildDefaults():void
        {
            _defaults = {};
            _defaults["box"] = makeBox();
            _defaults["text"] = makeText();
            _defaults["button"] = makeButton();
            _defaults["textInput"] = makeTextInput();
            _defaults["textArea"] = makeTextInput();
            _defaults["checkbox"] = makeCheckbox();
            // ONE shared instance: `resolve` copies the baseline into scratch1 and
            // never writes it in place, so every clickable kind can point at the
            // same style without any of them affecting another.
            _clickable = makeBox();
            _clickable.cursor = "hand";
            for (var i:int = 0; i < CLICKABLE.length; i++)
            {
                var k:String = String(CLICKABLE[i]);
                if (_defaults[k] == null) _defaults[k] = _clickable;
                else _defaults[k].cursor = "hand";
            }
        }

        // The baseline for a kind, OVERRIDE FIRST. The fallback to "box" is what makes
        // an unlisted kind legal (a custom widget gets the container baseline).
        public static function controlDefault(kind:String):Style
        {
            ensure();
            var o:Style = _overrides[kind];
            if (o != null) return o;
            var s:Style = _defaults[kind];
            return s != null ? s : _defaults["box"];
        }

        // The author's override layer. Build it FROM the current default and change
        // only what you mean -- a partial Style would write its own unset (null)
        // fields over the baseline and erase the rest.
        //
        // IT SURVIVES A THEME SWAP, and that is deliberate (a customisation the author
        // asked for must not vanish because the user flipped a switch). But it is a
        // LITERAL Style: its colours are whatever they were when it was built. If it
        // has to follow the palette, do not override the kind -- pass a style from the
        // factory instead, built from `Theme.tokens()` on every describe.
        public static function setControlDefault(kind:String, s:Style):void
        {
            ensure();
            if (s == null) throw new Error("asaot.ui: Theme.setControlDefault(\"" + kind + "\", null)");
            if (_overrides[kind] == null) _overrideCount = _overrideCount + 1;
            _overrides[kind] = s;
        }

        public static function clearControlDefault(kind:String):void
        {
            ensure();
            if (_overrides[kind] != null) _overrideCount = _overrideCount - 1;
            delete _overrides[kind];
        }

        public static function controlOverrideCount():int
        {
            ensure();
            return _overrideCount;
        }

        public static function resolve(out:Style, kind:String, parent:Style,
                                      r:StyleRefinement, dirOverride:String):void
        {
            ensure();
            var base:Style = controlDefault(kind);
            base.copyInto(_scratch1);
            _scratch2.clear();
            if (parent != null) parent.projectInherited(_scratch2);
            _scratch1.refineInto(out, _scratch2);
            if (r != null)
            {
                // `r` is the higher-priority layer, so it must not alias `out`:
                // refine into scratch2 (r wins over out), then copy into out.
                r.refineInto(_scratch2, out);
                _scratch2.copyInto(out);
            }
            if (dirOverride != null) out.flexDirection = dirOverride;
        }

        // ---- the baseline styles ------------------------------------------
        // Every colour here is a palette slot. The numbers that are NOT colours
        // (padding, radius, border width) stay literal: this class is not a design
        // system, it is the kit's own resting look.

        private static function makeBox():Style
        {
            var s:Style = new Style();
            s.boxSizing = "borderBox";
            return s;
        }

        private static function makeText():Style
        {
            var s:Style = new Style();
            s.text.fontSize = 14;
            s.text.color = _palette.text;
            return s;
        }

        private static function makeButton():Style
        {
            var s:Style = new Style();
            s.padding = Edges.of(9, 14, 9, 14);
            s.borderWidths = Edges.all(1);
            s.borderColor = _palette.borderStrong;
            s.cornerRadii = Corners.all(6);
            s.background = Fill.solid(_palette.controlSurface);
            s.text.fontSize = 14;
            s.text.color = _palette.textControl;
            return s;
        }

        private static function makeTextInput():Style
        {
            var s:Style = new Style();
            s.padding = Edges.of(7, 10, 7, 10);
            s.borderWidths = Edges.all(1);
            s.borderColor = _palette.borderInput;
            s.cornerRadii = Corners.all(4);
            s.background = Fill.solid(_palette.surface);
            s.text.fontSize = 14;
            s.text.color = _palette.textControl;
            return s;
        }

        private static function makeCheckbox():Style
        {
            var s:Style = new Style();
            s.text.fontSize = 14;
            s.text.color = _palette.textControl;
            return s;
        }
    }
}
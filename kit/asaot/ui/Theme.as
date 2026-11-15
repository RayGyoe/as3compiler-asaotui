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

        // ---- scopes (2026-11-15) ----------------------------------------
        // A scope is a palette applied to ONE subtree (see ScopedTheme). Cached by
        // PALETTE VALUE, not by call site: `themeScope()` runs on every describe, and
        // a fresh ScopedTheme per frame would rebuild a kind table per frame (garbage)
        // AND move every node's baseline pointer, which re-resolves the subtree and
        // defeats the pointer-identity test the resolver opens with.
        private static var _scopes:Array;
        private static var _scopeSeq:int;

        // ---- the describe stack (2026-11-15) ----------------------------
        // FACTORIES BAKE COLOURS AT DESCRIBE TIME (the table header fill, the app bar,
        // the breadcrumb links, the list separators). Those refinements are VALUES, so
        // they cannot be fixed at paint time -- the only moment a factory can learn
        // "this subtree is scoped" is WHILE IT RUNS. `themeScope(pal, build)` therefore
        // pushes the palette, calls the author's builder, and pops; `tokens()` answers
        // with the top of this stack, so every factory inside gets the scoped palette
        // without a single factory having to know scopes exist.
        //
        // SAFE BECAUSE DESCRIBE IS SYNCHRONOUS: the whole tree is built by one
        // depth-first call before reconcile/layout/paint run, so a palette can never be
        // "current" while a different node paints. Paint-time reads go through
        // `n.pal()` (the node's own scope), NOT through this stack.
        private static var _describe:Array;

        // ---- the geometry half (2026-11-15) ------------------------------
        // A skin is not only a palette: padding, radii, border widths and the type
        // scale are the other half, and they are LAYOUT inputs. They live in
        // `ThemeMetrics` and are consumed by the SAME baseline table the colours are,
        // so one build path serves both halves.
        //
        // TWO EPOCHS, ON PURPOSE. `themeEpoch` means "repaint" (a palette swap never
        // moved a number: see UiApp.markThemeDirty). `metricsEpoch` means "re-solve",
        // because a button really did get shorter. One epoch for both would force every
        // palette swap through a full layout pass for nothing.
        private static var _metrics:ThemeMetrics;
        private static var _metricsEpoch:int;

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
        //
        // DURING A DESCRIBE THIS ANSWERS WITH THE INHERITED SCOPE'S PALETTE when one is
        // on the stack: a factory that bakes a colour is building part of that
        // subtree, so the global palette would be the wrong answer (see _describe).
        public static function tokens():ThemeTokens
        {
            ensure();
            if (_describe.length > 0) return ThemeTokens(_describe[_describe.length - 1]);
            return _palette;
        }

        // The palette of the scope currently being described, or null. Factories do
        // not need this (they call tokens()); it exists so `themeScope` can nest
        // without saving a palette it did not push.
        public static function describeDepth():int
        {
            ensure();
            return _describe.length;
        }

        public static function pushDescribe(pal:ThemeTokens):void
        {
            ensure();
            if (pal == null)
            {
                throw new Error("asaot.ui: Theme.pushDescribe(null)");
            }
            _describe.push(pal);
        }

        // Returns the palette that was pushed, so a caller can assert it is popping
        // what it pushed instead of silently unbalancing the stack.
        public static function popDescribe():ThemeTokens
        {
            ensure();
            if (_describe.length == 0) return null;
            return ThemeTokens(_describe.pop());
        }

        // A scope for this palette value, reusing an equal one. THE SEARCH IS LINEAR
        // AND TINY: a program has as many scopes as its design has surfaces, not as
        // many as it has nodes.
        public static function scopeFor(pal:ThemeTokens):ScopedTheme
        {
            ensure();
            if (pal == null) return null;
            for (var i:int = 0; i < _scopes.length; i++)
            {
                var s:ScopedTheme = ScopedTheme(_scopes[i]);
                if (s.samePalette(pal)) return s;
            }
            _scopeSeq = _scopeSeq + 1;
            var made:ScopedTheme = new ScopedTheme(pal, _scopeSeq);
            _scopes.push(made);
            return made;
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

        // ---- metrics (the geometry half) ------------------------------------

        // The live metrics bundle. READ-ONLY by contract, same rule as `tokens()`:
        // mutate a CLONE and hand it to `setMetrics`, or nothing repaints.
        public static function metrics():ThemeMetrics
        {
            ensure();
            return _metrics;
        }

        // Changes only when the geometry bundle is swapped. `UiApp` compares it once
        // per frame and turns a change into a re-solve (the palette epoch only repaints).
        public static function metricsEpoch():int
        {
            ensure();
            return _metricsEpoch;
        }

        // COPY, do not alias -- the same reason `setTheme` copies its palette. A swap
        // that changes nothing is a no-op: bumping the epoch would re-solve the whole
        // tree to arrive at the same numbers.
        public static function setMetrics(m:ThemeMetrics):void
        {
            if (m == null)
            {
                throw new Error("asaot.ui: Theme.setMetrics(null) -- pass ThemeMetrics.base() "
                    + "/ ThemeMetrics.compact() / Theme.metrics().clone()");
            }
            ensure();
            if (_metrics.same(m)) return;
            _metrics.copyFrom(m);
            buildDefaults();
            // EVERY SCOPE REBUILDS ITS OWN BASELINE TABLE. A ScopedTheme keeps its own
            // palette but takes its geometry from the global bundle, so leaving it
            // alone would leave a scoped card on the old density -- the "half a
            // picture" failure, one dimension over.
            for (var i:int = 0; i < _scopes.length; i++) ScopedTheme(_scopes[i]).rebuild();
            // Overlay chrome bakes geometry as well as colours into refinements.
            OverlayChrome.rebuild();
            _metricsEpoch = _metricsEpoch + 1;
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
            _scopes = [];
            _scopeSeq = 0;
            _describe = [];
            _metrics = ThemeMetrics.base();
            _metricsEpoch = 0;
            buildDefaults();
        }

        private static function buildDefaults():void
        {
            var b:Object = buildBaselines(_palette, _metrics);
            _defaults = Object(b.defaults);
            _clickable = Style(b.clickable);
        }

        // THE KIND BASELINES, PARAMETERISED BY PALETTE. This is the ONE builder: the
        // global table (built from the live palette by setTheme) and every ScopedTheme
        // (built from its own) run through it, so a scope can never drift from the
        // global kit by a copied-and-edited table.
        //
        // Returns { defaults: kind -> Style, clickable: Style }. `clickable` is ONE
        // shared instance: `resolve` copies the baseline into scratch1 and never
        // writes it in place, so every clickable kind can point at the same style
        // without any of them affecting another.
        public static function buildBaselines(pal:ThemeTokens, m:ThemeMetrics = null):Object
        {
            if (m == null) m = _metrics != null ? _metrics : ThemeMetrics.base();
            var d:Object = {};
            d["box"] = makeBox();
            d["text"] = makeText(pal, m);
            d["button"] = makeButton(pal, m);
            d["textInput"] = makeTextInput(pal, m);
            d["textArea"] = makeTextInput(pal, m);
            d["checkbox"] = makeCheckbox(pal, m);
            d["chip"] = makeChip(pal, m);
            d["badge"] = makeBadge(pal, m);
            var clickable:Style = makeBox();
            clickable.cursor = "hand";
            for (var i:int = 0; i < CLICKABLE.length; i++)
            {
                var k:String = String(CLICKABLE[i]);
                if (d[k] == null) d[k] = clickable;
                else Style(d[k]).cursor = "hand";
            }
            return { defaults: d, clickable: clickable };
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

        // The author's override for a kind, or null. Read by ScopedTheme so the override
        // layer keeps its place in a scoped subtree (it is the second of the four
        // layers, and an override is a LITERAL Style -- it does not follow the palette
        // in either direction).
        public static function controlOverride(kind:String):Style
        {
            ensure();
            return _overrides[kind];
        }

        public static function controlOverrideCount():int
        {
            ensure();
            return _overrideCount;
        }

        public static function resolve(out:Style, kind:String, parent:Style,
                                      r:StyleRefinement, dirOverride:String,
                                      scope:ScopedTheme = null):void
        {
            ensure();
            var base:Style = scope != null ? scope.controlDefault(kind) : controlDefault(kind);
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
        // Every COLOUR here is a palette slot; every NUMBER a metrics slot. Neither is
        // a literal any more: a builder that hardcodes 9 or 6 is a skin that cannot
        // reach it (the `theme-tokens-vs-cui.md` audit listed exactly that as gap #1,
        // and it is closed here). The builders stay the ONE place a kind's resting look
        // is defined -- they just take both bundles as parameters now.

        private static function makeBox():Style
        {
            var s:Style = new Style();
            s.boxSizing = "borderBox";
            return s;
        }

        private static function makeText(pal:ThemeTokens, m:ThemeMetrics):Style
        {
            var s:Style = new Style();
            s.text.fontSize = m.font;
            s.text.color = pal.text;
            return s;
        }

        private static function makeButton(pal:ThemeTokens, m:ThemeMetrics):Style
        {
            var s:Style = new Style();
            s.padding = Edges.of(m.buttonPadY, m.buttonPadX, m.buttonPadY, m.buttonPadX);
            s.borderWidths = Edges.all(m.borderWidth);
            s.borderColor = pal.borderStrong;
            s.cornerRadii = Corners.all(m.radiusMd);
            s.background = Fill.solid(pal.controlSurface);
            s.text.fontSize = m.font;
            s.text.color = pal.textControl;
            return s;
        }

        private static function makeTextInput(pal:ThemeTokens, m:ThemeMetrics):Style
        {
            var s:Style = new Style();
            s.padding = Edges.of(m.inputPadY, m.inputPadX, m.inputPadY, m.inputPadX);
            s.borderWidths = Edges.all(m.borderWidth);
            s.borderColor = pal.borderInput;
            s.cornerRadii = Corners.all(m.radiusSm);
            s.background = Fill.solid(pal.surface);
            s.text.fontSize = m.font;
            s.text.color = pal.textControl;
            return s;
        }

        private static function makeCheckbox(pal:ThemeTokens, m:ThemeMetrics):Style
        {
            var s:Style = new Style();
            s.text.fontSize = m.font;
            s.text.color = pal.textControl;
            return s;
        }

        private static function makeChip(pal:ThemeTokens, m:ThemeMetrics):Style
        {
            var s:Style = new Style();
            s.padding = Edges.of(m.chipPadY, m.chipPadX, m.chipPadY, m.chipPadX);
            s.text.fontSize = m.font;
            s.text.color = pal.textControl;
            return s;
        }

        private static function makeBadge(pal:ThemeTokens, m:ThemeMetrics):Style
        {
            var s:Style = new Style();
            s.padding = Edges.of(m.badgePadY, m.badgePadX, m.badgePadY, m.badgePadX);
            s.text.fontSize = m.font;
            s.text.color = pal.textControl;
            return s;
        }
    }
}
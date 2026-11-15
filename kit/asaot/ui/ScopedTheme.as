// asaot.ui.ScopedTheme -- one palette applied to ONE SUBTREE.
//
// WHY THIS EXISTS (2026-11-15): `Theme` is a process-wide singleton, so "a darker
// sidebar over a lighter page" and "two panes of the same widgets side by side in
// different palettes" were both impossible: `setTheme` repaints the WHOLE tree, and
// the only per-subtree colour mechanism was a hand-written StyleRefinement on every
// node (which is not a theme -- it does not follow the palette, it does not reach
// widgets that paint themselves, and it cannot be the thing a designer swaps).
//
// A SCOPE IS A PALETTE PLUS ITS OWN KIND BASELINES. The baselines are the part that
// cannot be skipped: `Theme.controlDefault(kind)` bakes palette values into a Style,
// so a subtree that only swapped the palette at paint time would still resolve its
// resolved style -- borders, control surfaces, text colours -- from the GLOBAL
// palette. That is the "half a picture" failure this kit keeps punishing, so the
// table is rebuilt per scope from the scope's own colours (same builders, one
// parameter: Theme.buildBaselines).
//
// THE SCOPE'S PALETTE IS A COPY, for the same reason `Theme.setTheme` copies: a
// caller keeps its ThemeTokens instance and may keep mutating it, and a tree that
// changes colour without anyone asking is worse than one that ignores the edit.
//
// WHAT A SCOPE DOES **NOT** DO, stated here rather than discovered later:
//   * it does not reach the HOST OVERLAYS (menu / tooltip / date picker / toast).
//     Those live in UiApp's third retained tree with `OverlayChrome`'s baked styles,
//     which are rebuilt by `Theme.setTheme` only -- a dropdown opened from inside a
//     scoped panel is drawn in the GLOBAL palette. That is a real limitation, not a
//     bug: those layers are positioned in stage coordinates and can sit outside the
//     subtree that asked for the scope.
//   * it does not recolour an author's `setControlDefault` override. Overrides are
//     literal Styles by contract (they are the author's, they survive a swap), so
//     they win in every scope with whatever colours they were built with.
//   * `ThemeTokens` is not extended: a scope is a different VALUE of the same 45
//     slots, not a second token vocabulary.
//   * it does not scope GEOMETRY. Density lives in `ThemeMetrics` and is app-wide:
//     a scoped density would have to reach measurement (not just paint), and a
//     node's measurement must not depend on which pass is asking. A scope takes the
//     live metrics, and `Theme.setMetrics` rebuilds every scope's table.
package asaot.ui
{
    import asaot.ui.style.Corners;
    import asaot.ui.style.Edges;
    import asaot.ui.style.Fill;
    import asaot.ui.style.Style;

    public final class ScopedTheme
    {
        // The owned palette. Read-only by contract, like Theme.tokens().
        private var _palette:ThemeTokens;
        // kind -> Style, rebuilt by the constructor from `_palette`.
        private var _defaults:Object;
        // The shared clickable baseline (see Theme.buildBaselines).
        private var _clickable:Style;
        // Identity for the "is this the same scope?" test in UiNode. Two scopes with
        // the same palette are EQUAL (Theme.scopeFor caches them), so a describe that
        // rebuilds its palette every frame does not churn the tree.
        private var _id:int;

        public function ScopedTheme(pal:ThemeTokens, id:int):void
        {
            if (pal == null)
            {
                throw new Error("asaot.ui: ScopedTheme(null) -- pass ThemeTokens.light() / dark() / "
                    + "Theme.tokens().clone()");
            }
            this._palette = ThemeTokens.light();
            this._palette.copyFrom(pal);
            this._id = id;
            this.rebuild();
        }

        // Re-derive this scope's kind table from its palette and the LIVE metrics.
        // The palette belongs to the scope; the geometry belongs to the app (ThemeMetrics
        // is global by design -- see that file). `Theme.setMetrics` calls this for every
        // cached scope, so a density change reaches a scoped subtree too instead of
        // leaving it on the previous padding -- the "half a picture" failure, one
        // dimension over.
        public function rebuild():void
        {
            var b:Object = Theme.buildBaselines(this._palette);
            this._defaults = b.defaults;
            this._clickable = b.clickable;
        }

        public function tokens():ThemeTokens { return this._palette; }
        public function id():int { return this._id; }

        // The author's override layer wins here too (it is the higher-priority layer
        // of the four that Theme documents), then this scope's own baseline, then the
        // shared container baseline for an unlisted kind.
        public function controlDefault(kind:String):Style
        {
            var o:Style = Theme.controlOverride(kind);
            if (o != null) return o;
            var s:Style = this._defaults[kind];
            return s != null ? s : this._defaults["box"];
        }

        public function samePalette(t:ThemeTokens):Boolean
        {
            return ThemeTokens.same(this._palette, t);
        }
    }
}
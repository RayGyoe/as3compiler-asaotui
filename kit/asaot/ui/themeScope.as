// asaot.ui.themeScope -- a subtree that uses its own PALETTE (2026-11-15).
//
//   themeScope(SIDEBAR, function():Array { return [ navList(), ... ]; })
//
// WHY THE CHILDREN ARE A FUNCTION AND NOT AN ARRAY. Factories bake colours at DESCRIBE
// time (the table's header fill, the app bar's surface, the breadcrumb's link ink, the
// list's separators). Those refinements are VALUES -- they cannot be repaired at paint
// time -- so a subtree can only be genuinely themed if the factories that build it RUN
// while the palette is known. `themeScope` pushes the palette on Theme's describe
// stack, calls the builder, then pops; `Theme.tokens()` answers with whatever is on
// that stack, so every factory inside sees the scoped palette without knowing scopes
// exist. An array ARGUMENT would already have been evaluated by then (AS3 evaluates
// arguments before the call), which would bake the GLOBAL palette -- the half-themed
// subtree this whole feature is meant to avoid.
//
// SAFE BECAUSE DESCRIBE IS SYNCHRONOUS: the tree is built depth-first in one call,
// before reconcile/layout/paint, so the stack can never be "current" while a node from
// a different scope is being painted. Paint reads go through `UiNode.pal()` instead.
//
// THE STACK IS UNWOUND ON A THROW. A leaked push would recolor every later factory in
// the frame -- silently, and only after some other error -- so the pop is in a
// catch-and-rethrow rather than a bare statement.
//
// The node itself is a plain `box`: a scope is a colour boundary, not a layout one.
// Its own style/opts still work (`themeScope(pal, build, { padding: 12, gap: 8 })`).
package asaot.ui
{
    public function themeScope(pal:ThemeTokens, build:Function, opts:Object = null):Node
    {
        if (pal == null)
        {
            throw new Error("asaot.ui: themeScope(null, ...) -- pass ThemeTokens.dark(), "
                + "Theme.tokens().clone() or another palette");
        }
        if (build == null)
        {
            throw new Error("asaot.ui: themeScope(..., null) -- the second argument is a "
                + "function returning the children array, so the subtree is built while the "
                + "palette is in effect");
        }
        // The scope's OWN copy, so the factories in the builder agree with what paint and
        // resolve will later use (a caller mutating its ThemeTokens afterwards must not
        // recolour half the subtree).
        var scope:ScopedTheme = Theme.scopeFor(pal);
        Theme.pushDescribe(scope.tokens());
        var kids:Array = null;
        try
        {
            kids = build();
        }
        catch (e:Error)
        {
            Theme.popDescribe();
            throw e;
        }
        Theme.popDescribe();

        // An ARRAY, not a Node: the builder's contract is "return the children". A
        // single node would be the same thing in disguise, so accepting it would make
        // two shapes legal and hide the argument this API is named after. Say so
        // instead of dying in a #1034 two frames later.
        if (!(kids is Array))
        {
            throw new Error("asaot.ui: the themeScope builder must return an Array of "
                + "children (it returned " + kids + ") -- this is a colour boundary, not "
                + "a container: themeScope(pal, function ():Array { return [ ... ]; }, opts)");
        }

        var n:BoxNode = new BoxNode();
        OptionSupport.applyOpts(n, opts);
        n.theme = pal;
        OptionSupport.addChildren(n, kids);
        return n;
    }
}
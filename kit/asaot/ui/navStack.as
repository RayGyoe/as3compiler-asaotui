// asaot.ui.navStack -- the author-facing factory for NavStackNode (see
// NavStackNode.as for why the file is lowercase and the class is not).
//
//   navStack([home, detail, settings], { key: "nav", activeIndex: model.depth - 1,
//                                       onBack: function ():void { model.pop(); } })
//
// The pages are ordinary Nodes, back-most first. Each one is wrapped in an
// `position:absolute, inset:0` box so the pages OVERLAP (a stack is not a column)
// and only the top one is `visible` -- hidden pages stay mounted, which is what
// keeps a page's scroll offset and typed text alive while another page is shown.
//
// The wrapper key is derived from the page's OWN key, so a page keeps its node
// identity (and therefore its state) across pushes and pops. A page with no key
// falls back to its index, which is the reconciler's default and is only right
// while nothing is popped from the middle -- so pass a key for anything that can
// be inserted into the middle of the stack.
//
// `activeIndex` is REQUIRED to mean anything: the default (-1) shows the last page,
// i.e. the top of the stack, which is what push-then-render produces with no extra
// bookkeeping.
package asaot.ui
{
    import asaot.ui.style.StyleRefinement;
    import asaot.ui.style.pct;

    public function navStack(pages:Array, opts:Object = null):Node
    {
        var n:NavStackNode = new NavStackNode();
        n.pages = pages == null ? [] : pages;
        OptionSupport.applyOpts(n, opts);
        if (n.ariaName == null || n.ariaName == "") n.ariaName = "navigation";
        if (opts != null)
        {
            if (opts.activeIndex != null) n.activeIndex = int(Number(opts.activeIndex));
            if (opts.onBack != null) n.onBack = opts.onBack as Function;
        }
        // The one shape a page is given (see the loop below). Built HERE, not as a
        // file-level `var`: a module-level initialiser is not reliably run in this
        // subset (measured: the constant arrived null and every page kept its own
        // style, which looked exactly like "absolute is unsupported").
        var fill:StyleRefinement = StyleRefinement.from({
            position: "absolute", inset: 0, size: [pct(1), pct(1)] });
        var top:int = NavStackNode.topIndex(n.pages.length, n.activeIndex);
        for (var i:int = 0; i < n.pages.length; i++)
        {
            var p:Node = n.pages[i] as Node;
            if (p == null)
            {
                throw new Error("asaot.ui: navStack page " + i + " is not a Node");
            }
            // A PAGE FILLS THE STACK, and that is imposed here rather than asked of
            // the author: a page that had to size itself would have to know the
            // stack's current box, which is exactly what a stack is for.
            //
            // MEASURED (twice): the obvious spelling does not work in this engine.
            // Wrapping each page in an `position:absolute, inset:0` box does give it
            // the right RECT, but a percentage or `flexGrow` child INSIDE that box
            // collapses to height 0 -- a percentage height cannot resolve against a
            // size that came from insets. So the pages are absolute themselves, under
            // the (in-flow) stack, where `pct(1)` resolves against a definite parent.
            // Consequence, stated rather than hidden: the stack must have a size of
            // its own (an explicit one, or a parent that stretches it); a page is
            // exactly that box and puts anything smaller inside itself.
            var e:Element = p as Element;
            if (e == null)
            {
                throw new Error("asaot.ui: navStack page " + i + " is not an Element");
            }
            e.visible = (i == top);
            var own:StyleRefinement = p.style;
            p.style = own == null ? fill : own.withPatch(fill);
            n.addChild(p);
        }
        return n;
    }
}

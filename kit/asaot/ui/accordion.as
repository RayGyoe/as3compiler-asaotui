// asaot.ui.accordion -- the author-facing factory for AccordionNode (see
// AccordionNode.as for why the file is lowercase and the class is not).
//
//   accordion(
//     [{ title: "General", content: column({}, [...]) },
//      { title: "Advanced", content: column({}, [...]) }],
//     { key: "a", style: { size: [280, 220], gap: 1 },
//       activeIndex: bindTo(model, "open"), onToggle: onSection })
//
// The headers are `row` children whose ROLE IS "button" -- that is the ARIA shape
// of an accordion header, and it is also the marker the widget uses to tell a
// header from a panel. No key parsing, no positional arithmetic, and a wrong role
// fails loudly (the reconciler rejects a null role at mount).
package asaot.ui
{
    import asaot.ui.style.StyleRefinement;

    public function accordion(sections:Array, opts:Object = null):Node
    {
        var n:AccordionNode = new AccordionNode();
        n.sections = sections == null ? [] : sections;
        OptionSupport.applyOpts(n, opts);
        if (n.ariaName == null || n.ariaName == "") n.ariaName = "accordion";
        if (opts != null)
        {
            if (opts.activeIndex is Binding)
            {
                n.binding = Binding(opts.activeIndex);
                // `*`, NOT `Object`: an `Object` slot would box the value once per read.
                // Number() never depended on the G9 fix (阶段二四八) and the G14 Array-identity
                // hazard (阶段二百五十三) is closed too, so `*` is now purely the cheaper default.
                var v:* = n.binding.get();
                n.activeIndex = v == null ? -1 : Number(v);
            }
            else if (opts.activeIndex != null) n.activeIndex = Number(opts.activeIndex);
            if (opts.onToggle != null) n.onToggle = (opts.onToggle as Function);
        }

        // One style object for every header of this pass: the resolver skips a style
        // it has already seen (pointer identity), so the shared pointer is not just
        // tidier -- it keeps steady frames out of the resolver.
        //
        // THE HEADER CARRIES NO BACKGROUND, deliberately: the open/closed fill is
        // painted by AccordionWidget into the container's shapeA, which sits BEHIND
        // the header children (this is the same model the table uses for its stripes).
        // A header background declared HERE would be painted by the header itself --
        // i.e. in front of the container's fill -- and the open highlight would be
        // invisible. Found by probes/widgets/data (2026-10-23): the open header
        // sampled #f3f4f6 instead of #dbeafe.
        var headRef:StyleRefinement = StyleRefinement.from({
            padding: [AccordionNode.HEADER_PAD_H, AccordionNode.HEADER_PAD_V],
            text: { color: AccordionNode.HEADER_TEXT, fontWeight: "bold" }
        });

        var kids:Array = [];
        var count:int = n.sections.length;
        for (var i:int = 0; i < count; i++)
        {
            var sec:Object = n.sections[i];
            var title:String = sec.title == null ? "" : String(sec.title);
            kids.push(row({ key: "h" + i, role: "button", ariaName: title, style: headRef },
                          [text(title, { key: "t" + i })]));

            // Only the OPEN panel is a child: a collapsed panel must not occupy
            // layout space (see AccordionNode's header note).
            if (i == n.activeIndex && sec.content != null)
            {
                var c:Node = Node(sec.content);
                // A panel whose index shifts around must not be re-mounted on every
                // open/close, so give it a section-scoped key unless the author set one.
                if (c.key == null) c.key = "p" + i;
                kids.push(c);
            }
        }

        OptionSupport.addChildren(n, kids);
        return n;
    }
}
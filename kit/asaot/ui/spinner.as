// asaot.ui.spinner -- the author-facing factory for SpinnerNode (see SpinnerNode.as
// for why the file is lowercase and the class is not).
//
//   spinner({ key: "s", diameter: 20, tone: "info" })
//   spinner({ key: "s", spin: false, phase: 0.25 })   // a still picture
//
// `size: [20, 20]` in the style wins over `diameter` when both are given: the
// style is the layout float and passes straight to the engine, while `diameter`
// only fills in the intrinsic size when the style leaves it auto.
package asaot.ui
{
    public function spinner(opts:Object = null):Node
    {
        var n:SpinnerNode = new SpinnerNode();
        OptionSupport.applyOpts(n, opts);
        if (n.ariaName == null || n.ariaName == "") n.ariaName = "loading";
        if (opts != null)
        {
            if (opts.diameter != null) n.diameter = Number(opts.diameter);
            if (opts.thickness != null) n.thickness = Number(opts.thickness);
            if (opts.tone != null) n.tone = String(opts.tone);
            if (opts.spin != null) n.spin = Boolean(opts.spin);
            if (opts.phase != null) n.phase = Number(opts.phase);
        }
        return n;
    }
}

// asaot.ui.icon -- the author-facing factory for IconNode.
//
//   icon("M4 12 H20", { size: [24, 24], color: 0x111827 })
//   icon("M12 2 L22 22 L2 22 Z", { fill: true, stroke: false, size: [32, 32] })
//
// The path data is a STRING in SVG's `d` syntax (see PathData for exactly which
// commands survive and which throw). It is validated by PARSING IT HERE, at describe
// time: an unsupported command then throws at the author's call site, on the frame
// they wrote it, instead of inside a paint pass where the stack says "draw".
//
// `viewBox` is the data's own coordinate space (icon sets use 24). Anything but a
// positive number throws -- the glyph would otherwise be scaled by zero or by NaN and
// vanish with no explanation.
package asaot.ui
{
    public function icon(path:String, opts:Object = null):Node
    {
        var n:IconNode = new IconNode();
        OptionSupport.applyOpts(n, opts);
        if (n.ariaName == null || n.ariaName == "") n.ariaName = "icon";
        if (path == null || path == "") throw new Error("asaot.ui.icon: needs path data (SVG 'd' syntax, e.g. \"M4 12 H20\")");
        n.path = path;
        if (opts != null)
        {
            if (opts.viewBox != null)
            {
                var vb:Number = Number(opts.viewBox);
                if (!(vb > 0)) throw new Error("asaot.ui.icon: viewBox must be a positive number, got " + opts.viewBox);
                n.viewBox = vb;
            }
            if (opts.color != null) n.color = Number(opts.color);
            if (opts.stroke != null) n.stroke = Boolean(opts.stroke);
            if (opts.fill != null) n.fill = Boolean(opts.fill);
            if (opts.strokeWidth != null)
            {
                var sw:Number = Number(opts.strokeWidth);
                if (!(sw > 0)) throw new Error("asaot.ui.icon: strokeWidth must be a positive number, got " + opts.strokeWidth);
                n.strokeWidth = sw;
            }
        }
        // Parse once, now, so bad data fails at the call site (the result is dropped:
        // the widget re-parses with the tolerance its render scale implies).
        PathData.parse(n.path, 0.25);
        return n;
    }
}
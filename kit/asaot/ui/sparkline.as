// asaot.ui.sparkline -- the author-facing factory for SparklineNode.
//
//   sparkline({ values: series, version: market.tick, style: { size: [104, 38] } })
//   sparkline({ values: closes, color: 0x16A34A, fill: true, baseline: prevClose })
//
// A sparkline is 5..60 numbers and a box; anything more (axes, a legend, a
// tooltip) is a chart, and a chart is an app's, not a primitive's.
//
// WHAT THROWS AND WHY. A non-array `values` is a programming error and throws at
// the call site, on the frame it was written (the same rule `icon` applies to path
// data). A series with fewer than two samples does NOT throw: a live widget's first
// frame legitimately has one sample, and the widget draws nothing until there is a
// line. `strokeWidth` must be positive -- a zero width is a line nobody can see,
// which is never what the author meant.
package asaot.ui
{
    public function sparkline(opts:Object = null):Node
    {
        var n:SparklineNode = new SparklineNode();
        OptionSupport.applyOpts(n, opts);
        if (n.ariaName == null || n.ariaName == "") n.ariaName = "sparkline";
        if (opts != null)
        {
            if (opts.values != null)
            {
                if (!(opts.values is Array))
                {
                    throw new Error("asaot.ui.sparkline: values must be an Array of numbers, got "
                        + opts.values);
                }
                n.values = opts.values as Array;
            }
            if (opts.version != null) n.version = int(opts.version);
            if (opts.color != null) n.color = Number(opts.color);
            if (opts.fill != null) n.fill = Boolean(opts.fill);
            if (opts.dot != null) n.dot = Boolean(opts.dot);
            if (opts.baseline != null) n.baseline = Number(opts.baseline);
            if (opts.strokeWidth != null)
            {
                var sw:Number = Number(opts.strokeWidth);
                if (!(sw > 0))
                {
                    throw new Error("asaot.ui.sparkline: strokeWidth must be positive, got "
                        + opts.strokeWidth);
                }
                n.strokeWidth = sw;
            }
        }
        return n;
    }
}
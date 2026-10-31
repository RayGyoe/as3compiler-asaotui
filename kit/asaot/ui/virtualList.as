// asaot.ui.virtualList -- the author-facing factory for VirtualListNode.
//
//   virtualList({
//       key: "log", size: [280, 200],   // the viewport (a number height also works)
//       rowHeight: 20,                  // REQUIRED: the window arithmetic is row-granular
//       count: 10000,                   // REQUIRED: how many rows exist in the model
//       offsetY: 0,                     // row-granular; snapped here
//       overscan: 1,                    // extra rows above/below (default 0)
//       renderRow: function (i:int):Node { return ...; },   // REQUIRED
//       onScroll: function (y:Number):void { ... },
//       onVisible: function (first:int, last:int):void { ... },
//       scrollToIndex: 120               // -1 (default) = no request
//   })
//
// WHAT THE AUTHOR MUST DO. `renderRow(i)` is called ONCE PER MOUNTED ROW, not once
// per item -- that is the entire point. `onScroll(y)` is called when the wheel or a
// key asks for a different window; the author writes `y` back into the model and
// re-renders. Nothing else changes: the factory recomputes the window, the
// reconciler unmounts the rows that left and mounts the ones that arrived (keys are
// `"<base>:r<i>"` and therefore stable).
//
// EVERY ROW IS EXACTLY `rowHeight` TALL. The factory pins BOTH `height` and
// `minSize.height` on each rendered row (through `withPatch`, so the author's own
// style survives).
//
// WHY BOTH, measured rather than assumed (both halves were wrong on the first try):
//   * `height` alone does NOT hold. The window is `fit + 1` rows, so nine 20px rows
//     overflow a 150px viewport by exactly one row and flexbox correctly shrinks all
//     nine to 16.67px each. The MIN is what pins them (the engine applies min/max
//     after the flex solve), so the overflowing row stays fully outside the clip
//     instead of squeezing everything visible.
//   * `flexShrink: 0` instead of the min looks equivalent and is not: a style carrying
//     only `flexShrink` reaches the engine as `setFlex(0, 0, 0, UNIT_UNDEFINED)` -- the
//     seam's encoding of "flex: 1 with a zero basis" -- and every row collapses to
//     ZERO height. This probe caught exactly that (`row vl:r0 is 0 tall`), and it is
//     the same trap ScrollViewWidget's header records from the other side.
package asaot.ui
{
    import asaot.ui.kind.VirtualListWidget;
    import asaot.ui.style.StyleRefinement;

    public function virtualList(opts:Object = null):Node
    {
        var n:VirtualListNode = new VirtualListNode();
        OptionSupport.applyOpts(n, opts);
        if (opts == null) opts = {};

        var rh:Number = opts.rowHeight == null ? 0 : Number(opts.rowHeight);
        if (!(rh > 0))
        {
            // LOUD, not a fallback. A vlist without a row height has no definition of
            // "which rows are visible", so quietly picking 20 would produce a list
            // that silently shows the wrong slice.
            throw new Error("asaot.ui.virtualList: `rowHeight` must be a positive number"
                + " (got " + rh + "). The window is row-granular -- there is nothing to"
                + " window without a row height.");
        }
        var count:int = opts.count == null ? 0 : int(opts.count);
        if (count < 0) count = 0;
        var render:Function = opts.renderRow as Function;
        if (render == null)
        {
            throw new Error("asaot.ui.virtualList: `renderRow` is required -- it is the"
                + " function that builds one mounted row (function(index:int):Node).");
        }

        n.count = count;
        n.rowHeight = rh;
        n.renderRow = render;
        // The plain guard every factory in this kit uses for an optional Function.
        // A `cond ? null : value` ternary was the compiler-gaps G16 shape: it lost
        // the Function value, which is how the first version of this factory handed
        // the widget a null `onScroll` and made the wheel do nothing (the probe
        // caught it: "onScroll reported -1"). G16 is FIXED (compiler stage 266) and
        // probes/g16-ternary-null keeps the AOT deviation set empty; the guard
        // stays because "optional Function" is what it says.
        if (opts.onScroll != null) n.onScroll = (opts.onScroll as Function);
        if (opts.onVisible != null) n.onVisible = (opts.onVisible as Function);
        if (opts.scrollToIndex != null) n.scrollToIndex = int(opts.scrollToIndex);
        if (opts.overscan != null) n.overscan = int(opts.overscan);
        if (n.overscan < 0) n.overscan = 0;
        if (n.ariaName == null || n.ariaName == "") n.ariaName = "list of " + count;

        // The viewport height decides how many rows exist. Prefer the style (so
        // `size: [w, h]` and `height: h` are both honoured), else the documented
        // default -- a viewport has no intrinsic size.
        var vh:Number = VirtualListWidget.viewportHeight(n.style);
        if (!(vh > 0)) vh = VirtualListWidget.DEFAULT_H;

        // Row-granular offset. `round` (not floor) is the honest snap: an offset of
        // 1.9 rows is nearer row 2 than row 1, and the author who animated a
        // fractional offset gets the nearest window instead of a half-row jitter.
        var off:Number = opts.offsetY == null ? 0 : Number(opts.offsetY);
        var first:int = Math.round(off / rh);
        var fit:int = int(Math.ceil(vh / rh));
        var maxFirst:int = count - fit;
        if (maxFirst < 0) maxFirst = 0;
        if (first > maxFirst) first = maxFirst;
        if (first < 0) first = 0;
        n.offsetY = first * rh;
        n.firstIndex = first;
        n.visibleCount = fit;

        // +1 because a viewport whose height is not a multiple of rowHeight shows a
        // PARTIAL last row, and that row is real. overscan adds more on both sides.
        var window:int = fit + 1 + n.overscan * 2;
        var last:int = first + window - 1;
        if (last > count - 1) last = count - 1;
        n.lastIndex = last;

        var base:String = n.key == null ? "vlist" : String(n.key);
        var patch:StyleRefinement = StyleRefinement.from({ height: rh, minSize: [null, rh] });
        for (var i:int = first; i <= last; i++)
        {
            var row:Node = render(i);
            if (row == null)
            {
                throw new Error("asaot.ui.virtualList: renderRow(" + i + ") returned null;"
                    + " every mounted row must be a Node.");
            }
            if (row.key == null) row.key = base + ":r" + i;
            row.style = (row.style == null ? new StyleRefinement() : row.style).withPatch(patch);
            n.addChild(row);
        }
        return n;
    }
}
// asaot.ui.IconNode -- one glyph, drawn from SVG path data.
//
// Copy of the ChipNode recipe: class `IconNode`, lowercase factory `icon.as`
// (compiler-gaps.md G7), `role` mandatory, self-registration once from the ctor.
//
// WHY PATH DATA AND NOT AN IMAGE. An icon is 5..40 line and curve segments in a
// 24x24 box; a bitmap of it would need one file per size per colour, would blur when
// the window's device ratio is 1.5 or 2, and would still be the wrong colour on a
// dark surface. Path data scales exactly and takes its colour from the node.
//
// WHY THE BOX IS SQUARE AND `viewBox` IS ONE NUMBER. Every public icon set (Feather,
// Lucide, Material, Bootstrap) is authored in a square viewBox; a non-square one is
// expressible as a padded square, and a second axis here would only add a way to get
// the aspect wrong. A non-square box (the author's `size: [48, 24]`) still works: the
// glyph is fitted into it like `scaleMode: "fit"` and centred.
//
// STROKE VS FILL
// --------------
//   stroke (default) -- the outline, `strokeWidth` in VIEWBOX units, so it scales with
//                       the glyph (that is what the source SVG means by stroke-width).
//   fill             -- the closed subpaths filled with the same colour.
// Both can be on; then the fill is drawn first and the stroke over it.
//
// The stroke really is the width you ask for: measured on this backend 2026-10-25
// with a 6px lineStyle -- straight, quadratic, `drawCircle` and `drawRect` all
// rasterise exactly 6 rows. (The kit's older "stroke width is not honoured" notes
// came from a build that predates this measurement; the icon probe pins the current
// behaviour.) Caps and joins are round, which is what Lucide/Feather author with.
//
// CURVES: see PathData. This class only carries the data; the conversion of cubics to
// the engine's quadratics (and the refusal of arcs) happens there.
//
// SIZING. With no explicit size the intrinsic box IS the viewBox (24 by default), which
// is the same "one unit = one pixel at 100%" convention the icon sets use.
package asaot.ui
{
    import asaot.ui.kind.IconWidget;

    public class IconNode extends Element
    {
        // SVG path data, in viewBox units. Parsed (and cached) by the widget.
        public var path:String;
        // The data's coordinate space. One number: the box is square (see the header).
        public var viewBox:Number;
        // NaN means "the resolved text colour", then 0x111827.
        public var color:Number;
        // Outline width in VIEWBOX units (scaled with the glyph), not device pixels.
        public var strokeWidth:Number;
        public var stroke:Boolean;
        public var fill:Boolean;

        private static var registered:Boolean = false;

        public function IconNode():void
        {
            super("icon");
            if (!registered) { registered = true; Widgets.register("icon", new IconWidget()); }
            this.role = "img";
            this.path = "";
            this.viewBox = 24;
            this.color = NaN;
            this.strokeWidth = 2;
            this.stroke = true;
            this.fill = false;
        }
    }
}
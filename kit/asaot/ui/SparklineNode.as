// asaot.ui.SparklineNode -- a tiny line chart of one series, drawn into its box.
//
// WHY A KIND AND NOT A `stream` OF `icon` CALLS. See SparklineWidget's header: an
// icon's box is square and its glyph is fitted, so a 104 x 38 price line cannot be
// drawn with one. This is the kit's first PAINT-WITH-DATA kind -- every other kind
// paints from tokens and the solved rect alone.
//
// THE SERIES IS THE AUTHOR'S ARRAY
// --------------------------------
// `values` is kept BY REFERENCE and compared by identity, so a steady frame costs
// one pointer test and the widget never copies the data. That means an author who
// MUTATES the array in place must say so:
//
//     values: series           // the same array object every render
//     version: market.tick     // ... and this number changes when it moved
//
// A fresh array every render needs no version (`values` itself differs). Neither
// form allocates in the widget; the choice is only about who does.
//
// VALUES ARE NOT VALIDATED PER ELEMENT. A NaN sample is SKIPPED by the range
// computation (a gap in the data must not blank the whole line) and x is still the
// sample's index, so the shape stays honest. Fewer than two samples draws nothing:
// there is no line to draw, and inventing one would be worse than an empty box.
package asaot.ui
{
    import asaot.ui.kind.SparklineWidget;

    public class SparklineNode extends Element
    {
        // The series, oldest first. Numbers; NaN samples are skipped.
        public var values:Array;
        // Changes when `values` was edited IN PLACE (see the header). Ignored when
        // a new array is passed every render.
        public var version:int;
        // The line colour. NaN routes through the resolved text colour, then the
        // palette's textStrong -- the same rule `icon` uses.
        public var color:Number;
        // Fill the area between the line and the box's bottom edge (13% alpha).
        public var fill:Boolean;
        // The polyline's width in points (scaled with nothing: it is a point size).
        public var strokeWidth:Number;
        // A dot on the newest sample: the "this is live" cue.
        public var dot:Boolean;
        // A faint horizontal rule at this value (the previous close, usually).
        // NaN is "no rule". It is also joined into the y range, so the rule and the
        // line cannot disagree about where "flat" is.
        public var baseline:Number;

        private static var registered:Boolean = false;

        public function SparklineNode():void
        {
            super("sparkline");
            if (!registered) { registered = true; Widgets.register("sparkline", new SparklineWidget()); }
            this.role = "img";
            this.values = [];
            this.version = 0;
            this.color = NaN;
            this.fill = false;
            this.strokeWidth = 1.5;
            this.dot = true;
            this.baseline = NaN;
        }
    }
}
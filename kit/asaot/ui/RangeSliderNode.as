// asaot.ui.RangeSliderNode -- one track, two thumbs, a low and a high value.
//
// WHY IT IS NOT `slider` WITH A SECOND VALUE: the pair has an invariant the single
// slider does not -- low <= high -- and every interaction has to preserve it (the
// low thumb cannot be dragged past the high one, and the arrow keys have to know
// which thumb they move). Folding that into SliderNode would mean every existing
// slider carries a field and a clamp it can never use.
//
// NO `binding`, DELIBERATELY. `Binding` holds ONE value; a range is two. The only
// two shapes that fit are a two-element Array (one allocation on every pointer move
// of a drag -- exactly the per-gesture allocation the steady-state rule forbids) or
// a pair of Bindings (two models, and no single place that owns the invariant). So
// the author owns the pair and receives it whole through `onRange(lo, hi)`.
//
// `step` applies to the KEYBOARD only. A drag is continuous by construction -- the
// pointer's x IS the value -- and snapping a drag would make the thumb lag the
// cursor, which reads as "broken" long before it reads as "snapped".
package asaot.ui
{
    import asaot.ui.kind.RangeSliderWidget;

    public class RangeSliderNode extends Control
    {
        public var label:String;
        public var value:Number;       // the LOW thumb, 0..1
        public var value2:Number;      // the HIGH thumb, 0..1
        public var step:Number;        // keyboard increment (drag is continuous)
        public var onRange:Function;   // function (lo:Number, hi:Number)

        private static var registered:Boolean = false;

        public function RangeSliderNode(label:String):void
        {
            super("rangeSlider");
            if (!registered) { registered = true; Widgets.register("rangeSlider", new RangeSliderWidget()); }
            this.role = "slider";
            this.tabEnabled = true;
            this.label = label;
            this.value = 0;
            this.value2 = 1;
            this.step = 0.05;
            this.onRange = null;
        }
    }
}
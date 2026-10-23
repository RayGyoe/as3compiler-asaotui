// asaot.ui.style.StyleRefinement -- the author-facing PARTIAL style.
//
// WHY A SUBCLASS
// --------------
// The merged value and the author-written override have different meanings but
// the same field set, so we reuse `Style`'s fields and only give the partial a
// name plus an object-literal constructor (`StyleRefinement.from({...})`, the
// exact shape used by the design doc sections 5 and 8). A subclass rather than
// an alias so a reader cannot confuse the two at a call site, and so a future
// change (e.g. adding a "was this field written?" bitmap) has somewhere to go.
//
// A style constant should be built ONCE, at class-load time
// (`static const PAGE:StyleRefinement = StyleRefinement.from({...})`), so that
// `render()` hands the same pointer every frame and the resolver's pointer
// identity test (section 2.4 layer 3) skips it entirely.
package asaot.ui.style
{
    public class StyleRefinement extends Style
    {
        public function StyleRefinement():void { super(); }

        public static function from(o:Object):StyleRefinement
        {
            var r:StyleRefinement = new StyleRefinement();
            if (o == null) return r;
            if (o.flexDirection != null) r.flexDirection = String(o.flexDirection);
            if (o.width != null) r.size = new Size(lenOf(o.width), r.size != null ? r.size.height : null);
            if (o.height != null) r.size = new Size(r.size != null ? r.size.width : null, lenOf(o.height));
            // Array-valued shorthands must NOT be handed to an Object-typed
            // parameter (see Size's header); branch on `is Array` here and cast to
            // a typed Array parameter instead.
            if (o.size != null) r.size = o.size is Array ? Size.fromArray(o.size as Array) : Size.fromAny(o.size);
            if (o.minSize != null) r.minSize = o.minSize is Array ? Size.fromArray(o.minSize as Array) : Size.fromAny(o.minSize);
            if (o.maxSize != null) r.maxSize = o.maxSize is Array ? Size.fromArray(o.maxSize as Array) : Size.fromAny(o.maxSize);
            if (o.flexGrow != null) r.flexGrow = Number(o.flexGrow);
            if (o.flexShrink != null) r.flexShrink = Number(o.flexShrink);
            if (o.flexBasis != null) r.flexBasis = lenOf(o.flexBasis);
            if (o.padding != null) r.padding = o.padding is Array ? Edges.fromArray(o.padding as Array) : Edges.fromAny(o.padding);
            if (o.borderWidths != null)
            {
                r.borderWidths = o.borderWidths is Array ? Edges.fromArray(o.borderWidths as Array) : Edges.fromAny(o.borderWidths);
            }
            if (o.border != null)
            {
                // Convenience: a uniform border width, matching `border: 1`.
                var bw:Edges = o.border is Array ? Edges.fromArray(o.border as Array) : Edges.fromAny(o.border);
                if (bw != null) r.borderWidths = bw;
            }
            if (o.gap != null)
            {
                if (o.gap is Array)
                {
                    var ga:Array = o.gap as Array;
                    if (ga.length > 0) r.gapX = Number(ga[0]);
                    if (ga.length > 1) r.gapY = Number(ga[1]);
                    else if (ga.length > 0) r.gapY = Number(ga[0]);
                }
                else
                {
                    r.gapX = Number(o.gap); r.gapY = Number(o.gap);
                }
            }
            if (o.boxSizing != null) r.boxSizing = String(o.boxSizing);
            if (o.justifyContent != null) r.justifyContent = String(o.justifyContent);
            if (o.alignItems != null) r.alignItems = String(o.alignItems);
            if (o.alignSelf != null) r.alignSelf = String(o.alignSelf);
            if (o.alignContent != null) r.alignContent = String(o.alignContent);
            if (o.flexWrap != null) r.flexWrap = String(o.flexWrap);
            // margin / inset are LengthEdges: scalar (Length / Number / "auto")
            // through fromAny, an Array through fromArray (see LengthEdges header).
            if (o.margin != null) r.margin = o.margin is Array ? LengthEdges.fromArray(o.margin as Array) : LengthEdges.fromAny(o.margin);
            if (o.inset != null) r.inset = o.inset is Array ? LengthEdges.fromArray(o.inset as Array) : LengthEdges.fromAny(o.inset);
            if (o.position != null) r.position = String(o.position);
            if (o.overflow != null) r.overflow = String(o.overflow);
            if (o.display != null) r.display = String(o.display);
            if (o.aspectRatio != null) r.aspectRatio = Number(o.aspectRatio);
            // An Array-valued `background` is a gradient stop list (deferred, see
            // Fill's header). It MUST be branched on HERE, while the value is still a
            // dynamic read: once it goes into Fill.fromAny's Object-typed parameter
            // the Array is not boxed, `is Array` there is folded to false, and
            // `is Fill` reads the array header as a vtable -> 0xC0000005 (G14,
            // probes/obj-array-identity/ case 26). Until 2026-10-23 this line
            // forwarded unconditionally -- the one shorthand in this method that
            // skipped the branch every other Array-valued field does.
            if (o.background != null)
            {
                r.background = o.background is Array
                    ? Fill.fromArray(o.background as Array)
                    : Fill.fromAny(o.background);
            }
            if (o.borderColor != null) r.borderColor = Number(o.borderColor);
            if (o.cornerRadii != null) r.cornerRadii = o.cornerRadii is Array ? Corners.fromArray(o.cornerRadii as Array) : Corners.fromAny(o.cornerRadii);
            if (o.opacity != null) r.opacity = Number(o.opacity);
            if (o.visibility != null) r.visibility = String(o.visibility);
            if (o.transitionMs != null) r.transitionMs = Number(o.transitionMs);
            if (o.transitionEase != null) r.transitionEase = String(o.transitionEase);
            if (o.text != null) r.text = TextStyle.fromAny(o.text);
            return r;
        }

        private static function lenOf(o:Object):Length
        {
            if (o == null) return null;
            if (o is Length) return Length(o);
            if (o is Number) return Length.px(Number(o));
            return null;
        }

        // Copy-on-write patch (design doc section 2.4 layer 4): if the patch is
        // the same pointer, hand back `this` so identity -- and therefore the
        // resolver's skip test -- is preserved.
        //
        // NAMED `withPatch`, NOT `with`: `with` is a reserved word in strict AS3
        // and mxmlc rejects it as a method name ("Syntax error: 'with' is not
        // allowed here").
        public function withPatch(patch:StyleRefinement):StyleRefinement
        {
            if (patch == null || patch === this) return this;
            var base:Style = new Style();
            this.refineInto(base, new Style());
            var out:StyleRefinement = new StyleRefinement();
            patch.refineInto(out, base);
            return out;
        }
    }
}

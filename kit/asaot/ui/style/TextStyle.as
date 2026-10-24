// asaot.ui.style.TextStyle -- the INHERITABLE typography subset.
//
// This is the only style group that cascades from parent to child (design doc
// section 2.3): fontFamily/fontSize/fontWeight/fontStyle/color/leading/
// letterSpacing/textAlign/whiteSpace/textOverflow. Everything else in `Style`
// (size, padding, flex, decoration) is NOT inherited -- making layout properties
// inherit would be the classic "looks right" flexbox trap the doc warns about.
//
// The unset sentinel is `NaN` for numbers and `null` for strings, so a partial
// refinement only overrides the components it actually sets.
//
// `leading` is a LINE HEIGHT in points (a DefiniteLength in GPUI's model,
// geometry.rs:3472); we keep it a Number here because text measurement goes
// through flash.text.TextField, whose TextFormat.leading is already points.
//
// NO PACKAGE-LEVEL `textStyle(...)` HELPER: mxmlc requires one externally-visible
// definition per file named after it, and `textStyle.as` cannot coexist with
// `TextStyle.as` on a case-insensitive filesystem. Use `TextStyle.fromAny(o)`.
package asaot.ui.style
{
    public class TextStyle
    {
        public var fontFamily:String;
        public var fontSize:Number;
        public var fontWeight:String;
        public var fontStyle:String;
        public var color:Number;
        public var leading:Number;
        public var letterSpacing:Number;
        public var textAlign:String;
        // "nowrap" (default) | "normal". `normal` wraps at the node's POINT width;
        // it is measured at measure time because the wrapped height is what drives
        // auto height (PaintKit.measureField's wrapW).
        public var whiteSpace:String;
        // "clip" (default) | "ellipsis". Ellipsis applies to a single unwrapped
        // line; see TextWidget for why a wrapped one is not truncated here.
        public var textOverflow:String;

        public function TextStyle():void
        {
            this.fontFamily = null;
            this.fontSize = NaN;
            this.fontWeight = null;
            this.fontStyle = null;
            this.color = NaN;
            this.leading = NaN;
            this.letterSpacing = NaN;
            this.textAlign = null;
            this.whiteSpace = null;
            this.textOverflow = null;
        }

        public static function fromAny(o:Object):TextStyle
        {
            if (o == null) return null;
            // Built-in check only; duck-type the fields below. `is TextStyle` would
            // be an `is <userClass>` on a possibly-not-yet-initialized class, which
            // our AOT can turn into a crash (asaotui/compiler-gaps.md). A TextStyle
            // argument reads identically to a plain object literal.
            if (!(o is Object)) return null;
            var t:TextStyle = new TextStyle();
            if (o.fontFamily != null) t.fontFamily = String(o.fontFamily);
            if (o.fontSize != null) t.fontSize = lenToPx(o.fontSize);
            if (o.fontWeight != null) t.fontWeight = String(o.fontWeight);
            if (o.fontStyle != null) t.fontStyle = String(o.fontStyle);
            if (o.color != null) t.color = Number(o.color);
            if (o.leading != null) t.leading = lenToPx(o.leading);
            if (o.letterSpacing != null) t.letterSpacing = Number(o.letterSpacing);
            if (o.textAlign != null) t.textAlign = String(o.textAlign);
            if (o.whiteSpace != null) t.whiteSpace = strEnum(String(o.whiteSpace), "whiteSpace", "nowrap, normal");
            if (o.textOverflow != null) t.textOverflow = strEnum(String(o.textOverflow), "textOverflow", "clip, ellipsis");
            return t;
        }

        // Unknown VALUES throw here rather than falling back to the default: a
        // silently ignored `whiteSpace: "warp"` is a layout that simply does not
        // happen, and nothing on screen says why (AGENTS.md 2.5).
        private static function strEnum(v:String, field:String, accepted:String):String
        {
            if (v == "nowrap" || v == "normal" || v == "clip" || v == "ellipsis") return v;
            throw new Error("asaot.ui: " + field + " \"" + v + "\" is not supported (accepted: " + accepted + ")");
        }

        // `fontSize: px(24)` or `fontSize: 24`; `leading: px(28)` or a Number.
        private static function lenToPx(o:Object):Number
        {
            if (o is Length) return Length(o).value;
            return Number(o);
        }

        public function mergeInto(out:TextStyle, parent:TextStyle):void
        {
            out.fontFamily = this.fontFamily != null ? this.fontFamily : parent.fontFamily;
            out.fontSize = isNaN(this.fontSize) ? parent.fontSize : this.fontSize;
            out.fontWeight = this.fontWeight != null ? this.fontWeight : parent.fontWeight;
            out.fontStyle = this.fontStyle != null ? this.fontStyle : parent.fontStyle;
            out.color = isNaN(this.color) ? parent.color : this.color;
            out.leading = isNaN(this.leading) ? parent.leading : this.leading;
            out.letterSpacing = isNaN(this.letterSpacing) ? parent.letterSpacing : this.letterSpacing;
            out.textAlign = this.textAlign != null ? this.textAlign : parent.textAlign;
            out.whiteSpace = this.whiteSpace != null ? this.whiteSpace : parent.whiteSpace;
            out.textOverflow = this.textOverflow != null ? this.textOverflow : parent.textOverflow;
        }

        // A node's inherited projection: copy the components that cascade.
        public function copyCoverInto(out:TextStyle):void
        {
            out.fontFamily = this.fontFamily;
            out.fontSize = this.fontSize;
            out.fontWeight = this.fontWeight;
            out.fontStyle = this.fontStyle;
            out.color = this.color;
            out.leading = this.leading;
            out.letterSpacing = this.letterSpacing;
            out.textAlign = this.textAlign;
            out.whiteSpace = this.whiteSpace;
            out.textOverflow = this.textOverflow;
        }
    }
}
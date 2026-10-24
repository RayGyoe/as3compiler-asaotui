// asaot.ui.style.Style -- the flat style value table (design doc section 2.1).
//
// WHAT IT IS
// ----------
// One flat record of style values, borrowed from GPUI's `Style`
// (asaotui/gpui-src/crates/gpui/src/style.rs:180-322, 38 public fields). We keep
// the layout / box / decoration / text grouping but expose only the fields this
// toolkit can actually drive through the layout seam -- a field we cannot honour
// would be a silent wrong-semantics trap, which AGENTS.md 2.4 forbids. The
// remaining unimplemented GPUI field (grid) is deliberately ABSENT, and the seam
// itself throws loudly if someone reaches for it (seam/README.md section 4).
//
// `cursor` IS exposed (2026-10-26) and is the one field here that is not painted:
// it is applied to `Mouse.cursor`, which is a PROCESS-WIDE value, so it is
// re-derived from the hover chain on every hover change (UiApp.applyCursor) and
// never stored per node on the display list.
//
// `boxShadow` IS exposed (2026-10-25): it is DRAWN, not deferred. The runtime
// really renders a DropShadowFilter (`as_render_filtered`, src/emit.ts), and a
// box shadow lands on the node's BACKGROUND SHAPE, never on the backing -- a
// filter on the backing would shadow the children too (a drop shadow on the
// label and the icons), which is not what a box shadow means.
//
// ALIGNMENT / MARGIN / INSET / WRAP / POSITION / OVERFLOW / DISPLAY / RATIO are
// now exposed: the pure-AS3 engine implements alignment, wrap, margin and inset,
// and the NATIVE engine (Yoga) additionally implements display + aspect-ratio.
// Every field below is either unset (leave the engine default alone) or maps 1:1
// onto a seam setter in UiNode.applyEngineStyle; an unknown STRING value THROWS
// there naming the field, the value and the accepted set -- never a silent
// fallback (AGENTS.md 2.5).
//
// UNSET SENTINELS (there is no Option<T> in AS3)
// ----------------------------------------------
//   Number -> NaN means unset;  String/null object -> null means unset.
//   `text` is never null: it is a TextStyle whose COMPONENTS carry the unset
//   sentinels, because typography is the one group that merges component-wise.
//
// ZERO-ALLOCATION STEADY STATE (design doc section 2.4)
// -----------------------------------------------------
// `refineInto(out, parent)` writes into a caller-owned buffer and returns void;
// the resolver writes straight into the UiNode's own `resolved` Style, so a
// re-resolve allocates nothing. `refine(parent)` (which DOES allocate) exists
// only for tests and for building static constants once at startup.
package asaot.ui.style
{
    public class Style
    {
        // ---- layout ------------------------------------------------------
        public var flexDirection:String;   // "row" | "column"
        public var size:Size;              // null unset
        public var minSize:Size;
        public var maxSize:Size;
        public var flexGrow:Number;        // NaN unset
        public var flexShrink:Number;
        public var flexBasis:Length;       // null unset
        public var padding:Edges;          // null unset
        public var borderWidths:Edges;
        public var gapX:Number;            // NaN unset
        public var gapY:Number;
        public var boxSizing:String;       // null = border-box (engine default)
        public var justifyContent:String;  // null unset
        public var alignItems:String;      // null unset
        public var alignSelf:String;       // null unset
        public var alignContent:String;    // null unset
        public var flexWrap:String;        // null unset
        public var margin:LengthEdges;     // null unset
        public var inset:LengthEdges;      // null unset
        public var position:String;        // null unset
        public var overflow:String;        // null unset
        public var display:String;         // null unset
        public var aspectRatio:Number;     // NaN unset; <= 0 also means unset

        // ---- box / decoration -------------------------------------------
        public var background:Fill;        // null unset
        public var borderColor:Number;     // NaN unset
        public var cornerRadii:Corners;
        // Array of BoxShadow (null unset). Drawn as the background shape's
        // `filters[]`; an absent list means "no filter at all", so the steady
        // state allocates nothing.
        public var boxShadow:Array;
        public var opacity:Number;
        public var visibility:String;      // "visible" | "hidden" (inheritable)
        // The OS POINTER SHAPE over this node (inheritable, like visibility).
        // null = unset: the runtime's own rule decides -- I-beam over selectable
        // text, a hand over a `buttonMode` object (src/emit.ts
        // ASC_window_update_cursor). "auto" is the EXPLICIT spelling of that same
        // rule, so a node can stop an inherited "hand" by asking for auto.
        public var cursor:String;

        // ---- animation (NOT a visual field; consumed by UiNode.applyAnim) ----
        // `transitionMs` is the duration of a change to an animatable field
        // (opacity / background / borderColor). NaN = UNSET: the value snaps, and
        // UiNode never even calls the animator, so the default is byte-for-byte
        // today's behaviour. `transitionEase` is a name from anim/Ease.as; null
        // means "linear". Neither field is in `diffFlags`: changing the duration
        // alone changes no pixels, so it must not dirty anything.
        public var transitionMs:Number;    // NaN = unset (snap)
        public var transitionEase:String;  // null = "linear"

        // ---- text (inheritable) -----------------------------------------
        public var text:TextStyle;

        public function Style():void
        {
            this.flexDirection = null;
            this.flexGrow = NaN;
            this.flexShrink = NaN;
            this.gapX = NaN;
            this.gapY = NaN;
            this.boxSizing = null;
            this.justifyContent = null;
            this.alignItems = null;
            this.alignSelf = null;
            this.alignContent = null;
            this.flexWrap = null;
            this.position = null;
            this.overflow = null;
            this.display = null;
            this.aspectRatio = NaN;
            this.borderColor = NaN;
            this.boxShadow = null;
            this.opacity = NaN;
            this.visibility = null;
            this.cursor = null;
            this.transitionMs = NaN;
            this.transitionEase = null;
            this.text = new TextStyle();
        }

        // Reset every field to "unset". Used on the reusable scratch Styles so a
        // previous resolve cannot leak a stale component into the next one -- a
        // scratch Style must start from a known-empty state, not from whatever
        // the last node happened to leave behind.
        public function clear():void
        {
            this.flexDirection = null;
            this.size = null; this.minSize = null; this.maxSize = null;
            this.flexGrow = NaN; this.flexShrink = NaN; this.flexBasis = null;
            this.padding = null; this.borderWidths = null;
            this.gapX = NaN; this.gapY = NaN; this.boxSizing = null;
            this.justifyContent = null; this.alignItems = null; this.alignSelf = null;
            this.alignContent = null; this.flexWrap = null;
            this.margin = null; this.inset = null;
            this.position = null; this.overflow = null; this.display = null;
            this.aspectRatio = NaN;
            this.background = null; this.borderColor = NaN;
            this.cornerRadii = null; this.boxShadow = null;
            this.opacity = NaN; this.visibility = null; this.cursor = null;
            this.transitionMs = NaN; this.transitionEase = null;
            this.text = new TextStyle();
        }

        // ------------------------------------------------------------------
        // Merging: `this` wins where it sets a field, else `parent` supplies it.
        // This is GPUI's `Refineable::refine` semantics
        // (asaotui/gpui-src/crates/refineable/src/refineable.rs): a Some/`set`
        // field replaces, an unset one keeps the parent's, and struct-valued
        // fields merge PER COMPONENT.
        // ------------------------------------------------------------------
        public function refineInto(out:Style, parent:Style):void
        {
            out.flexDirection = this.flexDirection != null ? this.flexDirection : parent.flexDirection;
            out.size = mergeSize(this.size, parent.size);
            out.minSize = mergeSize(this.minSize, parent.minSize);
            out.maxSize = mergeSize(this.maxSize, parent.maxSize);
            out.flexGrow = isNaN(this.flexGrow) ? parent.flexGrow : this.flexGrow;
            out.flexShrink = isNaN(this.flexShrink) ? parent.flexShrink : this.flexShrink;
            out.flexBasis = this.flexBasis != null ? this.flexBasis : parent.flexBasis;
            out.padding = mergeEdges(this.padding, parent.padding);
            out.borderWidths = mergeEdges(this.borderWidths, parent.borderWidths);
            out.gapX = isNaN(this.gapX) ? parent.gapX : this.gapX;
            out.gapY = isNaN(this.gapY) ? parent.gapY : this.gapY;
            out.boxSizing = this.boxSizing != null ? this.boxSizing : parent.boxSizing;
            out.justifyContent = this.justifyContent != null ? this.justifyContent : parent.justifyContent;
            out.alignItems = this.alignItems != null ? this.alignItems : parent.alignItems;
            out.alignSelf = this.alignSelf != null ? this.alignSelf : parent.alignSelf;
            out.alignContent = this.alignContent != null ? this.alignContent : parent.alignContent;
            out.flexWrap = this.flexWrap != null ? this.flexWrap : parent.flexWrap;
            out.margin = mergeLengthEdges(this.margin, parent.margin);
            out.inset = mergeLengthEdges(this.inset, parent.inset);
            out.position = this.position != null ? this.position : parent.position;
            out.overflow = this.overflow != null ? this.overflow : parent.overflow;
            out.display = this.display != null ? this.display : parent.display;
            out.aspectRatio = isNaN(this.aspectRatio) ? parent.aspectRatio : this.aspectRatio;
            out.background = this.background != null ? this.background : parent.background;
            out.borderColor = isNaN(this.borderColor) ? parent.borderColor : this.borderColor;
            out.cornerRadii = mergeCorners(this.cornerRadii, parent.cornerRadii);
            // An ARRAY is a whole value (a stack of shadows), not a component-wise
            // merge target: a refinement either sets the stack or leaves it.
            out.boxShadow = this.boxShadow != null ? this.boxShadow : parent.boxShadow;
            out.opacity = isNaN(this.opacity) ? parent.opacity : this.opacity;
            out.visibility = this.visibility != null ? this.visibility : parent.visibility;
            out.cursor = this.cursor != null ? this.cursor : parent.cursor;
            out.transitionMs = isNaN(this.transitionMs) ? parent.transitionMs : this.transitionMs;
            out.transitionEase = this.transitionEase != null ? this.transitionEase : parent.transitionEase;
            this.text.mergeInto(out.text, parent.text);
        }

        // Allocating convenience, used for static constants and tests only.
        public function refine(parent:Style):Style
        {
            var out:Style = new Style();
            this.refineInto(out, parent);
            return out;
        }

        // The inheritable projection: `text.*`, `visibility` and `cursor` cascade
        // (design doc section 2.3). `cursor` is inherited because the pointer
        // shape is a property of the REGION, not of the object that happens to be
        // the hit target: without the cascade, hovering a button's padding and its
        // label would show two different cursors.
        public function projectInherited(out:Style):void
        {
            this.text.copyCoverInto(out.text);
            out.visibility = this.visibility;
            out.cursor = this.cursor;
        }

        public function copyInto(out:Style):void
        {
            out.flexDirection = this.flexDirection;
            out.size = copySize(this.size, out.size);
            out.minSize = copySize(this.minSize, out.minSize);
            out.maxSize = copySize(this.maxSize, out.maxSize);
            out.flexGrow = this.flexGrow;
            out.flexShrink = this.flexShrink;
            out.flexBasis = this.flexBasis;
            out.padding = copyEdges(this.padding, out.padding);
            out.borderWidths = copyEdges(this.borderWidths, out.borderWidths);
            out.gapX = this.gapX;
            out.gapY = this.gapY;
            out.boxSizing = this.boxSizing;
            out.justifyContent = this.justifyContent;
            out.alignItems = this.alignItems;
            out.alignSelf = this.alignSelf;
            out.alignContent = this.alignContent;
            out.flexWrap = this.flexWrap;
            out.margin = copyLengthEdges(this.margin, out.margin);
            out.inset = copyLengthEdges(this.inset, out.inset);
            out.position = this.position;
            out.overflow = this.overflow;
            out.display = this.display;
            out.aspectRatio = this.aspectRatio;
            out.background = this.background;
            out.borderColor = this.borderColor;
            out.cornerRadii = copyCorners(this.cornerRadii, out.cornerRadii);
            out.boxShadow = this.boxShadow;
            out.opacity = this.opacity;
            out.visibility = this.visibility;
            out.cursor = this.cursor;
            out.transitionMs = this.transitionMs;
            out.transitionEase = this.transitionEase;
            this.text.copyCoverInto(out.text);
        }

        // ------------------------------------------------------------------
        // Dirty classification (design doc section 3.3). Returns flags:
        //   1 = layout  (needs measure + arrange)
        //   2 = text    (may need measure for auto-sizing controls + paint)
        //   4 = decor   (paint only -- a hover must never reflow)
        // ------------------------------------------------------------------
        public static function diffFlags(prev:Style, cur:Style):int
        {
            var f:int = 0;
            if (!strEq(prev.flexDirection, cur.flexDirection)
                || !sizeEq(prev.size, cur.size) || !sizeEq(prev.minSize, cur.minSize)
                || !sizeEq(prev.maxSize, cur.maxSize)
                || !numEq(prev.flexGrow, cur.flexGrow) || !numEq(prev.flexShrink, cur.flexShrink)
                || !lenEq(prev.flexBasis, cur.flexBasis)
                || !edgesEq(prev.padding, cur.padding) || !edgesEq(prev.borderWidths, cur.borderWidths)
                || !numEq(prev.gapX, cur.gapX) || !numEq(prev.gapY, cur.gapY)
                || !strEq(prev.boxSizing, cur.boxSizing)
                || !strEq(prev.justifyContent, cur.justifyContent)
                || !strEq(prev.alignItems, cur.alignItems)
                || !strEq(prev.alignSelf, cur.alignSelf)
                || !strEq(prev.alignContent, cur.alignContent)
                || !strEq(prev.flexWrap, cur.flexWrap)
                || !lengthEdgesEq(prev.margin, cur.margin)
                || !lengthEdgesEq(prev.inset, cur.inset)
                || !strEq(prev.position, cur.position)
                || !strEq(prev.overflow, cur.overflow)
                || !strEq(prev.display, cur.display)
                || !numEq(prev.aspectRatio, cur.aspectRatio))
            {
                f |= 1;
            }
            if (!textEq(prev.text, cur.text)) f |= 2 | 4;
            if (!fillEq(prev.background, cur.background) || !numEq(prev.borderColor, cur.borderColor)
                || !cornersEq(prev.cornerRadii, cur.cornerRadii) || !numEq(prev.opacity, cur.opacity)
                || !shadowsEq(prev.boxShadow, cur.boxShadow)
                || !strEq(prev.visibility, cur.visibility)
                // NOT layout and NOT text: only the OS pointer changes. It still
                // dirties the frame, because UiApp re-derives Mouse.cursor at the
                // END of a paint pass (the new value must reach the window on the
                // frame the style changed, not on the next mouse move).
                || !strEq(prev.cursor, cur.cursor))
            {
                f |= 4;
            }
            return f;
        }

        // ---- the accepted pointer shapes ---------------------------------
        // flash.ui.MouseCursor is the source of truth (it is exactly what the
        // runtime's `Mouse.cursor` understands, src/emit.ts
        // ASC_cursor_kind_of_name). The list lives here so StyleRefinement.from can
        // reject a typo AT DESCRIBE TIME: the same typo assigned later would be
        // rejected inside a mouse-move handler, where the frame guard swallows the
        // error and the only trace is a console line.
        public static function checkCursor(v:String):String
        {
            if (v == "auto" || v == "arrow" || v == "button" || v == "hand" || v == "ibeam") return v;
            throw new Error("asaot.ui: style.cursor \"" + v
                + "\" is not a MouseCursor name (accepted: auto, arrow, button, hand, ibeam)");
        }

        // ---- small merge / compare helpers --------------------------------

        private static function mergeSize(a:Size, b:Size):Size
        {
            if (a == null) return b;
            var w:Length = a.width != null ? a.width : (b != null ? b.width : null);
            var h:Length = a.height != null ? a.height : (b != null ? b.height : null);
            // A Size is shared read-only after this, so returning a fresh one is
            // a startup/resolve-time allocation only for authored refinements.
            return new Size(w, h);
        }

        private static function copySize(a:Size, out:Size):Size
        {
            if (a == null) return null;
            if (out == null) out = new Size(null, null);
            out.width = a.width; out.height = a.height;
            return out;
        }

        private static function mergeEdges(a:Edges, b:Edges):Edges
        {
            if (a == null) return b;
            var t:Number = !isNaN(a.top) ? a.top : (b != null ? b.top : NaN);
            var r:Number = !isNaN(a.right) ? a.right : (b != null ? b.right : NaN);
            var bo:Number = !isNaN(a.bottom) ? a.bottom : (b != null ? b.bottom : NaN);
            var l:Number = !isNaN(a.left) ? a.left : (b != null ? b.left : NaN);
            return new Edges(t, r, bo, l);
        }

        private static function copyEdges(a:Edges, out:Edges):Edges
        {
            if (a == null) return null;
            if (out == null) out = new Edges(NaN, NaN, NaN, NaN);
            a.copyInto(out);
            return out;
        }

        // LengthEdges merge PER COMPONENT exactly like mergeEdges, but a side is
        // unset when its Length is null (not NaN). `margin`/`inset` are the only
        // LengthEdges fields, and a percent/auto side must survive the merge.
        private static function mergeLengthEdges(a:LengthEdges, b:LengthEdges):LengthEdges
        {
            if (a == null) return b;
            var t:Length = a.top != null ? a.top : (b != null ? b.top : null);
            var r:Length = a.right != null ? a.right : (b != null ? b.right : null);
            var bo:Length = a.bottom != null ? a.bottom : (b != null ? b.bottom : null);
            var l:Length = a.left != null ? a.left : (b != null ? b.left : null);
            return new LengthEdges(t, r, bo, l);
        }

        private static function copyLengthEdges(a:LengthEdges, out:LengthEdges):LengthEdges
        {
            if (a == null) return null;
            if (out == null) out = new LengthEdges(null, null, null, null);
            a.copyInto(out);
            return out;
        }

        private static function lengthEdgesEq(a:LengthEdges, b:LengthEdges):Boolean
        {
            if (a == null && b == null) return true;
            if (a == null || b == null) return false;
            return a.equals(b);
        }

        private static function mergeCorners(a:Corners, b:Corners):Corners
        {
            if (a == null) return b;
            var tl:Number = !isNaN(a.topLeft) ? a.topLeft : (b != null ? b.topLeft : NaN);
            var tr:Number = !isNaN(a.topRight) ? a.topRight : (b != null ? b.topRight : NaN);
            var br:Number = !isNaN(a.bottomRight) ? a.bottomRight : (b != null ? b.bottomRight : NaN);
            var bl:Number = !isNaN(a.bottomLeft) ? a.bottomLeft : (b != null ? b.bottomLeft : NaN);
            return new Corners(tl, tr, br, bl);
        }

        private static function copyCorners(a:Corners, out:Corners):Corners
        {
            if (a == null) return null;
            if (out == null) out = new Corners(NaN, NaN, NaN, NaN);
            a.copyInto(out);
            return out;
        }

        private static function numEq(a:Number, b:Number):Boolean
        {
            if (isNaN(a) && isNaN(b)) return true;
            return a == b;
        }

        private static function strEq(a:String, b:String):Boolean
        {
            if (a == null && b == null) return true;
            if (a == null || b == null) return false;
            return a == b;
        }

        private static function sizeEq(a:Size, b:Size):Boolean
        {
            if (a == null && b == null) return true;
            if (a == null || b == null) return false;
            return lenEq(a.width, b.width) && lenEq(a.height, b.height);
        }

        private static function lenEq(a:Length, b:Length):Boolean
        {
            if (a == null && b == null) return true;
            if (a == null || b == null) return false;
            return a.unit == b.unit && a.value == b.value;
        }

        private static function edgesEq(a:Edges, b:Edges):Boolean
        {
            if (a == null && b == null) return true;
            if (a == null || b == null) return false;
            return numEq(a.top, b.top) && numEq(a.right, b.right)
                && numEq(a.bottom, b.bottom) && numEq(a.left, b.left);
        }

        private static function cornersEq(a:Corners, b:Corners):Boolean
        {
            if (a == null && b == null) return true;
            if (a == null || b == null) return false;
            return numEq(a.topLeft, b.topLeft) && numEq(a.topRight, b.topRight)
                && numEq(a.bottomRight, b.bottomRight) && numEq(a.bottomLeft, b.bottomLeft);
        }

        private static function textEq(a:TextStyle, b:TextStyle):Boolean
        {
            if (a == null && b == null) return true;
            if (a == null || b == null) return false;
            return strEq(a.fontFamily, b.fontFamily) && numEq(a.fontSize, b.fontSize)
                && strEq(a.fontWeight, b.fontWeight) && strEq(a.fontStyle, b.fontStyle)
                && numEq(a.color, b.color) && numEq(a.leading, b.leading)
                && numEq(a.letterSpacing, b.letterSpacing) && strEq(a.textAlign, b.textAlign)
                // These two change the measured size as well as the pixels, so they
                // ride the same flag textEq already contributes (2|4).
                && strEq(a.whiteSpace, b.whiteSpace) && strEq(a.textOverflow, b.textOverflow);
        }

        private static function fillEq(a:Fill, b:Fill):Boolean
        {
            if (a == null && b == null) return true;
            if (a == null || b == null) return false;
            return a.equals(b);
        }

        // Element-wise and BY VALUE: a freshly parsed boxShadow must compare equal
        // to last frame's, otherwise every describe pass would repaint and rebuild
        // the filter list forever.
        public static function shadowsEqual(a:Array, b:Array):Boolean { return shadowsEq(a, b); }

        private static function shadowsEq(a:Array, b:Array):Boolean
        {
            if (a == null && b == null) return true;
            if (a == null || b == null) return false;
            if (a.length != b.length) return false;
            for (var i:int = 0; i < a.length; i++)
            {
                if (!BoxShadow(a[i]).equals(BoxShadow(b[i]))) return false;
            }
            return true;
        }
    }
}

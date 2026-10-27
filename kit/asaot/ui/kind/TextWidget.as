// asaot.ui.kind.TextWidget -- a static text run: one line, or wrapped lines.
//
// Its intrinsic size is measured through a REAL TextField (see Widget.measure),
// and that field doubles as the on-screen display object -- we never draw a
// second text pipeline (design doc section 4.4).
//
// WRAP vs ELLIPSIS (2026-10-25) -- they are exclusive, and the reason is
// structural, not stylistic:
//   * `whiteSpace: "normal"` WRAPS at the node's point width. The wrapped height
//     is what an auto-height text node must publish, so wrapping is a MEASURE-time
//     decision (PaintKit.measureField's wrapW). A percent width cannot work here:
//     the height would depend on a width the solver has not produced yet, so it
//     THROWS instead of guessing. (GPUI does this through `text_wrap` + a definite
//     width, geometry.rs; same constraint, same failure mode.)
//   * `textOverflow: "ellipsis"` TRUNCATES one unwrapped line to the final box
//     width. That width is only known at ARRANGE time, so this is a PAINT-time
//     decision -- hence the two cannot share a node. A wrapped node ignores
//     ellipsis rather than collapsing back to one line.
package asaot.ui.kind
{
    import asaot.ui.PaintKit;
    import asaot.ui.TextNode;
    import asaot.ui.UiNode;
    import asaot.ui.Widget;
    import asaot.ui.Node;
    import asaot.ui.style.Length;
    import asaot.ui.style.Style;

    import asaot.ui.LayoutConstants;

    import flash.display.Shape;

    public class TextWidget implements Widget
    {
        // Every other kind owns a Shape at child index 0 for the PAINT fields
        // (background / borderColor / cornerRadii / boxShadow / opacity) and draws it
        // through PaintKit.paintBox. Text did not: `paintBox` bails on a null shapeA, so
        // `background` on a text node was ACCEPTED and silently painted nothing -- found
        // by the docs audit, where three 300px tinted alignment lines came out untinted.
        // The shape goes in FIRST so the field draws on top of the tint.
        public function build(n:UiNode):void
        {
            n.shapeA = new Shape();
            n.backing.addChild(n.shapeA);
            n.tf = PaintKit.makeText(false);
            n.backing.addChild(n.tf);
        }

        public function payload(n:UiNode, desc:Node):Boolean
        {
            var tc:String = TextNode(desc).content;
            if (tc != n.textContent)
            {
                n.textContent = tc;
                return true;   // intrinsic width may change
            }
            return false;
        }

        public function wantsPress():Boolean { return false; }

        // The content width to wrap at, or NaN for "one line". Throws when the
        // author asked for wrapping without giving a width the measure pass can
        // use -- see the header.
        private function wrapWidth(n:UiNode, s:Style):Number
        {
            if (s.text.whiteSpace != "normal") return NaN;
            var w:Length = (s.size != null) ? s.size.width : null;
            if (w == null || w.isAuto() || w.unit != Length.UNIT_POINT)
            {
                throw new Error("asaot.ui: text whiteSpace \"normal\" needs a point width on the "
                    + "text node (got " + (w == null || w.isAuto() ? "auto" : "a percent length") + ")");
            }
            var contentW:Number = w.value - PaintKit.padH(s.padding) - PaintKit.borderH(s.borderWidths);
            if (contentW <= 0)
            {
                throw new Error("asaot.ui: text whiteSpace \"normal\" resolved to a non-positive "
                    + "content width (" + contentW + "px)");
            }
            return contentW;
        }

        public function measure(n:UiNode):void
        {
            if (n.tf == null) return;
            var s:Style = n.resolved;
            var wrapW:Number = wrapWidth(n, s);
            PaintKit.measureField(n, n.tf, n.textContent, s, wrapW);
            // The intrinsic size is the CONTENT size, so the box's own padding and
            // border have to be added on top: the engine's boxSizing defaults to
            // border-box, i.e. a point size is the WHOLE box. Publishing the bare
            // text width would leave the padding eating into the text -- a 4px
            // glyph with 4px padding got an 8px box and its run overflowed into
            // the next node (seen with the breadcrumb separator). Badge/Button/
            // Card/Chip already add the insets here; this one did not.
            if (PaintKit.autoW(s))
            {
                PaintKit.setPointSize(n, LayoutConstants.AXIS_WIDTH,
                    n.state.measuredW + PaintKit.padH(s.padding) + PaintKit.borderH(s.borderWidths));
            }
            if (PaintKit.autoH(s))
            {
                PaintKit.setPointSize(n, LayoutConstants.AXIS_HEIGHT,
                    n.state.measuredH + PaintKit.padV(s.padding) + PaintKit.borderV(s.borderWidths));
            }
        }

        public function arrange(n:UiNode):void
        {
            if (n.tf == null) return;
            // textWidth/textHeight describe the paragraph, whose paint origin is
            // (2, 2) inside the field. Align the paragraph to the content box,
            // not the field's outer rectangle (notably in flex-centred rows).
            n.tf.x = PaintKit.insetX(n) - PaintKit.TEXT_GUTTER;
            n.tf.y = PaintKit.insetY(n) - PaintKit.TEXT_GUTTER;
        }

        public function paint(n:UiNode):void
        {
            var s:Style = n.resolved;
            // The field was configured during measure (it had to be, to get an
            // intrinsic size); update the format for a decor-only change.
            if (n.tf != null && s.text.color >= 0) n.tf.textColor = uint(s.text.color);
            // Ellipsis, if asked for and if the final box is narrower than the run.
            // A WRAPPED node is skipped: truncating it would collapse the lines the
            // measure pass just laid out.
            if (n.tf != null && s.text.whiteSpace != "normal" && s.text.textOverflow == "ellipsis")
            {
                var contentW:Number = PaintKit.w1(n) - PaintKit.padH(s.padding) - PaintKit.borderH(s.borderWidths);
                if (contentW > 0 && n.tf.textWidth > contentW)
                {
                    PaintKit.ellipsize(n.tf, n.textContent, contentW);
                }
            }
            PaintKit.paintBox(n, s, PaintKit.w1(n), PaintKit.h1(n));
            PaintKit.decorate(n);
        }

        public function click(n:UiNode):Boolean { return false; }
    }
}
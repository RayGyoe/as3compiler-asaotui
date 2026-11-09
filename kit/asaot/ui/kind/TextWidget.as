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
    import asaot.ui.Dirty;
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
                // SUBTREE-LEVEL MEASURE (borrow gpui fast/dependencies.rs: a
                // text node's measure input is its own content+font+wrap, and
                // the intrinsic size is ONLY fed to the engine when the node is
                // auto-sized or wraps). A fixed-size, single-line run whose
                // content changed does NOT change its intrinsic size, so it must
                // not markLayoutDirty() and drag the whole tree through
                // measurePass + engine.calculate + arrangePass every tick. It is
                // a paint-only change: the field text is re-synced (and the run
                // re-aligned) inside paint(), and only this node repaints.
                if (isFixedSize(n.resolved))
                {
                    n.dirty |= Dirty.M_PAINT;
                    return false;
                }
                return true;   // auto-sized / wrapped: intrinsic size may change
            }
            return false;
        }

        // A run whose intrinsic size cannot feed the engine: neither axis is
        // auto, and it does not wrap (a wrapped height is what an auto-height
        // node publishes). Its content is display-only.
        private function isFixedSize(s:Style):Boolean
        {
            return s.text.whiteSpace != "normal"
                && !PaintKit.autoW(s)
                && !PaintKit.autoH(s);
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
            placeRun(n, n.resolved);
        }

        // Position the field's run at the content box and honour center/right
        // alignment. Shared by arrange (the full-solve path) and paint (the
        // fixed-size paint-only path), so the two can never drift.
        //
        // textWidth/textHeight describe the paragraph, whose paint origin is
        // (2, 2) inside the field. Align the paragraph to the content box,
        // not the field's outer rectangle (notably in flex-centred rows).
        //
        // `textAlign` ON A RUN THAT DOES NOT WRAP. The field is autoSize "left",
        // i.e. exactly as wide as the run, so the field's own alignment has no
        // slack to move within and silently does nothing -- measured: a 160pt
        // right-aligned node holding "12.34" painted at x 5..30, and a tab label
        // centred in a 106.67pt cell painted at 1..26 (cell centre 53.3). Only a
        // WRAPPED node ever had a field wider than its run (field.width = wrapW),
        // which is how `textAlign` stayed "working" in the one case the docs
        // demonstrated. Move the RUN inside the content box instead, the same way
        // PaintKit.centerText places a widget's own field: no re-shape, no second
        // text pipeline, and nothing changes for "left" (or for a run wider than
        // its box, which still overflows to the right as before).
        private function placeRun(n:UiNode, s:Style):void
        {
            n.tf.x = PaintKit.insetX(n) - PaintKit.TEXT_GUTTER;
            n.tf.y = PaintKit.insetY(n) - PaintKit.TEXT_GUTTER;
            var al:String = s.text.textAlign;
            if (s.text.whiteSpace != "normal" && (al == "center" || al == "right"))
            {
                var contentW:Number = PaintKit.w1(n) - PaintKit.padH(s.padding)
                    - PaintKit.borderH(s.borderWidths);
                var slack:Number = contentW - n.tf.textWidth;
                if (slack > 0.5) n.tf.x = n.tf.x + (al == "center" ? slack / 2 : slack);
            }
        }

        public function paint(n:UiNode):void
        {
            var s:Style = n.resolved;
            // PAINT-ONLY CONTENT SYNC. A fixed-size run skips the measure pass
            // (payload returns false and raises only M_PAINT), so the field still
            // holds the PREVIOUS content here. Re-shape it now, then re-align:
            // this is the one place a fixed-size text's changed content reaches
            // the display object, and it does not touch the engine. A wrapped or
            // auto-sized run never reaches this branch (its payload returned true
            // and the measure pass already re-shaped it), so `textContent` equals
            // `tf.text` and this is a single cheap string compare per paint.
            if (n.tf != null)
            {
                var want:String = n.textContent == null ? "" : n.textContent;
                if (n.tf.text != want)
                {
                    PaintKit.measureField(n, n.tf, n.textContent, s, NaN);
                    placeRun(n, s);
                }
            }
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
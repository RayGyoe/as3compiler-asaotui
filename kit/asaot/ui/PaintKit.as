// asaot.ui.PaintKit -- the drawing / text-measuring helpers shared by every
// widget kind.
//
// Lifted verbatim out of `UiNode`'s private methods when the per-kind `if`
// chains became the `Widget` seam. They are stateless functions over
// (Style, Shape, TextField), so they belong to no widget in particular:
//
//   * box drawing   -- background fill + border in ONE Graphics pass, so a
//                      rounded rect has both without the border being clipped
//                      (the 2026-10-22 "only a border, no fill" false alarm was
//                      chased through this code; see
//                      reviews/probe-demo-fill-2026-10-22.md)
//   * text formatting / intrinsic measurement -- `Style.text` -> TextFormat
//   * edge arithmetic -- padding/border sums and NaN-tolerant `nz`
//   * solved-rect arithmetic -- the content box inside border+padding
//
// Everything here is allocation-free except `formatFor`, which must build a
// TextFormat (there is no way to mutate one in place).
package asaot.ui
{
    import asaot.ui.style.Style;
    import asaot.ui.style.Edges;
    import asaot.ui.style.TextStyle;

    import asaot.ui.LayoutConstants;

    import flash.display.Shape;
    import flash.text.TextField;
    import flash.text.TextFormat;

    public class PaintKit
    {
        // ---- NaN-tolerant accessors --------------------------------------
        public static function nz(v:Number):Number { return isNaN(v) ? 0 : v; }

        public static function padV(e:Edges):Number { return e == null ? 0 : nz(e.top) + nz(e.bottom); }
        public static function padH(e:Edges):Number { return e == null ? 0 : nz(e.left) + nz(e.right); }
        public static function borderV(e:Edges):Number { return e == null ? 0 : nz(e.top) + nz(e.bottom); }
        public static function borderH(e:Edges):Number { return e == null ? 0 : nz(e.left) + nz(e.right); }

        // ---- intrinsic-size flags ----------------------------------------
        public static function autoW(s:Style):Boolean
        {
            return s.size == null || s.size.width == null || s.size.width.isAuto();
        }

        public static function autoH(s:Style):Boolean
        {
            return s.size == null || s.size.height == null || s.size.height.isAuto();
        }

        // A zero-sized backing would make Graphics draw nothing at all; the 1px
        // floor keeps a stroke visible on a not-yet-measured node (unchanged from
        // the pre-Widget-seam UiNode.w1()/h1()).
        public static function w1(n:UiNode):Number { return n.absW > 0 ? n.absW : 1; }
        public static function h1(n:UiNode):Number { return n.absH > 0 ? n.absH : 1; }

        // ---- solved-rect arithmetic --------------------------------------
        public static function insetX(n:UiNode):Number
        {
            var s:Style = n.resolved;
            return nz(s.borderWidths != null ? s.borderWidths.left : NaN)
                + nz(s.padding != null ? s.padding.left : NaN);
        }

        public static function insetY(n:UiNode):Number
        {
            var s:Style = n.resolved;
            return nz(s.borderWidths != null ? s.borderWidths.top : NaN)
                + nz(s.padding != null ? s.padding.top : NaN);
        }

        public static function contentW(n:UiNode):Number
        {
            var s:Style = n.resolved;
            var w:Number = n.absW - borderH(s.borderWidths) - padH(s.padding);
            return w > 0 ? w : 1;
        }

        public static function contentH(n:UiNode):Number
        {
            var s:Style = n.resolved;
            var h:Number = n.absH - borderV(s.borderWidths) - padV(s.padding);
            return h > 0 ? h : 1;
        }

        // ---- engine writes -------------------------------------------------
        // A measurement is always an explicit point size: the pure-AS3 engine has
        // no measure callback (seam/README.md section 4), so intrinsic sizing is
        // "text field first, then solve the tree with that as a fixed size".
        public static function setPointSize(n:UiNode, axis:int, v:Number):void
        {
            n.app.engine.setSize(n.engineNode, axis, v, LayoutConstants.UNIT_POINT);
        }

        // ---- text ----------------------------------------------------------
        public static function makeText(editable:Boolean):TextField
        {
            var t:TextField = new TextField();
            t.selectable = editable;
            t.mouseEnabled = editable;
            t.autoSize = "left";
            t.multiline = false;
            t.wordWrap = false;
            return t;
        }

        public static function formatFor(s:Style):TextFormat
        {
            var t:TextStyle = s.text;
            var f:TextFormat = new TextFormat();
            f.font = t.fontFamily != null ? t.fontFamily : "Arial";
            f.size = isNaN(t.fontSize) ? 14 : t.fontSize;
            f.color = isNaN(t.color) ? uint(0x000000) : uint(t.color);
            f.bold = t.fontWeight == "bold";
            f.italic = t.fontStyle == "italic";
            if (!isNaN(t.leading)) f.leading = t.leading;
            if (!isNaN(t.letterSpacing)) f.letterSpacing = t.letterSpacing;
            if (t.textAlign != null) f.align = t.textAlign;
            return f;
        }

        // Writes n.state.measuredW/H (the intrinsic size of `content`).
        public static function measureField(n:UiNode, field:TextField, content:String, s:Style):void
        {
            var f:TextFormat = formatFor(s);
            field.defaultTextFormat = f;
            field.autoSize = "left";
            field.multiline = false;
            field.wordWrap = false;
            field.text = content == null ? "" : content;
            field.setTextFormat(f);
            n.state.measuredW = field.textWidth;
            n.state.measuredH = field.textHeight;
            n.state.measureValid = 3;
        }

        // ---- box drawing ----------------------------------------------------
        // One Graphics pass: beginFill (if any) then lineStyle (if any), then a
        // single drawRoundRect/drawRect, then endFill. The fill MUST NOT be
        // committed before the stroke is set up, otherwise the stroke would sit
        // outside the shape's own path.
        public static function drawBox(sh:Shape, s:Style, w:Number, h:Number):void
        {
            var g:Object = sh.graphics;
            g.clear();
            var hasBg:Boolean = s.background != null;
            if (hasBg)
            {
                g.beginFill(s.background.rgb(), s.background.alpha());
            }
            var hasBorder:Boolean = s.borderWidths != null && !isNaN(s.borderColor);
            if (hasBorder)
            {
                g.lineStyle(nz(s.borderWidths.top), uint(s.borderColor) & 0xFFFFFF, 1.0);
            }
            if (hasBg || hasBorder)
            {
                var r:Number = 0;
                if (s.cornerRadii != null) r = nz(s.cornerRadii.topLeft);
                if (r > 0) g.drawRoundRect(0, 0, w, h, r * 2, r * 2);
                else g.drawRect(0, 0, w, h);
            }
            if (hasBg) g.endFill();
        }

        // Null-safe wrapper: many widgets have no background shape at all.
        public static function paintBox(n:UiNode, s:Style, w:Number, h:Number):void
        {
            if (n.shapeA != null) drawBox(n.shapeA, s, w, h);
        }
    }
}
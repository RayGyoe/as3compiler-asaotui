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
        // ---- interaction state -> pixels ----------------------------------
        //
        // THE STATE IS DERIVED, NOT AUTHORED. `ElementState` already carried
        // hover/pressed/focused/disabled as ints (it was written for exactly this)
        // and `UiNode` has been flipping hover/pressed since the first widget --
        // but nothing ever READ them, so a hovered button looked identical to an
        // idle one. Three numbers below turn that state into pixels with no new
        // style field:
        //
        //   hover   -- lift the surface toward white by HOVER_LIFT percent
        //   pressed -- sink it toward black by PRESS_SINK percent
        //   focused -- a 2px accent ring, DRAWN AS FOUR FILLED RECTS (not a
        //              lineStyle stroke: stroke width is not honoured on this
        //              backend -- see OverlayChrome's header), so the ring is
        //              integer-exact and a probe can assert a single pixel
        //   disabled-- the whole backing's alpha is scaled by DISABLED_ALPHA in
        //              UiNode (NOT here): dimming at the draw call would leave the
        //              label, an image and a chip at full strength, and it would
        //              multiply twice on a node that already dims itself
        //
        // IDLE MUST BE BYTE-IDENTICAL TO BEFORE. Every branch below is a no-op at
        // (0,0,0,0), which is what keeps the six gallery screenshots and every
        // widget probe baseline valid while adding the whole feature.
        public static const HOVER_LIFT:int = 8;      // percent toward white
        public static const PRESS_SINK:int = 12;     // percent toward black
        public static const DISABLED_ALPHA:Number = 0.45;
        public static const FOCUS_RING:uint = 0x2563EB;
        public static const FOCUS_RING_W:Number = 2;

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

        // ---- the state-aware box ------------------------------------------
        // ONE function carries hover / pressed / focused into every widget that
        // draws through paintBox -- 20+ kinds get the feedback with no widget-file
        // change (the same interception idea as `Anim` on `resolved`, one layer
        // down: here the interception is on the DRAW, because a hover must never
        // re-solve a style).
        public static function drawBoxFor(n:UiNode, sh:Shape, s:Style, w:Number, h:Number):void
        {
            var g:Object = sh.graphics;
            g.clear();
            // A HOVER MEANS "THIS SURFACE REACTS TO THE POINTER", so it is derived
            // only for an INTERACTIVE node. `state.hover` is set on every backing (the
            // MOUSE_OVER listener is wired in UiNode.createBacking for all kinds), and
            // honouring it everywhere turned every layout container into a :hover div
            // -- a plain `box` or the page root would lighten 8% whenever the pointer
            // crossed it. "Interactive" is the two things the library itself uses to
            // mean it: a focused-able control (tabEnabled) or a node some widget
            // handed a click handler to (chips, cards).
            var live:Boolean = (n.tabEnabled || n.onClick != null) && n.state.disabled == 0;
            var hoveredLift:int = (live && n.state.hover != 0) ? HOVER_LIFT : 0;
            var pressedSink:int = (live && n.state.pressed != 0) ? PRESS_SINK : 0;

            var hasBg:Boolean = s.background != null;
            if (hasBg)
            {
                var bg:uint = s.background.rgb();
                if (pressedSink > 0) bg = mixRGB(bg, 0x000000, pressedSink);
                else if (hoveredLift > 0) bg = mixRGB(bg, 0xFFFFFF, hoveredLift);
                g.beginFill(bg, s.background.alpha());
            }
            var hasBorder:Boolean = s.borderWidths != null && !isNaN(s.borderColor);
            if (hasBorder)
            {
                var bc:uint = uint(s.borderColor) & 0xFFFFFF;
                if (pressedSink > 0) bc = mixRGB(bc, 0x000000, pressedSink);
                else if (hoveredLift > 0) bc = mixRGB(bc, 0xFFFFFF, hoveredLift);
                g.lineStyle(nz(s.borderWidths.top), bc, 1.0);
            }
            if (hasBg || hasBorder)
            {
                var r:Number = 0;
                if (s.cornerRadii != null) r = nz(s.cornerRadii.topLeft);
                if (r > 0) g.drawRoundRect(0, 0, w, h, r * 2, r * 2);
                else g.drawRect(0, 0, w, h);
            }
            if (hasBg) g.endFill();

            if (n.state.focused != 0 && n.tabEnabled && n.state.disabled == 0
                && w >= FOCUS_RING_W * 4 && h >= FOCUS_RING_W * 4)
            {
                // Four filled bars, NOT a stroke: the ring then lands on integer
                // pixels (probe: (x+1,y) is exactly FOCUS_RING for any w,h).
                var t:Number = FOCUS_RING_W;
                g.beginFill(FOCUS_RING, 1.0);
                g.drawRect(0, 0, w, t);
                g.drawRect(0, h - t, w, t);
                g.drawRect(0, t, t, h - t - t);
                g.drawRect(w - t, t, t, h - t - t);
                g.endFill();
            }
        }

        // Percent blend of two packed RGB colours. Integer arithmetic with an
        // explicit round, so the result is a number a probe can predict exactly:
        // mixRGB(0xF3F4F6, white, 8) == 0xF4F5F7.
        public static function mixRGB(c:uint, target:uint, pct:int):uint
        {
            var r:int = int(uint(c >> 16) & 0xFF);
            var g:int = int(uint(c >> 8) & 0xFF);
            var b:int = int(uint(c) & 0xFF);
            var tr:int = int(uint(target >> 16) & 0xFF);
            var tg:int = int(uint(target >> 8) & 0xFF);
            var tb:int = int(uint(target) & 0xFF);
            r = r + Math.round((tr - r) * pct / 100);
            g = g + Math.round((tg - g) * pct / 100);
            b = b + Math.round((tb - b) * pct / 100);
            if (r < 0) r = 0; if (r > 255) r = 255;
            if (g < 0) g = 0; if (g > 255) g = 255;
            if (b < 0) b = 0; if (b > 255) b = 255;
            return uint((r << 16) | (g << 8) | b);
        }

        // The state colour for a widget that draws its own surface (chip, slider,
        // progress). Same rule as drawBoxFor, exposed so those kinds do not
        // re-derive it and drift. Same interactivity gate, same idle guarantee.
        public static function stateColor(n:UiNode, c:uint):uint
        {
            if (n.state.disabled != 0) return c;
            if (n.tabEnabled == false && n.onClick == null) return c;
            if (n.state.pressed != 0) return mixRGB(c, 0x000000, PRESS_SINK);
            if (n.state.hover != 0) return mixRGB(c, 0xFFFFFF, HOVER_LIFT);
            return c;
        }

        // Null-safe wrappers: many widgets have no background shape at all.
        public static function paintBox(n:UiNode, s:Style, w:Number, h:Number):void
        {
            if (n.shapeA != null) drawBoxFor(n, n.shapeA, s, w, h);
        }
    }
}
// demo/DocsStyle.as -- the docs app's own palette and metrics, in ONE place.
//
// WHY A SEPARATE FILE: the tour hand-computes rects from these numbers, and the
// section heights are arithmetic over them (see DocsView.blockHeight). If a
// metric lived next to the widget that used it, that arithmetic would silently
// drift from what the engine lays out -- which is exactly what the tour's
// "no text overflows its block" sweep catches.
package demo
{
    import asaot.ui.style.Length;
    import asaot.ui.style.StyleRefinement;

    public final class DocsStyle
    {
        // ---- window / chrome ------------------------------------------------
        public static const W:Number = 1000;
        public static const H:Number = 700;
        public static const NAV_W:Number = 248;
        public static const PAD_X:Number = 32;      // main column's left/right padding
        public static const HEAD_Y:Number = 24;

        // ---- nav list metrics ----------------------------------------------
        public static const NAV_H_ITEM:Number = 26;
        public static const NAV_H_GROUP:Number = 30;

        // ---- section metrics ------------------------------------------------
        public static const SEC_HEAD_H:Number = 22;      // the section's own heading
        public static const SEC_PROSE_H:Number = 17;     // one prose line
        public static const SEC_DEMO_H:Number = 76;      // default live-demo height
        public static const CODE_LINE_H:Number = 14;     // one monospace line
        public static const CODE_PAD_H:Number = 10;      // code box: 10 top + 10 bottom
        public static const SEC_GAP:Number = 18;         // between two sections
        // The FLOOR of the content column: a page whose blocks are shorter than
        // this still gets a column this tall, so a one-section page does not report
        // a zero-height content box. It is NOT the viewport's height -- the viewport
        // is whatever the window leaves the pane (see DOC_SCROLL), and the tour
        // reads `maxOffsetY` from the solved rect rather than assuming a number.
        public static const DOC_VIEW_H:Number = 580;
        // Inside a section: heading -> prose/demo -> code. These are the numbers
        // the block arithmetic adds up (gapY of the section's own column).
        public static const SEC_INNER_GAP:Number = 8;
        public static const SEC_PROSE_GAP:Number = 4;

        // ---- chrome styles --------------------------------------------------
        // The root is FLUID: the window's own size is the layout's size, so
        // resizing the window resizes both panes (and the two scroll viewports,
        // which take the height their column has left). Nothing here is pinned to
        // 1000x700 -- those numbers are only what the descriptor asks for, and the
        // tour derives every rect from the stage it actually got.
        public static const ROOT:StyleRefinement = StyleRefinement.from({
            flexDirection: "row", size: [Length.pct(1), Length.pct(1)], background: 0xFFFFFF
        });
        public static const BODY:StyleRefinement = StyleRefinement.from({
            flexDirection: "row", flexGrow: 1, size: [Length.pct(1), null]
        });
        public static const SIDE:StyleRefinement = StyleRefinement.from({
            flexDirection: "column", size: [Length.px(NAV_W), Length.pct(1)], background: 0xF8FAFC,
            borderWidths: [0, 1, 0, 0], borderColor: 0xE5E7EB, padding: [16, 14, 16, 14], gap: 4
        });
        public static const BRAND:StyleRefinement = StyleRefinement.from({
            size: [Length.pct(1), Length.px(28)],
            text: { fontSize: 20, fontWeight: "bold", color: 0x0F172A }
        });
        public static const TAG:StyleRefinement = StyleRefinement.from({
            size: [Length.pct(1), Length.px(16)],
            text: { fontSize: 11, color: 0x64748B }
        });
        public static const NAV:StyleRefinement = StyleRefinement.from({
            // flexGrow + a ZERO basis is the CSS `flex: 1`: the index viewport takes
            // whatever height the brand/tag/foot leave. A percentage height would
            // instead be a percentage OF THE SIDEBAR and overflow it.
            flexGrow: 1, flexBasis: 0, size: [Length.pct(1), null]
        });
        public static const NAV_COL:StyleRefinement = StyleRefinement.from({
            flexDirection: "column", size: [Length.pct(1), null], gap: 0
        });
        public static const NAV_GROUP:StyleRefinement = StyleRefinement.from({
            size: [Length.pct(1), Length.px(NAV_H_GROUP)], padding: [0, 10],
            text: { fontSize: 10, fontWeight: "bold", color: 0x94A3B8 }
        });
        public static const NAV_ITEM:StyleRefinement = StyleRefinement.from({
            flexDirection: "row", alignItems: "center", size: [Length.pct(1), Length.px(NAV_H_ITEM)],
            padding: [0, 10], cornerRadii: 6,
            // The row is transparent by design, but a container is only HITTABLE where
            // it PAINTS (Flash pick = the drawn region, not the layout box -- see
            // as_pick_hit_local in the runtime). Without a background the whole row but
            // the label glyphs is dead to the mouse, so the sidebar reads as broken.
            // The fill matches SIDE exactly, so nothing changes on screen.
            background: 0xF8FAFC
        });
        public static const NAV_ITEM_ON:StyleRefinement = StyleRefinement.from({
            flexDirection: "row", alignItems: "center", size: [Length.pct(1), Length.px(NAV_H_ITEM)],
            padding: [0, 10], cornerRadii: 6, background: 0xEFF6FF
        });
        public static const NAV_TEXT:StyleRefinement = StyleRefinement.from({
            size: [Length.pct(1), Length.px(NAV_H_ITEM)],
            text: { fontSize: 13, color: 0x334155 }
        });
        public static const NAV_TEXT_ON:StyleRefinement = StyleRefinement.from({
            size: [Length.pct(1), Length.px(NAV_H_ITEM)],
            text: { fontSize: 13, fontWeight: "bold", color: 0x1D4ED8 }
        });
        public static const FOOT:StyleRefinement = StyleRefinement.from({
            size: [Length.pct(1), Length.px(16)],
            text: { fontSize: 10, color: 0x94A3B8 }
        });

        public static const MAIN:StyleRefinement = StyleRefinement.from({
            flexDirection: "column", flexGrow: 1, size: [null, null], padding: [HEAD_Y, PAD_X, 16, PAD_X], gap: 4
        });
        public static const DOC_TITLE:StyleRefinement = StyleRefinement.from({
            size: [Length.pct(1), Length.px(30)],
            text: { fontFamily: "Courier New", fontSize: 22, fontWeight: "bold", color: 0x0F172A }
        });
        public static const DOC_BLURB:StyleRefinement = StyleRefinement.from({
            size: [Length.pct(1), Length.px(18)],
            text: { fontSize: 13, color: 0x334155 }
        });
        public static const DOC_META:StyleRefinement = StyleRefinement.from({
            size: [Length.pct(1), Length.px(16)],
            text: { fontFamily: "Courier New", fontSize: 11, color: 0x94A3B8 }
        });
        public static const DOC_SCROLL:StyleRefinement = StyleRefinement.from({
            // Same `flex: 1` idiom as NAV: the content pane owns the rest of the
            // window's height, so the whole app is fluid (see ROOT).
            flexGrow: 1, flexBasis: 0, size: [Length.pct(1), null]
        });
        public static const DOC_COL:StyleRefinement = StyleRefinement.from({
            flexDirection: "column", size: [Length.pct(1), null], gap: SEC_GAP
        });

        // ---- section styles -------------------------------------------------
        public static const SEC:StyleRefinement = StyleRefinement.from({
            flexDirection: "column", size: [Length.pct(1), null], gap: SEC_INNER_GAP
        });
        public static const SEC_HEAD:StyleRefinement = StyleRefinement.from({
            size: [Length.pct(1), Length.px(SEC_HEAD_H)],
            text: { fontSize: 15, fontWeight: "bold", color: 0x0F172A }
        });
        public static const PROSE:StyleRefinement = StyleRefinement.from({
            size: [Length.pct(1), Length.px(SEC_PROSE_H)],
            text: { fontSize: 12, color: 0x4B5563 }
        });
        // The live demo sits on its own surface, so a widget that paints nothing
        // (a skeleton, a transparent box) still shows where the demo IS.
        public static const DEMO:StyleRefinement = StyleRefinement.from({
            flexDirection: "row", alignItems: "center", flexWrap: "wrap",
            size: [Length.pct(1), Length.px(SEC_DEMO_H)], padding: 12, gap: 10,
            background: 0xFBFDFF, borderWidths: 1, borderColor: 0xDCE6F0, cornerRadii: 8
        });
        public static const CODE:StyleRefinement = StyleRefinement.from({
            flexDirection: "column", size: [Length.pct(1), null], padding: [CODE_PAD_H, 12],
            background: 0x0F172A, cornerRadii: 8
        });
        public static const CODE_LINE:StyleRefinement = StyleRefinement.from({
            size: [Length.pct(1), Length.px(CODE_LINE_H)],
            text: { fontFamily: "Courier New", fontSize: 11, color: 0xD7E1F0 }
        });

    }
}

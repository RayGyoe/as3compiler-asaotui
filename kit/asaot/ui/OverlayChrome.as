// asaot.ui.OverlayChrome -- the ONE palette + the shared style constants of the
// floating layer (dialog / drawer / popover / menu / toast / select).
//
// WHY ONE FILE: the six overlay kinds are one visual family, and their geometry
// is read back by ONE probe. Splitting the panel border colour across six Node
// classes is how "the menu and the popover are 1px different" happens. The kinds
// keep their own behaviour; the chrome lives here.
//
// Every style below is a `static const`, built ONCE. The factories hand the same
// pointer to the resolver on every frame, which is what keeps a settled overlay
// frame from re-resolving (design doc 2.4 layer 4: a refinement's pointer IS the
// skip test).
//
// ALL PANEL BORDERS ARE 1px AND ALL SURFACES ARE FILLS. `lineStyle` stroke width
// is not honoured on this backend (temp/stroke/, 2026-10-23), so a "hairline" is
// always `drawRect` -- which is also why the probe can assert exact colours.
package asaot.ui
{
    import asaot.ui.style.Corners;
    import asaot.ui.style.Fill;
    import asaot.ui.style.Length;
    import asaot.ui.style.Size;
    import asaot.ui.style.StyleRefinement;

    public final class OverlayChrome
    {
        // ---- palette ------------------------------------------------------
        // 0x66 alpha == 102/255 == 0.4 exactly, so a scrim over white composites
        // to exactly 0.6 * 255 = 153 (0x99) -- an exact number the probe can pin.
        public static const SCRIM:Fill = Fill.fromArgb(0x66, 0x00, 0x00, 0x00);
        public static const PANEL_BG:uint = 0xFFFFFF;
        public static const PANEL_BORDER:uint = 0xE5E7EB;
        public static const TITLE_COLOR:uint = 0x111827;
        public static const BODY_COLOR:uint = 0x374151;
        public static const ITEM_TEXT:uint = 0x1F2937;
        public static const ITEM_DISABLED:uint = 0x9CA3AF;
        public static const ITEM_HOVER:uint = 0xF3F4F6;
        public static const ITEM_SELECTED:uint = 0xDBEAFE;
        public static const TOAST_BG:uint = 0x111827;
        public static const TOAST_SUCCESS:uint = 0x065F46;
        public static const TOAST_DANGER:uint = 0x991B1B;
        public static const TOAST_TEXT_COLOR:uint = 0xFFFFFF;

        // ---- the window-sized host (see overlay.as) -----------------------
        public static const HOST:StyleRefinement = StyleRefinement.from({
            size: [Length.pct(1), Length.pct(1)],
            flexDirection: "column"
        });

        // ---- layers -------------------------------------------------------
        // A layer is an absolutely pinned box covering the WINDOW. `inset: 0`
        // pins BOTH axes (left+right, top+bottom), so the engine derives the size
        // and a resize needs no author involvement.
        public static const LAYER:StyleRefinement = StyleRefinement.from({
            position: "absolute", inset: 0, flexDirection: "column"
        });

        // Dialog: centre the panel on both axes.
        public static const LAYER_CENTER:StyleRefinement = LAYER.withPatch(StyleRefinement.from({
            justifyContent: "center", alignItems: "center"
        }));

        // Drawer: a ROW so `alignItems: stretch` makes the panel full-height, with
        // the panel pushed to the requested edge.
        public static const LAYER_ROW_START:StyleRefinement = LAYER.withPatch(StyleRefinement.from({
            flexDirection: "row", justifyContent: "flex-start", alignItems: "stretch"
        }));
        public static const LAYER_ROW_END:StyleRefinement = LAYER.withPatch(StyleRefinement.from({
            flexDirection: "row", justifyContent: "flex-end", alignItems: "stretch"
        }));
        public static const LAYER_COL_START:StyleRefinement = LAYER.withPatch(StyleRefinement.from({
            flexDirection: "column", justifyContent: "flex-start", alignItems: "stretch"
        }));
        public static const LAYER_COL_END:StyleRefinement = LAYER.withPatch(StyleRefinement.from({
            flexDirection: "column", justifyContent: "flex-end", alignItems: "stretch"
        }));

        // Toast stack: bottom-right, growing upwards. `flex-end` on BOTH axes is
        // what a notification corner is: the column is flush to the bottom edge
        // and every toast is flush to the right edge.
        public static const TOAST_LAYER:StyleRefinement = LAYER.withPatch(StyleRefinement.from({
            flexDirection: "column", justifyContent: "flex-end", alignItems: "flex-end",
            padding: 16, gap: 8
        }));

        // The full-window click catcher. A FULLY TRANSPARENT FILL, not "no fill":
        // this engine's pick test is path containment
        // (src/emit.ts as_shape_region_hit needs `_has_b`), so an object with no
        // geometry at all is un-pickable and the click would fall through to the
        // page behind. Alpha 0 keeps it invisible while still drawing the path.
        public static const CATCHER_FILL:Fill = Fill.fromArgb(0, 0, 0, 0);
        public static const CATCHER:StyleRefinement = StyleRefinement.from({
            position: "absolute", inset: 0, background: CATCHER_FILL
        });

        // The SCRIM is a filled catcher: it must both block and dim.
        public static const SCRIM_BOX:StyleRefinement = StyleRefinement.from({
            position: "absolute", inset: 0, background: SCRIM
        });

        // ---- panels -------------------------------------------------------
        public static const DIALOG_PANEL:StyleRefinement = StyleRefinement.from({
            flexDirection: "column", background: PANEL_BG, borderWidths: 1,
            borderColor: PANEL_BORDER, cornerRadii: 10, padding: 18, gap: 12
        });

        public static const DRAWER_PANEL:StyleRefinement = StyleRefinement.from({
            flexDirection: "column", background: PANEL_BG, padding: 16, gap: 12
        });

        public static const POPOVER_PANEL:StyleRefinement = StyleRefinement.from({
            flexDirection: "column", background: PANEL_BG, borderWidths: 1,
            borderColor: PANEL_BORDER, cornerRadii: 8, padding: 12, gap: 8
        });

        // The menu / dropdown surface: no vertical padding (the items carry their
        // own), 4px of horizontal inset so a hovered row is not flush to the edge.
        public static const MENU_PANEL:StyleRefinement = StyleRefinement.from({
            flexDirection: "column", background: PANEL_BG, borderWidths: 1,
            borderColor: PANEL_BORDER, cornerRadii: 8, padding: [4, 4]
        });

        public static const TOAST_BOX:StyleRefinement = StyleRefinement.from({
            flexDirection: "row", background: TOAST_BG, cornerRadii: 8,
            // [h, v] -- horizontal 14, vertical 10 (Edges.fromArray's 2-element form
            // is horizontal-then-vertical, NOT CSS's vertical-then-horizontal).
            padding: [14, 10], gap: 8
        });
        public static const TOAST_BOX_OK:StyleRefinement = TOAST_BOX.withPatch(StyleRefinement.from({
            background: TOAST_SUCCESS
        }));
        public static const TOAST_BOX_ERR:StyleRefinement = TOAST_BOX.withPatch(StyleRefinement.from({
            background: TOAST_DANGER
        }));

        public static const TOAST_TEXT:StyleRefinement = StyleRefinement.from({
            text: { fontSize: 13, color: TOAST_TEXT_COLOR }
        });

        // ---- list rows (menu / select dropdown) ---------------------------
        // A row is a fixed-height transparent box with one text child. The height is
        // fixed so the row pitch is a constant the probe can assert, and so the
        // highlight band of the selected row has a rect without measuring text.
        public static const MENU_ITEM:StyleRefinement = StyleRefinement.from({
            flexDirection: "row", alignItems: "center", height: 26, padding: [10, 0]
        });

        public static const MENU_TEXT:StyleRefinement = StyleRefinement.from({
            text: { fontSize: 13, color: ITEM_TEXT }
        });

        public static const MENU_ITEM_SEL:StyleRefinement = MENU_ITEM.withPatch(StyleRefinement.from({
            background: ITEM_SELECTED
        }));

        // ---- select -------------------------------------------------------
        // NO BORDER, deliberately: an absolutely-positioned child resolves against
        // the parent's PADDING box (border excluded), so a 1px border would offset
        // the dropdown by exactly 1px from the trigger's left edge -- and the probe
        // asserts they are flush. A filled, borderless trigger keeps the geometry
        // exact and is the common flat look anyway.
        public static const SELECT_TRIGGER:StyleRefinement = StyleRefinement.from({
            flexDirection: "row", alignItems: "center", height: 34, padding: [10, 0],
            background: 0xF3F4F6, cornerRadii: 6
        });

        public static const SELECT_CARET:uint = 0x6B7280;

        public static const SELECT_LABEL:StyleRefinement = StyleRefinement.from({
            text: { fontSize: 13, color: 0x111827 }, flexGrow: 1
        });

        // The dialog / drawer action bar: right-aligned, buttons side by side.
        public static const FOOTER_ROW:StyleRefinement = StyleRefinement.from({
            flexDirection: "row", justifyContent: "flex-end", gap: 8
        });

        // ---- text ---------------------------------------------------------
        public static const TITLE:StyleRefinement = StyleRefinement.from({
            text: { fontSize: 15, color: TITLE_COLOR }
        });
        public static const BODY:StyleRefinement = StyleRefinement.from({
            text: { fontSize: 13, color: BODY_COLOR }
        });

        public function OverlayChrome() { }
    }
}
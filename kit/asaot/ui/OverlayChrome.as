// asaot.ui.OverlayChrome -- the ONE palette + the shared style constants of the
// floating layer (dialog / drawer / popover / menu / toast / select).
//
// WHY ONE FILE: the six overlay kinds are one visual family, and their geometry
// is read back by ONE probe. Splitting the panel border colour across six Node
// classes is how "the menu and the popover are 1px different" happens. The kinds
// keep their own behaviour; the chrome lives here.
//
// THE COLOURS COME FROM `Theme.tokens()` (2026-10-27). This class is the ONE place
// in the kit that cannot read the palette at paint time, and the reason is the
// resolver: a `StyleRefinement` is a VALUE that gets resolved into a `Style` before
// anything paints, so a colour baked into one is fixed until the refinement itself
// is rebuilt. Hence `rebuild()`: `Theme.setTheme()` calls it, and every
// colour-bearing member is re-created against the new palette. Geometry-only
// members (layers, paddings, the day grid, TREE_ROW) stay `const` -- they never
// change, and keeping them const is what makes "this one is theme-dependent"
// visible by reading the declaration.
//
// THE POINTER-IDENTITY SKIP STILL HOLDS. `rebuild()` creates NEW refinement
// pointers, so the very next reconcile re-resolves every overlay node -- the same
// mechanism an author's changed `style:` pointer drives. On a settled frame the
// factories hand the resolver the same pointer every time and nothing re-resolves.
//
// DECLARATION ORDER IS LOAD-BEARING: `_ready` sits after every `const` that
// `rebuild()` reads and before every `var` it writes. A static initialiser runs in
// declaration order, so when `boot()` runs, `MENU_ITEM` / `DAY_W` / `CATCHER_FILL`
// exist and the `var`s it assigns exist (with no initialiser to overwrite them
// afterwards). Moving `_ready` to the top of the file would make `MENU_ITEM` null
// inside `rebuild()` -- a null refinement handed to a factory.
//
// ALL PANEL BORDERS ARE 1px AND ALL SURFACES ARE FILLS. A "hairline" is always
// `drawRect`, because a fill is integer-exact and the probe can assert exact colours.
// (This file used to say stroke width was not honoured on this backend; that was
// re-measured on 2026-10-25 and is false -- see probes/widgets/icon. Strokes are fine;
// integer-exact fills are what this file wants.)
package asaot.ui
{
    import asaot.ui.style.Corners;
    import asaot.ui.style.Fill;
    import asaot.ui.style.Length;
    import asaot.ui.style.Size;
    import asaot.ui.style.StyleRefinement;

    public final class OverlayChrome
    {
        // ---- geometry-only (theme independent, const) ----------------------

        // The window-sized host (see overlay.as).
        public static const HOST:StyleRefinement = StyleRefinement.from({
            size: [Length.pct(1), Length.pct(1)],
            flexDirection: "column"
        });

        // A layer is an absolutely pinned box covering the WINDOW. `inset: 0` pins
        // BOTH axes (left+right, top+bottom), so the engine derives the size
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

        // A menu row: fixed height so the row pitch is a constant the probe can
        // assert, and so the highlight band of the selected row has a rect without
        // measuring text. The SELECTED variant carries a background, so it is rebuilt.
        public static const MENU_ITEM:StyleRefinement = StyleRefinement.from({
            flexDirection: "row", alignItems: "center", height: 26, padding: [10, 0]
        });

        // The dialog / drawer action bar: right-aligned, buttons side by side.
        public static const FOOTER_ROW:StyleRefinement = StyleRefinement.from({
            flexDirection: "row", justifyContent: "flex-end", gap: 8
        });

        // ---- tree geometry ------------------------------------------------
        // A row is the ordinary 26pt item with a left padding the FACTORY derives
        // from the depth (see tree.as). The twisty is PAINTED by TreeWidget inside
        // that padding, so a row's own style never has to know whether its branch is
        // open -- the widget reads `rows[i].open` and draws the right triangle.
        //
        // The two numbers that must agree are here: TREE_INDENT (the step per depth)
        // and TREE_HIT (how far into a row a click counts as "on the twisty" rather
        // than "on the label"). TreeWidget owns the drawing and the hit test.
        public static const TREE_INDENT:Number = 18;
        public static const TREE_PAD:Number = 22;
        public static const TREE_HIT:Number = 22;
        public static const TREE_ROW_H:Number = 26;
        public static const TREE_ROW:StyleRefinement = StyleRefinement.from({
            flexDirection: "row", alignItems: "center", height: TREE_ROW_H
        });

        // ---- date picker geometry -----------------------------------------
        // 7 columns of 28pt cells and 6 week rows: the numbers the factory pins so the
        // grid is exactly DAY_W * 7 wide (a day cell must not stretch, or the click
        // column would depend on the panel width).
        public static const DAY_W:Number = 28;
        public static const DAY_H:Number = 26;

        // FIRST THING AFTER THE GEOMETRY: fill every `var` below before the first read
        // of any of them. See the header for why this line's POSITION matters.
        private static var _ready:Boolean = boot();

        // ---- palette (assigned by rebuild) ---------------------------------
        // 0x66 alpha == 102/255 == 0.4 exactly, so a scrim over white composites
        // to exactly 0.6 * 255 = 153 (0x99) -- an exact number the probe can pin.
        public static var SCRIM:Fill;
        public static var PANEL_BG:uint;
        public static var PANEL_BORDER:uint;
        public static var TITLE_COLOR:uint;
        public static var BODY_COLOR:uint;
        public static var ITEM_TEXT:uint;
        public static var ITEM_DISABLED:uint;
        public static var ITEM_HOVER:uint;
        public static var ITEM_SELECTED:uint;
        public static var TOAST_BG:uint;
        public static var TOAST_SUCCESS:uint;
        public static var TOAST_DANGER:uint;
        public static var TOAST_TEXT_COLOR:uint;
        public static var SELECT_CARET:uint;
        public static var TREE_TWISTY:uint;

        // ---- colour-bearing chrome (assigned by rebuild) -------------------
        public static var SCRIM_BOX:StyleRefinement;
        public static var DIALOG_PANEL:StyleRefinement;
        public static var DRAWER_PANEL:StyleRefinement;
        public static var POPOVER_PANEL:StyleRefinement;
        public static var MENU_PANEL:StyleRefinement;
        public static var TOAST_BOX:StyleRefinement;
        public static var TOAST_BOX_OK:StyleRefinement;
        public static var TOAST_BOX_ERR:StyleRefinement;
        public static var TOAST_TEXT:StyleRefinement;
        public static var MENU_TEXT:StyleRefinement;
        public static var MENU_ITEM_SEL:StyleRefinement;
        public static var SELECT_TRIGGER:StyleRefinement;
        public static var SELECT_LABEL:StyleRefinement;
        public static var TITLE:StyleRefinement;
        public static var BODY:StyleRefinement;
        public static var TREE_TEXT:StyleRefinement;
        public static var DAY_TEXT:StyleRefinement;
        public static var DAY_MUTED:StyleRefinement;
        public static var DAY_NAV:StyleRefinement;
        public static var DAY_NAV_TEXT:StyleRefinement;
        public static var DP_TITLE:StyleRefinement;

        public function OverlayChrome() { }

        private static function boot():Boolean
        {
            rebuild();
            return true;
        }

        // Re-create everything that holds a colour. Called by `Theme.setTheme()`, and
        // once at class-init time. Idempotent: it reads the palette and assigns, so
        // calling it twice with the same palette produces equal (not identical) values.
        public static function rebuild():void
        {
            var t:ThemeTokens = Theme.tokens();

            SCRIM = Fill.solid(t.scrim);
            PANEL_BG = t.surface;
            PANEL_BORDER = t.border;
            TITLE_COLOR = t.textStrong;
            BODY_COLOR = t.textBody;
            ITEM_TEXT = t.textItem;
            ITEM_DISABLED = t.textDisabled;
            ITEM_HOVER = t.surfaceMuted;
            ITEM_SELECTED = t.accentSoft;
            TOAST_BG = t.surfaceToast;
            TOAST_SUCCESS = t.successStrong;
            TOAST_DANGER = t.dangerStrong;
            TOAST_TEXT_COLOR = t.onInverse;
            SELECT_CARET = t.textMuted;
            TREE_TWISTY = t.textMuted;

            SCRIM_BOX = StyleRefinement.from({
                position: "absolute", inset: 0, background: SCRIM
            });

            DIALOG_PANEL = StyleRefinement.from({
                flexDirection: "column", background: PANEL_BG, borderWidths: 1,
                borderColor: PANEL_BORDER, cornerRadii: 10, padding: 18, gap: 12
            });

            DRAWER_PANEL = StyleRefinement.from({
                flexDirection: "column", background: PANEL_BG, padding: 16, gap: 12
            });

            POPOVER_PANEL = StyleRefinement.from({
                flexDirection: "column", background: PANEL_BG, borderWidths: 1,
                borderColor: PANEL_BORDER, cornerRadii: 8, padding: 12, gap: 8
            });

            // The menu / dropdown surface: no vertical padding (the items carry their
            // own), 4px of horizontal inset so a hovered row is not flush to the edge.
            MENU_PANEL = StyleRefinement.from({
                flexDirection: "column", background: PANEL_BG, borderWidths: 1,
                borderColor: PANEL_BORDER, cornerRadii: 8, padding: [4, 4]
            });

            TOAST_BOX = StyleRefinement.from({
                flexDirection: "row", background: TOAST_BG, cornerRadii: 8,
                // [h, v] -- horizontal 14, vertical 10 (Edges.fromArray's 2-element form
                // is horizontal-then-vertical, NOT CSS's vertical-then-horizontal).
                padding: [14, 10], gap: 8
            });
            TOAST_BOX_OK = TOAST_BOX.withPatch(StyleRefinement.from({
                background: TOAST_SUCCESS
            }));
            TOAST_BOX_ERR = TOAST_BOX.withPatch(StyleRefinement.from({
                background: TOAST_DANGER
            }));

            TOAST_TEXT = StyleRefinement.from({
                text: { fontSize: 13, color: TOAST_TEXT_COLOR }
            });

            MENU_TEXT = StyleRefinement.from({
                text: { fontSize: 13, color: ITEM_TEXT }
            });

            MENU_ITEM_SEL = MENU_ITEM.withPatch(StyleRefinement.from({
                background: ITEM_SELECTED
            }));

            // ---- select -------------------------------------------------------
            // NO BORDER, deliberately: an absolutely-positioned child resolves against
            // the parent's PADDING box (border excluded), so a 1px border would offset
            // the dropdown by exactly 1px from the trigger's left edge -- and the probe
            // asserts they are flush. A filled, borderless trigger keeps the geometry
            // exact and is the common flat look anyway.
            SELECT_TRIGGER = StyleRefinement.from({
                flexDirection: "row", alignItems: "center", height: 34, padding: [10, 0],
                background: t.surfaceMuted, cornerRadii: 6
            });

            SELECT_LABEL = StyleRefinement.from({
                text: { fontSize: 13, color: t.textStrong }, flexGrow: 1
            });

            TITLE = StyleRefinement.from({
                text: { fontSize: 15, color: TITLE_COLOR }
            });
            BODY = StyleRefinement.from({
                text: { fontSize: 13, color: BODY_COLOR }
            });

            TREE_TEXT = StyleRefinement.from({
                text: { fontSize: 13, color: ITEM_TEXT }
            });

            DAY_TEXT = StyleRefinement.from({
                text: { fontSize: 12, color: ITEM_TEXT }
            });
            DAY_MUTED = StyleRefinement.from({
                text: { fontSize: 12, color: ITEM_DISABLED }
            });
            DAY_NAV = StyleRefinement.from({
                flexDirection: "row", alignItems: "center", justifyContent: "center",
                width: DAY_W, height: DAY_H, background: t.surface
            });
            DAY_NAV_TEXT = StyleRefinement.from({
                text: { fontSize: 13, color: t.textStrong }
            });
            DP_TITLE = StyleRefinement.from({
                text: { fontSize: 13, color: t.textStrong }, flexGrow: 1
            });
        }
    }
}
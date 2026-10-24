// demo/DocsDemo.as -- the small shared vocabulary the example sections draw with:
// a label, a tile, a panel, and the three button skins. Kept in one class so the
// pages stay about the WIDGET they document rather than about their own styling.
package demo
{
    import asaot.ui.Node;
    import asaot.ui.box;
    import asaot.ui.style.Length;
    import asaot.ui.style.StyleRefinement;
    import asaot.ui.text;

    public final class DocsDemo
    {
        // 12px slate: the caption under or beside an example.
        public static const LABEL:StyleRefinement = StyleRefinement.from({
            text: { fontSize: 12, color: 0x64748B }
        });
        public static const LABEL_B:StyleRefinement = StyleRefinement.from({
            text: { fontSize: 12, fontWeight: "bold", color: 0x334155 }
        });
        public static const MONO:StyleRefinement = StyleRefinement.from({
            text: { fontFamily: "Courier New", fontSize: 11, color: 0x64748B }
        });
        // A tinted slab: "this box is 160 wide" without drawing a border.
        public static const TILE:StyleRefinement = StyleRefinement.from({
            size: [96, 40], padding: [11, 10], background: 0xDBEAFE, cornerRadii: 6,
            text: { fontSize: 12, color: 0x1E3A8A }
        });
        public static const TILE_ALT:StyleRefinement = StyleRefinement.from({
            size: [96, 40], padding: [11, 10], background: 0xE0E7FF, cornerRadii: 6,
            text: { fontSize: 12, color: 0x3730A3 }
        });
        public static const PANEL:StyleRefinement = StyleRefinement.from({
            padding: 12, background: 0xF8FAFC, borderWidths: 1, borderColor: 0xE2E8F0,
            cornerRadii: 8
        });
        public static const PRIMARY:StyleRefinement = StyleRefinement.from({
            size: [128, 36], background: 0x2563EB, borderColor: 0x1D4ED8, cornerRadii: 8,
            text: { fontSize: 13, fontWeight: "bold", color: 0xFFFFFF }
        });

        public static const QUIET:StyleRefinement = StyleRefinement.from({
            size: [128, 36], background: 0xFFFFFF, borderColor: 0xD1D5DB, cornerRadii: 8,
            text: { fontSize: 13, color: 0x334155 }
        });
        public static const DANGER:StyleRefinement = StyleRefinement.from({
            size: [128, 36], background: 0xDC2626, borderColor: 0xB91C1C, cornerRadii: 8,
            text: { fontSize: 13, fontWeight: "bold", color: 0xFFFFFF }
        });

        public static function tile(label:String, alt:Boolean):Node
        {
            // The child text inherits the parent's text.* (colour, size), so a tile
            // needs no per-child style at all.
            return box({ style: alt ? TILE_ALT : TILE }, [
                text(label, { ariaName: "" })
            ]);
        }

        public static function cap(s:String):Node
        {
            return text(s, { style: LABEL, ariaName: "" });
        }
    }
}

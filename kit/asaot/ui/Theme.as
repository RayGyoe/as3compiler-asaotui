// asaot.ui.Theme -- control defaults + the four-layer style resolution
// (design doc section 2.3).
//
// RESOLUTION ORDER (low -> high priority):
//   1. controlDefault(kind)        // static, built once
//   2. theme slot                  // (the hook `setControlDefault` fills)
//   3. parent's INHERITED subset   // only text.* + visibility
//   4. node.style (the refinement) // author's explicit override
//
// WHY LAYOUT DEFAULTS ARE NOT INHERITED: flexbox properties do not cascade; only
// the typography subset does. Making `size`/`padding` inherit would "look right"
// on a shallow tree and then diverge from every browser. This table is the
// concrete expression of the doc's warning.
//
// THE RESOLVE WRITES INTO A CALLER BUFFER (`out`), and the two scratch Styles are
// reused statics, so no per-node `Style` is allocated here. Composite buffers
// (Size/Edges/Corners) may still be allocated when a refinement actually
// changes -- and that only happens on a frame where a style pointer changed,
// never in a steady frame (the resolver's pointer-identity test skips first).
package asaot.ui
{
    import asaot.ui.style.Style;
    import asaot.ui.style.StyleRefinement;
    import asaot.ui.style.Length;
    import asaot.ui.style.Size;
    import asaot.ui.style.Edges;
    import asaot.ui.style.Corners;
    import asaot.ui.style.Fill;
    import asaot.ui.style.TextStyle;

    public final class Theme
    {
        private static var _scratch1:Style;
        private static var _scratch2:Style;
        private static var _defaults:Object;   // kind -> Style

        // Kinds whose whole region IS the interactive thing. They hand the pointer
        // the hand shape (the same affordance AIR gives a SimpleButton). The list
        // is deliberately short: a scroll view, a list, a table and a tree are
        // SELECTABLE REGIONS, not buttons -- a hand over every pixel of a 400px
        // list claims every pixel is clickable, which is exactly the kind of lie
        // that makes a pointer feel broken. Roles that are clickable only when the
        // author says so (image / avatar / card / box) set `cursor` themselves.
        private static const CLICKABLE:Array = ["button", "checkbox", "radio", "switch",
            "slider", "select", "combobox", "tabs", "menu", "accordion", "pagination",
            "breadcrumb", "chip", "datePicker"];
        private static var _clickable:Style;

        private static function ensure():void
        {
            if (_scratch1 != null) return;
            _scratch1 = new Style();
            _scratch2 = new Style();
            _defaults = {};
            _defaults["box"] = makeBox();
            _defaults["text"] = makeText();
            _defaults["button"] = makeButton();
            _defaults["textInput"] = makeTextInput();
            _defaults["textArea"] = makeTextInput();
            _defaults["checkbox"] = makeCheckbox();
            // ONE shared instance: `resolve` copies the baseline into scratch1 and
            // never writes it in place, so every clickable kind can point at the
            // same style without any of them affecting another.
            _clickable = makeBox();
            _clickable.cursor = "hand";
            for (var i:int = 0; i < CLICKABLE.length; i++)
            {
                var k:String = String(CLICKABLE[i]);
                if (_defaults[k] == null) _defaults[k] = _clickable;
                else _defaults[k].cursor = "hand";
            }
        }

        public static function controlDefault(kind:String):Style
        {
            ensure();
            var s:Style = _defaults[kind];
            return s != null ? s : _defaults["box"];
        }

        // A theme is allowed to replace a control's baseline once, at startup.
        public static function setControlDefault(kind:String, s:Style):void
        {
            ensure();
            _defaults[kind] = s;
        }

        public static function resolve(out:Style, kind:String, parent:Style,
                                      r:StyleRefinement, dirOverride:String):void
        {
            ensure();
            var base:Style = controlDefault(kind);
            base.copyInto(_scratch1);
            _scratch2.clear();
            if (parent != null) parent.projectInherited(_scratch2);
            _scratch1.refineInto(out, _scratch2);
            if (r != null)
            {
                // `r` is the higher-priority layer, so it must not alias `out`:
                // refine into scratch2 (r wins over out), then copy into out.
                r.refineInto(_scratch2, out);
                _scratch2.copyInto(out);
            }
            if (dirOverride != null) out.flexDirection = dirOverride;
        }

        // ---- the baseline styles ------------------------------------------

        private static function makeBox():Style
        {
            var s:Style = new Style();
            s.boxSizing = "borderBox";
            return s;
        }

        private static function makeText():Style
        {
            var s:Style = new Style();
            s.text.fontSize = 14;
            s.text.color = 0x1A1A1A;
            return s;
        }

        private static function makeButton():Style
        {
            var s:Style = new Style();
            s.padding = Edges.of(9, 14, 9, 14);
            s.borderWidths = Edges.all(1);
            s.borderColor = 0xD0D0D0;
            s.cornerRadii = Corners.all(6);
            s.background = Fill.solid(0xFFF1F3F5);
            s.text.fontSize = 14;
            s.text.color = 0x202020;
            return s;
        }

        private static function makeTextInput():Style
        {
            var s:Style = new Style();
            s.padding = Edges.of(7, 10, 7, 10);
            s.borderWidths = Edges.all(1);
            s.borderColor = 0xCCCCCC;
            s.cornerRadii = Corners.all(4);
            s.background = Fill.solid(0xFFFFFFFF);
            s.text.fontSize = 14;
            s.text.color = 0x202020;
            return s;
        }

        private static function makeCheckbox():Style
        {
            var s:Style = new Style();
            s.text.fontSize = 14;
            s.text.color = 0x202020;
            return s;
        }
    }
}
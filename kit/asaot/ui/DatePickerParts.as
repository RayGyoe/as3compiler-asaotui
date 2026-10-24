// asaot.ui.DatePickerParts -- the pieces `datePicker` builds more than once.
//
// A class with statics rather than package-level functions: mxmlc resolves a
// package-level function only from a file named after it (compiler-gaps G7), and two
// arrow cells in one factory are not worth two files.
package asaot.ui
{
    public final class DatePickerParts
    {
        // One month-navigation cell: a DAY_W x DAY_H box with a centred glyph. The
        // glyph is U+2039 / U+203A (single angle quotes) -- Latin-1 so it needs no font
        // work, and it reads as an arrow at 13pt.
        public static function nav(key:String, glyph:String):Node
        {
            var cell:Node = box({ key: key, style: OverlayChrome.DAY_NAV, ariaName: "" });
            cell.addChild(text(glyph, { key: key + ":t", style: OverlayChrome.DAY_NAV_TEXT,
                                        ariaName: "" }));
            return cell;
        }

        public function DatePickerParts() { }
    }
}
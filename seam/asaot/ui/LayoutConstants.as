// asaot.ui.LayoutConstants -- the frozen integer enums that both layout-engine
// implementations (As3LayoutEngine and the emitted NativeLayoutEngine) share.
//
// These values are OURS, not Yoga's. They are copied verbatim from the opaque C
// seam header `u1-prototype/yoga_glue.h` (the `AS_UI_*` enum block); the native
// built-in maps each one onto Yoga's own enum with an explicit switch, and the
// pure-AS3 engine interprets them directly. Keeping the two in lock-step here is
// what lets the two engines be swapped through the same `LayoutEngine` interface
// without a single call site changing.
//
// The 0..100 percentage spelling is Yoga's (see the C header comment): the
// author-facing Fraction is 0..1 and is multiplied by 100 before it reaches the
// engine.
package asaot.ui
{
    public final class LayoutConstants
    {
        // Style.flexDirection -- as_ui_yg_set_flex_direction
        public static const FLEX_DIR_COLUMN:int = 0;
        public static const FLEX_DIR_COLUMN_REVERSE:int = 1;
        public static const FLEX_DIR_ROW:int = 2;
        public static const FLEX_DIR_ROW_REVERSE:int = 3;

        // Style.flexWrap -- as_ui_yg_set_flex_wrap
        public static const WRAP_NO_WRAP:int = 0;
        public static const WRAP_WRAP:int = 1;
        public static const WRAP_WRAP_REVERSE:int = 2;

        // Style.alignItems / alignSelf / alignContent -- as_ui_yg_set_align_*
        public static const ALIGN_AUTO:int = 0;
        public static const ALIGN_FLEX_START:int = 1;
        public static const ALIGN_CENTER:int = 2;
        public static const ALIGN_FLEX_END:int = 3;
        public static const ALIGN_STRETCH:int = 4;
        public static const ALIGN_BASELINE:int = 5;
        public static const ALIGN_SPACE_BETWEEN:int = 6;
        public static const ALIGN_SPACE_AROUND:int = 7;
        public static const ALIGN_SPACE_EVENLY:int = 8;
        public static const ALIGN_START:int = 9;
        public static const ALIGN_END:int = 10;

        // Style.justifyContent -- as_ui_yg_set_justify
        public static const JUSTIFY_AUTO:int = 0;
        public static const JUSTIFY_FLEX_START:int = 1;
        public static const JUSTIFY_CENTER:int = 2;
        public static const JUSTIFY_FLEX_END:int = 3;
        public static const JUSTIFY_SPACE_BETWEEN:int = 4;
        public static const JUSTIFY_SPACE_AROUND:int = 5;
        public static const JUSTIFY_SPACE_EVENLY:int = 6;
        public static const JUSTIFY_STRETCH:int = 7;
        public static const JUSTIFY_START:int = 8;
        public static const JUSTIFY_END:int = 9;

        // Edge -- margin / padding / border / inset (position)
        public static const EDGE_LEFT:int = 0;
        public static const EDGE_TOP:int = 1;
        public static const EDGE_RIGHT:int = 2;
        public static const EDGE_BOTTOM:int = 3;
        public static const EDGE_START:int = 4;
        public static const EDGE_END:int = 5;
        public static const EDGE_HORIZONTAL:int = 6;
        public static const EDGE_VERTICAL:int = 7;
        public static const EDGE_ALL:int = 8;

        // Gutter -- Style.gap (row-gap / column-gap) -- as_ui_yg_set_gap
        public static const GUTTER_COLUMN:int = 0;
        public static const GUTTER_ROW:int = 1;
        public static const GUTTER_ALL:int = 2;

        // Dimension -- which of width/height an axis-taking call refers to
        public static const AXIS_WIDTH:int = 0;
        public static const AXIS_HEIGHT:int = 1;

        // Unit -- the length trichotomy (value, unit) -- see the C header comment
        public static const UNIT_UNDEFINED:int = 0;
        public static const UNIT_POINT:int = 1;
        public static const UNIT_PERCENT:int = 2;
        public static const UNIT_AUTO:int = 3;
        public static const UNIT_MAX_CONTENT:int = 4;
        public static const UNIT_FIT_CONTENT:int = 5;
        public static const UNIT_STRETCH:int = 6;

        // Style.display -- as_ui_yg_set_display
        public static const DISPLAY_FLEX:int = 0;
        public static const DISPLAY_NONE:int = 1;
        public static const DISPLAY_CONTENTS:int = 2;
        public static const DISPLAY_GRID:int = 3;

        // Style.position -- as_ui_yg_set_position_type
        public static const POSITION_STATIC:int = 0;
        public static const POSITION_RELATIVE:int = 1;
        public static const POSITION_ABSOLUTE:int = 2;

        // Direction -- writing direction for a layout pass -- as_ui_yg_calculate
        public static const DIR_INHERIT:int = 0;
        public static const DIR_LTR:int = 1;
        public static const DIR_RTL:int = 2;

        // Style.overflowX / overflowY collapsed -- as_ui_yg_set_overflow
        public static const OVERFLOW_VISIBLE:int = 0;
        public static const OVERFLOW_HIDDEN:int = 1;
        public static const OVERFLOW_SCROLL:int = 2;

        // BoxSizing -- the reference frame of size/padding/border. Note: the
        // engine default is BORDER_BOX, the opposite of CSS's content-box.
        public static const BOX_SIZING_BORDER_BOX:int = 0;
        public static const BOX_SIZING_CONTENT_BOX:int = 1;

        // MeasureMode -- what a measure callback is told about an axis
        public static const MEASURE_UNDEFINED:int = 0;
        public static const MEASURE_EXACTLY:int = 1;
        public static const MEASURE_AT_MOST:int = 2;

        public function LayoutConstants() { }
    }
}

/* yoga_glue.h -- the OPAQUE C seam between `asaot.ui` and the flexbox layout
 * engine (Yoga). U1 prototype.
 *
 * WHAT THIS HEADER IS
 * -------------------
 * This is the one and only contract the AS3 side (`asaot.ui`) sees. It is
 * deliberately opaque, following the precedent set by the text glue (15
 * functions, docs/zh-cn/rust-text-backend.md section 1.1) and by
 * vendor/sqlite_glue.c:
 *
 *   - a node is an opaque `void*` handle; the C side NEVER dereferences it;
 *   - every value crossing the seam is a scalar (float/int/double) or our own
 *     fixed enum constants;
 *   - NOT ONE Yoga type (`YGNodeRef`, `YGValue`, `YGMeasureMode`, `YGEdge` ...)
 *     appears here. `<yoga/Yoga.h>` is included by yoga_glue.cc only.
 *
 * The point of the opacity is replaceability: this seam was designed so the
 * implementation behind it (currently Yoga) can be swapped wholesale without
 * touching a single line of `asaot.ui`, exactly as rust-text-backend.md section
 * 1.1 argues for the text backend. If a Yoga enum or struct ever leaked into
 * this header that property would be gone.
 *
 * ENUM CONSTANTS ARE OURS, NOT YOGA'S
 * -----------------------------------
 * Every constant below has a value chosen and frozen by us. It is NOT the Yoga
 * enum value and must never be assumed to equal it. yoga_glue.cc maps our value
 * onto Yoga's with an explicit switch, so reordering Yoga's enums (or replacing
 * Yoga) cannot silently change what `AS_UI_FLEX_DIR_ROW` means.
 *
 * LENGTH TRI-STATE (the API-design length trichotomy)
 * ---------------------------------------------------
 * `ui-toolkit-api-design.md` section 2.2 defines three length kinds:
 *   AbsoluteLength = {px, rem}          -> a point value
 *   DefiniteLength = {Absolute, Fraction} -> a point value OR a 0..1 fraction
 *   Length         = {Definite, Auto}   -> a point, a fraction, or auto
 * and CSS adds `undefined` (the property was never set). We carry all of that
 * in the SAME shape Yoga itself uses for a style value: a pair
 * `(float value, int unit)`. `unit` is one of the AS_UI_UNIT_* constants:
 *   AS_UI_UNIT_UNDEFINED  -- property not set; engine default applies
 *   AS_UI_UNIT_POINT      -- value is logical points (px in the design)
 *   AS_UI_UNIT_PERCENT    -- value is a percentage in [0,100] (Yoga's spelling;
 *                            the design's `Fraction` 0..1 is multiplied by 100
 *                            at the call site -- see note in yoga_glue.cc)
 *   AS_UI_UNIT_AUTO       -- auto (used by size / margin / flex-basis)
 * plus the newer intrinsic keywords Yoga supports (max-content etc.).
 * This is the minimum shape that can carry section 2.1's Style fields
 * (`size`, `minSize`, `maxSize`, `margin`, `padding`, `flexBasis`, `gap`,
 * `inset`, grid tracks...); a bare `float` could not express `auto`.
 *
 * The design says a `Fraction` is 0..1, not 0..100. We keep the seam at 0..100
 * because that is what Yoga's `*Percent` setters take and what CSS percentages
 * mean; the 0..1 -> 0..100 conversion belongs to `asaot.ui`, not here. (Documented
 * so the two spellings never get confused.)
 *
 * NULL HANDLES
 * ------------
 * The AS3 object graph does not guarantee lifetime ordering with respect to this
 * seam (a GC'd UiNode may be freed after its handle is passed down, and error
 * paths may call a setter on a half-built node). Every function therefore
 * tolerates a NULL node / config / callback argument and returns a safe default
 * (no-op, or zeros for the readers) rather than dereferencing. See yoga_glue.cc.
 *
 * USAGE (mirrors the three-pass pipeline in ui-toolkit-api-design.md section 3)
 * ---------------------------------------------------------------------------
 *   void* cfg  = as_ui_yg_config_new(0.0f, 1);
 *   void* root = as_ui_yg_node_new(cfg);
 *   void* child= as_ui_yg_node_new(cfg);
 *   as_ui_yg_set_size(root, AS_UI_AXIS_WIDTH, 200, AS_UI_UNIT_POINT);
 *   as_ui_yg_set_flex_direction(root, AS_UI_FLEX_DIR_COLUMN);
 *   as_ui_yg_set_padding(root, AS_UI_EDGE_ALL, 16, AS_UI_UNIT_POINT);
 *   as_ui_yg_node_insert(root, child, 0);
 *   as_ui_yg_calculate(root, 1000, 1000, AS_UI_DIR_LTR);
 *   float r[4]; as_ui_yg_layout_get(root, r);   // left, top, width, height
 *   as_ui_yg_node_free_recursive(root);
 *   as_ui_yg_config_free(cfg);
 */
#ifndef AS_UI_YOGA_GLUE_H
#define AS_UI_YOGA_GLUE_H

#ifdef __cplusplus
extern "C" {
#endif

/* ------------------------------------------------------------------------- *
 * Frozen enums (our values, never Yoga's -- see header comment)
 * ------------------------------------------------------------------------- */

/* FlexDirection -- Style.flexDirection */
enum {
  AS_UI_FLEX_DIR_COLUMN = 0,
  AS_UI_FLEX_DIR_COLUMN_REVERSE = 1,
  AS_UI_FLEX_DIR_ROW = 2,
  AS_UI_FLEX_DIR_ROW_REVERSE = 3
};

/* Wrap -- Style.flexWrap */
enum {
  AS_UI_WRAP_NO_WRAP = 0,
  AS_UI_WRAP_WRAP = 1,
  AS_UI_WRAP_WRAP_REVERSE = 2
};

/* Align -- Style.alignItems / alignSelf / alignContent */
enum {
  AS_UI_ALIGN_AUTO = 0,
  AS_UI_ALIGN_FLEX_START = 1,
  AS_UI_ALIGN_CENTER = 2,
  AS_UI_ALIGN_FLEX_END = 3,
  AS_UI_ALIGN_STRETCH = 4,
  AS_UI_ALIGN_BASELINE = 5,
  AS_UI_ALIGN_SPACE_BETWEEN = 6,
  AS_UI_ALIGN_SPACE_AROUND = 7,
  AS_UI_ALIGN_SPACE_EVENLY = 8,
  AS_UI_ALIGN_START = 9,
  AS_UI_ALIGN_END = 10
};

/* Justify -- Style.justifyContent */
enum {
  AS_UI_JUSTIFY_AUTO = 0,
  AS_UI_JUSTIFY_FLEX_START = 1,
  AS_UI_JUSTIFY_CENTER = 2,
  AS_UI_JUSTIFY_FLEX_END = 3,
  AS_UI_JUSTIFY_SPACE_BETWEEN = 4,
  AS_UI_JUSTIFY_SPACE_AROUND = 5,
  AS_UI_JUSTIFY_SPACE_EVENLY = 6,
  AS_UI_JUSTIFY_STRETCH = 7,
  AS_UI_JUSTIFY_START = 8,
  AS_UI_JUSTIFY_END = 9
};

/* Edge -- margin / padding / border / inset (position). The *axis* members are
 * the "horizontal"/"vertical"/"all" shorthands; the engine expands them. START
 * and END are writing-direction aware; LTR-only builds can treat them as
 * LEFT/RIGHT. */
enum {
  AS_UI_EDGE_LEFT = 0,
  AS_UI_EDGE_TOP = 1,
  AS_UI_EDGE_RIGHT = 2,
  AS_UI_EDGE_BOTTOM = 3,
  AS_UI_EDGE_START = 4,
  AS_UI_EDGE_END = 5,
  AS_UI_EDGE_HORIZONTAL = 6,
  AS_UI_EDGE_VERTICAL = 7,
  AS_UI_EDGE_ALL = 8
};

/* Gutter -- Style.gap (row-gap / column-gap) */
enum {
  AS_UI_GUTTER_COLUMN = 0,
  AS_UI_GUTTER_ROW = 1,
  AS_UI_GUTTER_ALL = 2
};

/* Dimension -- which of width/height a size/minmax call refers to */
enum {
  AS_UI_AXIS_WIDTH = 0,
  AS_UI_AXIS_HEIGHT = 1
};

/* Unit -- the length trichotomy (value, unit) */
enum {
  AS_UI_UNIT_UNDEFINED = 0,
  AS_UI_UNIT_POINT = 1,
  AS_UI_UNIT_PERCENT = 2,
  AS_UI_UNIT_AUTO = 3,
  AS_UI_UNIT_MAX_CONTENT = 4,
  AS_UI_UNIT_FIT_CONTENT = 5,
  AS_UI_UNIT_STRETCH = 6
};

/* Display -- Style.display */
enum {
  AS_UI_DISPLAY_FLEX = 0,
  AS_UI_DISPLAY_NONE = 1,
  AS_UI_DISPLAY_CONTENTS = 2,
  AS_UI_DISPLAY_GRID = 3
};

/* PositionType -- Style.position */
enum {
  AS_UI_POSITION_STATIC = 0,
  AS_UI_POSITION_RELATIVE = 1,
  AS_UI_POSITION_ABSOLUTE = 2
};

/* Direction -- writing direction for a layout pass */
enum {
  AS_UI_DIR_INHERIT = 0,
  AS_UI_DIR_LTR = 1,
  AS_UI_DIR_RTL = 2
};

/* Overflow -- Style.overflowX / overflowY (Yoga carries one value for both) */
enum {
  AS_UI_OVERFLOW_VISIBLE = 0,
  AS_UI_OVERFLOW_HIDDEN = 1,
  AS_UI_OVERFLOW_SCROLL = 2
};

/* BoxSizing -- the reference frame of size/padding/border. NOTE: Yoga (and this
 * seam) default to BORDER_BOX, the opposite of CSS's content-box default; see
 * check-layout.md case d and ui-toolkit-api-design.md section 2.1 (box-sizing is
 * on the design's "not introduced for now" list, so we inherit Yoga's default). */
enum {
  AS_UI_BOX_SIZING_BORDER_BOX = 0,
  AS_UI_BOX_SIZING_CONTENT_BOX = 1
};

/* MeasureMode -- passed to a measure callback to say what the parent knows.
 * Undefined: unconstrained. Exactly: you WILL be this size. AtMost: you may be
 * up to this size. */
enum {
  AS_UI_MEASURE_UNDEFINED = 0,
  AS_UI_MEASURE_EXACTLY = 1,
  AS_UI_MEASURE_AT_MOST = 2
};

/* ------------------------------------------------------------------------- *
 * Measure callback (intrinsic sizing: text, images, ...)
 * ------------------------------------------------------------------------- */
/* A measured leaf reports a size by WRITING two floats into `out_wh`
 * (out_wh[0] = width, out_wh[1] = height).
 *
 * Deviation from the precheck draft (u1-yoga-precheck.md section 6.3 #21), which
 * wrote `float (*fn)(...)`: a measure callback returns BOTH a width and a height,
 * so a single-float return cannot express it. A struct return would drag a shared
 * type across the seam; an out-array keeps the seam to plain C scalars. `ctx` is
 * the opaque pointer supplied alongside the callback at registration time (the
 * AS3-side text object); the seam never inspects it. */
typedef void (*as_ui_measure_fn)(
    void* ctx,
    float available_width,
    int width_mode,   /* AS_UI_MEASURE_* */
    float available_height,
    int height_mode,  /* AS_UI_MEASURE_* */
    float out_wh[2]);

/* ------------------------------------------------------------------------- *
 * Config
 * ------------------------------------------------------------------------- */
/* Create a layout config. `point_scale` is the device-pixel grid factor:
 *   0.0  -> do not snap results to a pixel grid (raw floats; handy for tests)
 *   1.0  -> snap to whole pixels
 *   DPR  -> snap to that device grid
 * `use_web_defaults` != 0 selects the flexbox-on-the-web default style
 * (flex-direction: row, align-content: stretch, flex-shrink: 1, flex-basis:
 * auto for a positive `flex`), matching CSS/GPUI defaults; 0 keeps Yoga's
 * own defaults (column). Returns an opaque config handle, never NULL in
 * practice (falls back to the engine's shared default config on OOM). */
void* as_ui_yg_config_new(float point_scale, int use_web_defaults);

/* Free a config from as_ui_yg_config_new. NULL is a no-op. */
void as_ui_yg_config_free(void* cfg);

/* ------------------------------------------------------------------------- *
 * Node lifecycle
 * ------------------------------------------------------------------------- */
/* Create a node attached to `cfg` (NULL cfg -> engine default config). */
void* as_ui_yg_node_new(void* cfg);

/* Free ONE node (not its children) and any measure bookkeeping it owns.
 * The node must already have been removed from its parent. NULL is a no-op. */
void as_ui_yg_node_free(void* node);

/* Free a whole subtree rooted at `node` (children included) and all measure
 * bookkeeping. NULL is a no-op. */
void as_ui_yg_node_free_recursive(void* node);

/* Insert `child` at `index` under `parent` (index clamped to [0, childCount]).
 * Any NULL handle is a no-op. The seam does not own the child afterwards. */
void as_ui_yg_node_insert(void* parent, void* child, int index);

/* Remove `child` from `parent`. NULL handles are a no-op. */
void as_ui_yg_node_remove(void* parent, void* child);

/* ------------------------------------------------------------------------- *
 * Style setters (each maps onto ui-toolkit-api-design.md section 2.1 fields)
 * ------------------------------------------------------------------------- */
void as_ui_yg_set_flex_direction(void* node, int direction);        /* Style.flexDirection */
void as_ui_yg_set_flex_wrap(void* node, int wrap);                  /* Style.flexWrap */
void as_ui_yg_set_justify(void* node, int justify);                 /* Style.justifyContent */
void as_ui_yg_set_align_items(void* node, int align);               /* Style.alignItems */
void as_ui_yg_set_align_self(void* node, int align);                /* Style.alignSelf */
void as_ui_yg_set_align_content(void* node, int align);             /* Style.alignContent */

/* flexGrow / flexShrink / flexBasis in one call (the CSS `flex` shorthand).
 * `basis` uses the (value, unit) trichotomy. */
void as_ui_yg_set_flex(void* node, float grow, float shrink, float basis, int basis_unit);

/* width / height (axis = AS_UI_AXIS_*) as a (value, unit) length. */
void as_ui_yg_set_size(void* node, int axis, float value, int unit);

/* min- or max- width/height. `is_max` != 0 selects max. */
void as_ui_yg_set_minmax(void* node, int axis, int is_max, float value, int unit);

/* margin (Length: point / percent / auto) on one edge or an axis shorthand. */
void as_ui_yg_set_margin(void* node, int edge, float value, int unit);

/* padding (DefiniteLength: point / percent) on one edge or an axis shorthand. */
void as_ui_yg_set_padding(void* node, int edge, float value, int unit);

/* border width (AbsoluteLength: points only) on one edge or an axis shorthand. */
void as_ui_yg_set_border(void* node, int edge, float value);

/* gap (DefiniteLength) for column / row / all gutters. */
void as_ui_yg_set_gap(void* node, int gutter, float value, int unit);

/* inset (top/right/bottom/left) as a Length; only meaningful with
 * AS_UI_POSITION_ABSOLUTE (or relative for an offset). */
void as_ui_yg_set_position(void* node, int edge, float value, int unit);

/* Style.position */
void as_ui_yg_set_position_type(void* node, int position_type);

/* Style.display (flex / none / contents / grid). */
void as_ui_yg_set_display(void* node, int display);

/* Style.overflowX / overflowY collapsed to the single value Yoga keeps. */
void as_ui_yg_set_overflow(void* node, int overflow);

/* Style.aspectRatio; value <= 0 clears it (design uses NaN = "unset"). */
void as_ui_yg_set_aspect_ratio(void* node, float ratio);

/* The reference frame for size/padding/border. Default is border-box. */
void as_ui_yg_set_box_sizing(void* node, int box_sizing);

/* ------------------------------------------------------------------------- *
 * Measure callback registration
 * ------------------------------------------------------------------------- */
/* Register an intrinsic-size callback on a leaf node (text/images).
 * The node must have no children. `fn`/`ctx` may be NULL to clear it. */
void as_ui_yg_set_measure(void* node, as_ui_measure_fn fn, void* ctx);

/* ------------------------------------------------------------------------- *
 * Compute / query
 * ------------------------------------------------------------------------- */
/* Run a layout pass on the tree rooted at `node`, given the available space and
 * the owner direction. Reads results via as_ui_yg_layout_get. */
void as_ui_yg_calculate(void* node, float available_width, float available_height, int direction);

/* Force a node dirty so the next as_ui_yg_calculate re-lays it out. */
void as_ui_yg_set_dirty(void* node);

/* Read the computed rectangle of `node` RELATIVE TO ITS PARENT into
 * out[0]=left, out[1]=top, out[2]=width, out[3]=height. For a NULL node (or a
 * node never laid out) all four are set to 0. */
void as_ui_yg_layout_get(const void* node, float out[4]);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* AS_UI_YOGA_GLUE_H */

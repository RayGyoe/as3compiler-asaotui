// yoga_glue.cc -- implementation of the ONE opaque seam between `asaot.ui` and
// the flexbox layout engine (Yoga). U1 prototype.
//
// This file is the ONLY place in the whole U1 layout path that includes
// <yoga/Yoga.h> or names any Yoga type. Everything the C side (and thus the
// generated C / the AS3-side LayoutEngine) sees is declared in yoga_glue.h as a
// `void*` handle plus our own frozen enum constants and scalars. If you need to
// reach for a Yoga symbol somewhere else, the seam is being violated.
//
// Responsibilities, in one breath: (1) turn our frozen enum values into Yoga's
// enums with an explicit switch so a Yoga enum reorder cannot silently change
// meaning; (2) carry the length trichotomy as Yoga already does, a (value, unit)
// pair; (3) never dereference a NULL handle; (4) own the small pieces of state
// Yoga does not free for us (the measure-callback registration, held in the
// node's user context).
//
// Precedent: vendor/sqlite_glue.c (single file, `as_sql_*`, plain C types) and
// vendor/skila_text_glue.cc (the 15-function opaque text seam, see
// docs/zh-cn/rust-text-backend.md section 1.1).

#include "yoga_glue.h"

#include <yoga/Yoga.h>

#include <stdlib.h>

// ---------------------------------------------------------------------------
// Our frozen enum -> Yoga enum. Every switch has a safe `default` that picks
// the engine's own default, so an out-of-range int from a corrupted AS3 side
// degrades to a sane layout instead of reading past an enum.
// ---------------------------------------------------------------------------
namespace {

YGFlexDirection mapFlexDirection(int d) {
  switch (d) {
    case AS_UI_FLEX_DIR_COLUMN: return YGFlexDirectionColumn;
    case AS_UI_FLEX_DIR_COLUMN_REVERSE: return YGFlexDirectionColumnReverse;
    case AS_UI_FLEX_DIR_ROW: return YGFlexDirectionRow;
    case AS_UI_FLEX_DIR_ROW_REVERSE: return YGFlexDirectionRowReverse;
    default: return YGFlexDirectionColumn;
  }
}

YGWrap mapWrap(int w) {
  switch (w) {
    case AS_UI_WRAP_NO_WRAP: return YGWrapNoWrap;
    case AS_UI_WRAP_WRAP: return YGWrapWrap;
    case AS_UI_WRAP_WRAP_REVERSE: return YGWrapWrapReverse;
    default: return YGWrapNoWrap;
  }
}

YGAlign mapAlign(int a) {
  switch (a) {
    case AS_UI_ALIGN_AUTO: return YGAlignAuto;
    case AS_UI_ALIGN_FLEX_START: return YGAlignFlexStart;
    case AS_UI_ALIGN_CENTER: return YGAlignCenter;
    case AS_UI_ALIGN_FLEX_END: return YGAlignFlexEnd;
    case AS_UI_ALIGN_STRETCH: return YGAlignStretch;
    case AS_UI_ALIGN_BASELINE: return YGAlignBaseline;
    case AS_UI_ALIGN_SPACE_BETWEEN: return YGAlignSpaceBetween;
    case AS_UI_ALIGN_SPACE_AROUND: return YGAlignSpaceAround;
    case AS_UI_ALIGN_SPACE_EVENLY: return YGAlignSpaceEvenly;
    case AS_UI_ALIGN_START: return YGAlignStart;
    case AS_UI_ALIGN_END: return YGAlignEnd;
    default: return YGAlignAuto;
  }
}

YGJustify mapJustify(int j) {
  switch (j) {
    case AS_UI_JUSTIFY_AUTO: return YGJustifyAuto;
    case AS_UI_JUSTIFY_FLEX_START: return YGJustifyFlexStart;
    case AS_UI_JUSTIFY_CENTER: return YGJustifyCenter;
    case AS_UI_JUSTIFY_FLEX_END: return YGJustifyFlexEnd;
    case AS_UI_JUSTIFY_SPACE_BETWEEN: return YGJustifySpaceBetween;
    case AS_UI_JUSTIFY_SPACE_AROUND: return YGJustifySpaceAround;
    case AS_UI_JUSTIFY_SPACE_EVENLY: return YGJustifySpaceEvenly;
    case AS_UI_JUSTIFY_STRETCH: return YGJustifyStretch;
    case AS_UI_JUSTIFY_START: return YGJustifyStart;
    case AS_UI_JUSTIFY_END: return YGJustifyEnd;
    default: return YGJustifyFlexStart;
  }
}

YGEdge mapEdge(int e) {
  switch (e) {
    case AS_UI_EDGE_LEFT: return YGEdgeLeft;
    case AS_UI_EDGE_TOP: return YGEdgeTop;
    case AS_UI_EDGE_RIGHT: return YGEdgeRight;
    case AS_UI_EDGE_BOTTOM: return YGEdgeBottom;
    case AS_UI_EDGE_START: return YGEdgeStart;
    case AS_UI_EDGE_END: return YGEdgeEnd;
    case AS_UI_EDGE_HORIZONTAL: return YGEdgeHorizontal;
    case AS_UI_EDGE_VERTICAL: return YGEdgeVertical;
    case AS_UI_EDGE_ALL: return YGEdgeAll;
    default: return YGEdgeAll;
  }
}

YGGutter mapGutter(int g) {
  switch (g) {
    case AS_UI_GUTTER_COLUMN: return YGGutterColumn;
    case AS_UI_GUTTER_ROW: return YGGutterRow;
    case AS_UI_GUTTER_ALL: return YGGutterAll;
    default: return YGGutterAll;
  }
}

YGDirection mapDirection(int d) {
  switch (d) {
    case AS_UI_DIR_INHERIT: return YGDirectionInherit;
    case AS_UI_DIR_LTR: return YGDirectionLTR;
    case AS_UI_DIR_RTL: return YGDirectionRTL;
    default: return YGDirectionLTR;
  }
}

YGDisplay mapDisplay(int d) {
  switch (d) {
    case AS_UI_DISPLAY_FLEX: return YGDisplayFlex;
    case AS_UI_DISPLAY_NONE: return YGDisplayNone;
    case AS_UI_DISPLAY_CONTENTS: return YGDisplayContents;
    case AS_UI_DISPLAY_GRID: return YGDisplayGrid;
    default: return YGDisplayFlex;
  }
}

YGPositionType mapPositionType(int p) {
  switch (p) {
    case AS_UI_POSITION_STATIC: return YGPositionTypeStatic;
    case AS_UI_POSITION_RELATIVE: return YGPositionTypeRelative;
    case AS_UI_POSITION_ABSOLUTE: return YGPositionTypeAbsolute;
    default: return YGPositionTypeRelative;
  }
}

YGOverflow mapOverflow(int o) {
  switch (o) {
    case AS_UI_OVERFLOW_VISIBLE: return YGOverflowVisible;
    case AS_UI_OVERFLOW_HIDDEN: return YGOverflowHidden;
    case AS_UI_OVERFLOW_SCROLL: return YGOverflowScroll;
    default: return YGOverflowVisible;
  }
}

YGBoxSizing mapBoxSizing(int b) {
  switch (b) {
    case AS_UI_BOX_SIZING_BORDER_BOX: return YGBoxSizingBorderBox;
    case AS_UI_BOX_SIZING_CONTENT_BOX: return YGBoxSizingContentBox;
    default: return YGBoxSizingBorderBox;
  }
}

int mapMeasureMode(YGMeasureMode m) {
  switch (m) {
    case YGMeasureModeUndefined: return AS_UI_MEASURE_UNDEFINED;
    case YGMeasureModeExactly: return AS_UI_MEASURE_EXACTLY;
    case YGMeasureModeAtMost: return AS_UI_MEASURE_AT_MOST;
    default: return AS_UI_MEASURE_UNDEFINED;
  }
}

// ---------------------------------------------------------------------------
// Measure-callback bookkeeping.
//
// Yoga delivers a measure call as a bare function pointer plus the *node*, and
// exposes one user-data slot per node (YGNodeSetContext). We need BOTH the
// caller's function and the caller's opaque `ctx` to be reachable from the node,
// so we allocate one tiny record per measured node and park it in that slot.
//
// This is one heap allocation per text/image node at STRUCTURAL time (node
// creation / measure registration), never on the layout hot path and never per
// frame, so it does not violate the zero-per-frame-allocation rule of
// ui-toolkit-api-design.md section 7. It is owned solely by this file: the C
// side never sets a Yoga node context, so we can free it ourselves in
// node_free / node_free_recursive without guessing who owns the pointer.
// ---------------------------------------------------------------------------
struct AsUiMeasureEntry {
  as_ui_measure_fn fn;
  void* ctx;
};

YGSize ygMeasureBridge(
    const YGNode* node,
    float availableWidth,
    YGMeasureMode widthMode,
    float availableHeight,
    YGMeasureMode heightMode) {
  AsUiMeasureEntry* entry =
      static_cast<AsUiMeasureEntry*>(YGNodeGetContext(node));
  YGSize size;
  size.width = 0.0f;
  size.height = 0.0f;
  if (entry != nullptr && entry->fn != nullptr) {
    float out[2];
    out[0] = 0.0f;
    out[1] = 0.0f;
    entry->fn(
        entry->ctx,
        availableWidth,
        mapMeasureMode(widthMode),
        availableHeight,
        mapMeasureMode(heightMode),
        out);
    size.width = out[0];
    size.height = out[1];
  }
  return size;
}

// Free a node's measure record (if any) and clear the context slot.
void freeMeasureEntry(const YGNode* node) {
  void* ctx = YGNodeGetContext(node);
  if (ctx != nullptr) {
    free(ctx);
    YGNodeSetContext(const_cast<YGNode*>(node), nullptr);
  }
}

// Free measure records for a whole subtree, children first. Used by
// as_ui_yg_node_free_recursive: YGNodeFreeRecursive deletes the Yoga nodes but
// knows nothing about our records, so we must walk the tree ourselves first.
void freeMeasureEntriesRecursive(YGNode* node) {
  const size_t count = YGNodeGetChildCount(node);
  for (size_t i = 0; i < count; i++) {
    freeMeasureEntriesRecursive(YGNodeGetChild(node, i));
  }
  freeMeasureEntry(node);
}

}  // namespace

extern "C" {

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------
void* as_ui_yg_config_new(float point_scale, int use_web_defaults) {
  YGConfigRef config = YGConfigNew();
  if (config == nullptr) {
    return nullptr;
  }
  // Web defaults = flexbox-as-CSS defaults (flex-direction: row, align-content:
  // stretch, flex-shrink: 1, flex-basis: auto for a positive `flex`). The
  // api-design doc's Style default flexDirection is "row" (matching GPUI
  // crates/gpui/src/style.rs, whose `Default for Style` is FlexDirection::Row),
  // so a UI toolkit should ask for web defaults.
  YGConfigSetUseWebDefaults(config, use_web_defaults != 0);
  // point_scale == 0 disables pixel-grid snapping; that is the honest setting
  // for a layout test that wants raw floats. The real backend would pass the
  // window DPR here.
  YGConfigSetPointScaleFactor(config, point_scale);
  return static_cast<void*>(config);
}

void as_ui_yg_config_free(void* cfg) {
  if (cfg != nullptr) {
    YGConfigFree(static_cast<YGConfigRef>(cfg));
  }
}

// ---------------------------------------------------------------------------
// Node lifecycle
// ---------------------------------------------------------------------------
void* as_ui_yg_node_new(void* cfg) {
  YGNodeRef node;
  if (cfg != nullptr) {
    node = YGNodeNewWithConfig(static_cast<YGConfigRef>(cfg));
  } else {
    node = YGNodeNew();
  }
  return static_cast<void*>(node);
}

void as_ui_yg_node_free(void* node) {
  if (node == nullptr) {
    return;
  }
  freeMeasureEntry(static_cast<YGNode*>(node));
  YGNodeFree(static_cast<YGNodeRef>(node));
}

void as_ui_yg_node_free_recursive(void* node) {
  if (node == nullptr) {
    return;
  }
  // Yoga does not release our measure records; walk first, then let Yoga free
  // the nodes.
  freeMeasureEntriesRecursive(static_cast<YGNode*>(node));
  YGNodeFreeRecursive(static_cast<YGNodeRef>(node));
}

void as_ui_yg_node_insert(void* parent, void* child, int index) {
  if (parent == nullptr || child == nullptr) {
    return;
  }
  YGNodeRef p = static_cast<YGNodeRef>(parent);
  const size_t count = YGNodeGetChildCount(p);
  size_t at = (index < 0) ? 0 : static_cast<size_t>(index);
  if (at > count) {
    at = count;  // clamp instead of letting Yoga's assert fire
  }
  YGNodeInsertChild(p, static_cast<YGNodeRef>(child), at);
}

void as_ui_yg_node_remove(void* parent, void* child) {
  if (parent == nullptr || child == nullptr) {
    return;
  }
  YGNodeRemoveChild(
      static_cast<YGNodeRef>(parent), static_cast<YGNodeRef>(child));
}

// ---------------------------------------------------------------------------
// Style setters
// ---------------------------------------------------------------------------
void as_ui_yg_set_flex_direction(void* node, int direction) {
  if (node != nullptr) {
    YGNodeStyleSetFlexDirection(
        static_cast<YGNodeRef>(node), mapFlexDirection(direction));
  }
}

void as_ui_yg_set_flex_wrap(void* node, int wrap) {
  if (node != nullptr) {
    YGNodeStyleSetFlexWrap(static_cast<YGNodeRef>(node), mapWrap(wrap));
  }
}

void as_ui_yg_set_justify(void* node, int justify) {
  if (node != nullptr) {
    YGNodeStyleSetJustifyContent(
        static_cast<YGNodeRef>(node), mapJustify(justify));
  }
}

void as_ui_yg_set_align_items(void* node, int align) {
  if (node != nullptr) {
    YGNodeStyleSetAlignItems(static_cast<YGNodeRef>(node), mapAlign(align));
  }
}

void as_ui_yg_set_align_self(void* node, int align) {
  if (node != nullptr) {
    YGNodeStyleSetAlignSelf(static_cast<YGNodeRef>(node), mapAlign(align));
  }
}

void as_ui_yg_set_align_content(void* node, int align) {
  if (node != nullptr) {
    YGNodeStyleSetAlignContent(static_cast<YGNodeRef>(node), mapAlign(align));
  }
}

void as_ui_yg_set_flex(
    void* node, float grow, float shrink, float basis, int basis_unit) {
  if (node == nullptr) {
    return;
  }
  YGNodeRef n = static_cast<YGNodeRef>(node);
  YGNodeStyleSetFlexGrow(n, grow);
  YGNodeStyleSetFlexShrink(n, shrink);
  switch (basis_unit) {
    case AS_UI_UNIT_POINT:
      YGNodeStyleSetFlexBasis(n, basis);
      break;
    case AS_UI_UNIT_PERCENT:
      YGNodeStyleSetFlexBasisPercent(n, basis);
      break;
    case AS_UI_UNIT_AUTO:
      YGNodeStyleSetFlexBasisAuto(n);
      break;
    case AS_UI_UNIT_MAX_CONTENT:
      YGNodeStyleSetFlexBasisMaxContent(n);
      break;
    case AS_UI_UNIT_FIT_CONTENT:
      YGNodeStyleSetFlexBasisFitContent(n);
      break;
    case AS_UI_UNIT_STRETCH:
      YGNodeStyleSetFlexBasisStretch(n);
      break;
    case AS_UI_UNIT_UNDEFINED:
    default:
      // points(NaN) => undefined, i.e. reset to the engine default.
      YGNodeStyleSetFlexBasis(n, YGUndefined);
      break;
  }
}

namespace {
// Which of the three width/height properties we are writing. Plain `size`,
// `min-size` and `max-size` are three DISTINCT Yoga accessor families; sharing
// one "isMax" flag between size and min was a bug caught by case e (min-width
// was silently written as width). Keep them separate.
enum SizeSlot { SLOT_SIZE = 0, SLOT_MIN = 1, SLOT_MAX = 2 };

void applySizeUnit(
    YGNodeRef n, bool isWidth, SizeSlot slot, float value, int unit) {
  switch (unit) {
    case AS_UI_UNIT_POINT:
      if (isWidth) {
        if (slot == SLOT_MAX) YGNodeStyleSetMaxWidth(n, value);
        else if (slot == SLOT_MIN) YGNodeStyleSetMinWidth(n, value);
        else YGNodeStyleSetWidth(n, value);
      } else {
        if (slot == SLOT_MAX) YGNodeStyleSetMaxHeight(n, value);
        else if (slot == SLOT_MIN) YGNodeStyleSetMinHeight(n, value);
        else YGNodeStyleSetHeight(n, value);
      }
      break;
    case AS_UI_UNIT_PERCENT:
      if (isWidth) {
        if (slot == SLOT_MAX) YGNodeStyleSetMaxWidthPercent(n, value);
        else if (slot == SLOT_MIN) YGNodeStyleSetMinWidthPercent(n, value);
        else YGNodeStyleSetWidthPercent(n, value);
      } else {
        if (slot == SLOT_MAX) YGNodeStyleSetMaxHeightPercent(n, value);
        else if (slot == SLOT_MIN) YGNodeStyleSetMinHeightPercent(n, value);
        else YGNodeStyleSetHeightPercent(n, value);
      }
      break;
    case AS_UI_UNIT_AUTO:
      // Only width/height accept `auto`; min/max have no auto keyword.
      if (slot == SLOT_SIZE) {
        if (isWidth) YGNodeStyleSetWidthAuto(n);
        else YGNodeStyleSetHeightAuto(n);
      } else if (isWidth) {
        if (slot == SLOT_MAX) YGNodeStyleSetMaxWidth(n, YGUndefined);
        else YGNodeStyleSetMinWidth(n, YGUndefined);
      } else {
        if (slot == SLOT_MAX) YGNodeStyleSetMaxHeight(n, YGUndefined);
        else YGNodeStyleSetMinHeight(n, YGUndefined);
      }
      break;
    case AS_UI_UNIT_MAX_CONTENT:
      if (isWidth) {
        if (slot == SLOT_MAX) YGNodeStyleSetMaxWidthMaxContent(n);
        else if (slot == SLOT_MIN) YGNodeStyleSetMinWidthMaxContent(n);
        else YGNodeStyleSetWidthMaxContent(n);
      } else {
        if (slot == SLOT_MAX) YGNodeStyleSetMaxHeightMaxContent(n);
        else if (slot == SLOT_MIN) YGNodeStyleSetMinHeightMaxContent(n);
        else YGNodeStyleSetHeightMaxContent(n);
      }
      break;
    case AS_UI_UNIT_FIT_CONTENT:
      if (isWidth) {
        if (slot == SLOT_MAX) YGNodeStyleSetMaxWidthFitContent(n);
        else if (slot == SLOT_MIN) YGNodeStyleSetMinWidthFitContent(n);
        else YGNodeStyleSetWidthFitContent(n);
      } else {
        if (slot == SLOT_MAX) YGNodeStyleSetMaxHeightFitContent(n);
        else if (slot == SLOT_MIN) YGNodeStyleSetMinHeightFitContent(n);
        else YGNodeStyleSetHeightFitContent(n);
      }
      break;
    case AS_UI_UNIT_STRETCH:
      if (isWidth) {
        if (slot == SLOT_MAX) YGNodeStyleSetMaxWidthStretch(n);
        else if (slot == SLOT_MIN) YGNodeStyleSetMinWidthStretch(n);
        else YGNodeStyleSetWidthStretch(n);
      } else {
        if (slot == SLOT_MAX) YGNodeStyleSetMaxHeightStretch(n);
        else if (slot == SLOT_MIN) YGNodeStyleSetMinHeightStretch(n);
        else YGNodeStyleSetHeightStretch(n);
      }
      break;
    case AS_UI_UNIT_UNDEFINED:
    default:
      // points(NaN) => undefined, i.e. reset the property.
      if (isWidth) {
        if (slot == SLOT_MAX) YGNodeStyleSetMaxWidth(n, YGUndefined);
        else if (slot == SLOT_MIN) YGNodeStyleSetMinWidth(n, YGUndefined);
        else YGNodeStyleSetWidth(n, YGUndefined);
      } else {
        if (slot == SLOT_MAX) YGNodeStyleSetMaxHeight(n, YGUndefined);
        else if (slot == SLOT_MIN) YGNodeStyleSetMinHeight(n, YGUndefined);
        else YGNodeStyleSetHeight(n, YGUndefined);
      }
      break;
  }
}
}  // namespace

void as_ui_yg_set_size(void* node, int axis, float value, int unit) {
  if (node == nullptr) {
    return;
  }
  applySizeUnit(
      static_cast<YGNodeRef>(node),
      axis == AS_UI_AXIS_WIDTH,
      SLOT_SIZE,
      value,
      unit);
}

void as_ui_yg_set_minmax(void* node, int axis, int is_max, float value, int unit) {
  if (node == nullptr) {
    return;
  }
  applySizeUnit(
      static_cast<YGNodeRef>(node),
      axis == AS_UI_AXIS_WIDTH,
      is_max != 0 ? SLOT_MAX : SLOT_MIN,
      value,
      unit);
}

void as_ui_yg_set_margin(void* node, int edge, float value, int unit) {
  if (node == nullptr) {
    return;
  }
  YGNodeRef n = static_cast<YGNodeRef>(node);
  YGEdge e = mapEdge(edge);
  switch (unit) {
    case AS_UI_UNIT_POINT:
      YGNodeStyleSetMargin(n, e, value);
      break;
    case AS_UI_UNIT_PERCENT:
      YGNodeStyleSetMarginPercent(n, e, value);
      break;
    case AS_UI_UNIT_AUTO:
      YGNodeStyleSetMarginAuto(n, e);
      break;
    case AS_UI_UNIT_UNDEFINED:
    default:
      YGNodeStyleSetMargin(n, e, YGUndefined);
      break;
  }
}

void as_ui_yg_set_padding(void* node, int edge, float value, int unit) {
  if (node == nullptr) {
    return;
  }
  YGNodeRef n = static_cast<YGNodeRef>(node);
  YGEdge e = mapEdge(edge);
  switch (unit) {
    case AS_UI_UNIT_POINT:
      YGNodeStyleSetPadding(n, e, value);
      break;
    case AS_UI_UNIT_PERCENT:
      YGNodeStyleSetPaddingPercent(n, e, value);
      break;
    case AS_UI_UNIT_UNDEFINED:
    default:
      YGNodeStyleSetPadding(n, e, YGUndefined);
      break;
  }
}

void as_ui_yg_set_border(void* node, int edge, float value) {
  if (node != nullptr) {
    YGNodeStyleSetBorder(static_cast<YGNodeRef>(node), mapEdge(edge), value);
  }
}

void as_ui_yg_set_gap(void* node, int gutter, float value, int unit) {
  if (node == nullptr) {
    return;
  }
  YGNodeRef n = static_cast<YGNodeRef>(node);
  YGGutter g = mapGutter(gutter);
  switch (unit) {
    case AS_UI_UNIT_POINT:
      YGNodeStyleSetGap(n, g, value);
      break;
    case AS_UI_UNIT_PERCENT:
      YGNodeStyleSetGapPercent(n, g, value);
      break;
    case AS_UI_UNIT_UNDEFINED:
    default:
      YGNodeStyleSetGap(n, g, YGUndefined);
      break;
  }
}

void as_ui_yg_set_position(void* node, int edge, float value, int unit) {
  if (node == nullptr) {
    return;
  }
  YGNodeRef n = static_cast<YGNodeRef>(node);
  YGEdge e = mapEdge(edge);
  switch (unit) {
    case AS_UI_UNIT_POINT:
      YGNodeStyleSetPosition(n, e, value);
      break;
    case AS_UI_UNIT_PERCENT:
      YGNodeStyleSetPositionPercent(n, e, value);
      break;
    case AS_UI_UNIT_AUTO:
      YGNodeStyleSetPositionAuto(n, e);
      break;
    case AS_UI_UNIT_UNDEFINED:
    default:
      YGNodeStyleSetPosition(n, e, YGUndefined);
      break;
  }
}

void as_ui_yg_set_position_type(void* node, int position_type) {
  if (node != nullptr) {
    YGNodeStyleSetPositionType(
        static_cast<YGNodeRef>(node), mapPositionType(position_type));
  }
}

void as_ui_yg_set_display(void* node, int display) {
  if (node != nullptr) {
    YGNodeStyleSetDisplay(static_cast<YGNodeRef>(node), mapDisplay(display));
  }
}

void as_ui_yg_set_overflow(void* node, int overflow) {
  if (node != nullptr) {
    YGNodeStyleSetOverflow(static_cast<YGNodeRef>(node), mapOverflow(overflow));
  }
}

void as_ui_yg_set_aspect_ratio(void* node, float ratio) {
  if (node == nullptr) {
    return;
  }
  // The design spells "unset" as NaN (ui-toolkit-api-design.md section 2.1);
  // Yoga also treats NaN as unset, so pass it straight through.
  YGNodeStyleSetAspectRatio(static_cast<YGNodeRef>(node), ratio);
}

void as_ui_yg_set_box_sizing(void* node, int box_sizing) {
  if (node != nullptr) {
    YGNodeStyleSetBoxSizing(
        static_cast<YGNodeRef>(node), mapBoxSizing(box_sizing));
  }
}

// ---------------------------------------------------------------------------
// Measure callback registration
// ---------------------------------------------------------------------------
void as_ui_yg_set_measure(void* node, as_ui_measure_fn fn, void* ctx) {
  if (node == nullptr) {
    return;
  }
  YGNodeRef n = static_cast<YGNodeRef>(node);
  if (fn == nullptr) {
    // Clear. YGNodeSetMeasureFunc(nullptr) also resets the node type to Default,
    // so reclaim our record too.
    YGNodeSetMeasureFunc(n, nullptr);
    freeMeasureEntry(n);
    return;
  }
  if (YGNodeGetChildCount(n) != 0) {
    // Yoga aborts (assertFatal) on a measure node with children; guarding here
    // keeps a mis-built tree from taking the process down.
    return;
  }
  AsUiMeasureEntry* entry =
      static_cast<AsUiMeasureEntry*>(YGNodeGetContext(n));
  if (entry == nullptr) {
    entry = static_cast<AsUiMeasureEntry*>(malloc(sizeof(AsUiMeasureEntry)));
    if (entry == nullptr) {
      return;  // OOM: leave the node unmeasured rather than crash
    }
    YGNodeSetContext(n, entry);
  }
  entry->fn = fn;
  entry->ctx = ctx;
  YGNodeSetMeasureFunc(n, ygMeasureBridge);
}

// ---------------------------------------------------------------------------
// Compute / query
// ---------------------------------------------------------------------------
void as_ui_yg_calculate(
    void* node, float available_width, float available_height, int direction) {
  if (node == nullptr) {
    return;
  }
  YGNodeCalculateLayout(
      static_cast<YGNodeRef>(node),
      available_width,
      available_height,
      mapDirection(direction));
}

void as_ui_yg_set_dirty(void* node) {
  if (node != nullptr) {
    YGNodeMarkDirty(static_cast<YGNodeRef>(node));
  }
}

void as_ui_yg_layout_get(const void* node, float out[4]) {
  if (out == nullptr) {
    return;
  }
  if (node == nullptr) {
    out[0] = out[1] = out[2] = out[3] = 0.0f;
    return;
  }
  YGNodeConstRef n = static_cast<YGNodeConstRef>(node);
  out[0] = YGNodeLayoutGetLeft(n);
  out[1] = YGNodeLayoutGetTop(n);
  out[2] = YGNodeLayoutGetWidth(n);
  out[3] = YGNodeLayoutGetHeight(n);
}

}  // extern "C"

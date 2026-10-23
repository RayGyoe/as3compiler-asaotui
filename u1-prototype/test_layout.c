/* test_layout.c -- U1 acceptance test for the yoga_glue seam.
 *
 * Pure C, no test framework. Each case builds ONE tree, runs one layout pass,
 * and checks the computed rectangles against values that are HAND-COMPUTED in
 * the comment above the case (the formula is written out, not just a number).
 *
 * Contract (from ui-toolkit-feasibility.md section 7, the U1 acceptance line):
 *   "the same tree under Yoga matches hand-computed rectangles item by item".
 *
 * Float tolerance: EPS = 0.01 (see below). Any mismatch is a FINDING, not
 * something to paper over -- if a value disagrees with the flexbox/CSS standard
 * we say so in check-layout.md and decide whether the hand-calc or the glue is
 * wrong. Do not widen EPS to make a case pass.
 *
 * Build + run: ./build.sh (native), or build.sh --wasm (emscripten).
 */

#include "yoga_glue.h"

#include <math.h>
#include <stdint.h>
#include <stdio.h>

/* EPS: layout values here are exact multiples of 1 or small fractions, but they
 * pass through `float` arithmetic (grow ratio 1/6, percent scaling, pixel-grid
 * rounding is disabled via point_scale=0). 0.01 is far below the smallest
 * meaningful difference in these cases (the smallest distinct value is 1.0),
 * yet comfortably above `float` round-off (~1e-5 relative). */
#define EPS 0.01f

static int g_checks = 0;
static int g_failures = 0;

static int nearly(float a, float b) { return fabsf(a - b) <= EPS; }

/* Check one rectangle (left, top, width, height) and print got vs want. */
static void check_rect(
    const char* label,
    const float got[4],
    float want_l,
    float want_t,
    float want_w,
    float want_h) {
  g_checks++;
  int ok = nearly(got[0], want_l) && nearly(got[1], want_t) &&
           nearly(got[2], want_w) && nearly(got[3], want_h);
  if (!ok) {
    g_failures++;
  }
  printf(
      "  %-10s got (l=%8.3f t=%8.3f w=%8.3f h=%8.3f)  want (l=%8.3f t=%8.3f "
      "w=%8.3f h=%8.3f)  %s\n",
      label,
      got[0],
      got[1],
      got[2],
      got[3],
      want_l,
      want_t,
      want_w,
      want_h,
      ok ? "OK" : "*** MISMATCH ***");
}

static void case_header(const char* title) { printf("\n=== %s ===\n", title); }

/* Layout config used by every case: no pixel-grid snapping (raw floats) and
 * web/flexbox defaults (flex-direction: row, align-content: stretch,
 * flex-shrink: 1). */
static void* make_config(void) { return as_ui_yg_config_new(0.0f, 1); }

/* ---- the fake text measurer (case f) -------------------------------------
 * Intrinsic size model: every character is 7 points wide, every line is 16
 * points tall. The character count is smuggled through the opaque `ctx` as an
 * integer (this mirrors how the real AS3 side would pass a text object). */
static void fake_text_measure(
    void* ctx, float aw, int wm, float ah, int hm, float out[2]) {
  (void)ah;
  (void)hm;
  const int len = (int)(intptr_t)ctx;
  const float char_w = 7.0f;
  const float line_h = 16.0f;
  const float text_w = (float)len * char_w;

  if (wm == AS_UI_MEASURE_UNDEFINED || aw <= 0.0f) {
    out[0] = text_w;   /* one line, full width */
    out[1] = line_h;
    return;
  }
  /* Width is bounded by the available width; lines = ceil(text_w / avail). */
  const float lines = (text_w > aw) ? (float)ceil((double)text_w / (double)aw) : 1.0f;
  out[0] = (text_w < aw) ? text_w : aw;
  out[1] = lines * line_h;
}

/* --------------------------------------------------------------------------
 * Case a -- single node with fixed width/height.
 *   Expected: a leaf with an explicit width/height is placed at the origin of
 *   its parent with exactly the size set (nothing else can influence it).
 *   want = (left 0, top 0, width 100, height 50).
 * ------------------------------------------------------------------------ */
static void case_a(void* cfg) {
  case_header("a) single node, fixed width=100 height=50");
  void* root = as_ui_yg_node_new(cfg);
  as_ui_yg_set_size(root, AS_UI_AXIS_WIDTH, 100.0f, AS_UI_UNIT_POINT);
  as_ui_yg_set_size(root, AS_UI_AXIS_HEIGHT, 50.0f, AS_UI_UNIT_POINT);

  as_ui_yg_calculate(root, 1000.0f, 1000.0f, AS_UI_DIR_LTR);

  float r[4];
  as_ui_yg_layout_get(root, r);
  check_rect("root", r, 0.0f, 0.0f, 100.0f, 50.0f);

  as_ui_yg_node_free_recursive(root);
}

/* --------------------------------------------------------------------------
 * Case b -- column container with padding + row-gap.
 *   root: flexDirection=column, width=200, height=300, padding=16 all edges,
 *         row-gap=10, align-items=flex-start.
 *   three children: width=100, height=40 each.
 *
 *   Hand calc (column = main axis is vertical):
 *     content box top    = padding-top  = 16
 *     content box left   = padding-left = 16
 *     child[i].top = 16 + i*(40 + gap)      // gap sits BETWEEN items only
 *     child[i].left = 16 (flex-start, width is explicit)
 *   => child0.top = 16
 *      child1.top = 16 + 40 + 10 = 66
 *      child2.top = 16 + 80 + 20 = 116
 *   root keeps its explicit 200x300 (content 120+2*16+2*10=172 < 268, no
 *   overflow, so root is exactly 200x300).
 * ------------------------------------------------------------------------ */
static void case_b(void* cfg) {
  case_header("b) column + padding(16) + row-gap(10), 3 children 100x40");
  void* root = as_ui_yg_node_new(cfg);
  as_ui_yg_set_flex_direction(root, AS_UI_FLEX_DIR_COLUMN);
  as_ui_yg_set_size(root, AS_UI_AXIS_WIDTH, 200.0f, AS_UI_UNIT_POINT);
  as_ui_yg_set_size(root, AS_UI_AXIS_HEIGHT, 300.0f, AS_UI_UNIT_POINT);
  as_ui_yg_set_padding(root, AS_UI_EDGE_ALL, 16.0f, AS_UI_UNIT_POINT);
  as_ui_yg_set_gap(root, AS_UI_GUTTER_ROW, 10.0f, AS_UI_UNIT_POINT);
  as_ui_yg_set_align_items(root, AS_UI_ALIGN_FLEX_START);

  void* child[3];
  for (int i = 0; i < 3; i++) {
    child[i] = as_ui_yg_node_new(cfg);
    as_ui_yg_set_size(child[i], AS_UI_AXIS_WIDTH, 100.0f, AS_UI_UNIT_POINT);
    as_ui_yg_set_size(child[i], AS_UI_AXIS_HEIGHT, 40.0f, AS_UI_UNIT_POINT);
    as_ui_yg_node_insert(root, child[i], i);
  }

  as_ui_yg_calculate(root, 1000.0f, 1000.0f, AS_UI_DIR_LTR);

  float r[4];
  as_ui_yg_layout_get(root, r);
  check_rect("root", r, 0.0f, 0.0f, 200.0f, 300.0f);
  as_ui_yg_layout_get(child[0], r);
  check_rect("child0", r, 16.0f, 16.0f, 100.0f, 40.0f);
  as_ui_yg_layout_get(child[1], r);
  check_rect("child1", r, 16.0f, 66.0f, 100.0f, 40.0f);
  as_ui_yg_layout_get(child[2], r);
  check_rect("child2", r, 16.0f, 116.0f, 100.0f, 40.0f);

  as_ui_yg_node_free_recursive(root);
}

/* --------------------------------------------------------------------------
 * Case c -- row container, three grow factors 1:2:3, flex-basis 0.
 *   root: flexDirection=row, width=300, height=100.
 *   children: flex-basis=0, grow = 1 / 2 / 3, height=100 (main axis = width).
 *
 *   Hand calc (all bases 0):
 *     free space = 300 - (0+0+0) = 300
 *     total grow = 1 + 2 + 3 = 6
 *     width[i]   = 300 * grow[i] / 6
 *     x[0] = 0
 *     x[1] = width[0] = 50
 *     x[2] = 50 + 100 = 150
 *   => (0,0,50,100), (50,0,100,100), (150,0,150,100)
 * ------------------------------------------------------------------------ */
static void case_c(void* cfg) {
  case_header("c) row + grow 1:2:3, basis 0, root 300x100");
  void* root = as_ui_yg_node_new(cfg);
  as_ui_yg_set_flex_direction(root, AS_UI_FLEX_DIR_ROW);
  as_ui_yg_set_size(root, AS_UI_AXIS_WIDTH, 300.0f, AS_UI_UNIT_POINT);
  as_ui_yg_set_size(root, AS_UI_AXIS_HEIGHT, 100.0f, AS_UI_UNIT_POINT);

  const float grow[3] = {1.0f, 2.0f, 3.0f};
  void* child[3];
  for (int i = 0; i < 3; i++) {
    child[i] = as_ui_yg_node_new(cfg);
    as_ui_yg_set_flex(child[i], grow[i], 1.0f, 0.0f, AS_UI_UNIT_POINT);
    as_ui_yg_set_size(child[i], AS_UI_AXIS_HEIGHT, 100.0f, AS_UI_UNIT_POINT);
    as_ui_yg_node_insert(root, child[i], i);
  }

  as_ui_yg_calculate(root, 1000.0f, 1000.0f, AS_UI_DIR_LTR);

  float r[4];
  as_ui_yg_layout_get(child[0], r);
  check_rect("child0", r, 0.0f, 0.0f, 50.0f, 100.0f);
  as_ui_yg_layout_get(child[1], r);
  check_rect("child1", r, 50.0f, 0.0f, 100.0f, 100.0f);
  as_ui_yg_layout_get(child[2], r);
  check_rect("child2", r, 150.0f, 0.0f, 150.0f, 100.0f);

  as_ui_yg_node_free_recursive(root);
}

/* --------------------------------------------------------------------------
 * Case d -- percentage width/height vs the parent's padding + border.
 *   root: width=200, height=100, padding=20 all, border=10 all,
 *         align-items=flex-start (so the child is NOT stretched).
 *   child: width=50%, height=50%.
 *
 *   THE QUESTION this case exists to answer empirically:
 *     is a percentage resolved against the parent's CONTENT box (inside
 *     padding+border, the CSS standard) or its BORDER box (the full 200x100)?
 *
 *   Web/CSS standard expectation:
 *     content box = 200 - 2*padding(20) - 2*border(10) = 200 - 40 - 20 = 140
 *     content box height = 100 - 40 - 20 = 40
 *     child width  = 50% * 140 = 70
 *     child height = 50% *  40 = 20
 *     child left   = border-left + padding-left = 10 + 20 = 30
 *     child top    = border-top  + padding-top  = 10 + 20 = 30
 *   => (30, 30, 70, 20).  If the engine instead used the border box it would
 *   report (30,30,100,50) -- see check-layout.md, this was MEASURED.
 *
 *   Note: Yoga's box-sizing default is BORDER-BOX (opposite of CSS's
 *   content-box default), which is why width=200 here is the border box.
 * ------------------------------------------------------------------------ */
static void case_d(void* cfg) {
  case_header("d) percent width/height vs parent padding(20)+border(10)");
  void* root = as_ui_yg_node_new(cfg);
  as_ui_yg_set_flex_direction(root, AS_UI_FLEX_DIR_COLUMN);
  as_ui_yg_set_size(root, AS_UI_AXIS_WIDTH, 200.0f, AS_UI_UNIT_POINT);
  as_ui_yg_set_size(root, AS_UI_AXIS_HEIGHT, 100.0f, AS_UI_UNIT_POINT);
  as_ui_yg_set_padding(root, AS_UI_EDGE_ALL, 20.0f, AS_UI_UNIT_POINT);
  as_ui_yg_set_border(root, AS_UI_EDGE_ALL, 10.0f);
  as_ui_yg_set_align_items(root, AS_UI_ALIGN_FLEX_START);

  void* child = as_ui_yg_node_new(cfg);
  as_ui_yg_set_size(child, AS_UI_AXIS_WIDTH, 50.0f, AS_UI_UNIT_PERCENT);
  as_ui_yg_set_size(child, AS_UI_AXIS_HEIGHT, 50.0f, AS_UI_UNIT_PERCENT);
  as_ui_yg_node_insert(root, child, 0);

  as_ui_yg_calculate(root, 1000.0f, 1000.0f, AS_UI_DIR_LTR);

  float r[4];
  as_ui_yg_layout_get(root, r);
  check_rect("root", r, 0.0f, 0.0f, 200.0f, 100.0f);
  as_ui_yg_layout_get(child, r);
  check_rect("child", r, 30.0f, 30.0f, 70.0f, 20.0f);

  as_ui_yg_node_free_recursive(root);
}

/* --------------------------------------------------------------------------
 * Case e -- min/max width clamping a flex length.
 *
 * e1) min-width wins over flex-shrink:
 *     root: row, width=100.
 *     child: flex-basis=200 (point), flex-shrink=1, min-width=150, height=50.
 *     Hand calc: the single item wants to shrink from 200 to 100 (the content
 *     width), but min-width=150 clamps it => width 150 (overflows the parent
 *     by 50).  want = (0,0,150,50).
 *
 * e2) max-width wins over flex-grow:
 *     root: row, width=300.
 *     child: flex-basis=100, flex-grow=1, max-width=150, height=50.
 *     Hand calc: free = 300-100 = 200, grow would take it to 300, but
 *     max-width=150 clamps it => width 150.  want = (0,0,150,50).
 * ------------------------------------------------------------------------ */
static void case_e(void* cfg) {
  case_header("e) min/max width clamp flex-basis (e1 min, e2 max)");

  /* e1 */
  {
    void* root = as_ui_yg_node_new(cfg);
    as_ui_yg_set_flex_direction(root, AS_UI_FLEX_DIR_ROW);
    as_ui_yg_set_size(root, AS_UI_AXIS_WIDTH, 100.0f, AS_UI_UNIT_POINT);
    void* child = as_ui_yg_node_new(cfg);
    as_ui_yg_set_flex(child, 0.0f, 1.0f, 200.0f, AS_UI_UNIT_POINT);
    as_ui_yg_set_minmax(child, AS_UI_AXIS_WIDTH, 0, 150.0f, AS_UI_UNIT_POINT);
    as_ui_yg_set_size(child, AS_UI_AXIS_HEIGHT, 50.0f, AS_UI_UNIT_POINT);
    as_ui_yg_node_insert(root, child, 0);

    as_ui_yg_calculate(root, 1000.0f, 1000.0f, AS_UI_DIR_LTR);
    float r[4];
    as_ui_yg_layout_get(child, r);
    check_rect("e1 child", r, 0.0f, 0.0f, 150.0f, 50.0f);
    as_ui_yg_node_free_recursive(root);
  }

  /* e2 */
  {
    void* root = as_ui_yg_node_new(cfg);
    as_ui_yg_set_flex_direction(root, AS_UI_FLEX_DIR_ROW);
    as_ui_yg_set_size(root, AS_UI_AXIS_WIDTH, 300.0f, AS_UI_UNIT_POINT);
    void* child = as_ui_yg_node_new(cfg);
    as_ui_yg_set_flex(child, 1.0f, 1.0f, 100.0f, AS_UI_UNIT_POINT);
    as_ui_yg_set_minmax(child, AS_UI_AXIS_WIDTH, 1, 150.0f, AS_UI_UNIT_POINT);
    as_ui_yg_set_size(child, AS_UI_AXIS_HEIGHT, 50.0f, AS_UI_UNIT_POINT);
    as_ui_yg_node_insert(root, child, 0);

    as_ui_yg_calculate(root, 1000.0f, 1000.0f, AS_UI_DIR_LTR);
    float r[4];
    as_ui_yg_layout_get(child, r);
    check_rect("e2 child", r, 0.0f, 0.0f, 150.0f, 50.0f);
    as_ui_yg_node_free_recursive(root);
  }
}

/* --------------------------------------------------------------------------
 * Case f -- measure callback (intrinsic size) driving text wrapping height.
 *   Fake text: width = chars * 7, line height = 16 (see fake_text_measure).
 *
 * f1) one line: root column width=100, align-items=flex-start, one text child
 *     of 10 chars (10*7 = 70 <= 100).
 *     measure(AtMost 100) => width 70, lines 1, height 16.
 *     root height is auto => content height = 16.
 *     want child = (0,0,70,16); root = (0,0,100,16).
 *
 * f2) wrapped: root column width=40, same 10-char text (70 > 40).
 *     measure(AtMost 40) => lines = ceil(70/40) = 2, width 40, height 32.
 *     want child = (0,0,40,32); root = (0,0,40,32).
 *
 * NOTE (measured finding, see check-layout.md): the available space passed to
 * calculate is the size the ROOT is stretched to when the root has no explicit
 * size on that axis. Passing (1000,1000) turns an auto-height root into 1000,
 * not into its content height. To observe intrinsic/content sizing we pass an
 * UNDEFINED (NaN) available box, which is exactly how a caller would ask the
 * engine to size the root to its content.
 * ------------------------------------------------------------------------ */
static void case_f(void* cfg) {
  case_header("f) measure callback: text wrap height (7pt/char, 16pt/line)");

  /* f1: 10 chars, fits in 100 -> 1 line */
  {
    void* root = as_ui_yg_node_new(cfg);
    as_ui_yg_set_flex_direction(root, AS_UI_FLEX_DIR_COLUMN);
    as_ui_yg_set_size(root, AS_UI_AXIS_WIDTH, 100.0f, AS_UI_UNIT_POINT);
    as_ui_yg_set_align_items(root, AS_UI_ALIGN_FLEX_START);
    void* text = as_ui_yg_node_new(cfg);
    as_ui_yg_set_measure(
        text, fake_text_measure, (void*)(intptr_t)10);
    as_ui_yg_node_insert(root, text, 0);

    as_ui_yg_calculate(root, NAN, NAN, AS_UI_DIR_LTR);
    float r[4];
    as_ui_yg_layout_get(root, r);
    check_rect("f1 root ", r, 0.0f, 0.0f, 100.0f, 16.0f);
    as_ui_yg_layout_get(text, r);
    check_rect("f1 text ", r, 0.0f, 0.0f, 70.0f, 16.0f);
    as_ui_yg_node_free_recursive(root);
  }

  /* f2: 10 chars, only 40 wide -> wraps to 2 lines */
  {
    void* root = as_ui_yg_node_new(cfg);
    as_ui_yg_set_flex_direction(root, AS_UI_FLEX_DIR_COLUMN);
    as_ui_yg_set_size(root, AS_UI_AXIS_WIDTH, 40.0f, AS_UI_UNIT_POINT);
    as_ui_yg_set_align_items(root, AS_UI_ALIGN_FLEX_START);
    void* text = as_ui_yg_node_new(cfg);
    as_ui_yg_set_measure(
        text, fake_text_measure, (void*)(intptr_t)10);
    as_ui_yg_node_insert(root, text, 0);

    as_ui_yg_calculate(root, NAN, NAN, AS_UI_DIR_LTR);
    float r[4];
    as_ui_yg_layout_get(root, r);
    check_rect("f2 root ", r, 0.0f, 0.0f, 40.0f, 32.0f);
    as_ui_yg_layout_get(text, r);
    check_rect("f2 text ", r, 0.0f, 0.0f, 40.0f, 32.0f);
    as_ui_yg_node_free_recursive(root);
  }
}

/* --------------------------------------------------------------------------
 * Case g (bonus) -- NULL-handle tolerance.
 *   The seam must never crash when handed a NULL node / config / callback,
 *   because AS3 lifetimes are not guaranteed. Every call here is a no-op or
 *   returns zeros; the process must reach the end.
 * ------------------------------------------------------------------------ */
static void case_g_null(void) {
  case_header("g) NULL-handle tolerance (must not crash)");
  as_ui_yg_config_free(NULL);
  as_ui_yg_node_free(NULL);
  as_ui_yg_node_free_recursive(NULL);
  as_ui_yg_node_insert(NULL, NULL, 3);
  as_ui_yg_node_remove(NULL, NULL);
  as_ui_yg_set_flex_direction(NULL, AS_UI_FLEX_DIR_ROW);
  as_ui_yg_set_size(NULL, AS_UI_AXIS_WIDTH, 10.0f, AS_UI_UNIT_POINT);
  as_ui_yg_set_padding(NULL, AS_UI_EDGE_ALL, 1.0f, AS_UI_UNIT_POINT);
  as_ui_yg_set_gap(NULL, AS_UI_GUTTER_ALL, 1.0f, AS_UI_UNIT_POINT);
  as_ui_yg_set_measure(NULL, fake_text_measure, NULL);
  as_ui_yg_calculate(NULL, 100.0f, 100.0f, AS_UI_DIR_LTR);
  as_ui_yg_set_dirty(NULL);
  void* node = as_ui_yg_node_new(NULL); /* NULL config -> engine default */
  as_ui_yg_set_measure(node, NULL, NULL); /* clear */
  float r[4];
  as_ui_yg_layout_get(NULL, r);
  g_checks++;
  int ok = nearly(r[0], 0.0f) && nearly(r[1], 0.0f) && nearly(r[2], 0.0f) &&
           nearly(r[3], 0.0f);
  if (!ok) g_failures++;
  printf("  layout_get(NULL) -> (%.1f,%.1f,%.1f,%.1f)  want zeros  %s\n",
         r[0], r[1], r[2], r[3], ok ? "OK" : "*** MISMATCH ***");
  as_ui_yg_node_free_recursive(node);
  printf("  survived all NULL calls  OK\n");
}

int main(void) {
  printf("U1 layout seam acceptance -- yoga_glue vs hand-computed rectangles\n");
  printf("tolerance EPS = %.3f, point_scale = 0 (no pixel snapping), web defaults\n",
         (double)EPS);

  void* cfg = make_config();

  case_a(cfg);
  case_b(cfg);
  case_c(cfg);
  case_d(cfg);
  case_e(cfg);
  case_f(cfg);
  case_g_null();

  as_ui_yg_config_free(cfg);

  printf("\n---- %d checks, %d failures ----\n", g_checks, g_failures);
  if (g_failures != 0) {
    printf("RESULT: FAIL\n");
    return 1;
  }
  printf("RESULT: PASS\n");
  return 0;
}

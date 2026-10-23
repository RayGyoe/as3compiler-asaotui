#include "yoga_glue.h"
#include <math.h>
#include <stdio.h>

static void show(const char* tag, void* n) {
  float r[4];
  as_ui_yg_layout_get(n, r);
  printf("%-22s w=%8.3f h=%8.3f (l=%.3f t=%.3f)\n", tag, r[2], r[3], r[0], r[1]);
}

int main(void) {
  void* cfg = as_ui_yg_config_new(0.0f, 1);

  /* e-variants: min-width vs flex-shrink */
  for (int variant = 0; variant < 5; variant++) {
    void* root = as_ui_yg_node_new(cfg);
    as_ui_yg_set_flex_direction(root, AS_UI_FLEX_DIR_ROW);
    as_ui_yg_set_size(root, AS_UI_AXIS_WIDTH, 100.0f, AS_UI_UNIT_POINT);
    void* c = as_ui_yg_node_new(cfg);
    as_ui_yg_set_size(c, AS_UI_AXIS_HEIGHT, 50.0f, AS_UI_UNIT_POINT);
    as_ui_yg_set_minmax(c, AS_UI_AXIS_WIDTH, 0, 150.0f, AS_UI_UNIT_POINT);
    char tag[64];
    switch (variant) {
      case 0: /* flexBasis 200 shrink 1 */
        as_ui_yg_set_flex(c, 0.0f, 1.0f, 200.0f, AS_UI_UNIT_POINT);
        snprintf(tag, sizeof tag, "basis200 shrink1 min150"); break;
      case 1: /* explicit width 200 shrink 1 */
        as_ui_yg_set_size(c, AS_UI_AXIS_WIDTH, 200.0f, AS_UI_UNIT_POINT);
        as_ui_yg_set_flex(c, 0.0f, 1.0f, 200.0f, AS_UI_UNIT_POINT);
        snprintf(tag, sizeof tag, "width200 shrink1 min150"); break;
      case 2: /* no shrink, min only */
        as_ui_yg_set_size(c, AS_UI_AXIS_WIDTH, 200.0f, AS_UI_UNIT_POINT);
        as_ui_yg_set_flex(c, 0.0f, 0.0f, 200.0f, AS_UI_UNIT_POINT);
        snprintf(tag, sizeof tag, "width200 shrink0 min150"); break;
      case 3: /* explicit width 100 with min150 */
        as_ui_yg_set_size(c, AS_UI_AXIS_WIDTH, 100.0f, AS_UI_UNIT_POINT);
        as_ui_yg_set_flex(c, 0.0f, 0.0f, 100.0f, AS_UI_UNIT_POINT);
        snprintf(tag, sizeof tag, "width100 min150"); break;
      case 4: /* basis 200 shrink 1 min150, roomy parent */
        as_ui_yg_set_size(root, AS_UI_AXIS_WIDTH, 500.0f, AS_UI_UNIT_POINT);
        as_ui_yg_set_flex(c, 0.0f, 1.0f, 200.0f, AS_UI_UNIT_POINT);
        snprintf(tag, sizeof tag, "parent500 basis200"); break;
    }
    as_ui_yg_node_insert(root, c, 0);
    as_ui_yg_calculate(root, 1000.0f, 1000.0f, AS_UI_DIR_LTR);
    show(tag, c);
    as_ui_yg_node_free_recursive(root);
  }

  /* f-variant: root height auto with NaN available height */
  {
    void* root = as_ui_yg_node_new(cfg);
    as_ui_yg_set_flex_direction(root, AS_UI_FLEX_DIR_COLUMN);
    as_ui_yg_set_size(root, AS_UI_AXIS_WIDTH, 40.0f, AS_UI_UNIT_POINT);
    void* c = as_ui_yg_node_new(cfg);
    as_ui_yg_set_size(c, AS_UI_AXIS_HEIGHT, 32.0f, AS_UI_UNIT_POINT);
    as_ui_yg_node_insert(root, c, 0);
    as_ui_yg_calculate(root, NAN, NAN, AS_UI_DIR_LTR);
    show("root auto (NaN avail)", root);
    as_ui_yg_node_free_recursive(root);
  }

  as_ui_yg_config_free(cfg);
  return 0;
}

// mixed probe: build with the glue, read back with raw Yoga getters.
#include "yoga_glue.h"
#include <yoga/Yoga.h>
#include <stdio.h>

int main(void) {
  void* cfg = as_ui_yg_config_new(0.0f, 1);
  void* root = as_ui_yg_node_new(cfg);
  as_ui_yg_set_flex_direction(root, AS_UI_FLEX_DIR_ROW);
  as_ui_yg_set_size(root, AS_UI_AXIS_WIDTH, 100.0f, AS_UI_UNIT_POINT);
  void* c = as_ui_yg_node_new(cfg);
  as_ui_yg_set_minmax(c, AS_UI_AXIS_WIDTH, 0, 150.0f, AS_UI_UNIT_POINT);
  printf("after glue set_minmax: YGNodeStyleGetMinWidth = %f\n",
         YGNodeStyleGetMinWidth((YGNodeConstRef)c).value);
  as_ui_yg_set_flex(c, 0.0f, 1.0f, 200.0f, AS_UI_UNIT_POINT);
  printf("after glue set_flex:   MinWidth=%f FlexBasis=%f\n",
         YGNodeStyleGetMinWidth((YGNodeConstRef)c).value,
         YGNodeStyleGetFlexBasis((YGNodeConstRef)c).value);
  as_ui_yg_set_size(c, AS_UI_AXIS_HEIGHT, 50.0f, AS_UI_UNIT_POINT);
  as_ui_yg_node_insert(root, c, 0);
  as_ui_yg_calculate(root, 1000.0f, 1000.0f, AS_UI_DIR_LTR);
  float r[4];
  as_ui_yg_layout_get(c, r);
  printf("glue result w=%f\n", r[2]);
  as_ui_yg_node_free_recursive(root);
  as_ui_yg_config_free(cfg);
  return 0;
}

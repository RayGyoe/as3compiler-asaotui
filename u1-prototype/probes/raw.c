// raw Yoga probe: does Yoga itself honor an explicit min-width?
#include <yoga/Yoga.h>
#include <math.h>
#include <stdio.h>

static void show(const char* tag, YGNodeRef n) {
  printf("%-30s w=%8.3f h=%8.3f\n", tag, YGNodeLayoutGetWidth(n),
         YGNodeLayoutGetHeight(n));
}

int main(void) {
  YGConfigRef cfg = YGConfigNew();
  YGConfigSetUseWebDefaults(cfg, true);
  YGConfigSetPointScaleFactor(cfg, 0.0f);
  printf("errata=%d\n", (int)YGConfigGetErrata(cfg));

  // 1) explicit width 100 + minWidth 150 (shrink irrelevant, item not flexible)
  {
    YGNodeRef root = YGNodeNewWithConfig(cfg);
    YGNodeStyleSetFlexDirection(root, YGFlexDirectionRow);
    YGNodeStyleSetWidth(root, 100.0f);
    YGNodeRef c = YGNodeNewWithConfig(cfg);
    YGNodeStyleSetWidth(c, 100.0f);
    YGNodeStyleSetMinWidth(c, 150.0f);
    YGNodeStyleSetHeight(c, 50.0f);
    YGNodeInsertChild(root, c, 0);
    YGNodeCalculateLayout(root, 1000, 1000, YGDirectionLTR);
    printf("minWidth get=%f\n", YGNodeStyleGetMinWidth(c).value);
    show("width100 min150 (raw)", c);
    YGNodeFreeRecursive(root);
  }

  // 2) flexBasis 200 shrink 1 minWidth 150 in 100 container
  {
    YGNodeRef root = YGNodeNewWithConfig(cfg);
    YGNodeStyleSetFlexDirection(root, YGFlexDirectionRow);
    YGNodeStyleSetWidth(root, 100.0f);
    YGNodeRef c = YGNodeNewWithConfig(cfg);
    YGNodeStyleSetFlexBasis(c, 200.0f);
    YGNodeStyleSetFlexShrink(c, 1.0f);
    YGNodeStyleSetMinWidth(c, 150.0f);
    YGNodeStyleSetHeight(c, 50.0f);
    YGNodeInsertChild(root, c, 0);
    YGNodeCalculateLayout(root, 1000, 1000, YGDirectionLTR);
    show("basis200 shrink1 min150 (raw)", c);
    YGNodeFreeRecursive(root);
  }

  // 3) same but width instead of flexBasis
  {
    YGNodeRef root = YGNodeNewWithConfig(cfg);
    YGNodeStyleSetFlexDirection(root, YGFlexDirectionRow);
    YGNodeStyleSetWidth(root, 100.0f);
    YGNodeRef c = YGNodeNewWithConfig(cfg);
    YGNodeStyleSetWidth(c, 200.0f);
    YGNodeStyleSetFlexShrink(c, 1.0f);
    YGNodeStyleSetMinWidth(c, 150.0f);
    YGNodeStyleSetHeight(c, 50.0f);
    YGNodeInsertChild(root, c, 0);
    YGNodeCalculateLayout(root, 1000, 1000, YGDirectionLTR);
    show("width200 shrink1 min150 (raw)", c);
    YGNodeFreeRecursive(root);
  }

  YGConfigFree(cfg);
  return 0;
}

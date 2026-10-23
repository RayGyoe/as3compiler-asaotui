// M3: "use many APIs" probe. Touches layout + a wide slice of the style setter
// surface (flex direction/wrap/justify/align/padding/margin/gap/position/etc.)
// plus the YGValue (percent/pt/auto) forms and enum ToString helpers. Volume
// grows monotonically with the number of distinct reachable symbol groups.
#include <stdio.h>
#include <yoga/Yoga.h>

int main(void) {
  YGConfigRef cfg = YGConfigNew();
  YGConfigSetUseWebDefaults(cfg, true);
  YGConfigSetPointScaleFactor(cfg, 2.0f);

  YGNodeRef root = YGNodeNewWithConfig(cfg);
  YGNodeStyleSetFlexDirection(root, YGFlexDirectionRow);
  YGNodeStyleSetFlexWrap(root, YGWrapWrap);
  YGNodeStyleSetJustifyContent(root, YGJustifySpaceBetween);
  YGNodeStyleSetAlignItems(root, YGAlignCenter);
  YGNodeStyleSetAlignContent(root, YGAlignSpaceAround);
  YGNodeStyleSetWidth(root, 640);
  YGNodeStyleSetHeightPercent(root, 80);
  YGNodeStyleSetMinWidth(root, 100);
  YGNodeStyleSetMaxHeight(root, 200);
  YGNodeStyleSetPadding(root, YGEdgeAll, 4);
  YGNodeStyleSetMargin(root, YGEdgeHorizontal, 6);
  YGNodeStyleSetGap(root, YGGutterRow, 3);
  YGNodeStyleSetPositionType(root, YGPositionTypeRelative);
  YGNodeStyleSetOverflow(root, YGOverflowHidden);
  YGNodeStyleSetDisplay(root, YGDisplayFlex);

  for (int i = 0; i < 4; i++) {
    YGNodeRef c = YGNodeNewWithConfig(cfg);
    YGNodeStyleSetFlexGrow(c, 1.0f);
    YGNodeStyleSetFlexShrink(c, (float)i);
    YGNodeStyleSetFlexBasisPercent(c, 25.0f);
    YGNodeStyleSetWidthAuto(c);
    YGNodeStyleSetHeight(c, 20 + i);
    YGNodeStyleSetAspectRatio(c, 1.5f);
    YGNodeInsertChild(root, c, i);
  }

  YGNodeCalculateLayout(root, 640, YGUndefined, YGDirectionLTR);

  const char* fl =
      YGFlexDirectionToString(YGNodeStyleGetFlexDirection(root));
  float x = YGNodeLayoutGetLeft(root);
  float y = YGNodeLayoutGetTop(root);
  printf("%s %.1f %.1f\n", fl, x, y);

  YGNodeFreeRecursive(root);
  YGConfigFree(cfg);
  return 0;
}

// Minimal C program that drives the Yoga C API. Used for the link-size matrix:
// linked with and without libyoga.a to isolate Yoga's real contribution to a
// final executable (with --gc-sections / -dead_strip).
//
// Deliberately uses only the C API (yoga/Yoga.h) because OUR generated code is C
// (AGENTS.md §2.1): the C++ is hidden behind the C seam.
#include <stdio.h>
#include <yoga/Yoga.h>

int main(void) {
  YGConfigRef cfg = YGConfigNew();
  YGConfigSetPointScaleFactor(cfg, 0.0f); // 0 = no rounding, deterministic float

  YGNodeRef root = YGNodeNewWithConfig(cfg);
  YGNodeStyleSetFlexDirection(root, YGFlexDirectionRow);
  YGNodeStyleSetWidth(root, 300);
  YGNodeStyleSetHeight(root, 100);

  YGNodeRef a = YGNodeNewWithConfig(cfg);
  YGNodeStyleSetWidth(a, 50);
  YGNodeStyleSetFlexGrow(a, 1);
  YGNodeInsertChild(root, a, 0);

  YGNodeRef b = YGNodeNewWithConfig(cfg);
  YGNodeStyleSetWidth(b, 50);
  YGNodeStyleSetFlexGrow(b, 2);
  YGNodeInsertChild(root, b, 1);

  YGNodeCalculateLayout(root, YGUndefined, YGUndefined, YGDirectionLTR);

  float w0 = YGNodeLayoutGetWidth(a);
  float w1 = YGNodeLayoutGetWidth(b);
  printf("%.1f %.1f\n", w0, w1);

  YGNodeFreeRecursive(root);
  YGConfigFree(cfg);
  return (w0 + w1) == 300.0f ? 0 : 1;
}

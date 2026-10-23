// M3: DCE probe. Only new/free a node -- no layout, no styling. If Yoga's layout
// core (CalculateLayout.cpp) is NOT reachable from these calls, /OPT:REF must
// drop it and this should be much smaller than the full program.
#include <stdio.h>
#include <yoga/Yoga.h>

int main(void) {
  YGConfigRef cfg = YGConfigNew();
  YGNodeRef n = YGNodeNewWithConfig(cfg);
  YGNodeRef m = YGNodeNew();
  YGNodeFree(m);
  YGNodeFreeRecursive(n);
  YGConfigFree(cfg);
  printf("ok\n");
  return 0;
}

// Decisive control for the wasip1 delta: does Yoga's ++size come from its own
// code, or from the WASI libc it drags in (Yoga's Log.cpp / AssertFatal.cpp call
// printf-family functions, and wasi libc's float formatting is not small)?
//
// If `floor_printf` lands near `yoga_one`, the "delta" was libc, not Yoga.
#include <stdio.h>

int main(void) {
  char buf[64];
  snprintf(buf, sizeof buf, "%.3f", 1.5);
  printf("%s\n", buf);
  return 0;
}
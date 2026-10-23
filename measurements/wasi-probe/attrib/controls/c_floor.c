// C-only floor: no Yoga. Linked both with `clang` (pure C) and `clang++` (adds
// the C++ runtime floor) to measure what the C++ toolchain alone costs before
// Yoga contributes a single byte.
#include <stdio.h>
int main(void) {
  printf("hi\n");
  return 0;
}

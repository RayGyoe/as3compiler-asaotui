// Control: cost of the std::terminate() path that Yoga's AssertFatal.cpp
// references under -fno-exceptions (fatalWithMessage -> std::terminate).
#include <cstdio>
#include <exception>
int main(int argc, char**) {
  if (argc > 99) std::terminate();
  printf("ok\n");
  return 0;
}

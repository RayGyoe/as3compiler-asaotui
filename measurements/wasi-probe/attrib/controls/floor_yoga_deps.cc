// Control: the libc/libc++ payload a *minimal* Yoga program cannot avoid even
// before any layout code runs:
//   * operator new/delete  -> wasi-libc dlmalloc (YogaNodeNew/Node::Node)
//   * vfprintf via va_list -> Yoga's default logger (Log.cpp getDefaultLogger)
//   * std::terminate       -> AssertFatal.cpp fatalWithMessage under -fno-exceptions
//   * a formatting printf  -> the stdio path
// i.e. it is "floor_cpp + Yoga's unavoidable library dependencies". Anything
// above this is Yoga's own code.
#include <cstdio>
#include <cstdarg>
#include <cstdlib>
#include <exception>

static int logger(const char* fmt, va_list ap) { return vfprintf(stderr, fmt, ap); }

int main(int argc, char**) {
  int* p = new int(7);
  char buf[32];
  snprintf(buf, sizeof buf, "%d", *p);
  printf("%s\n", buf);
  if (argc > 99) std::terminate();
  (void)logger;
  delete p;
  return 0;
}

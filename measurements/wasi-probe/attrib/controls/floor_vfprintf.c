// Control: cost of the vfprintf/vprintf path that Yoga's Log.cpp default logger
// calls. Takes va_list exactly like getDefaultLogger's lambda does, so the
// compiler cannot fold it to a simpler printf.
#include <stdio.h>
#include <stdarg.h>
static int my_vlog(const char* fmt, va_list ap) { return vfprintf(stderr, fmt, ap); }
int main(void) {
  char buf[32];
  snprintf(buf, sizeof buf, "%d", 42);
  va_list ap; (void)ap;
  fprintf(stderr, "%s\n", buf);
  (void)my_vlog;
  return 0;
}

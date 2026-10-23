// Control: cost of abort() (what libc++'s verbose_abort ends up calling).
#include <stdlib.h>
int main(int argc, char**) { if (argc > 99) abort(); return 0; }

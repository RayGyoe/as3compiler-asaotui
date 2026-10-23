// Control: how much does C++ operator new/delete (malloc/free path, dlmalloc)
// cost on wasip1? Yoga's Config/Node allocate through it unconditionally.
#include <cstdio>
int main() {
  int* p = new int(7);
  printf("%d\n", *p);
  delete p;
  return 0;
}

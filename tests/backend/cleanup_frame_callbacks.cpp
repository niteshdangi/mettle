#include "../../runtime/panic.h"
#include <algorithm>
#include <array>
#include <cstdio>
#include <vector>

namespace {
std::vector<int> trace;
}

extern "C" void mettle_test_leaf_drop(void *address) {
  int tag = *static_cast<int *>(address);
  trace.push_back(tag);
  if (tag == 99)
    mettle_rt_panic(10);
}

extern "C" void mettle_test_parent_drop(void *address) {
  int tag = *static_cast<int *>(address);
  trace.push_back(1000 + tag);
  if (tag == 20)
    mettle_rt_panic(9);
}

extern "C" int mettle_test_cleanup_result() {
  constexpr std::array expected{7,  1010, 10,   11, 12, 1013, 13, 14, 1015,
                                15, 16,   1020, 20, 21, 1020, 20, 21, 1030,
                                30, 31,   1040, 40, 41, 1017, 17, 18, 1019,
                                19, 22,   1020, 20, 21, 1020, 20, 21};
  if (trace.size() != expected.size() ||
      !std::equal(trace.begin(), trace.end(), expected.begin())) {
    for (int tag : trace)
      std::fprintf(stderr, "%d ", tag);
    std::fprintf(stderr, "\n");
    return 42;
  }
  return 0;
}

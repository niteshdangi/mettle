#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdio>
#include <span>
#include <vector>

namespace {
std::vector<std::int32_t> trace;
}

extern "C" void mettle_test_cleanup_source_record(std::int32_t tag) {
  trace.push_back(tag);
}

extern "C" std::int32_t mettle_test_cleanup_source_result(std::int32_t code,
                                                          std::int32_t mode) {
  constexpr std::array<std::int32_t, 60> scopes{
      102,  103,  101,             // statement temporaries
      201,  202,                   // if condition
      301,  310,  302,  311,  303, // while conditions
      401,  402,  403,  404,  406,  407, 409, 410,
      411,  412,                   // short-circuit operands
      502,  501,  503,             // discarded block tail
      605,  602,  603,  604,  601, // reverse roots, ordered fields
      701,  703,  702,  712,  711, // owned return and early return
      810,  830,  820,  811,  831,  821, 840, 801, // continue and break
      1002, 1001, 1004, 1003,       // protected labeled break result
      1021, 1010, 1022, 1011, 1030, // cross-loop continue cleanup
      1101, 1102, 1103,             // active variants only
      1121, 1199, 1121, 1122,       // failed fields, established whole
      1132, 1133, 1131              // consuming array rest
  };
  constexpr std::array<std::int32_t, 4> arguments{902, 903, 905, 901};
  std::span<const std::int32_t> expected(scopes);
  if (mode != 0)
    expected = arguments;
  bool valid =
      code == (mode == 0 ? 0 : 1) &&
      std::equal(trace.begin(), trace.end(), expected.begin(), expected.end());
  std::FILE *output = valid ? stdout : stderr;
  std::fprintf(output, "%s:", mode == 0 ? "scopes" : "argument-unwind");
  for (auto tag : trace)
    std::fprintf(output, " %d", tag);
  std::fprintf(output, "; caught=%d\n", code);
  return valid ? 0 : 46;
}

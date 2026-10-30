#pragma once

#include "syntax/ast.h"
#include <string>
#include <vector>

namespace mettle::expansion {
// Command-line selectors of a harness executable: the program name, one of
// these and the decimal index of a `Module::tests` entry.
inline constexpr const char *harnessTestSelector = "--mettle-test-run";
inline constexpr const char *harnessBenchSelector = "--mettle-bench-run";
// Exit status of a test that returned its typed failure.
inline constexpr int harnessFailureStatus = 70;
// Exit status of a harness invoked with an unknown selector or entry.
inline constexpr int harnessUsageStatus = 64;
// Samples per benchmark: the harness prints the iteration count, then the
// total nanoseconds of each sample.
inline constexpr int harnessBenchSamples = 11;

// Mettle source of the harness entry for the selected entries: an
// `fn main(): i32` that runs the entry named on the command line, so one
// executable serves every test with each run isolated in its own process.
// A test exits 0 on success and `harnessFailureStatus` when it returns its
// failure (`harnessUsageStatus` for a selector it does not know); panics end
// the process through the runtime. A benchmark prints `ITERATIONS SAMPLE...`
// (calibrated so a sample takes at least 10 ms) and exits 0. Only the root
// module's functions are addressable.
std::string harnessSource(const std::vector<Module::TestFunction> &tests,
                          bool bench);
} // namespace mettle::expansion

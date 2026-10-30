#pragma once

#include <optional>
#include <set>
#include <string>

namespace mettle::driver {
struct Options {
  Options();
  std::string command, input, output, emit = "executable", profile = "debug";
  std::string target, cc, sysroot, libraryDirectory;
  // Package features that `@cfg(feature = "...")` tests.
  std::set<std::string> features;
  std::optional<bool> checks;
  bool freestanding = false;
};
std::optional<Options> options(int argc, char **argv);
void usage();
int run(const Options &options);
} // namespace mettle::driver

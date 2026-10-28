#pragma once

#include <optional>
#include <string>

namespace mettle::driver {
struct Options {
  Options();
  std::string command, input, output, emit = "executable", profile = "debug";
  std::string target, cc, sysroot;
  std::optional<bool> checks;
};
std::optional<Options> options(int argc, char **argv);
void usage();
int run(const Options &options);
} // namespace mettle::driver

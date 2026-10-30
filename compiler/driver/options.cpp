#include "driver/options.h"
#include "backend/llvm/object.h"
#include <iostream>

namespace mettle::driver {
Options::Options()
    : target(backend::defaultTargetTriple()), cc(METTLE_CXX_PATH),
      sysroot(METTLE_SYSROOT_PATH), libraryDirectory(METTLE_LIBRARY_PATH) {}
void usage() {
  std::cout
      << "Usage: mettle check|tokens|syntax FILE\n"
         "       mettle build FILE -o OUTPUT [--emit "
         "executable|object|llvm|ir]\n"
         "         [--profile debug|release] [--overflow-checks on|off]\n"
         "         [--target TRIPLE] [--cc CXX] [--sysroot PATH]\n"
         "         [--library-dir PATH] [--feature NAME]...\n"
         "         [--freestanding] (object/LLVM/IR output, aborting panics, "
         "no implicit hosted entry)\n"
         "Executable output requires the runtime target (the default); use "
         "--emit object for other targets.\n"
         "Scalar/product compiler with field initialization, owned moves, "
         "read/mut/take calls and control flow.\n"
         "Stored views, destructors and unwind cleanup remain incomplete.\n";
}
std::optional<Options> options(int argc, char **argv) {
  if (argc < 3)
    return std::nullopt;
  Options result;
  result.command = argv[1];
  if (result.command != "build" && result.command != "check" &&
      result.command != "tokens" && result.command != "syntax")
    return std::nullopt;
  for (int i = 2; i < argc; ++i) {
    std::string arg = argv[i];
    if (arg == "--freestanding") {
      result.freestanding = true;
      continue;
    }
    if (!arg.empty() && arg[0] == '-') {
      if (++i == argc)
        return std::nullopt;
      std::string value = argv[i];
      if (arg == "-o")
        result.output = value;
      else if (arg == "--emit")
        result.emit = value;
      else if (arg == "--profile")
        result.profile = value;
      else if (arg == "--target")
        result.target = value;
      else if (arg == "--cc")
        result.cc = value;
      else if (arg == "--library-dir")
        result.libraryDirectory = value;
      else if (arg == "--sysroot")
        result.sysroot = value;
      else if (arg == "--feature")
        result.features.insert(value);
      else if (arg == "--overflow-checks" && (value == "on" || value == "off"))
        result.checks = value == "on";
      else
        return std::nullopt;
    } else if (result.input.empty())
      result.input = arg;
    else
      return std::nullopt;
  }
  if (result.input.empty() ||
      (result.freestanding && result.command == "build" &&
       result.emit == "executable") ||
      (result.command == "build" && result.output.empty()) ||
      (result.profile != "debug" && result.profile != "release") ||
      (result.emit != "executable" && result.emit != "object" &&
       result.emit != "llvm" && result.emit != "ir"))
    return std::nullopt;
  return result;
}
} // namespace mettle::driver

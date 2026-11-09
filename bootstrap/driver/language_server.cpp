#include "driver/language_server.h"
#include "backend/llvm/numeric.h"
#include "driver/options.h"
#include "expansion/expand.h"
#include "lsp/server.h"
#include "types/target.h"
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <string>
#include <utility>

namespace mettle::driver {
int languageServer(int argc, char **argv) {
  Options defaults;
  std::string library = defaults.libraryDirectory, triple = defaults.target;
  bool freestanding = false;
  for (int i = 2; i < argc; ++i) {
    std::string arg = argv[i];
    if (arg == "--freestanding")
      freestanding = true;
    else if ((arg == "--library-dir" || arg == "--target") && i + 1 < argc)
      (arg == "--target" ? triple : library) = argv[++i];
    else
      return 2;
  }
  auto facts = targetFacts(triple);
  expansion::Configuration configuration;
  configuration.os = facts.system == TargetSystem::Linux    ? "linux"
                     : facts.system == TargetSystem::Darwin ? "macos"
                                                            : "";
  configuration.arch = facts.arch == TargetArch::X86_64    ? "x86_64"
                       : facts.arch == TargetArch::Aarch64 ? "aarch64"
                                                           : "";
  configuration.family = configuration.os.empty() ? "" : "unix";
  configuration.endian = facts.littleEndian ? "little" : "big";
  configuration.pointerWidth = facts.pointerBits;
  configuration.targetFeatures = facts.baseline;
  resolution::Library native;
  native.directory = library;
  native.freestanding = freestanding;
  native.configuration = configuration;
  lsp::Configuration server{
      std::move(native),
      [](const std::string &path) -> std::optional<Source> {
        std::error_code error;
        auto canonical = std::filesystem::canonical(path, error);
        if (error)
          return std::nullopt;
        std::ifstream file(canonical, std::ios::binary);
        if (!file)
          return std::nullopt;
        return Source{canonical.generic_string(),
                      std::string(std::istreambuf_iterator<char>(file), {})};
      },
      facts, METTLE_VERSION, backend::evaluateNumeric};
  return lsp::serve(std::cin, std::cout, server);
}
} // namespace mettle::driver

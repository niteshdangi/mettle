#include "driver/inspect.h"
#include "driver/options.h"
#include "driver/output.h"
#include "pipeline/compile.h"
#include "resolution/load.h"
#include "syntax/lexer.h"
#include "syntax/parser.h"
#include "types/target.h"
#include "llvm/Support/MemoryBuffer.h"
#include <filesystem>
#include <iostream>

namespace mettle::driver {
int run(const Options &options) {
  auto buffer = llvm::MemoryBuffer::getFile(options.input);
  if (!buffer) {
    std::cerr << "mettle: error[io]: cannot read " << options.input << ": "
              << buffer.getError().message() << '\n';
    return 1;
  }
  std::error_code pathError;
  auto rootPath = std::filesystem::canonical(options.input, pathError);
  Source source{pathError ? options.input : rootPath.generic_string(),
                (*buffer)->getBuffer().str()};
  Diagnostics diagnostics;
  if (options.command == "tokens" || options.command == "syntax") {
    Module tree;
    if (options.command == "tokens")
      tree.tokens = tokenize(source, diagnostics);
    else
      tree = parse(source, diagnostics);
    inspect(tree);
    diagnostics.print(source, std::cerr);
    return diagnostics.empty() ? 0 : 1;
  }
  if (!targetFacts(options.target).initialProfile()) {
    diagnostics.error(
        "feature", {},
        "source compilation supports Darwin ARM64 and Linux x86-64 targets");
    diagnostics.print(source, std::cerr);
    return 1;
  }
  resolution::SourceProvider provider =
      [&](const std::string &path) -> std::optional<Source> {
    std::error_code error;
    bool exists = std::filesystem::exists(path, error);
    if (!exists && !error)
      return std::nullopt;
    auto child = llvm::MemoryBuffer::getFile(path);
    if (!child) {
      diagnostics.error(
          "io", {}, "cannot read " + path + ": " + child.getError().message());
      return std::nullopt;
    }
    auto canonical = std::filesystem::canonical(path, error);
    if (error) {
      diagnostics.error("io", {},
                        "cannot identify " + path + ": " + error.message());
      return std::nullopt;
    }
    return Source{canonical.generic_string(), (*child)->getBuffer().str()};
  };
  auto facts = targetFacts(options.target);
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
  configuration.features = options.features;
  auto tree = resolution::load(
      source, provider, diagnostics,
      {options.libraryDirectory, options.freestanding, configuration});
  auto program = tree ? pipeline::compile(std::move(*tree), diagnostics,
                                          !options.freestanding, facts)
                      : std::nullopt;
  if (!program) {
    diagnostics.print(source, std::cerr);
    return 1;
  }
  return options.command == "check" ? 0 : emit(options, source, *program);
}
} // namespace mettle::driver
